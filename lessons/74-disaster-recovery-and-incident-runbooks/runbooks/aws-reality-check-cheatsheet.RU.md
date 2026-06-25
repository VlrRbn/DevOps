# AWS Reality Check Cheatsheet

Какой AWS CLI command использовать, чтобы проверить реальное состояние ресурса в AWS?

Terraform показывает, что он думает через `state` и `plan`.

AWS reality check показывает, что реально существует в AWS прямо сейчас.

## Главная модель

```text
Terraform resource type -> AWS service -> describe/get/list command
```

Примеры:

```text
aws_autoscaling_group -> autoscaling -> describe-auto-scaling-groups
aws_lb_target_group   -> elbv2       -> describe-target-health
aws_iam_role          -> iam         -> get-role
aws_s3_bucket         -> s3api       -> head-bucket / get-bucket-*
```

## Как искать команду

Через AWS CLI help:

```bash
aws help
aws elbv2 help
aws elbv2 describe-target-health help
aws autoscaling help
aws iam help
```

Быстрый поиск:

```bash
aws elbv2 help | grep describe
aws autoscaling help | grep describe
aws iam help | grep role
aws s3api help | grep bucket
```

## Сеть и compute

| Terraform resource | AWS CLI reality check | Что смотреть |
| --- | --- | --- |
| `aws_vpc` | `aws ec2 describe-vpcs --vpc-ids <vpc-id>` | VPC exists, CIDR, tags, state |
| `aws_subnet` | `aws ec2 describe-subnets --subnet-ids <subnet-id>` | subnet exists, AZ, CIDR, route table association indirectly |
| `aws_route_table` | `aws ec2 describe-route-tables --route-table-ids <rtb-id>` | routes, associations, default route |
| `aws_internet_gateway` | `aws ec2 describe-internet-gateways --internet-gateway-ids <igw-id>` | attached VPC, tags |
| `aws_nat_gateway` | `aws ec2 describe-nat-gateways --nat-gateway-ids <nat-id>` | state, subnet, public IP, failure reason |
| `aws_security_group` | `aws ec2 describe-security-groups --group-ids <sg-id>` | ingress/egress, VPC, tags |
| `aws_instance` | `aws ec2 describe-instances --instance-ids <instance-id>` | state, subnet, SGs, private IP, IAM profile |
| `aws_launch_template` | `aws ec2 describe-launch-templates --launch-template-ids <lt-id>` | template exists, latest/default version |
| `aws_launch_template` version | `aws ec2 describe-launch-template-versions --launch-template-id <lt-id>` | AMI, instance type, SGs, IAM profile |
| `aws_vpc_endpoint` | `aws ec2 describe-vpc-endpoints --vpc-endpoint-ids <vpce-id>` | state, service, subnets, SGs, private DNS |

## Load Balancer и target health

| Terraform resource | AWS CLI reality check | Что смотреть |
| --- | --- | --- |
| `aws_lb` | `aws elbv2 describe-load-balancers --load-balancer-arns <alb-arn>` | state, scheme, subnets, SGs, DNS |
| `aws_lb_listener` | `aws elbv2 describe-listeners --load-balancer-arn <alb-arn>` | port, protocol, default action |
| `aws_lb_target_group` | `aws elbv2 describe-target-groups --target-group-arns <tg-arn>` | port, protocol, health check config |
| target health | `aws elbv2 describe-target-health --target-group-arn <tg-arn>` | targets registered, `healthy/unhealthy/initial`, reason |

Useful query:

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform output -raw web_tg_arn)" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table
```

## Auto Scaling

| Terraform resource | AWS CLI reality check | Что смотреть |
| --- | --- | --- |
| `aws_autoscaling_group` | `aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg-name>` | min/max/desired, instances, health, launch template |
| ASG activities | `aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg-name>` | failed launches, instance refresh events, errors |
| Instance refresh | `aws autoscaling describe-instance-refreshes --auto-scaling-group-name <asg-name>` | status, percentage, rollback, reason |

Useful query:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$(terraform output -raw web_asg_name)" \
  --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Min:MinSize,Max:MaxSize,Desired:DesiredCapacity,Instances:Instances[].{Id:InstanceId,State:LifecycleState,Health:HealthStatus}}' \
  --output json
```

## IAM

