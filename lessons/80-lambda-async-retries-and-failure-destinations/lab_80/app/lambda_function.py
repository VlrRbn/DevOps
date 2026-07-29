import json
import logging
import os
from typing import Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def parse_event(event: object) -> tuple[str, str]:
    """Validate the asynchronous event contract before processing it."""
    if not isinstance(event, dict):
        raise ValueError("event must be a JSON object")

    event_id = event.get("event_id")
    if not isinstance(event_id, str) or not event_id.strip():
        raise ValueError("event_id must be a non-empty string")

    mode = event.get("mode", "success")
    if mode not in {"success", "fail"}:
        raise ValueError("mode must be success or fail")

    return event_id.strip(), mode


def lambda_handler(event: object, context: Any) -> dict[str, str]:
    """Process one event and expose an intentional failure path for the lab."""
    event_id, mode = parse_event(event)
    request_id = getattr(context, "aws_request_id", "local")
    environment = os.environ.get("APP_ENV", "unknown")

    logger.info(
        json.dumps(
            {
                "event": "async_event_received",
                "event_id": event_id,
                "mode": mode,
                "environment": environment,
                "request_id": request_id,
            }
        )
    )

    if mode == "fail":
        # Raising is intentional: Lambda must classify the attempt as failed,
        # retry it, and eventually publish an invocation record to SQS.
        raise RuntimeError(f"intentional failure for event_id={event_id}")

    result = {
        "status": "processed",
        "event_id": event_id,
        "environment": environment,
        "request_id": request_id,
    }

    # START/END/REPORT lines describe the runtime lifecycle and also appear
    # around failed attempts. This application-level record proves that the
    # handler reached its successful completion path.
    logger.info(
        json.dumps(
            {
                "event": "async_event_processed",
                **result,
            }
        )
    )

    return result
