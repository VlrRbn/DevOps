### Debug access policy (SSM only, SSH disabled)

**Intent:** All interactive/debug access to private instances is done via **AWS Systems Manager (SSM)**. **SSH is disabled** (no inbound 22, no bastion, no public IP). This keeps the attack surface small and makes access auditable.

#### Allowed access paths

* **Interactive shell:** Laptop → AWS SSM Session Manager → EC2
  (`aws ssm start-session --target i-...`)
* **Port forwarding:** Laptop → SSM tunnel → EC2 → local service port
  Example: Nginx `80` → `localhost:8080`, Postgres `5432` → `localhost:5432`

#### Explicitly not allowed

* **No SSH**:

  * Security Groups: **no inbound TCP/22**
  * Instances: **no public IP**
  * No bastion hosts
* **No “temporary openings”**

#### Required controls (SSM must work)

* Instance profile includes **AmazonSSMManagedInstanceCore**
* **SSM Agent running** on the instance
* Network egress to SSM via **either**:

  * NAT, **or**
  * VPC Interface Endpoints: `ssm`, `ssmmessages`, `ec2messages`
* Security Group **egress** and NACLs must allow required outbound traffic (SSM/endpoints)

#### Least privilege guidance

* Humans authenticate to AWS via IAM/SSO, then use SSM.
* Restrict who can start sessions:

  * Allow `ssm:StartSession` only to approved roles/users
  * Scope to instance tags, e.g. `ResourceTag/Role = web` (or `Environment = dev`)
* Prefer logging/auditing:

  * Enable session logging to CloudWatch Logs and/or S3

#### Exception policy

If SSM is unavailable, treat it as an incident:

* Fix connectivity (endpoints/NAT/IAM/agent) rather than opening SSH.
* SSH may be allowed **only** with time-bound approval + tight scope:

  * single source IP, single instance, short TTL, and post-mortem cleanup.
