# Proof Pack For Lesson 60

## What It Is

`Proof Pack` for lesson 60 is the minimum artifact set that proves:

- backend bucket was created correctly;
- Terraform env was pointed at remote backend;
- state is now read from S3, not trusted from local files;
- locking and versioning were observed, not just assumed.

## Why It Matters

1. Confirms that remote state is really active.
2. Gives you recovery evidence if something goes wrong later.
3. Builds the habit of operational proof instead of memory.

## When To Collect

Collect at least once after migration, and once during locking drill.

Recommended checkpoints:

1. After `backend-bootstrap` apply.
2. After `terraform init -backend-config=backend.hcl -migrate-state`.
3. During lock contention test.
4. During state version history check.

## What Must Be Included

- bootstrap apply output
- bucket security checks:
  - versioning
  - public access block
  - encryption
- migration output from `terraform init -backend-config=backend.hcl -migrate-state`
- `terraform state pull` sample
- S3 object existence check for `terraform.tfstate`
- lock contention output
- state version history output

## Standard Collection (ready-to-run commands)

Run from:

`lessons/60-remote-state-and-locking/lab_60/terraform/envs`

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l60-proof-$STAMP"
mkdir -p "$OUT"

export AWS_PAGER=""
export STATE_BUCKET="vlrrbn-tfstate-179151669003-eu-west-1"
export STATE_KEY="lab60/dev/full/terraform.tfstate"

# 1) Backend migration output
terraform init -backend-config=backend.hcl -migrate-state \
  2>&1 | tee "$OUT/init-migrate.log"

# 2) State pull sample
terraform state pull | head -n 40 > "$OUT/state-pull-head.txt"

# 3) Bucket versioning
aws s3api get-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --region eu-west-1 \
  --no-cli-pager > "$OUT/bucket-versioning.json"

# 4) Bucket public access block
aws s3api get-public-access-block \
  --bucket "$STATE_BUCKET" \
  --region eu-west-1 \
  --no-cli-pager > "$OUT/public-access-block.json"

# 5) Bucket encryption
aws s3api get-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --region eu-west-1 \
  --no-cli-pager \
  --cli-connect-timeout 5 \
  --cli-read-timeout 10 > "$OUT/bucket-encryption.json"

# 6) State object presence
aws s3 ls "s3://$STATE_BUCKET/$STATE_KEY" > "$OUT/state-object.txt"

# 7) State version history
aws s3api list-object-versions \
  --bucket "$STATE_BUCKET" \
  --prefix "$STATE_KEY" \
  --region eu-west-1 \
  --no-cli-pager > "$OUT/object-versions.json"
```

## Locking Drill Evidence

Use two terminals.

Terminal A:

```bash
terraform apply
```

Leave it waiting at confirmation.

Terminal B:

```bash
terraform plan -lock-timeout=30s 2>&1 | tee "$OUT/lock-contention.txt"
```

Optional:

```bash
aws s3api list-object-versions \
  --bucket "$STATE_BUCKET" \
  --prefix "${STATE_KEY}.tflock" \
  --region eu-west-1 \
  --no-cli-pager > "$OUT/lockfile-versions.json"
```

Important:

- this drill needs a non-empty plan in terminal A;
- if terminal A says `No changes`, first introduce one harmless temporary diff.

## Decision File (recommended)

```bash
cat > "$OUT/decision.txt" <<EOF
decision=REMOTE_BACKEND_OK
reason=state pull works, S3 object exists, lock contention reproduced, versioning visible
timestamp=$(date -Is)
operator=$(whoami)
EOF
```

## Archive For Storage/Handoff

```bash
tar -C /tmp -czf "/tmp/$(basename "$OUT").tar.gz" "$(basename "$OUT")"
echo "saved: /tmp/$(basename "$OUT").tar.gz"
```

## Quick Check

- Does `init-migrate.log` show backend migration?
- Does `state-pull-head.txt` prove Terraform is reading backend state?
- Does `state-object.txt` prove the S3 object exists?
- Do bucket checks show versioning + encryption + public access block?
- Does `lock-contention.txt` show real contention or timeout behavior?
- Does `object-versions.json` show version history?
