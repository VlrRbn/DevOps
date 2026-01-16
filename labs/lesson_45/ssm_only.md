# ssm_only

## Architecture documented as “SSM-only”

### SSM-only access model (no SSH, no bastion, no Internet)

**Intent:** обеспечить управляемый доступ к приватным EC2 **без публичных IP**, **без SSH**, **без bastion**, **без NAT/Internet egress** — только через **AWS Systems Manager Session Manager**.

---

## Key decisions

- **Inbound access to instances — запрещён** (нет SSH, нет inbound rules под админку).
- Доступ выполняется через **IAM (who can start sessions)** + **SSM Agent (instance initiates outbound)**.
- EC2 instances находятся в **private subnets** и **не имеют маршрута в IGW/NAT**.
- Для связи SSM Agent с AWS используются **VPC Interface Endpoints (PrivateLink)**:
    - `com.amazonaws.${region}.ssm`
    - `com.amazonaws.${region}.ssmmessages`
    - `com.amazonaws.${region}.ec2messages`

---

## Network flow

1. Админ запускает `aws ssm start-session` (или через Console).
2. SSM управляет сессией через сервисы SSM.
3. **SSM Agent на EC2** устанавливает HTTPS (443) соединения **к приватным DNS-именам**, которые резолвятся в **private IP интерфейсных endpoints** внутри VPC.
4. Трафик остаётся **внутри AWS backbone**, без выхода в интернет.

---

## Security controls

- **Instance IAM role:** `AmazonSSMManagedInstanceCore`.
- **VPC DNS:** `enable_dns_support = true`, `enable_dns_hostnames = true`.
- **Endpoint SG:** inbound **443 from VPC CIDR** (или лучше — from instance SG), outbound — по необходимости.
- **Instance SG:** egress **443** (until endpoints).
- **Private DNS enabled:** `private_dns_enabled = true` on endpoints (иначе агент попытается ходить в public endpoints → без NAT всё умрёт).

---

## Operational notes

- Если ставить пакеты в user-data через интернет-репозитории — **первый бутстрап потребует `egress`** (NAT) **или** использовть:
    - готовый AMI (golden) с SSM Agent и нужными пакетами,
    - S3 Gateway Endpoint + приватные репозитории,
    - CodeArtifact/Repo внутри VPC и т.д.
- После бутстрапа NAT можно выключать: доступ по SSM сохранится.