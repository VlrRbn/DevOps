# Blue/Green Cutover Steps (Manual)

Assumptions:
- You are in `lesson51_60/lesson_54/lab_54/terraform/envs`
- `terraform output` is available for this state

## 1) Bring up GREEN (warm-up)

Edit `lesson51_60/lesson_54/lab_54/terraform/envs/terraform.tfvars`:
```
green_min_size         = 2
green_desired_capacity = 2
```

Apply:
```bash
terraform apply
```

## 2) Wait for GREEN targets to be healthy

Get target group ARN:
```bash
terraform output -json web_tg_arns | python3 -c "import json,sys; print(json.load(sys.stdin)['green'])"
```

Wait:
```bash
aws elbv2 wait target-in-service --target-group-arn "$(terraform output -json web_tg_arns | python3 -c "import json,sys; print(json.load(sys.stdin)['green'])")"
```

## 3) Shift traffic (90/10 or 0/100)

Edit `lesson51_60/lesson_54/lab_54/terraform/envs/terraform.tfvars`:
```
traffic_weight_blue  = 90
traffic_weight_green = 10
```

Apply:
```bash
terraform apply
```

## 4) Full cutover to GREEN

Edit `lesson51_60/lesson_54/lab_54/terraform/envs/terraform.tfvars`:
```
traffic_weight_blue  = 0
traffic_weight_green = 100
```

Apply:
```bash
terraform apply
```

## 5) Rollback (instant)

Edit `lesson51_60/lesson_54/lab_54/terraform/envs/terraform.tfvars`:
```
traffic_weight_blue  = 100
traffic_weight_green = 0
```

Apply:
```bash
terraform apply
```

## 6) Scale GREEN down (after rollback or after final cutover validation)

Edit `lesson51_60/lesson_54/lab_54/terraform/envs/terraform.tfvars`:
```
green_min_size         = 0
green_desired_capacity = 0
```

Apply:
```bash
terraform apply
```
