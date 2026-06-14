# Cloud Security Platform — Infrastructure (Terraform)

> **Shared AWS infrastructure for the Cloud Security Platform** — provisions all resources needed to run the AWS Governance Copilot and Security Discovery Copilot on AWS free tier.

Built by [Ishwarya Lakshmi C](https://github.com/IshwaryaLakshmiC) · [ishwaryaaunfiltered.live](https://ishwaryaaunfiltered.live)

---

## Services hosted on this infrastructure

| Service | Port | Description |
|---------|------|-------------|
| [aws-governance-copilot](https://github.com/IshwaryaLakshmiC/aws-governance-copilot) | 8000 (`:80/governance`) | AI security + cost intelligence over real AWS |
| [security-discovery-copilot](https://github.com/IshwaryaLakshmiC/security-discovery-copilot) | 8001 (`:80/discovery`) | SE discovery, gap analysis, vendor recommendations, executive summary |

Both services share: VPC, RDS (separate tables), EC2, IAM role, Bedrock access.

---

## What this provisions

| Resource | Purpose | Free tier |
|----------|---------|-----------|
| VPC + subnets + SGs | Network isolation | ✓ Free |
| RDS PostgreSQL 15 db.t3.micro + pgvector | Shared DB for both apps | ✓ 750hrs/month |
| EC2 t2.micro + Nginx | App server + reverse proxy | ✓ 750hrs/month |
| IAM roles + policies | Least-privilege for Bedrock + AWS read-only | ✓ Free |
| S3 (state + app cache) | Terraform backend + session exports | ✓ 5GB free |
| DynamoDB (state locks) | Terraform state locking | ✓ Free tier |
| Bedrock (Claude Sonnet + Titan) | LLM + embeddings | ~$3-5/month demo usage |

---

## Quick start

```bash
git clone https://github.com/IshwaryaLakshmiC/cloud-security-platform-infra
cd cloud-security-platform-infra

# Generate SSH key
ssh-keygen -t ed25519 -C "cloud-security-platform" -f ~/.ssh/cloud-security-platform

# Configure
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — paste public key, set your IP, set DB password

# Deploy (~10 minutes, RDS is the slow part)
terraform init
terraform plan
terraform apply

# Get endpoints
terraform output

# Initialise database
cd ../..
bash scripts/init-db.sh
```

---

## After `terraform apply`

```bash
# 1. Note your EC2 IP
terraform output ec2_public_ip

# 2. SSH in
ssh -i ~/.ssh/cloud-security-platform ec2-user@<EC2_IP>

# 3. Deploy Governance Copilot
git clone https://github.com/IshwaryaLakshmiC/aws-governance-copilot /opt/governance-copilot
sudo systemctl enable --now governance-copilot

# 4. Deploy Discovery Copilot
git clone https://github.com/IshwaryaLakshmiC/security-discovery-copilot /opt/discovery-copilot
sudo systemctl enable --now discovery-copilot

# 5. Verify
curl http://<EC2_IP>/health
```

---

## Enable S3 backend (after first apply)

```bash
# Get the bucket name
terraform output s3_state_bucket

# Uncomment backend block in environments/dev/main.tf
# Update bucket name with your account ID
terraform init -migrate-state
```

---

## Module structure

```
modules/
  vpc/      — VPC, subnets, IGW, route tables, SGs (ports 22, 80, 8000, 8001)
  rds/      — PostgreSQL 15 + pgvector, db.t3.micro, private subnet
  ec2/      — t2.micro + EIP + Nginx reverse proxy + systemd services
  iam/      — App role: Bedrock + AWS read-only + S3 cache access
  s3/       — Terraform state bucket + DynamoDB locks + app cache bucket
environments/
  dev/      — Wires all modules, S3 backend config
scripts/
  init-db.sh — Creates all tables for both services (run once after apply)
```

---

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

**Ishwarya Lakshmi C** — Senior DevOps & Cloud Security Engineer  
[GitHub](https://github.com/IshwaryaLakshmiC) · [Website](https://ishwaryaaunfiltered.live) · [LinkedIn](https://linkedin.com/in/ishwaryachengalvarayan)
