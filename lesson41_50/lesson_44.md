# lesson_44

---

# AWS SSM Session Manager: Access Private EC2 Without SSH (IAM + VPC Endpoints) IAM → SSM → Private EC2

**Date:** 2025-01-11

**Topic:** Replace SSH-based access with **AWS Systems Manager Session Manager**:

- Give EC2 an **instance profile** with `AmazonSSMManagedInstanceCore`
- Ensure **SSM Agent** is present/running
- Connect via **SSM Session Manager** (console or CLI)
- Use **VPC Interface Endpoints** so private instances work **without NAT/Internet**

SSM prerequisites and agent requirements: ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-prerequisites.html))

VPC endpoint approach: ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html))

CLI start-session requires Session Manager plugin: ([awscli.amazonaws.com](https://awscli.amazonaws.com/v2/documentation/api/2.0.33/reference/ssm/start-session.html))

---

## Goals

- Access **private EC2** without:
    - public IP
    - inbound 22/tcp
    - bastion hopping
- Enforce access via **IAM** (who can connect, when, why)
- Make SSM work **even with no internet/NAT** using VPC endpoints

---

## Pocket Cheat

| Task | Command / Place | Why |
| --- | --- | --- |
| Attach instance permissions | IAM Role + Instance Profile + `AmazonSSMManagedInstanceCore` | Required for Session Manager ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html)) |
| Start session (CLI) | `aws ssm start-session --target i-...` | SSH-like shell via SSM ([docs.aws.amazon.com](https://docs.aws.amazon.com/cli/latest/reference/ssm/start-session.html)) |
| Start session (Console) | Systems Manager → Session Manager → Start session | Fast manual access ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html)) |
| No internet access | Create VPC endpoints: `ssm`, `ssmmessages`, `ec2messages` | SSM works privately ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)) |
| Install agent (if missing) | Ubuntu SSM Agent install doc | Fix “instance not managed” ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/agent-install-ubuntu.html)) |

---

## 1) Terraform: Create IAM role + instance profile for SSM

Add to your Terraform (root, where EC2 resources are defined):

### 1.1 IAM role (trust for EC2)

```hcl
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

```

### 1.2 Attach AWS-managed policy

`AmazonSSMManagedInstanceCore` is the standard baseline for managed instances. ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html))

```hcl
resource "aws_iam_role_policy_attachment" "ec2_ssm_role_attach" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

```

### 1.3 Instance profile

```hcl
resource "aws_iam_instance_profile" "ec2_ssm_instance_profile" {
  name = "${var.project_name}-ec2-ssm-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

```

---

## 2) Terraform: Attach instance profile to your EC2 (private web is the main target)

On  `aws_instance.web`:

```hcl
iam_instance_profile = aws_iam_instance_profile.ec2_ssm_instance_profile.name

```

That’s it: instance now has IAM permissions for SSM.

---

## 3) Ensure SSM Agent is running

Prereqs: SSM Agent version minimum requirements are documented by AWS. ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-prerequisites.html))

### 3.1 Add to user_data (Ubuntu) as fallback

In  `web-userdata.sh`, append:

```bash
# SSM Agent (fallback install)
if ! command -v amazon-ssm-agent >/dev/null 2>&1; then
  snap install amazon-ssm-agent --classic || true
fi

systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || true

```

If you prefer official AWS method, AWS documents Ubuntu install steps too. ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/agent-install-ubuntu.html))

---

## 4) Connectivity requirement: internet/NAT OR VPC endpoints

SSM needs to talk to AWS APIs (Session Manager + message channels). AWS recommends using **Interface VPC endpoints** for better security posture, especially for private instances. ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html))

### Option A — simplest (you already have NAT in full mode)

Keep NAT: private instance can reach SSM endpoints via outbound internet.

### Option B — best practice + cost saver

Add VPC interface endpoints so **private subnet works without NAT/IGW**:

Create endpoints for:

- `com.amazonaws.<region>.ssm`
- `com.amazonaws.<region>.ssmmessages`
- `com.amazonaws.<region>.ec2messages`

These endpoints are specifically involved in session channels and messaging. ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up-messageAPIs.html))

**Terraform sketch:**

- create a small SG for endpoints: allow inbound 443 from your private subnets
- create `aws_vpc_endpoint` (type `Interface`) in your private subnets with `private_dns_enabled = true`

---

## 5) Start a session

### 5.1 Console path

Systems Manager → Session Manager → Start session → pick instance. ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html))

### 5.2 CLI (Linux/macOS)

AWS CLI interactive session requires the **Session Manager plugin**. ([awscli.amazonaws.com](https://awscli.amazonaws.com/v2/documentation/api/2.0.33/reference/ssm/start-session.html))

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].{Id:InstanceId,Ping:PingStatus,Platform:PlatformName}' \
  --output table

aws ssm start-session --target i-***

# systemctl is-active snap.amazon-ssm-agent.amazon-ssm-agent.service
```

CLI reference: ([docs.aws.amazon.com](https://docs.aws.amazon.com/cli/latest/reference/ssm/start-session.html))

“Bastion host is optional when AWS Systems Manager Session Manager is used, because SSM provides secure, auditable, keyless access over HTTPS without opening inbound ports.”

```bash
cd /tmp
curl -fsSLO "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
sudo apt -f install -y

session-manager-plugin --version

```

---

## 6) Kill SSH (the satisfying part)

After SSM works:

- Remove inbound `22/tcp` rules from **bastion SG** and **web SG**
- Or gate them behind a variable like `enable_ssh = false`

Result:

- no open port 22
- all access is logged/audited by IAM + SSM
- bastion becomes optional (or can be destroyed)

---

## Pitfalls

- Instance not visible in Session Manager:
    - SSM Agent missing/not running ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-prerequisites.html))
    - missing instance profile permissions ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html))
    - no network path to SSM endpoints (fix: NAT or VPC endpoints) ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html))
- CLI start-session fails:
    - Session Manager plugin not installed locally ([awscli.amazonaws.com](https://awscli.amazonaws.com/v2/documentation/api/2.0.33/reference/ssm/start-session.html))

---

## Core

- [ ]  Add IAM role + instance profile + attach `AmazonSSMManagedInstanceCore`.
- [ ]  Attach instance profile to `aws_instance.web`.
- [ ]  Confirm instance shows up as managed node / can start session.
- [ ]  Get a shell via Session Manager (console or CLI).
- [ ]  Implement VPC endpoints for SSM so private works **without NAT**.
- [ ]  Remove all SSH ingress rules; bastion no longer needed.
- [ ]  Write “access_policy.md”: who can start sessions and why.