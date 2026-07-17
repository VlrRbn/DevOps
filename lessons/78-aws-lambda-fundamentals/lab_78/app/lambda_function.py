import json
import logging
import os
from typing import Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def build_greeting(name: str) -> str:
    """Keep application validation independent of the Lambda runtime."""
    if not isinstance(name, str):
        raise ValueError("name must be a string")

    normalized_name = name.strip()
    if not normalized_name:
        raise ValueError("name must not be empty")

    return f"Hello, {normalized_name}!"


def lambda_handler(event: object, context: Any) -> dict[str, str]:
    """Adapt the untrusted Lambda event and AWS context to application logic."""
    # JSON can legally be null, an array, or a scalar; only an object supports
    # the key-based contract expected by this handler.
    if not isinstance(event, dict):
        raise ValueError("event must be a JSON object")

    name = event.get("name", "world")
    message = build_greeting(name)

    # AWS supplies this attribute in Lambda; the fallback keeps local tests
    # independent from the real runtime context object.
    request_id = getattr(context, "aws_request_id", "local")
    environment = os.environ.get("APP_ENV", "unknown")

    # Log selected operational fields, not the complete input event.
    logger.info(
        json.dumps(
            {
                "event": "greeting_created",
                "environment": environment,
                "request_id": request_id,
            }
        )
    )

    return {
        "message": message,
        "environment": environment,
        "request_id": request_id,
    }
