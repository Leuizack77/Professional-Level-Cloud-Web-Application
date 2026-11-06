#!/usr/bin/env bash
# ==============================================================================
# user-data.sh — EC2 Launch Template Bootstrap Script
# Target OS: Amazon Linux 2023 (ap-south-1)
# Security Policy: ZERO hardcoded secrets. Credentials retrieved dynamically
# via instance IAM Role from AWS Systems Manager Parameter Store or Secrets Manager.
# ==============================================================================

set -euo pipefail

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "[INFO] Starting bootstrap at $(date -u)"

# 1. Update OS and install runtime packages
echo "[INFO] Installing system dependencies..."
dnf update -y
dnf install -y python3.11 python3.11-pip git awscli jq

# 2. Create application system user and directory
echo "[INFO] Creating application user and directory structure..."
if ! id -u appuser >/dev/null 2>&1; then
    useradd -m -s /bin/bash appuser
fi

APP_DIR="/opt/notes-api"
mkdir -p "${APP_DIR}"
chown -R appuser:appuser "${APP_DIR}"

# 3. Clone or deploy application code
# (In production, replace with your GitHub repository URL or S3 artifact tarball)
REPO_URL="https://github.com/your-org/professional-level-cloud-web-application.git"

if [ ! -d "${APP_DIR}/.git" ]; then
    echo "[INFO] Cloning application repository..."
    sudo -u appuser git clone "${REPO_URL}" "${APP_DIR}" || {
        echo "[WARN] Git clone failed or placeholder used; ensuring backend directory exists..."
        mkdir -p "${APP_DIR}/backend/app"
    }
fi

cd "${APP_DIR}/backend"

# 4. Set up Python virtual environment
echo "[INFO] Setting up Python virtual environment..."
sudo -u appuser python3.11 -m venv venv
sudo -u appuser ./venv/bin/pip install --upgrade pip

if [ -f requirements.txt ]; then
    sudo -u appuser ./venv/bin/pip install -r requirements.txt
else
    sudo -u appuser ./venv/bin/pip install fastapi "uvicorn[standard]" sqlalchemy "psycopg[binary]" pydantic-settings python-dotenv
fi

# 5. Retrieve Database Credentials from AWS SSM Parameter Store / Secrets Manager
# IAM role attached to EC2 must have ssm:GetParameter or secretsmanager:GetSecretValue permission
echo "[INFO] Retrieving database credentials from AWS..."
AWS_REGION="ap-south-1"

# Option A: AWS SSM Parameter Store (Free Tier friendly)
DB_URL=$(aws ssm get-parameter \
    --region "${AWS_REGION}" \
    --name "/notes-app/DATABASE_URL" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text 2>/dev/null || echo "")

# Fallback Option B: Secrets Manager if SSM parameter is empty
if [ -z "${DB_URL}" ]; then
    SECRET_JSON=$(aws secretsmanager get-secret-value \
        --region "${AWS_REGION}" \
        --secret-id "prod/notes-app/database" \
        --query "SecretString" \
        --output text 2>/dev/null || echo "")

    if [ -n "${SECRET_JSON}" ]; then
        DB_USER=$(echo "${SECRET_JSON}" | jq -r '.username')
        DB_PASS=$(echo "${SECRET_JSON}" | jq -r '.password')
        DB_HOST=$(echo "${SECRET_JSON}" | jq -r '.host')
        DB_PORT=$(echo "${SECRET_JSON}" | jq -r '.port // 5432')
        DB_NAME=$(echo "${SECRET_JSON}" | jq -r '.dbname // "notes_db"')
        DB_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    fi
fi

if [ -z "${DB_URL}" ]; then
    echo "[ERROR] Failed to retrieve database credentials from AWS. Check IAM Role and Parameter/Secret name."
    exit 1
fi

# Write environment configuration (permissions 0600, appuser only)
cat <<EOF > "${APP_DIR}/backend/.env"
DATABASE_URL=${DB_URL}
HOST=0.0.0.0
PORT=8000
ENVIRONMENT=production
CORS_ORIGINS=https://*
EOF

chown appuser:appuser "${APP_DIR}/backend/.env"
chmod 600 "${APP_DIR}/backend/.env"

# 6. Configure systemd service for FastAPI
echo "[INFO] Creating systemd service..."
cat <<EOF > /etc/systemd/system/notes-api.service
[Unit]
Description=Notes Application FastAPI Service
After=network.target

[Service]
Type=simple
User=appuser
Group=appuser
WorkingDirectory=${APP_DIR}/backend
EnvironmentFile=${APP_DIR}/backend/.env
ExecStart=${APP_DIR}/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 7. Start and enable systemd service
echo "[INFO] Enabling and starting notes-api service..."
systemctl daemon-reload
systemctl enable --now notes-api

# 8. Self-test health probe locally
echo "[INFO] Validating local health check..."
sleep 3
if curl -s -f http://localhost:8000/health >/dev/null; then
    echo "[SUCCESS] Notes API initialized and /health responded with 200 OK at $(date -u)"
else
    echo "[WARN] Service started but /health probe did not immediately respond 200. Check: journalctl -u notes-api"
fi

