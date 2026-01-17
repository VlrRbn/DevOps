# lesson_47

---

# EC2 Hardening: IMDSv2 Only + Practical Tests

**Date:** 2025-01-16

**Topic:** EC2 Metadata Hardening: From IMDSv1 to IMDSv2 (with Tests)

## Goal

- Force EC2 to use **IMDSv2 only**
- Understand what breaks and why
- Verify from inside the instance that IMDSv1 is blocked and IMDSv2 works

---

### 1) Enable IMDSv2-only on instances (Terraform)

On `aws_instance.web` add:

```hcl
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }
```

Explanation:

| Setting | What it does | Why it matters |
| --- | --- | --- |
| `http_tokens = "required"` | IMDSv2 is required | IMDSv1 (no token) is blocked → basic protection against SSRF |
| `http_put_response_hop_limit = 1` | metadata/token can’t be forwarded across extra hops | mitigates some SSRF scenarios via proxies/containers/iptables tricks |
| `http_endpoint = "enabled"` | metadata is available at all | usually needed (IAM role creds, userdata scripts, agents). Disabling it can break anything that reads IMDS |

### 2) Apply

```bash
terraform fmt -recursive
terraform apply

```

Important: if user data / scripts read from IMDS, then after the apply they must use IMDSv2.

---

### 3) Prove IMDSv1 is blocked

Connect to the instance (SSM session), then run:

```bash
aws ssm describe-instance-information
aws ssm start-session --target i-07ffe5626f2af4b4c

# IMDSv1 attempt (should fail / be rejected)
curl -sS --max-time 2 http://169.254.169.254/latest/meta-data/ -o /dev/null -w "code=%{http_code}\n"

# or the same
curl -sS -o /dev/null -w "code=%{http_code}\n" --max-time 2 http://169.254.169.254/latest/meta-data/

```

**Common outcomes:**

| Result | What it means in practice |
| --- | --- |
| `code=000` | **No HTTP response** (timeout, no route, blocked by a filter/iptables, not running on EC2, or the container/namespace can’t reach `169.254.169.254`) |
| `code=401` | **IMDS is reachable but requires an IMDSv2 token** (`http_tokens = required`) |
| `code=200` | IMDS responded (usually means the IMDS endpoint is reachable; without a token this often implies an IMDSv1-style request is being allowed) |
| `code=403` | **Access denied by policy/context**, often due to **hop limit** (e.g., the request is not “direct” but goes through an extra hop/proxy/container) or other IMDS restrictions |
| `code=404` | Path/resource not found (rare unless the URL is wrong) |

---

### 4) Prove IMDSv2 works (token flow)

```bash
TOKEN="$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")"

curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id

```

---

### 5) Quick sanity check (role creds still accessible via IMDSv2)

If instance has an IAM role:

```bash
TOKEN="$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")"
ROLE_NAME="$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/)"

curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME" | head -n 5
  
# or REDACTED
curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME" \
| sed -E 's/"(AccessKeyId|SecretAccessKey|Token)" *: *"[^"]+"/"\1":"REDACTED"/g'

# 401
curl -sS -o /dev/null -w "code=%{http_code}\n" http://169.254.169.254/latest/meta-data/

# 200
TOKEN="$(curl -sS -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")"
curl -sS -o /dev/null -w "code=%{http_code}\n" \
  -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/

```

(Do not paste this anywhere — it contains temporary credentials.)

---

## 6) Mini script: “prove 401/200”

```bash
cat <<'EOF' > /tmp/imds-test.sh
#!/usr/bin/env bash
set -euo pipefail

echo "[1] IMDSv1-style request (no token) should be 401"
curl -sS -o /dev/null -w "code=%{http_code}\n" http://169.254.169.254/latest/meta-data/

echo "[2] Get IMDSv2 token"
TOKEN="$(curl -sS -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")"

echo "[3] IMDSv2 request should be 200"
curl -sS -o /dev/null -w "code=%{http_code}\n" \
  -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/

echo "[4] instance-id:"
curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id
echo
EOF

chmod +x /tmp/imds-test.sh
bash /tmp/imds-test.sh

```

---

### A) Break-test

- Find any script/code what have that calls IMDS without a token (IMDSv1 style)
- Fix it to use IMDSv2 (token first)

| Before (will break) | After (IMDSv2 OK) |
| --- | --- |
| `curl -sS http://169.254.169.254/latest/meta-data/instance-id` | `curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id` |

### B) Document a security note

Add to lesson notes:

- Why IMDSv2 matters (SSRF protection baseline)
- Your default setting: “IMDSv2 required”

Run a container that tries to read IMDS, it “dies” with `hop_limit = 1`. That’s not a bug — it’s a feature.

---

## Pitfalls

- Some tools/scripts silently rely on IMDSv1 and start failing.
- If you ever do containers that query IMDS, hop limit matters.

---

## Security notes

- Why IMDSv2: the token-based model reduces SSRF risk — it’s harder for an attacker to pull metadata/credentials by simply “hitting a URL.”
- Default: require IMDSv2 for any EC2 that has an IAM role or any sensitive user-data scripts.
- SSM-only access: inbound is closed and SSH is disabled — IMDSv2 complements that model by reducing the chance of credential leakage via SSRF in an application.

---

## Acceptance Criteria

- [ ]  `curl .../meta-data/` without a token returns `401` (not `000`).
- [ ]  A token can be fetched (`PUT /latest/api/token`), and requests with the token return `200`.
- [ ]  `instance-id` can be read via IMDSv2.
- [ ]  (If an IAM role is attached) `iam/security-credentials/` can be listed via IMDSv2.