# LAB54 -> LAB55 Postmortem (SSM Proxy + Rolling Fleet)

## Цель документа
Кратко зафиксировать:
- какую проблему мы получили при переходе с `lab_54`,
- почему она проявилась,
- что именно поменяли в `lab_55`,
- как проверить, что исправление полное.

Это не `README`, а технический разбор инцидента и финального решения.

---

## Симптомы
- `aws ssm start-session` периодически падал с `TargetNotConnected` или `ConnectionLost`.
- Иногда `describe-instance-information` показывал `PingStatus=None`.
- После `terraform apply` поведение было нестабильным: временно работало, затем отваливалось.
- Terraform входил в цикл изменений SG (`создать 4 правила -> изменить SG -> снова создать`).

---

## Что было в `lab_54` и почему это маскировало проблему

### 1) Скрытая связка AMI proxy с web
В `lab_54` proxy AMI был с fallback:

```hcl
ami = coalesce(var.ssm_proxy_ami_id, var.web_ami_blue_id)
```

Итог: если `ssm_proxy_ami_id` не задан, proxy запускался на web AMI (`blue`), и это скрывало проблемы отдельного proxy-образа.

### 2) Blue/Green-архитектура и иные точки изменения
`lab_54` был с двумя флотами (blue/green), weighted listener и NAT-логикой.  
При переходе к single fleet rolling (`lab_55`) эти скрытые зависимости и дрифт стали заметны.

---

## Корневые причины в `lab_55` (по факту диагностики)

### 1) Нестабильная установка SSM Agent в proxy AMI
- В базовых Ubuntu образах агент может быть через `snap`.
- Попытка поставить `.deb` поверх `snap` даёт конфликт.
- Регистрационные артефакты агента внутри AMI могли переноситься на новые инстансы.

### 2) Конфликт модели управления Security Group
- Одновременно использовались:
  - inline SG rules в `aws_security_group`,
  - отдельные ресурсы `aws_security_group_rule`.
- Это давало цикл Terraform и временные сетевые несогласованности.

### 3) Runtime-флап регистрации/канала SSM
- На части запусков был таймаут до `ssm/ssmmessages` во время инициализации агента.
- Вкупе с пунктами выше это давало непредсказуемый результат после `apply`.

---

## Что исправил (финальное состояние)

## 1) Декуплинг AMI proxy от web
Файл: `terraform/modules/network/main.tf`

Было:
```hcl
ami = coalesce(var.ssm_proxy_ami_id, var.web_ami_blue_id)
```

Стало:
```hcl
ami = var.ssm_proxy_ami_id
```

Итог: смена `web_ami_id` больше не влияет на `ssm_proxy`.

## 2) Переход `lab_55` на single fleet rolling
- Один `Launch Template`, один `ASG`, один `Target Group`.
- Обновление версии через `ASG Instance Refresh`.

Итог: урок 55 теперь про rolling обновление внутри одного флота, а не blue/green.

## 3) Исправление proxy AMI (SSM Agent)
Файл: `packer/ssm_proxy/scripts/install-ssm-agent.sh`

Сделано:
- Удаление `snap`-варианта агента (если есть).
- Установка официального регионального `.deb` агента.
- Принудительный systemd restart policy (`Restart=always`).
- Очистка registration/log state перед снимком AMI:
  - `/var/lib/amazon/ssm/*`
  - `/var/log/amazon/ssm/*`

Итог: новые инстансы из AMI регистрируются как “чистые”.

## 4) Нормализация SG для proxy/endpoints без архитектурного расширения доступа
Файл: `terraform/modules/network/main.tf`

Сделано:
- Убрана конфликтующая схема, вызывавшая Terraform loop.
- Сохранён строгий security intent:
  - proxy egress `443` только к `ssm_endpoint` SG (не ко всему `vpc_cidr`),
  - отдельные ingress-правила в endpoint SG для proxy/web при необходимости.

Итог: нет бесконечного цикла в планах и нет расширения прав “на весь VPC:443”.

---

## Проверка, что фикс полный

## 1) Terraform стабилен
```bash
terraform plan
```
Ожидаемо: нет повторяющегося цикла правил SG.

## 2) Proxy online в SSM
```bash
IID=$(terraform output -raw ssm_proxy_instance_id)
aws --region eu-west-1 ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$IID" \
  --query 'InstanceInformationList[0].PingStatus' --output text
```
Ожидаемо: `Online`.

## 3) Start session работает
```bash
aws --region eu-west-1 ssm start-session --target "$IID"
```
Ожидаемо: интерактивная сессия без `TargetNotConnected`.

## 4) Смена `web_ami_id` не ломает proxy
1. Меняем только `web_ami_id` в `terraform.tfvars`.
2. `terraform apply`.
3. Повторяем пункты 2 и 3 выше.

Ожидаемо: `ssm_proxy` остаётся рабочим.

---

## Вывод
Проблема была не в одной точке, а в комбинации:
- скрытая историческая связка AMI,
- нестабильный lifecycle SSM Agent в proxy AMI,
- конфликт схемы управления SG.

В `lab_55` это разрезано и стабилизировано:
- proxy AMI независим,
- rolling обновление реально single-fleet,
- SSM канал и Terraform-планы предсказуемы.
