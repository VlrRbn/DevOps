# lesson_46

---

# SSM Port Forwarding: Access Private Services (Web/DB) Without Opening Ports

**Date:** 2025-01-14

**Topic:** Use **AWS SSM Session Manager Port Forwarding** to reach private instances/services from my laptop:

- private Nginx (80) → `localhost:8080`
- DB port (5432) → `localhost:5432`
    
    No inbound rules, no bastion, no public IP.
    

---

## Goals

- Confirm my private EC2 is reachable via SSM.
- Set up port forwarding from laptop to a private instance port.
- Validate traffic path: Laptop → SSM → EC2 → Service.
- Keep security tight: **SG inbound stays closed**.

---

## Preconditions

- EC2 has IAM instance profile with `AmazonSSMManagedInstanceCore`.
- SSM Agent is running.
- Network allows SSM connectivity:
    - either NAT **or** VPC endpoints (`ssm`, `ssmmessages`, `ec2messages`) from lesson_45.
- Laptop has:
    - AWS CLI configured
    - Session Manager plugin installed

---

## Pocket Cheat

| Task | Command | Why |
| --- | --- | --- |
| List managed instances | `aws ssm describe-instance-information` | Confirm SSM sees the node |
| Start shell session | `aws ssm start-session --target i-...` | Baseline connectivity |
| Port forward (local→remote) | `aws ssm start-session --document-name AWS-StartPortForwardingSession ...` | Tunnel a port securely |
| Test locally | `curl http://127.0.0.1:8080` | Prove it works |

---
