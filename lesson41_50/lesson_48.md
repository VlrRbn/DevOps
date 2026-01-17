# lesson_48

---

# ALB + 2 Targets: Health Checks, Security Groups, Real Load Balancing

**Date:** 2026-01-17

**Topic:** Build an **Application Load Balancer** with:

- 2 EC2 targets (two web instances)
- target group + HTTP listener
- health checks
- proper security groups

> ALB requires at least two subnets in different AZs (standard ALB behavior). (docs.aws.amazon.com)
> 
> 
> Default ALB health check path for HTTP is `/`. ([docs.aws.amazon.com](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html))
> 

---

## Goals

- Create an **internet-facing ALB** in public subnets (2 AZs).
- Run **two web EC2 instances**.
- Register instances in a **target group**.
- Verify:
    - Target health is **healthy**
    - Requests are **load balanced** (see if instance identity in response)

---

## Layout

```
labs/lesson_48/terraform/
├─ modules/
│  └─ network/
│     ├─ main.tf
│     ├─ outputs.tf
│     ├─ variables.tf
│     └─ scripts/
│        └─ web-userdata.sh
└─ envs/
   ├─ main.tf
   ├─ outputs.tf
   ├─ terraform.tfvars
   └─ variables.tf
   
```
