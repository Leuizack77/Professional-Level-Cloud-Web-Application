#!/usr/bin/env bash
# ==============================================================================
# user-data.sh — EC2 Launch Template Bootstrap Script (Production Multi-AZ ASG)
# Target OS: Amazon Linux 2023 (ap-southeast-2 / multi-region safe)
# Security Policy: ZERO hardcoded secrets. Credentials retrieved dynamically
# via instance IAM Role (EC2-SSM-Role) from SSM Parameter Store or Secrets Manager.
# ==============================================================================

set -euo pipefail

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "[INFO] Starting Phase 2 ASG instance bootstrap at $(date -u)"

# ------------------------------------------------------------------------------
# 1. Fetch EC2 Metadata & Region dynamically via IMDSv2
# ------------------------------------------------------------------------------
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300" || echo "")
if [ -n "${IMDS_TOKEN}" ]; then
    AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/placement/region || echo "ap-southeast-2")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/instance-id || echo "i-unknown")
else
    AWS_REGION="ap-southeast-2"
    INSTANCE_ID="i-unknown"
fi
echo "[INFO] Running on Instance ${INSTANCE_ID} in Region ${AWS_REGION}"

# ------------------------------------------------------------------------------
# 2. Update OS and install runtime packages (if not already baked into Golden AMI)
# ------------------------------------------------------------------------------
echo "[INFO] Verifying runtime dependencies..."
if ! command -v python3.11 >/dev/null 2>&1 || ! command -v aws >/dev/null 2>&1; then
    dnf update -y
    dnf install -y python3.11 python3.11-pip git awscli jq unzip
fi

# ------------------------------------------------------------------------------
# 3. Create application user & directory structure
# ------------------------------------------------------------------------------
APP_USER="appuser"
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${APP_USER}"
fi

APP_DIR="/var/www/notes-app"
mkdir -p "${APP_DIR}/backend"
chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"

# ------------------------------------------------------------------------------
# 4. Stage Application Code (S3 Artifact, Golden AMI, or Local Deploy)
# ------------------------------------------------------------------------------
# If code is already present (e.g. pre-baked in Golden AMI), skip download
if [ -f "${APP_DIR}/backend/run.py" ] && [ -d "${APP_DIR}/backend/app" ]; then
    echo "[INFO] Application code already present at ${APP_DIR}/backend."
else
    echo "[INFO] Fetching application package..."
    # Check if an S3 deployment bucket is specified via SSM parameter
    S3_DEPLOY_BUCKET=$(aws ssm get-parameter \
        --region "${AWS_REGION}" \
        --name "/notes-app/DEPLOY_BUCKET" \
        --query "Parameter.Value" \
        --output text 2>/dev/null || echo "")

    if [ -n "${S3_DEPLOY_BUCKET}" ] && aws s3 ls "s3://${S3_DEPLOY_BUCKET}/deploy.zip" --region "${AWS_REGION}" >/dev/null 2>&1; then
        echo "[INFO] Downloading deploy.zip from s3://${S3_DEPLOY_BUCKET}..."
        aws s3 cp "s3://${S3_DEPLOY_BUCKET}/deploy.zip" /tmp/deploy.zip --region "${AWS_REGION}"
        unzip -o /tmp/deploy.zip -d "${APP_DIR}"
        chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
    else
        echo "[WARN] No S3 deploy bucket configured. Checking /opt/cloud-notes source..."
        if [ -d "/opt/cloud-notes/backend" ]; then
            cp -a /opt/cloud-notes/backend/. "${APP_DIR}/backend/"
            chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
        fi
    fi
fi

cd "${APP_DIR}/backend"

# ------------------------------------------------------------------------------
# 5. Set up Python virtual environment
# ------------------------------------------------------------------------------
echo "[INFO] Configuring Python 3.11 virtual environment..."
if [ ! -d "venv" ]; then
    sudo -u "${APP_USER}" python3.11 -m venv venv
    sudo -u "${APP_USER}" ./venv/bin/pip install --upgrade pip
fi

if [ -f requirements.txt ]; then
    sudo -u "${APP_USER}" ./venv/bin/pip install -r requirements.txt
else
    sudo -u "${APP_USER}" ./venv/bin/pip install fastapi "uvicorn[standard]" sqlalchemy "psycopg[binary]" pydantic-settings python-dotenv alembic
fi

