import hashlib
import json
import logging
import os
import time
from typing import Any, Callable
from uuid import uuid4

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class IdempotencyConflict(ValueError):
    """The same key was reused for a different business payload."""


class IdempotencyInProgress(RuntimeError):
    """Another invocation currently owns this idempotency key."""


def parse_event(event: object) -> dict[str, str]:
    """Validate and normalize the small business-event contract."""
    if not isinstance(event, dict):
        raise ValueError("event must be a JSON object")

    fields: dict[str, str] = {}
    for name in ("idempotency_key", "customer_id", "report_date"):
        value = event.get(name)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{name} must be a non-empty string")
        fields[name] = value.strip()

    return fields


def payload_hash(event: dict[str, str]) -> str:
    """Return a stable digest used to detect unsafe key reuse."""
    business_payload = {
        "customer_id": event["customer_id"],
        "report_date": event["report_date"],
    }
    canonical = json.dumps(
        business_payload,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def is_conditional_failure(error: Exception) -> bool:
    """Recognize DynamoDB's conditional-write rejection without botocore."""
    response = getattr(error, "response", {})
    code = response.get("Error", {}).get("Code") if isinstance(response, dict) else None
    return code == "ConditionalCheckFailedException"


def claim_or_replay(
    table: Any,
    event: dict[str, str],
    owner_token: str,
    now_epoch: int,
    claim_ttl_seconds: int,
) -> tuple[str, dict[str, str] | None]:
    """Atomically claim a key, or return the result of a completed request."""
    key = event["idempotency_key"]
    digest = payload_hash(event)
    claim_expires_at = now_epoch + claim_ttl_seconds

    try:
        table.put_item(
            Item={
                "idempotency_key": key,
                "status": "IN_PROGRESS",
                "payload_hash": digest,
                "owner_token": owner_token,
                "created_at": now_epoch,
                "updated_at": now_epoch,
                "expires_at": claim_expires_at,
            },
            # An expired item may still physically exist because DynamoDB TTL
            # deletion is asynchronous. The condition makes it reclaimable.
            ConditionExpression=(
                "attribute_not_exists(idempotency_key) OR expires_at < :now"
            ),
            ExpressionAttributeValues={":now": now_epoch},
        )
        return "CLAIMED", None
    except Exception as error:
        if not is_conditional_failure(error):
            raise

    response = table.get_item(
        Key={"idempotency_key": key},
        ConsistentRead=True,
    )
    existing = response.get("Item")
    if not isinstance(existing, dict):
        # The item can disappear between the failed condition and this read.
        # Failing is safer than processing without a confirmed claim.
        raise IdempotencyInProgress(f"claim changed concurrently for key={key}")

    if existing.get("payload_hash") != digest:
        raise IdempotencyConflict(
            f"idempotency_key={key} was already used for another payload"
        )

    if existing.get("status") == "COMPLETED":
        saved = existing.get("result_json")
        if not isinstance(saved, str):
            raise RuntimeError(f"completed record has no result for key={key}")
        decoded = json.loads(saved)
        if not isinstance(decoded, dict) or not all(
            isinstance(name, str) and isinstance(value, str)
            for name, value in decoded.items()
        ):
            raise RuntimeError(f"completed record has an invalid result for key={key}")
        return "REPLAYED", decoded

    raise IdempotencyInProgress(f"processing already in progress for key={key}")


def complete_claim(
    table: Any,
    key: str,
    digest: str,
    owner_token: str,
    result: dict[str, str],
    now_epoch: int,
    record_ttl_seconds: int,
) -> None:
    """Complete only the claim still owned by this invocation."""
    table.update_item(
        Key={"idempotency_key": key},
        UpdateExpression=(
            "SET #status = :completed, result_json = :result_json, "
            "updated_at = :now, expires_at = :expires_at"
        ),
        ConditionExpression=(
            "#status = :in_progress AND payload_hash = :payload_hash "
            "AND owner_token = :owner_token"
        ),
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={
            ":completed": "COMPLETED",
            ":in_progress": "IN_PROGRESS",
            ":payload_hash": digest,
            ":owner_token": owner_token,
            ":result_json": json.dumps(result, sort_keys=True),
            ":now": now_epoch,
            ":expires_at": now_epoch + record_ttl_seconds,
        },
    )


def generate_report(event: dict[str, str]) -> dict[str, str]:
    """Represent the business action without calling another external system."""
    report_id = hashlib.sha256(
        event["idempotency_key"].encode("utf-8")
    ).hexdigest()[:12]
    return {
        "report_id": report_id,
        "customer_id": event["customer_id"],
        "report_date": event["report_date"],
        "status": "generated",
    }


def process_event(
    event: object,
    context: Any,
    table: Any,
    now_epoch: int,
    claim_ttl_seconds: int,
    record_ttl_seconds: int,
    processor: Callable[[dict[str, str]], dict[str, str]] = generate_report,
    owner_token: str | None = None,
) -> dict[str, str]:
    """Run the idempotency state machine around one business action."""
    parsed = parse_event(event)
    request_id = getattr(context, "aws_request_id", "local")
    # Lambda can preserve RequestId across managed retries. A fresh UUID makes
    # this fencing token unique to one actual handler execution attempt.
    attempt_token = owner_token or str(uuid4())

    decision, saved_result = claim_or_replay(
        table,
        parsed,
        attempt_token,
        now_epoch,
        claim_ttl_seconds,
    )
    if decision == "REPLAYED":
        logger.info(
            json.dumps(
                {
                    "event": "idempotency_replay",
                    "idempotency_key": parsed["idempotency_key"],
                    "owner_token": attempt_token,
                    "request_id": request_id,
                }
            )
        )
        return {**saved_result, "idempotency_status": "REPLAYED"}

    logger.info(
        json.dumps(
            {
                "event": "idempotency_claimed",
                "idempotency_key": parsed["idempotency_key"],
                "owner_token": attempt_token,
                "request_id": request_id,
            }
        )
    )

    result = processor(parsed)
    complete_claim(
        table,
        parsed["idempotency_key"],
        payload_hash(parsed),
        attempt_token,
        result,
        now_epoch,
        record_ttl_seconds,
    )

    logger.info(
        json.dumps(
            {
                "event": "idempotency_completed",
                "idempotency_key": parsed["idempotency_key"],
                "owner_token": attempt_token,
                "request_id": request_id,
            }
        )
    )
    return {**result, "idempotency_status": "PROCESSED"}


def lambda_handler(event: object, context: Any) -> dict[str, str]:
    """AWS entry point; boto3 is imported lazily to keep unit tests local."""
    import boto3

    table_name = os.environ["IDEMPOTENCY_TABLE_NAME"]
    claim_ttl_seconds = int(os.environ.get("CLAIM_TTL_SECONDS", "300"))
    record_ttl_seconds = int(os.environ.get("RECORD_TTL_SECONDS", "86400"))
    table = boto3.resource("dynamodb").Table(table_name)

    return process_event(
        event,
        context,
        table,
        int(time.time()),
        claim_ttl_seconds,
        record_ttl_seconds,
    )
