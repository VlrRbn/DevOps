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
    - These conditions must be met:
    - the instance must have egress to SSM (via NAT or VPC endpoints)
    - the SG outbound rules must not be locked down to zero
    - the NACL must not block outbound traffic or return traffic

---

## Preconditions

- EC2 has IAM instance profile with `AmazonSSMManagedInstanceCore`.
- SSM Agent is running.
- Network allows SSM connectivity:
    - either NAT **or** VPC endpoints (`ssm`, `ssmmessages`, `ec2messages`) from lesson_45.
- Laptop has:
    - AWS CLI configured (`export AWS_REGION="eu-west-1"`)
    - Session Manager plugin installed (`session-manager-plugin --version`)

---

## Pocket Cheat

| Task | Command | Why |
| --- | --- | --- |
| List managed instances | `aws ssm describe-instance-information` | Confirm SSM sees the node |
| Start shell session | `aws ssm start-session --target i-...` | Baseline connectivity |
| Port forward (local→remote) | `aws ssm start-session --document-name AWS-StartPortForwardingSession ...` | Tunnel a port securely |
| Test locally | `curl http://127.0.0.1:8080` | Prove it works |

---

## 1) Get the instance ID (private web)

If you output it from Terraform — use that.

If not, list instances in AWS CLI by tag:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=web" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text

```

Save it:

```bash
WEB_INSTANCE_ID="i-xxxxxxxxxxxxxxxxx"

```

---

## 2) Sanity check: can SSM see the instance?

```bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[].{Id:InstanceId,Ping:PingStatus,Platform:PlatformName,Version:AgentVersion}" \
  --output table
  
# or, or how you want
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$WEB_INSTANCE_ID" \
  --region eu-west-1

```

And I want:

- `PingStatus` = `Online`

---

## 3) Port forward private Nginx (remote 80 → local 8080)

Run on laptop:

```bash
aws ssm start-session \
  --target "$WEB_INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'

# or with Heredoc
aws ssm start-session \
  --target "$WEB_INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=80,localPortNumber=8080 \
  --region "$AWS_REGION"

```

Keep this terminal open (it’s the tunnel).

Now in another terminal:

```bash
curl -i http://127.0.0.1:8080 | head

```

Or open in browser:

- `http://127.0.0.1:8080`

✅ If nginx is running on the instance, you’ll see your page.

---

## 4) Prove (no inbound rules needed)

Check your Security Group inbound for web:

- it does **not** need 80 from your IP
- it does **not** need 22 at all

SSM tunnel is initiated outbound from the instance (via endpoints/NAT), so inbound stays shut.

---

## 5) Run the DB directly on EC2 (fastest)

Perfect for testing SSM port forwarding. No RDS, no subnet groups — everything is local.

## 5.1 Install PostgreSQL on the same EC2 instance

Connect to the instance using a normal SSM session:

```bash
aws ssm start-session --target "$WEB_INSTANCE_ID"

# Next, on the instance:
sudo apt update
sudo apt install -y postgresql

# Verify that the database is listening on the port:
sudo ss -lntp | grep 5432 || true

```

## 5.2 Create a test database and user

```bash
sudo -u postgres psql

# Inside
CREATE DATABASE ssm_test;
CREATE USER ssm_user WITH PASSWORD 'ssm_pass';
GRANT ALL PRIVILEGES ON DATABASE ssm_test TO ssm_user;
\q

# Make sure Postgres is listening on localhost
sudo grep listen_addresses /etc/postgresql/*/main/postgresql.conf

```

## 5.3 Port forward a DB port (example 5432)

Same pattern:

```bash
aws ssm start-session \
  --target "$WEB_INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5432"],"localPortNumber":["5432"]}'

```

Then you can connect locally (example with psql):

```bash
psql -h 127.0.0.1 -p 5432 -U ssm_user ssm_test

# Expected:
# ssm_test=>
```

This is the WAY: Laptop → SSM → EC2 → PostgreSQL

---

## 6) Troubleshooting

### “TargetNotConnected” / instance not Online

- instance profile missing `AmazonSSMManagedInstanceCore`
- SSM Agent not running
- no network path to SSM endpoints (fix NAT or VPC endpoints)

### Tunnel starts but curl fails

- service not listening on remote port
    - on instance (via normal SSM shell):
        
        ```bash
        sudo ss -tulpn | grep -E ':80|:5432' || true
        
        ```
        
- nginx not running:
    
    ```bash
    sudo systemctl status nginx --no-pager
    
    ```
    

### IF start-session shell but port forwarding fails

- check the document name spelling
- check local port already in use (`8080` busy → pick `18080`)

---

## Core

- [ ]  Port-forward private nginx 80 → localhost:8080.
- [ ]  Can curl it locally.
- [ ]  SG inbound remains closed (no 0.0.0.0/0 for 80 needed for you).
- [ ]  Add a second web instance and forward to each (8081/8082).
- [ ]  Write a small “Debug access policy” note: SSM only, SSH disabled.
- [ ]  Automate: a helper script `tools/ssm-forward.sh` that:
    - finds instance by tag (Role=web)
    - starts forwarding to a chosen local port