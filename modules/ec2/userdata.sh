#!/bin/bash
set -e

# ── System setup ──────────────────────────────────────────────
yum update -y
yum install -y python3.11 python3.11-pip git postgresql15 nginx

pip3.11 install --upgrade pip
pip3.11 install \
  fastapi uvicorn \
  boto3 \
  psycopg2-binary pgvector \
  openai httpx \
  python-dotenv \
  anthropic \
  pydantic-settings

# ── Shared environment ────────────────────────────────────────
cat > /etc/cloud-security-platform.env << 'ENVEOF'
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
AWS_REGION=${aws_region}
S3_CACHE_BUCKET=${s3_cache_bucket}
BEDROCK_MODEL_ID=anthropic.claude-3-sonnet-20240229-v1:0
BEDROCK_EMBEDDING_MODEL_ID=amazon.titan-embed-text-v2:0
FRONTEND_URL=http://localhost
ENVEOF
chmod 600 /etc/cloud-security-platform.env

# ── App directories ───────────────────────────────────────────
mkdir -p /opt/governance-copilot
mkdir -p /opt/discovery-copilot
chown ec2-user:ec2-user /opt/governance-copilot /opt/discovery-copilot

# Symlink shared env into both app dirs
ln -s /etc/cloud-security-platform.env /opt/governance-copilot/.env
ln -s /etc/cloud-security-platform.env /opt/discovery-copilot/.env

# ── Governance Copilot — port 8000 ───────────────────────────
cat > /etc/systemd/system/governance-copilot.service << 'SVCEOF'
[Unit]
Description=AWS Governance Copilot
After=network.target postgresql.service

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/governance-copilot
ExecStart=/usr/bin/python3.11 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=5
EnvironmentFile=/etc/cloud-security-platform.env
StandardOutput=journal
StandardError=journal
SyslogIdentifier=governance-copilot

[Install]
WantedBy=multi-user.target
SVCEOF

# ── Discovery Copilot — port 8001 ────────────────────────────
cat > /etc/systemd/system/discovery-copilot.service << 'SVCEOF'
[Unit]
Description=Security Discovery Copilot
After=network.target governance-copilot.service

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/discovery-copilot
ExecStart=/usr/bin/python3.11 -m uvicorn app.main:app --host 0.0.0.0 --port 8001 --workers 2
Restart=always
RestartSec=5
EnvironmentFile=/etc/cloud-security-platform.env
StandardOutput=journal
StandardError=journal
SyslogIdentifier=discovery-copilot

[Install]
WantedBy=multi-user.target
SVCEOF

# ── Nginx reverse proxy ───────────────────────────────────────
cat > /etc/nginx/conf.d/cloud-security-platform.conf << 'NGINXEOF'
server {
    listen 80;
    server_name _;

    # Governance Copilot API
    location /governance/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
    }

    # Discovery Copilot API
    location /discovery/ {
        proxy_pass http://127.0.0.1:8001/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;

        # SSE support
        proxy_buffering off;
        proxy_cache off;
        proxy_set_header Connection '';
        proxy_http_version 1.1;
        chunked_transfer_encoding on;
    }

    # Health check
    location /health {
        return 200 '{"status":"ok","services":["governance-copilot","discovery-copilot"]}';
        add_header Content-Type application/json;
    }
}
NGINXEOF

systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

echo "Bootstrap complete."
echo "Deploy apps:"
echo "  git clone https://github.com/IshwaryaLakshmiC/aws-governance-copilot /opt/governance-copilot"
echo "  git clone https://github.com/IshwaryaLakshmiC/security-discovery-copilot /opt/discovery-copilot"
echo "Then: systemctl enable --now governance-copilot discovery-copilot"
