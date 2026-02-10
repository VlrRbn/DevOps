# LAB54 -> LAB55 Postmortem (SSM Proxy + Rolling Fleet)

## Document Goal
Capture, in a compact form:
- what issue appeared during migration from `lab_54`,
- why it happened,
- what was changed in `lab_55`,
- how to verify the fix is complete.

This is not a `README`; it is an incident/fix report.

---

## Symptoms
- `aws ssm start-session` intermittently failed with `TargetNotConnected` or `ConnectionLost`.
- `describe-instance-information` sometimes returned `PingStatus=None`.
- After `terraform apply`, behavior was unstable: temporarily working, then failing again.
- Terraform entered an SG loop (`create 4 rules -> modify SG -> create 4 rules again`).

---

## What Existed in `lab_54` and Why It Masked the Problem

### 1) Hidden proxy AMI fallback to web
In `lab_54`, proxy AMI had a fallback:

```hcl
ami = coalesce(var.ssm_proxy_ami_id, var.web_ami_blue_id)
```

Result: if `ssm_proxy_ami_id` was not set, proxy used the web (`blue`) AMI, which masked issues in a dedicated proxy image.

### 2) Blue/Green architecture with different change points
`lab_54` used two fleets (blue/green), weighted listener, and NAT logic.  
During migration to single-fleet rolling (`lab_55`), hidden dependencies and SG drift became visible.

---

## Root Causes in `lab_55` (Based on Diagnosis)

### 1) Unstable SSM Agent installation path in proxy AMI
- Base Ubuntu images may already include agent via `snap`.
- Installing `.deb` over `snap` causes package conflicts.
- Agent registration artifacts could be baked into AMI and reused by new instances.

### 2) Security Group management model conflict
- Two models were mixed at the same time:
  - inline SG rules in `aws_security_group`,
  - separate `aws_security_group_rule` resources.
- This caused Terraform loops and temporary networking inconsistency.

### 3) Runtime SSM registration/channel flapping
- Some boots had timeouts to `ssm/ssmmessages` during agent initialization.
- Combined with the above points, this produced unpredictable post-`apply` behavior.

---

## What Was Fixed (Final State)

## 1) Decoupled proxy AMI from web AMI
File: `terraform/modules/network/main.tf`

Before:
```hcl
ami = coalesce(var.ssm_proxy_ami_id, var.web_ami_blue_id)
```

After:
```hcl
ami = var.ssm_proxy_ami_id
```

Result: changing `web_ami_id` no longer affects `ssm_proxy`.

## 2) `lab_55` moved to single-fleet rolling
- One `Launch Template`, one `ASG`, one `Target Group`.
- Version rollout through `ASG Instance Refresh`.

Result: lesson 55 now demonstrates rolling update inside a single fleet (not blue/green).

## 3) Fixed proxy AMI SSM Agent setup
File: `packer/ssm_proxy/scripts/install-ssm-agent.sh`

Changes:
- Remove `snap` agent variant if present.
- Install official regional `.deb` agent package.
- Enforce systemd restart policy (`Restart=always`).
- Clean registration/log state before AMI snapshot:
  - `/var/lib/amazon/ssm/*`
  - `/var/log/amazon/ssm/*`

Result: new instances from AMI register as clean instances.

## 4) Normalized SG rules without widening access
File: `terraform/modules/network/main.tf`

Changes:
- Removed conflicting SG rule management pattern that caused Terraform loops.
- Preserved strict security intent:
  - proxy egress `443` only to `ssm_endpoint` SG (not to full `vpc_cidr`),
  - endpoint ingress rules explicitly allow proxy/web where needed.

Result: no endless plan loop and no broad “VPC-wide:443” allowance.

---

## Validation Checklist

## 1) Terraform plan is stable
```bash
terraform plan
```
Expected: no repeating SG rule loop.

## 2) Proxy is online in SSM
```bash
IID=$(terraform output -raw ssm_proxy_instance_id)
aws --region eu-west-1 ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$IID" \
  --query 'InstanceInformationList[0].PingStatus' --output text
```
Expected: `Online`.

## 3) Session start works
```bash
aws --region eu-west-1 ssm start-session --target "$IID"
```
Expected: interactive session opens without `TargetNotConnected`.

## 4) `web_ami_id` change does not break proxy
1. Change only `web_ami_id` in `terraform.tfvars`.
2. Run `terraform apply`.
3. Repeat checks from steps 2 and 3 above.

Expected: `ssm_proxy` remains healthy.

---

## Conclusion
The issue was a combination of:
- hidden historical AMI coupling,
- unstable SSM Agent lifecycle in proxy AMI,
- SG management model conflict.

In `lab_55`, this is now isolated and stabilized:
- proxy AMI is independent,
- rolling update is truly single-fleet,
- SSM channel and Terraform plans are predictable.
