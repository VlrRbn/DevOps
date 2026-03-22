# Proof Pack Для Lesson 60

## Что Это

`Proof Pack` для lesson 60 — это минимальный набор артефактов, который доказывает:

- backend bucket поднят корректно;
- Terraform env действительно переведён на remote backend;
- state теперь читается из S3, а не из старых local файлов;
- locking и versioning были не просто настроены, а реально проверены.

## Зачем Это Нужно

1. Подтверждает, что remote state реально активен.
2. Даёт recovery-артефакты, если потом что-то сломается.
3. Приучает к operational proof вместо памяти.

## Когда Собирать

Минимум один раз после миграции и один раз во время locking drill.

Рекомендуемые точки:

1. После `backend-bootstrap` apply.
2. После `terraform init -backend-config=backend.hcl -migrate-state`.
3. Во время lock contention test.
4. Во время проверки state version history.

## Что Должно Входить

- output bootstrap apply
- bucket security checks:
  - versioning
  - public access block
  - encryption
- migration output из `terraform init -backend-config=backend.hcl -migrate-state`
- sample вывода `terraform state pull`
- проверка существования `terraform.tfstate` в S3
- output lock contention
- output state version history

## Стандартный Сбор (готовые команды)

Запускать из:

`lessons/60-remote-state-and-locking/lab_60/terraform/envs`

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l60-proof-$STAMP"
mkdir -p "$OUT"

export AWS_PAGER=""
export STATE_BUCKET="vlrrbn-tfstate-123456789012-eu-west-1"
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

# 6) Проверка state object
aws s3 ls "s3://$STATE_BUCKET/$STATE_KEY" > "$OUT/state-object.txt"

# 7) История версий state
aws s3api list-object-versions \
  --bucket "$STATE_BUCKET" \
  --prefix "$STATE_KEY" \
  --region eu-west-1 \
  --no-cli-pager > "$OUT/object-versions.json"
```

## Артефакты Для Locking Drill

Используй два терминала.

Терминал A:

```bash
terraform apply
```

Оставь его ждать подтверждения.

Терминал B:

```bash
terraform plan -lock-timeout=30s 2>&1 | tee "$OUT/lock-contention.txt"
```

Опционально:

```bash
aws s3api list-object-versions \
  --bucket "$STATE_BUCKET" \
  --prefix "${STATE_KEY}.tflock" \
  --region eu-west-1 \
  --no-cli-pager > "$OUT/lockfile-versions.json"
```

Важно:

- этот drill требует non-empty plan в терминале A;
- если terminal A пишет `No changes`, сначала внеси одно безопасное временное изменение.

## Файл Решения (рекомендуется)

```bash
cat > "$OUT/decision.txt" <<EOF
decision=REMOTE_BACKEND_OK
reason=state pull works, S3 object exists, lock contention reproduced, versioning visible
timestamp=$(date -Is)
operator=$(whoami)
EOF
```

## Упаковка Для Хранения/Передачи

```bash
tar -C /tmp -czf "/tmp/$(basename "$OUT").tar.gz" "$(basename "$OUT")"
echo "saved: /tmp/$(basename "$OUT").tar.gz"
```

## Быстрая Проверка

- Показывает ли `init-migrate.log`, что миграция backend произошла?
- Доказывает ли `state-pull-head.txt`, что Terraform читает backend state?
- Доказывает ли `state-object.txt`, что S3 object существует?
- Показывают ли bucket-checks versioning + encryption + public access block?
- Есть ли в `lock-contention.txt` реальный contention или timeout?
- Видна ли история версий в `object-versions.json`?
