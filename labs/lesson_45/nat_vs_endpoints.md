# nat_vs_endpoints

## Document “NAT vs Endpoints” — NAT egress vs Endpoint-only egress

---

### 1. NAT-based egress

**Что это:** приватные инстансы ходят наружу через NAT Gateway (0.0.0.0/0 → NAT).

**Плюсы**

- Работает для всего: yum/apt, pip/npm, внешние API, time sync, сторонние агенты.
- Меньше думать о том, какие сервисы нужны — интернет “покрывает всё”.

**Минусы**

- **Стоимость NAT** (особенно на трафике).
- Расширенная поверхность egress.
- Аудит хуже: приходится доказывать, что egress контролируется.

**Когда выбирать**

- Dev/PoC среды.
- Workloads, которым реально нужен постоянный доступ к внешним API/репозиториям.
- Когда скорость важнее egress-минимизации.

---

### 2. Endpoint-only egress (PrivateLink)

**Что это:** **нет 0.0.0.0/0 на NAT/IGW**, инстансы общаются только с тем, что явно дали через:

- Interface endpoints (PrivateLink) для AWS API,
- Gateway endpoints (S3/DynamoDB),
- плюс внутренние сервисы в VPC.

**Плюсы**

- **Реально “без интернета”**: проще аудит и модель угроз.
- Egress становится **явно перечисленным** (allow-list).
- Часто дешевле на трафике, и предсказуемее.

**Минусы**

- Нужно понимать зависимости (какие AWS сервисы и endpoints нужны).
- Bootstrap сложнее (пакеты, обновления, репозитории).
- Иногда надо добавлять endpoints “по факту” (CloudWatch, KMS, S3 и т.д.).

**Когда выбирать**

- Prod / regulated environments.
- Когда политика: “никакого интернета из приватных подсетей”.
- Когда нужен управляемый egress через allow-list.

---

### Минимум для SSM Session Manager без NAT

Чтобы Session Manager работал при **полном отсутствии интернет-маршрута**, нужны:

- Interface endpoints: `ssm`, `ssmmessages`, `ec2messages`
- `private_dns_enabled = true`
- SG/egress 443 настроены правильно