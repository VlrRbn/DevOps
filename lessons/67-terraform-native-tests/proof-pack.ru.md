# Proof Pack Урока 67

Запускай из:

```bash
cd lessons/67-terraform-native-tests/lab_67/terraform/modules/network
```

Создай evidence folder:

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

Ожидаемо:

```text
Success! 13 passed, 0 failed.
```

## 3. Drill Evidence

Для каждого drill из урока сохрани output падающего test до того, как вернёшь intentional break назад:

```bash
terraform test -no-color > "$EVIDENCE_DIR/drill-name.txt" 2>&1 || true
```

Рекомендуемые файлы:

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
CI run URL: <paste GitHub Actions run URL>

Evidence:
- native tests run from modules/network
- provider is mocked
- valid contract input test passes
- invalid input tests pass through expect_failures
- output contract test passes with mocked apply
- active CI workflow is .github/workflows/lesson67-terraform-native-tests.yml
EOF_DECISION
```

Не коммить `.terraform/`, state, local tfvars, backend files или real environment data.
