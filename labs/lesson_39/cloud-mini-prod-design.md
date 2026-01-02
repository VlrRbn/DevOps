# Cloud 101 — Conceptual Map

## 1. From labs to the cloud

- Linux host with iptables + netns + NAT
  ≈ Cloud VPC + subnets + Internet/NAT gateways

- UFW on Ubuntu
  ≈ Security Group rules for a VM

- Kubernetes NetworkPolicy
  ≈ fine-grained internal traffic control inside a VPC (on top of SG)

- K8s ServiceAccount + Role/RoleBinding
  ≈ IAM roles + policies for cloud services/instances

- VPC is not “one machine” and not “one local network.” It’s a virtual router plus route tables and network interfaces.
  A subnet is not a separate netns — it’s an L3 segment (a CIDR range) within a VPC, tied to an Availability Zone.



+------------------------- Интернет ------------------------------------+
|                              | (публичные IP)                         |
+---------------------------- IGW --------------------------------------+
|            Internet Gateway — “ворота” VPC в интернет                 |
+------------------------------+----------------------------------------+
|                              |                                        |
+---------------------------- VPC --------------------------------------+
|                     Virtual Privat Cloud                              |
|  +---------------------+        +-----------------------+             |
|  |  Public Subnet      |        |  Private App Subnet   |             |
|  |  < Bastion / ALB >  |        |   (web/app/k8s-nodes) |             |
|  |                     |        |                       |             |
|  |  (route:            |        |  (route:              |             |
|  |   0.0.0.0/0 -> IGW) |        |  0.0.0.0/0 -> NAT GW) |             |
|  |         |           |        +-----------------------+             |
|  |         |           |        |                       |             |
|  |  NAT Gateway (EIP)  |        | DB Subnets / isolated |             |
|  |                     |        |    (db, cache)        |             |
|  |                     |        |                       |             |
|  |                     |        | (route: NO 0.0.0.0/0) |             |
|  +---------------------+        +-----------------------+             |
|                                                                       |
+-----------------------------------------------------------------------+

## 2. Traffic flow: “how I SSH in, and why the DB isn’t reachable from the internet”

1) Laptop → Bastion: via the bastion’s public IP (it’s in a public subnet, with a `0.0.0.0/0` route to the IGW, and its SG "inbound tcp/22" allows SSH only from my piblic IP).

2) Bastion → Web: inside the VPC via the web instance’s private IP "example 10.0.2.10", traffic stays within the VPC - using the “local” route for the VPC CIDR (the web SG allows SSH only from the bastion SG).

3) Web → DB: the web instance reaches the DB over the private network; the DB SG allows the DB port "example tcp/5432 or 3306" only from the web SG, the DB is in a private subnet, and it doesn’t need internet access.

4) Internet → DB: not possible, because:
  * the DB has no public IP,
  * the private subnet has no route through the IGW, NO (0.0.0.0/0 → IGW absent)
  * the DB SG has no `0.0.0.0/0` ingress rule, only from SG web.

## 3. Mini-prod VPC design

### 3.1 VPC and CIDR

- VPC CIDR: 10.10.0.0/16

### 3.2 Subnets

- Public subnet A: 10.10.1.0/24
- Public subnet B: 10.10.2.0/24
- Private subnet A: 10.10.11.0/24
- Private subnet B: 10.10.12.0/24

### 3.3 Internet access

- Internet Gateway attached to VPC
- Public subnets route 0.0.0.0/0 → IGW
- Private subnets route 0.0.0.0/0 → NAT gateway in public subnet A

### 3.4 Typical instances / roles

- Bastion host in public subnet A:
  - Security group: ssh from my IP only, maybe k8s control-plane access

- Web nodes in public or private subnets:
  - SG: allow 80/443 from internet (public case) or from load balancer
  - SSH only from Bastion SG

- DB in private subnet:
  - SG: allow DB port only from web SG (no direct internet)
