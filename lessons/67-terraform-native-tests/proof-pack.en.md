# Lesson 67 Proof Pack

Run from:

```bash
cd lessons/67-terraform-native-tests/lab_67/terraform/modules/network
```

Create evidence folder:

```bash
export EVIDENCE_DIR="../../../../evidence/l67-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
```

## 1. Tooling and Init

```bash
terraform version > "$EVIDENCE_DIR/terraform-version.txt" 2>&1
terraform init -backend=false -input=false -no-color > "$EVIDENCE_DIR/terraform-init.txt" 2>&1
```

## 2. Native Tests

```bash
terraform test -no-color > "$EVIDENCE_DIR/terraform-test.txt" 2>&1
terraform test -verbose -no-color > "$EVIDENCE_DIR/terraform-test-verbose.txt" 2>&1
```

Expected:

```text
Success! 13 passed, 0 failed.
```

## 3. Drill Evidence

For each drill in the lesson, save the failing test output before reverting the intentional break:

```bash
terraform test -no-color > "$EVIDENCE_DIR/drill-name.txt" 2>&1 || true
```

Recommended drill files:

```text
drill-bad-project-name.txt
drill-remove-ami-validation.txt
drill-one-private-subnet.txt
drill-reserved-tag.txt
drill-output-rename.txt
```

## 4. Decision

```bash
cat > "$EVIDENCE_DIR/decision.txt" <<'EOF_DECISION'
Decision: PASS
Lesson: 67-terraform-native-tests
CI run URL: <paste GitHub Actions run URL or N/A for local-only proof>

Evidence:
- native tests run from modules/network
- provider is mocked
- valid contract input test passes
- invalid input tests pass through expect_failures
- output contract test passes with mocked apply
- active CI workflow is .github/workflows/lesson67-terraform-native-tests.yml
EOF_DECISION
```

Do not commit `.terraform/`, state, local tfvars, backend files, or real environment data.
