# access_policy

---

## Access Policy: EC2 Access via AWS SSM Session Manager

> Access to private EC2 instances is IAM-controlled and provided exclusively via AWS SSM Session Manager. No SSH, no bastion hosts, no inbound access, no internet egress.
> 

### Access model

Доступ к EC2 осуществляется **исключительно через AWS Systems Manager Session Manager**.

- SSH (`22/tcp`) — запрещён
- Bastion hosts — не используются
- Inbound access к EC2 — отсутствует
- Доступ — только через IAM + SSM

---

### Who can start a session

Только IAM principals (users / roles), которым явно разрешено:

- `ssm:StartSession`
- `ssm:DescribeSessions`
- `ssm:TerminateSession`

Доступ предоставляется:

- через IAM policies,
- с привязкой к environment / account,
- при необходимости — с условиями (tags, MFA, time-based access).

---

### Why this model is used

- **Security:**
    
    Нет открытых inbound портов, нет SSH-ключей, нет bastion attack surface.
    
- **Least privilege:**
    
    Доступ есть только у тех, кому он реально нужен, и только когда разрешено IAM.
    
- **Network isolation:**
    
    EC2 не имеет internet egress; доступ обеспечивается через VPC Interface Endpoints (PrivateLink).
    

---

### Enforcement

- EC2 instances имеют IAM role с `AmazonSSMManagedInstanceCore`
- Все SSH ingress rules удалены
- NAT Gateway не используется (endpoint-only egress)
- Любой доступ к instance = **IAM decision**

---

## IAM policy: SSM Session Access

Полный интерактивный доступ к EC2 через Session Manager

**Чего НЕ даёт:** SSH, inbound, доступ к самим EC2 API

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowStartSSMSession",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession",
        "ssm:ResumeSession",
        "ssm:TerminateSession",
        "ssm:DescribeSessions",
        "ssm:GetConnectionStatus"
      ],
      "Resource": "*"
    }
  ]
}

```

- Пользователь **может подключаться к EC2**
- Может **закрывать свои сессии**
- **Не может**:
    - логиниться по SSH
    - трогать Security Groups
    - запускать/останавливать инстансы

---

## IAM policy: SSM Session

Доступ **только к конкретным EC2**, по тегам (если нет нужного тега - сессия не стартует)

### EC2 tagging requirement

```
SSMAccess  = true
Environment = prod

```

### IAM policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSSMSessionOnlyToTaggedInstances",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ssm:resourceTag/SSMAccess": "true",
          "ssm:resourceTag/Environment": "prod"
        }
      }
    },
    {
      "Sid": "AllowSessionLifecycle",
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeSessions",
        "ssm:TerminateSession",
        "ssm:GetConnectionStatus"
      ],
      "Resource": "*"
    }
  ]
}

```

- нельзя “случайно” зайти не туда
- нельзя подключиться к любому EC2
- доступ **строго по тегам**

---

## MFA enforcement - сессии **только с MFA**.

```json
"Condition": {
  "Bool": {
    "aws:MultiFactorAuthPresent": "true"
  }
}

```