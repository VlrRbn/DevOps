"""Check credential handling and HTTP failure propagation without AWS access."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "invoke-api.sh"


class SignedRequestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "request.json").write_text('{"quantity":3,"unit_price_cents":1250}')
        # Synthetic strings only; never resolve the real developer AWS profile.
        (self.root / "aws").write_text('''#!/usr/bin/env bash
[[ "$*" == "configure export-credentials --format process" ]] || exit 2
echo '{"AccessKeyId":"FAKEACCESS","SecretAccessKey":"FAKESECRET","SessionToken":"FAKETOKEN"}'
''')
        (self.root / "curl").write_text('''#!/usr/bin/env bash
set -euo pipefail
[[ "$*" != *FAKESECRET* && "$*" != *FAKETOKEN* ]] || exit 98
config="$(cat)"
[[ "$config" == *'user = "FAKEACCESS:FAKESECRET"'* ]] || exit 97
[[ "$config" == *'X-Amz-Security-Token: FAKETOKEN'* ]] || exit 96
if [[ "${TEST_HTTP_STATUS:-200}" == 000 ]]; then
  echo 000
  exit "${TEST_CURL_EXIT:-7}"
fi
while (( $# )); do
  case "$1" in
    --output) shift; echo '{"result":"synthetic"}' >"$1" ;;
    --dump-header) shift; echo 'HTTP/2 synthetic' >"$1" ;;
  esac
  shift
done
echo "${TEST_HTTP_STATUS:-200}"
exit "${TEST_CURL_EXIT:-0}"
''')
        for name in ("aws", "curl"):
            (self.root / name).chmod(0o700)
        self.env = {**os.environ, "PATH": f"{self.root}:{os.environ['PATH']}"}

    def run_script(self, endpoint="https://abc123.execute-api.eu-west-1.amazonaws.com"):
        return subprocess.run(
            ["bash", "-x", str(SCRIPT), endpoint, "eu-west-1",
             str(self.root / "request.json"), str(self.root / "response")],
            env=self.env, text=True, capture_output=True, check=False,
        )

    def test_success_keeps_credentials_out_of_output_and_artifacts(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HTTP=200", result.stdout)
        artifacts = "".join(p.read_text() for p in self.root.glob("response.*"))
        for secret in ("FAKEACCESS", "FAKESECRET", "FAKETOKEN"):
            self.assertNotIn(secret, result.stdout + result.stderr + artifacts)

    def test_http_error_retains_evidence_and_nonzero_exit(self):
        self.env.update(TEST_HTTP_STATUS="403", TEST_CURL_EXIT="22")
        result = self.run_script()
        self.assertEqual(result.returncode, 22)
        self.assertEqual((self.root / "response.status.txt").read_text().strip(), "403")
        self.assertTrue((self.root / "response.body.json").exists())

    def test_network_failure_is_not_reported_as_success(self):
        for name in ("body.json", "headers.txt"):
            (self.root / f"response.{name}").write_text("previous successful response")
        self.env.update(TEST_HTTP_STATUS="000", TEST_CURL_EXIT="7")
        self.assertEqual(self.run_script().returncode, 7)
        for name in ("body.json", "headers.txt"):
            self.assertEqual((self.root / f"response.{name}").read_text(), "")
        self.assertEqual((self.root / "response.status.txt").read_text().strip(), "000")

    def test_other_hosts_and_region_mismatch_are_rejected(self):
        for endpoint in ("https://example.com", "http://abc123.execute-api.eu-west-1.amazonaws.com",
                         "https://abc123.execute-api.us-east-1.amazonaws.com"):
            with self.subTest(endpoint=endpoint):
                self.assertEqual(self.run_script(endpoint).returncode, 2)


if __name__ == "__main__":
    unittest.main()
