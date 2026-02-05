# Lesson 54 — Blue/Green Deployments with ALB + ASG
This lesson implements a blue/green deployment setup using an internal ALB, two target groups, and two ASGs. It includes version markers in the baked AMIs, weighted traffic shifting, and fast rollback.

## Prerequisites
- AWS credentials configured
- Terraform installed
- Packer installed (if baking AMIs)
- Access to the internal ALB via SSM proxy

## Layout
- `lesson51_60/lesson_54/lesson_54.md` — full lesson guide
- `lesson51_60/lesson_54/blue_green_cutover_steps.md` — cutover steps (manual)
- `lesson51_60/lesson_54/commands.md` — AWS CLI quick commands
- `lesson51_60/lesson_54/lab_54/packer` — AMI bake scripts
- `lesson51_60/lesson_54/lab_54/terraform/envs` — Terraform entrypoint and tfvars
- `lesson51_60/lesson_54/lab_54/terraform/modules/network` — VPC/ALB/ASG module

## Quick Start
1. Bake two AMIs (blue/green) with version markers.
2. Put their AMI IDs into `lesson51_60/lesson_54/lab_54/terraform/envs/terraform.tfvars`.
3. Apply Terraform:

```bash
cd lesson51_60/lesson_54/lab_54/terraform/envs
terraform apply
```

## Blue/Green Workflow (Manual)
1. Keep green scaled to zero and weights at 100/0.
2. Scale green up and wait for healthy targets.
3. Shift traffic (90/10 → 0/100).
4. Roll back instantly by restoring weights to 100/0.

See `lesson51_60/lesson_54/blue_green_cutover_steps.md` for exact steps and `lesson51_60/lesson_54/commands.md` for CLI helpers.

## Key Variables
In `lesson51_60/lesson_54/lab_54/terraform/envs/terraform.tfvars`:

- `web_ami_blue_id`, `web_ami_green_id`
- `traffic_weight_blue`, `traffic_weight_green`
- `blue_min_size`, `blue_desired_capacity`, `blue_max_size`
- `green_min_size`, `green_desired_capacity`, `green_max_size`
- `tg_slow_start_seconds`, `health_check_healthy_threshold`

## Troubleshooting
- **Targets unhealthy (404):** health check path mismatch. Ensure TG checks `/` or update your AMI accordingly.
- **No green traffic at 90/10:** check green targets are healthy and stickiness is off.
- **SSM session fails:** your network may block WebSockets. Try another network.

## Notes
- ALB is internal; access is via the SSM proxy.
- ASG with `health_check_type = "ELB"` will replace unhealthy instances.
- If green is bad and weights > 0, users will see errors.
