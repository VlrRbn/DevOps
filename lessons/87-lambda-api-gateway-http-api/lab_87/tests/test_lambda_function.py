import base64
import copy
import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB / "app"))
import lambda_function as app  # noqa: E402


class HttpApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.event = json.loads((LAB / "events" / "quote-v2.json").read_text())
        self.context = SimpleNamespace(aws_request_id="lambda-test-request")

    def invoke(self):
        return app.lambda_handler(self.event, self.context)

    def test_quote_response_has_explicit_proxy_contract(self):
        result = self.invoke()
        self.assertEqual(result["statusCode"], 200)
        self.assertIsInstance(result["body"], str)
        self.assertFalse(result["isBase64Encoded"])
        self.assertEqual(json.loads(result["body"])["total_cents"], 3750)
        self.assertEqual(result["headers"]["x-request-id"], "api-test-request")

    def test_health_without_body(self):
        self.event = json.loads((LAB / "events" / "health-v2.json").read_text())
        self.assertEqual(json.loads(self.invoke()["body"])["status"], "ok")

    def test_external_envelopes_are_validated_at_runtime(self):
        for event in (None, "text", [], {}, {"Records": []}, {"version": "1.0"}):
            with self.subTest(event=event), self.assertRaises(ValueError):
                app.lambda_handler(event, self.context)

    def test_missing_request_context_is_rejected(self):
        self.event["requestContext"] = None
        with self.assertRaises(ValueError):
            self.invoke()

    def test_invalid_json_and_non_objects_return_400(self):
        for body in ("{", "null", "[]", '"text"', ""):
            with self.subTest(body=body):
                self.event["body"] = body
                self.assertEqual(self.invoke()["statusCode"], 400)

    def test_semantic_validation_rejects_booleans_floats_and_bad_ranges(self):
        for key, value in (("quantity", True), ("quantity", 1.5), ("quantity", 0),
                           ("quantity", 101), ("unit_price_cents", -1),
                           ("unit_price_cents", 1_000_001), ("unit_price_cents", "1250")):
            payload = {"quantity": 3, "unit_price_cents": 1250, key: value}
            with self.subTest(payload=payload):
                self.event["body"] = json.dumps(payload)
                self.assertEqual(self.invoke()["statusCode"], 422)

    def test_unknown_or_missing_fields_return_422(self):
        for payload in ({"quantity": 3}, {"quantity": 3, "unit_price_cents": 1250, "coupon": "free"}):
            self.event["body"] = json.dumps(payload)
            self.assertEqual(self.invoke()["statusCode"], 422)

    def test_media_type_is_checked_and_charset_is_supported(self):
        self.event["headers"]["content-type"] = "text/plain"
        self.assertEqual(self.invoke()["statusCode"], 415)
        self.event["headers"]["content-type"] = "application/json; charset=utf-8"
        self.assertEqual(self.invoke()["statusCode"], 200)

    def test_base64_payload_is_decoded(self):
        self.event["body"] = base64.b64encode(self.event["body"].encode()).decode()
        self.event["isBase64Encoded"] = True
        self.assertEqual(json.loads(self.invoke()["body"])["total_cents"], 3750)

    def test_invalid_base64_or_utf8_returns_400(self):
        self.event["isBase64Encoded"] = True
        for body in ("!not-base64!", base64.b64encode(b"\xff").decode()):
            self.event["body"] = body
            self.assertEqual(self.invoke()["statusCode"], 400)

    def test_body_size_limit_covers_plain_and_base64_data(self):
        raw = b" " * (app.MAX_BODY_BYTES + 1)
        for encoded in (False, True):
            self.event["body"] = base64.b64encode(raw).decode() if encoded else raw.decode()
            self.event["isBase64Encoded"] = encoded
            self.assertEqual(self.invoke()["statusCode"], 413)

    def test_unknown_route_has_defensive_404(self):
        self.event["routeKey"] = "POST /missing"
        self.assertEqual(self.invoke()["statusCode"], 404)

    def test_logs_correlate_requests_without_payloads_or_credentials(self):
        self.event["headers"]["authorization"] = "DO-NOT-LOG-HEADER"
        self.event["body"] = '{"private":"DO-NOT-LOG-BODY"}'
        with self.assertLogs(app.logger, level="INFO") as logs:
            self.invoke()
        output = "\n".join(logs.output)
        self.assertIn("api-test-request", output)
        self.assertIn("lambda-test-request", output)
        self.assertNotIn("DO-NOT-LOG", output)

    def test_unexpected_defect_propagates_instead_of_becoming_200(self):
        with patch.object(app, "calculate_quote", side_effect=RuntimeError("defect")):
            with self.assertLogs(app.logger, level="ERROR"), self.assertRaises(RuntimeError):
                self.invoke()

    def test_repeating_calculation_has_same_business_result(self):
        first = json.loads(self.invoke()["body"])
        self.event = copy.deepcopy(self.event)
        self.event["requestContext"]["requestId"] = "another-request"
        second = json.loads(self.invoke()["body"])
        self.assertEqual(first["total_cents"], second["total_cents"])
        self.assertNotEqual(first["request_id"], second["request_id"])


if __name__ == "__main__":
    unittest.main()
