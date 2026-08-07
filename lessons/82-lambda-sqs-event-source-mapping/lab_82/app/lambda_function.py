import hashlib
import json
import logging
from typing import Any, Callable

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class MessageContractError(ValueError):
    """An SQS record or its JSON body does not match the consumer contract."""


def parse_record(record: object) -> tuple[str, dict[str, object]]:
    """Validate one SQS record and return its message ID and body object."""
    if not isinstance(record, dict):
        raise MessageContractError("SQS record must be an object")

    message_id = record.get("messageId")
    if not isinstance(message_id, str) or not message_id.strip():
        # Without messageId Lambda cannot identify one failed item in the
        # ReportBatchItemFailures response, so the whole invocation must fail.
        raise MessageContractError("SQS record must contain a non-empty messageId")

    raw_body = record.get("body")
    if not isinstance(raw_body, str):
        raise MessageContractError("SQS record body must be a JSON string")

    try:
        body = json.loads(raw_body)
    except json.JSONDecodeError as error:
        raise MessageContractError("SQS record body must contain valid JSON") from error

    if not isinstance(body, dict):
        raise MessageContractError("SQS message body must decode to an object")

    task_id = body.get("task_id")
    action = body.get("action")
    should_fail = body.get("should_fail", False)

    if not isinstance(task_id, str) or not task_id.strip():
        raise MessageContractError("task_id must be a non-empty string")
    if action != "generate_report":
        raise MessageContractError("action must be generate_report")
    if not isinstance(should_fail, bool):
        raise MessageContractError("should_fail must be a boolean")

    return message_id, {
        "task_id": task_id.strip(),
        "action": action,
        "should_fail": should_fail,
    }


def generate_report(message: dict[str, object]) -> dict[str, str]:
    """Perform a deterministic lab action with no external side effect."""
    task_id = str(message["task_id"])
    if message["should_fail"]:
        raise RuntimeError(f"simulated poison message task_id={task_id}")

    return {
        "task_id": task_id,
        "report_id": hashlib.sha256(task_id.encode("utf-8")).hexdigest()[:12],
        "status": "generated",
    }


def process_batch(
    event: object,
    processor: Callable[[dict[str, object]], dict[str, str]] = generate_report,
) -> dict[str, list[dict[str, str]]]:
    """Process records independently and report only failed message IDs."""
    if not isinstance(event, dict):
        raise MessageContractError("event must be an SQS event object")

    records = event.get("Records")
    if not isinstance(records, list):
        raise MessageContractError("event.Records must be a list")

    failures: list[dict[str, str]] = []
    for record in records:
        # messageId is required before per-record error handling because a
        # partial batch response cannot identify a malformed record without it.
        if not isinstance(record, dict):
            raise MessageContractError("SQS record must be an object")
        message_id = record.get("messageId")
        if not isinstance(message_id, str) or not message_id.strip():
            raise MessageContractError("SQS record must contain a non-empty messageId")

        try:
            _, message = parse_record(record)
            result = processor(message)
            logger.info(
                json.dumps(
                    {
                        "event": "sqs_message_processed",
                        "message_id": message_id,
                        "task_id": message["task_id"],
                        "report_id": result["report_id"],
                    }
                )
            )
        except Exception as error:
            # Returning the identifier keeps successful records acknowledged
            # while this record becomes visible for another receive attempt.
            logger.error(
                json.dumps(
                    {
                        "event": "sqs_message_failed",
                        "message_id": message_id,
                        "error_type": type(error).__name__,
                        "error": str(error),
                    }
                )
            )
            failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": failures}


def lambda_handler(event: object, context: Any) -> dict[str, list[dict[str, str]]]:
    """AWS Lambda entry point for an SQS event source mapping."""
    del context
    return process_batch(event)