# ------------------------------------------------------------------------------
# 6. Retrieve Database Credentials & Configuration from AWS SSM / Secrets Manager
# ------------------------------------------------------------------------------
echo "[INFO] Retrieving database credentials from AWS..."

# Option A: Full DATABASE_URL from SSM Parameter Store
DB_URL=$(aws ssm get-parameter \
    --region "${AWS_REGION}" \
    --name "/notes-app/DATABASE_URL" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text 2>/dev/null || echo "")

# Option B: Discrete JSON secret from AWS Secrets Manager
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
        ENCODED_PASS=$(./venv/bin/python -c "import urllib.parse, sys; print(urllib.parse.quote_plus(sys.argv[1]))" "${DB_PASS}")
        DB_URL="postgresql://${DB_USER}:${ENCODED_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require"
    fi
fi

# Fallback: Check if local .env already exists with credentials
if [ -z "${DB_URL}" ] && [ -f "${APP_DIR}/backend/.env" ]; then
    DB_URL=$(grep "^DATABASE_URL=" "${APP_DIR}/backend/.env" | cut -d= -f2- || echo "")
fi

if [ -z "${DB_URL}" ]; then
    echo "[ERROR] Failed to resolve database credentials. Check IAM Role permissions and SSM/Secrets Manager name."
    exit 1
fi

# Retrieve CORS Origins from SSM (with safe local/ALB fallbacks; strictly NO wildcard '*')
ALLOWED_CORS=$(aws ssm get-parameter \
    --region "${AWS_REGION}" \
    --name "/notes-app/CORS_ORIGINS" \
    --query "Parameter.Value" \
    --output text 2>/dev/null || echo "http://localhost,http://127.0.0.1")

# Clean wildcard if mistakenly passed
ALLOWED_CORS=$(echo "${ALLOWED_CORS}" | sed 's/\*//g' | sed 's/,,/,/g')
if [ -z "${ALLOWED_CORS}" ]; then
    ALLOWED_CORS="http://localhost,http://127.0.0.1"
fi

# Write environment configuration (permissions 0600, appuser only)
cat <<EOF > "${APP_DIR}/backend/.env"
DATABASE_URL=${DB_URL}
HOST=0.0.0.0
PORT=8000
ENVIRONMENT=production
CORS_ORIGINS=${ALLOWED_CORS}
DB_POOL_SIZE=10
DB_MAX_OVERFLOW=5
DB_POOL_TIMEOUT=30
DB_POOL_RECYCLE=1800
EOF

chown "${APP_USER}:${APP_USER}" "${APP_DIR}/backend/.env"
chmod 600 "${APP_DIR}/backend/.env"

# ------------------------------------------------------------------------------
# 7. Apply Alembic Database Migrations
# ------------------------------------------------------------------------------
echo "[INFO] Running Alembic migrations to ensure schema is up-to-date..."
sudo -u "${APP_USER}" ./venv/bin/alembic upgrade head || {
    echo "[WARN] Alembic migration failed or was already applied."
}

# ------------------------------------------------------------------------------
# 8. Configure systemd service for FastAPI
# ------------------------------------------------------------------------------
echo "[INFO] Configuring systemd service..."
cat <<EOF > /etc/systemd/system/notes-api.service
[Unit]
Description=Notes Application FastAPI Backend Service
After=network.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}/backend
EnvironmentFile=${APP_DIR}/backend/.env
ExecStart=${APP_DIR}/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=notes-api

# Security Sandboxing
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------------------------
# 9. Start & Enable Service
# ------------------------------------------------------------------------------
echo "[INFO] Enabling and starting notes-api service..."
systemctl daemon-reload
systemctl enable --now notes-api

# ------------------------------------------------------------------------------
# 10. Self-Test Health Probes
# ------------------------------------------------------------------------------
echo "[INFO] Validating local health check..."
sleep 4
if curl -s -f http://127.0.0.1:8000/health >/dev/null; then
    echo "[SUCCESS] Notes API initialized and /health responded 200 OK at $(date -u)"
else
    echo "[ERROR] /health probe failed! Check: journalctl -u notes-api -n 30"
    exit 1
fi

if curl -s -f http://127.0.0.1:8000/health/ready >/dev/null; then
    echo "[SUCCESS] /health/ready probe verified: Process and Database both connected."
else
    echo "[WARN] /health/ready did not return 200 OK. Database might still be initializing."
fi

echo "[INFO] Instance bootstrap complete at $(date -u)"
