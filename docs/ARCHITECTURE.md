# Architecture — Cloud Security Platform Infrastructure

## AWS Resource Architecture

```
                         ┌──────────────────────────────────────────┐
                         │           AWS Account (us-east-1)         │
                         │                                            │
                         │  ┌──────────────────────────────────────┐ │
                         │  │         VPC  10.0.0.0/16             │ │
                         │  │                                       │ │
                         │  │  ┌─────────────┐  ┌───────────────┐  │ │
Internet ───────────────►│  │  │Public Subnet│  │Private Subnet │  │ │
                         │  │  │10.0.1.0/24  │  │10.0.2-3.0/24  │  │ │
                         │  │  │             │  │               │  │ │
                         │  │  │  ┌────────┐ │  │  ┌─────────┐ │  │ │
                         │  │  │  │  EC2   │ │  │  │   RDS   │ │  │ │
                         │  │  │  │t2.micro│◄├──┤  │Postgres │ │  │ │
                         │  │  │  │FastAPI │ │  │  │+ pgvec  │ │  │ │
                         │  │  │  │:8000   │ │  │  │db.t3.mic│ │  │ │
                         │  │  │  └───┬────┘ │  │  └─────────┘ │  │ │
                         │  │  │      │EIP   │  │               │  │ │
                         │  │  └──────┼──────┘  └───────────────┘  │ │
                         │  │         │                              │ │
                         │  └─────────┼──────────────────────────── ┘ │
                         │            │                                 │
                         │  ┌─────────┼──────────────────────────────┐ │
                         │  │         │   AWS Services (collectors)   │ │
                         │  │         ▼                               │ │
                         │  │  IAM · S3 · EC2 · GuardDuty            │ │
                         │  │  CloudTrail · RDS · Lambda              │ │
                         │  │  Cost Explorer · Security Hub           │ │
                         │  └────────────────────┬────────────────────┘ │
                         │                       │                       │
                         │  ┌────────────────────▼────────────────────┐ │
                         │  │              AWS Bedrock                 │ │
                         │  │  Claude 3 Sonnet  +  Titan Embeddings V2 │ │
                         │  └──────────────────────────────────────────┘ │
                         └──────────────────────────────────────────────┘
```

## Security Group Rules

```
App Server SG (EC2)                    RDS SG
─────────────────────────              ──────────────────────────────
Inbound:                               Inbound:
  22   TCP  your-ip/32  SSH              5432  TCP  app-sg-id  PostgreSQL
  8000 TCP  0.0.0.0/0   FastAPI        Outbound:
  443  TCP  0.0.0.0/0   HTTPS            ALL   0.0.0.0/0
Outbound:
  ALL  0.0.0.0/0
```

## IAM Role — Least Privilege

```
EC2 Instance Profile → App Role
        │
        ├── BedrockAccess Policy
        │     • bedrock:InvokeModel
        │     • bedrock:InvokeModelWithResponseStream
        │     Resources: Claude Sonnet + Titan Embeddings only
        │
        └── SecurityReadOnly Policy
              • iam:List*, iam:Get*, iam:GenerateCredentialReport
              • s3:GetBucket*, s3:ListAllMyBuckets
              • ec2:Describe*
              • guardduty:List*, guardduty:Get*
              • cloudtrail:LookupEvents, GetTrailStatus
              • rds:Describe*, rds:List*
              • lambda:List*, lambda:Get*
              • ce:GetCostAndUsage, GetAnomalies
              • securityhub:GetFindings
```

## Database Schema (pgvector)

```
findings table
──────────────────────────────────────────────────────
id            SERIAL PRIMARY KEY
finding_id    TEXT UNIQUE
service       TEXT          -- iam|s3|ec2|guardduty|cost
severity      TEXT          -- critical|high|medium|low
title         TEXT
description   TEXT
resource_id   TEXT
region        TEXT
account_id    TEXT
raw_data      JSONB
collected_at  TIMESTAMPTZ
embedding     vector(1536)  -- Titan Embeddings V2

Indexes:
  findings_embedding_idx  USING ivfflat (cosine)
  findings_service_idx
  findings_severity_idx
  findings_collected_at_idx

cost_anomalies table         chat_history table
─────────────────────        ──────────────────────────
id, anomaly_id               id, session_id, role
service, region              content, created_at
amount_usd, expected_usd
anomaly_date, description
```

## Module Dependency Graph

```
environments/dev/main.tf
        │
        ├── module.vpc
        │     outputs → subnet_ids, sg_ids
        │
        ├── module.iam
        │     outputs → instance_profile_name, role_arn
        │
        ├── module.rds (depends on vpc)
        │     inputs  ← private_subnet_ids, rds_sg_id
        │     outputs → db_host, db_port, db_name
        │
        └── module.ec2 (depends on vpc, iam, rds)
              inputs  ← public_subnet_id, app_sg_id
              inputs  ← instance_profile_name
              inputs  ← db_host, db_port (from rds)
              outputs → public_ip, ssh_command
```

## Shared Infrastructure

```
This infra serves TWO applications:

cloud-security-platform          security-discovery-copilot
─────────────────────           ──────────────────────────
findings table                  discovery_sessions table
cost_anomalies table            gap_analysis table
chat_history table              vendor_capabilities table (RAG)
                                framework_controls table (RAG)

Both apps share:
  • Same RDS instance (separate table namespaces)
  • Same EC2 (different FastAPI routers on /governance, /discovery)
  • Same Bedrock IAM role
  • Same VPC/networking
```

## Cost Estimate (Free Tier)

```
Resource              Free tier             Estimated cost
────────────────────  ────────────────────  ──────────────
EC2 t2.micro          750 hrs/month         $0.00
RDS db.t3.micro       750 hrs/month         $0.00
EIP (attached)        Free when attached    $0.00
S3 (state + cache)    5GB free              $0.00
Data transfer         1GB free outbound     ~$0.05
Bedrock Claude        Not free tier         ~$2-4/month
Cost Explorer API     $0.01/request         ~$1/month
────────────────────────────────────────────────────────
Total estimated                             ~$3-5/month
```
