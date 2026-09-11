"""HTTP API payload v2 adapter and a side-effect-free quote calculator."""

import base64
import binascii
import json
import logging
from typing import TypedDict, cast

logger = logging.getLogger()
logger.setLevel(logging.INFO)
MAX_BODY_BYTES = 4096


class HttpResponse(TypedDict):
    """Explicit Lambda proxy response; body is a string, not a Python dict."""

    statusCode: int
    headers: dict[str, str]
    body: str
    isBase64Encoded: bool


class RequestError(ValueError):
    """Expected client error that can safely become an HTTP response."""

    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code


def as_object(value: object) -> dict[str, object]:
    # Type annotations do not validate input at runtime. Narrow external JSON
    # values before using .get(), including the outer invocation envelope.
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise ValueError("Expected an object with string keys")
    return cast(dict[str, object], value)


def response(status: int, payload: dict[str, object], request_id: str) -> HttpResponse:
    return {
        "statusCode": status,
        "headers": {
            "content-type": "application/json",
            "cache-control": "no-store",
            "x-request-id": request_id,
        },
        "body": json.dumps({**payload, "request_id": request_id}),
        "isBase64Encoded": False,
    }


def read_json_body(event: dict[str, object]) -> dict[str, object]:
    headers = event.get("headers")
    if not isinstance(headers, dict):
        raise RequestError(415, "unsupported_media_type", "Use application/json")
    content_type = headers.get("content-type")
    if not isinstance(content_type, str) or (
        content_type.split(";", 1)[0].strip().lower() != "application/json"
    ):
        raise RequestError(415, "unsupported_media_type", "Use application/json")

    body = event.get("body")
    encoded = event.get("isBase64Encoded", False)
    if not isinstance(body, str) or not body or not isinstance(encoded, bool):
        raise RequestError(400, "invalid_body", "A JSON request body is required")

    # Bound work before decoding, then enforce the actual decoded size. This is
    # an application limit; it does not change API Gateway's service quota.
    if len(body) > (4 * ((MAX_BODY_BYTES + 2) // 3) if encoded else MAX_BODY_BYTES):
        raise RequestError(413, "body_too_large", "Body exceeds 4096 bytes")
    try:
        raw = base64.b64decode(body, validate=True) if encoded else body.encode("utf-8")
        if len(raw) > MAX_BODY_BYTES:
            raise RequestError(413, "body_too_large", "Body exceeds 4096 bytes")
        decoded: object = json.loads(raw.decode("utf-8"))
        return as_object(decoded)
    except RequestError:
        raise
    except (ValueError, UnicodeError, binascii.Error, RecursionError) as error:
        raise RequestError(400, "invalid_json", "Body must be a UTF-8 JSON object") from error


def calculate_quote(payload: dict[str, object]) -> dict[str, object]:
    if set(payload) != {"unit_price_cents", "quantity"}:
        raise RequestError(422, "invalid_quote", "Provide unit_price_cents and quantity only")
    price = payload["unit_price_cents"]
    quantity = payload["quantity"]
    # bool is a subclass of int in Python; True must not become one item/cent.
    if type(price) is not int or not 1 <= price <= 1_000_000:
        raise RequestError(422, "invalid_quote", "unit_price_cents must be an integer from 1 to 1000000")
    if type(quantity) is not int or not 1 <= quantity <= 100:
        raise RequestError(422, "invalid_quote", "quantity must be an integer from 1 to 100")
    return {
        "currency": "EUR",
        "unit_price_cents": price,
        "quantity": quantity,
        "total_cents": price * quantity,
    }


def lambda_handler(event: object, context: object) -> HttpResponse:
    envelope = as_object(event)
    if envelope.get("version") != "2.0":
        raise ValueError("Expected HTTP API payload version 2.0")
    request_context = as_object(envelope.get("requestContext"))
    http = as_object(request_context.get("http"))
    request_id = request_context.get("requestId")
    route = envelope.get("routeKey")
    if not isinstance(request_id, str) or not request_id:
        raise ValueError("Missing API Gateway requestId")
    if not isinstance(route, str) or not isinstance(http.get("method"), str):
        raise ValueError("Missing routeKey or HTTP method")

    # Log only correlation and outcome fields. Never log the event, Authorization,
    # session token, full headers, or request body.
    log_fields = {
        "api_request_id": request_id,
        "lambda_request_id": getattr(context, "aws_request_id", "local"),
        "route": route,
    }
    try:
        if route == "GET /health" and http["method"] == "GET":
            result = response(200, {"status": "ok"}, request_id)
        elif route == "POST /quotes" and http["method"] == "POST":
            result = response(200, calculate_quote(read_json_body(envelope)), request_id)
        else:
            # Normally unmatched routes are rejected by API Gateway before Lambda.
            result = response(404, {"error": "not_found"}, request_id)
    except RequestError as error:
        result = response(error.status, {"error": error.code, "message": str(error)}, request_id)
    except Exception as error:
        logger.error(json.dumps({**log_fields, "event": "request_failed", "error_type": type(error).__name__}))
        raise  # Unexpected defects must not be reported as successful HTTP 200.

    logger.info(json.dumps({**log_fields, "event": "request_completed", "status": result["statusCode"]}))
    return result
