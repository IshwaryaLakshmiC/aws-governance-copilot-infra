#!/bin/bash
# init-db.sh — Initialise database for both services
# Run ONCE after terraform apply
# Usage: bash scripts/init-db.sh
set -e

echo "==> Getting RDS host from Terraform outputs..."
cd environments/dev
DB_HOST=$(terraform output -raw rds_host)
cd ../..

echo "DB Host: $DB_HOST"
echo "DB Name: cloud_security_platform"
echo ""
read -s -p "Enter RDS password: " DB_PASS
echo ""

PGPASSWORD=$DB_PASS psql "host=$DB_HOST port=5432 dbname=cloud_security_platform user=platform_admin sslmode=require" << 'SQL'

-- ── Extensions ────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- for text search

-- ──────────────────────────────────────────────────────────────
-- GOVERNANCE COPILOT TABLES
-- ──────────────────────────────────────────────────────────────

-- AWS security findings (IAM, S3, EC2, GuardDuty, etc.)
CREATE TABLE IF NOT EXISTS findings (
    id           SERIAL PRIMARY KEY,
    finding_id   TEXT UNIQUE NOT NULL,
    service      TEXT NOT NULL,
    severity     TEXT,
    title        TEXT NOT NULL,
    description  TEXT,
    resource_id  TEXT,
    region       TEXT,
    account_id   TEXT,
    raw_data     JSONB,
    collected_at TIMESTAMPTZ DEFAULT NOW(),
    embedding    vector(1536)
);

CREATE INDEX IF NOT EXISTS findings_embedding_idx
    ON findings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS findings_service_idx    ON findings (service);
CREATE INDEX IF NOT EXISTS findings_severity_idx   ON findings (severity);
CREATE INDEX IF NOT EXISTS findings_collected_idx  ON findings (collected_at DESC);

-- Cost anomalies
CREATE TABLE IF NOT EXISTS cost_anomalies (
    id            SERIAL PRIMARY KEY,
    anomaly_id    TEXT UNIQUE,
    service       TEXT,
    region        TEXT,
    amount_usd    NUMERIC(10,2),
    expected_usd  NUMERIC(10,2),
    anomaly_date  DATE,
    description   TEXT,
    collected_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Governance copilot chat history
CREATE TABLE IF NOT EXISTS governance_chat_history (
    id         SERIAL PRIMARY KEY,
    session_id TEXT NOT NULL,
    role       TEXT NOT NULL,
    content    TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS gov_chat_session_idx ON governance_chat_history (session_id, created_at DESC);

-- ──────────────────────────────────────────────────────────────
-- DISCOVERY COPILOT TABLES
-- ──────────────────────────────────────────────────────────────

-- Discovery sessions
CREATE TABLE IF NOT EXISTS discovery_sessions (
    id           TEXT PRIMARY KEY,
    company_name TEXT NOT NULL DEFAULT 'Prospect',
    industry     TEXT,
    company_size TEXT,
    scenario_id  TEXT,
    status       TEXT DEFAULT 'discovery',
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    updated_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Discovery messages (full transcript per session)
CREATE TABLE IF NOT EXISTS discovery_messages (
    id         SERIAL PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES discovery_sessions(id) ON DELETE CASCADE,
    role       TEXT NOT NULL,
    content    TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS disc_msg_session_idx ON discovery_messages (session_id, created_at ASC);

-- Gap analysis results (stored for retrieval)
CREATE TABLE IF NOT EXISTS gap_analysis_results (
    id                  SERIAL PRIMARY KEY,
    session_id          TEXT NOT NULL REFERENCES discovery_sessions(id) ON DELETE CASCADE,
    gaps                JSONB NOT NULL DEFAULT '[]',
    maturity_scores     JSONB NOT NULL DEFAULT '{}',
    overall_risk_level  TEXT,
    compliance_status   JSONB NOT NULL DEFAULT '{}',
    top_3_priorities    JSONB NOT NULL DEFAULT '[]',
    generated_at        TIMESTAMPTZ DEFAULT NOW()
);

-- Vendor recommendations
CREATE TABLE IF NOT EXISTS recommendation_results (
    id              SERIAL PRIMARY KEY,
    session_id      TEXT NOT NULL REFERENCES discovery_sessions(id) ON DELETE CASCADE,
    recommendations JSONB NOT NULL DEFAULT '[]',
    generated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Vendor capability cards (RAG source)
-- Populated once from data/vendor_cards/ JSON files
CREATE TABLE IF NOT EXISTS vendor_capabilities (
    id                    SERIAL PRIMARY KEY,
    vendor                TEXT NOT NULL,
    domain                TEXT NOT NULL,
    capability            TEXT NOT NULL,
    description           TEXT,
    fits_when             TEXT,
    not_fits_when         TEXT,
    cost_tier             TEXT,
    implementation_complexity TEXT,
    embedding             vector(1536)
);

CREATE INDEX IF NOT EXISTS vendor_cap_embedding_idx
    ON vendor_capabilities USING ivfflat (embedding vector_cosine_ops) WITH (lists = 50);
CREATE INDEX IF NOT EXISTS vendor_cap_domain_idx ON vendor_capabilities (domain);
CREATE INDEX IF NOT EXISTS vendor_cap_vendor_idx ON vendor_capabilities (vendor);

-- Advanced SE analysis results (objections, arch options, stakeholders, deal risk)
CREATE TABLE IF NOT EXISTS advanced_analysis (
    id               SERIAL PRIMARY KEY,
    session_id       TEXT NOT NULL REFERENCES discovery_sessions(id) ON DELETE CASCADE,
    analysis_type    TEXT NOT NULL,  -- objections | arch_options | stakeholders | deal_risk | executive
    result           JSONB NOT NULL,
    generated_at     TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS advanced_analysis_session_idx ON advanced_analysis (session_id, analysis_type);

SELECT 'Database initialised successfully' AS status;
SELECT extname, extversion FROM pg_extension WHERE extname IN ('vector', 'pg_trgm');
SQL

echo ""
echo "==> Database initialised for both services."
echo "==> Tables created: findings, cost_anomalies, governance_chat_history"
echo "==>                 discovery_sessions, discovery_messages, gap_analysis_results"
echo "==>                 recommendation_results, vendor_capabilities, advanced_analysis"