| Terraform resource | AWS CLI reality check | Что смотреть |
| --- | --- | --- |
| `aws_iam_role` | `aws iam get-role --role-name <role-name>` | role exists, trust policy, ARN |
| `aws_iam_role_policy` | `aws iam get-role-policy --role-name <role-name> --policy-name <policy-name>` | inline policy actions/resources/conditions |
| `aws_iam_role_policy_attachment` | `aws iam list-attached-role-policies --role-name <role-name>` | managed policies attached |
| `aws_iam_instance_profile` | `aws iam get-instance-profile --instance-profile-name <name>` | role attached to instance profile |
| OIDC provider | `aws iam get-open-id-connect-provider --open-id-connect-provider-arn <arn>` | client IDs, thumbprints, URL |

Trust policy check:

```bash
aws iam get-role \
  --role-name lab74-dev-github-actions-apply-role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json
```

## S3 backend и state

| Проверка | AWS CLI reality check | Что смотреть |
| --- | --- | --- |
| bucket exists | `aws s3api head-bucket --bucket <bucket>` | доступен ли bucket |
| state object | `aws s3api head-object --bucket <bucket> --key <state-key>` | exists, size, LastModified, VersionId, encryption |
| object versions | `aws s3api list-object-versions --bucket <bucket> --prefix <state-key>` | latest version, previous versions |
| bucket versioning | `aws s3api get-bucket-versioning --bucket <bucket>` | `Status: Enabled` |
| encryption | `aws s3api get-bucket-encryption --bucket <bucket>` | SSE-S3 или SSE-KMS |
| public access block | `aws s3api get-public-access-block --bucket <bucket>` | все block flags true |
| bucket policy | `aws s3api get-bucket-policy --bucket <bucket>` | deny insecure transport, access boundaries |

State object example:

```bash
aws s3api head-object \
  --bucket "$TF_STATE_BUCKET" \
  --key "lab74/dev/full/terraform.tfstate" \
  --output json
```

## CloudWatch

| Terraform resource | AWS CLI reality check | Что смотреть |
| --- | --- | --- |
| `aws_cloudwatch_metric_alarm` | `aws cloudwatch describe-alarms --alarm-names <alarm-name>` | `StateValue`, reason, threshold, dimensions |
| metrics | `aws cloudwatch get-metric-statistics ...` | recent datapoints, not always needed in first check |

Alarm state example:

```bash
aws cloudwatch describe-alarms \
  --alarm-names \
    lab74-dev-alb-unhealthy-hosts \
    lab74-dev-alb-5xx-critical \
    lab74-dev-target-5xx-critical \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
  --output table
```

## Secrets и SSM

| Terraform/resource concept | AWS CLI reality check | Что смотреть |
| --- | --- | --- |
| SSM parameter metadata | `aws ssm describe-parameters --parameter-filters Key=Name,Option=Equals,Values=<name>` | exists, type, last modified |
| SSM parameter value | `aws ssm get-parameter --name <name> --with-decryption` | только если есть approval на чтение секрета |
| Secrets Manager metadata | `aws secretsmanager describe-secret --secret-id <name>` | exists, ARN, rotation, last changed |
| Secrets Manager value | `aws secretsmanager get-secret-value --secret-id <name>` | только если есть approval на чтение секрета |

## Session Manager / SSM managed instances

| Проверка | AWS CLI reality check | Что смотреть |
| --- | --- | --- |
| managed instance visible | `aws ssm describe-instance-information --filters Key=InstanceIds,Values=<instance-id>` | PingStatus, AgentVersion, PlatformName |
| command invocation | `aws ssm get-command-invocation --command-id <id> --instance-id <instance-id>` | status, stdout/stderr |

## Как выбирать, что проверять

Проверяй то, что связано с incident symptom.

| Symptom | First AWS reality checks |
| --- | --- |
| `apply` failed on ASG | ASG, scaling activities, launch template, EC2 instances |
| targets unhealthy | target health, ASG instances, EC2 state, CloudWatch alarms |
| ALB unreachable | load balancer, listeners, target groups, SGs, subnets |
| IAM AccessDenied | role, inline policy, attached policies, trust policy, CloudTrail if available |
| state/version issue | S3 head-object, list-object-versions, bucket versioning |
| SSM access broken | managed instance info, VPC endpoints, instance profile, SGs |

## Что сохранять в proof-pack

Сохраняй только релевантные outputs:

```bash
aws autoscaling describe-auto-scaling-groups ... > aws-asg.json
aws elbv2 describe-target-health ... > aws-target-health.json
aws cloudwatch describe-alarms ... > aws-alarms.json
aws s3api head-object ... > aws-state-object-head.json
```

Перед публикацией проверь sensitive data:

- account IDs;
- ARNs;
- private IPs;
- internal DNS names;
- secret values;
- emails/user names;
- incident screenshots.
