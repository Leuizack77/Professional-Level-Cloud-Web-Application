#!/usr/bin/env bash
# ==============================================================================
# setup-server.sh — Step 1 Single Server Provisioning Script
# Target OS: Amazon Linux 2023 (ap-south-1)
# Components: Nginx (Reverse Proxy & Static Hosting), FastAPI (API), PostgreSQL 16
# Security: Zero hardcoded passwords. Password prompted or passed via -p flag.
# ==============================================================================

set -euo pipefail

# Ensure script is executed with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] setup-server.sh must be executed as root (e.g. sudo ./setup-server.sh)"
    exit 1
fi

echo "===================================================================="
echo " Starting Step 1 Single-Server Setup on Amazon Linux 2023"
echo " Date: $(date -u)"
echo "===================================================================="

# ------------------------------------------------------------------------------
# 1. Parse or Prompt for Database Password (Never Hardcoded, Never Printed)
# ------------------------------------------------------------------------------
DB_PASS=""
while getopts "p:" opt; do
    case "${opt}" in
        p) DB_PASS="${OPTARG}" ;;
        *) echo "Usage: sudo $0 [-p <database_password>]" && exit 1 ;;
    esac
done

if [ -z "${DB_PASS}" ]; then
    echo ""
    echo "--- PostgreSQL Configuration ---"
    read -r -s -p "Enter secure password for database user 'notes_user' (leave empty to generate): " USER_INPUT
    echo ""
    if [ -n "${USER_INPUT}" ]; then
        DB_PASS="${USER_INPUT}"
    else
        DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 24)
        echo "[INFO] Generated secure random database password."
    fi
fi

# ------------------------------------------------------------------------------
# 2. Update OS & Install System Dependencies
# ------------------------------------------------------------------------------
echo "[1/8] Updating package repository and installing runtime packages..."
dnf update -y
dnf install -y python3.11 python3.11-pip python3.11-devel git gcc nginx unzip

# Install PostgreSQL 16 (or available release on AL2023)
if dnf list postgresql16-server >/dev/null 2>&1; then
    dnf install -y postgresql16-server postgresql16
    PG_SERVICE="postgresql-16"
    PG_SETUP="postgresql-16-setup"
elif dnf list postgresql15-server >/dev/null 2>&1; then
    dnf install -y postgresql15-server postgresql15
    PG_SERVICE="postgresql-15"
    PG_SETUP="postgresql-15-setup"
else
    dnf install -y postgresql-server postgresql
    PG_SERVICE="postgresql"
    PG_SETUP="postgresql-setup"
fi

# ------------------------------------------------------------------------------
# 3. Initialize and Start PostgreSQL Service
# ------------------------------------------------------------------------------
echo "[2/8] Initializing and starting PostgreSQL service (${PG_SERVICE})..."
PG_INITIALIZED=0
if [ -s "/var/lib/pgsql/data/PG_VERSION" ] || [ -s "/var/lib/pgsql/16/data/PG_VERSION" ]; then
    PG_INITIALIZED=1
fi

if [ "${PG_INITIALIZED}" -eq 0 ]; then
    echo "[INFO] Initializing PostgreSQL cluster..."
    if command -v "${PG_SETUP}" >/dev/null 2>&1; then
        "${PG_SETUP}" initdb 2>/dev/null || "${PG_SETUP}" --initdb 2>/dev/null || true
    fi
    if [ ! -s "/var/lib/pgsql/data/PG_VERSION" ] && [ ! -s "/var/lib/pgsql/16/data/PG_VERSION" ]; then
        if command -v postgresql-setup >/dev/null 2>&1; then
            postgresql-setup --initdb --unit "${PG_SERVICE}" 2>/dev/null || postgresql-setup --initdb 2>/dev/null || true
        fi
    fi
    if [ ! -s "/var/lib/pgsql/data/PG_VERSION" ] && [ ! -s "/var/lib/pgsql/16/data/PG_VERSION" ]; then
        mkdir -p /var/lib/pgsql/data
        chown -R postgres:postgres /var/lib/pgsql
        sudo -u postgres initdb -D /var/lib/pgsql/data
    fi
fi

systemctl daemon-reload
systemctl enable --now "${PG_SERVICE}"
systemctl is-active --quiet "${PG_SERVICE}" || {
    echo "[ERROR] Failed to start PostgreSQL service (${PG_SERVICE})"
    exit 1
}

# Create compatibility symlink for postgresql.service
ln -sf "/usr/lib/systemd/system/${PG_SERVICE}.service" /etc/systemd/system/postgresql.service 2>/dev/null || true

# Configure postgresql.conf to strictly bind to loopback 127.0.0.1
PG_CONF=$(find /var/lib/pgsql -name "postgresql.conf" 2>/dev/null | head -n 1)
if [ -n "${PG_CONF}" ]; then
    if grep -q "^#*listen_addresses\s*=" "${PG_CONF}"; then
        sed -i -E "s/^#*listen_addresses\s*=.*$/listen_addresses = '127.0.0.1'/" "${PG_CONF}"
    else
        echo "listen_addresses = '127.0.0.1'" >> "${PG_CONF}"
    fi
fi

# Configure pg_hba.conf to require scram-sha-256 for local TCP connections
PG_HBA=$(find /var/lib/pgsql -name "pg_hba.conf" 2>/dev/null | head -n 1)
if [ -n "${PG_HBA}" ]; then
    sed -i -E 's/host\s+all\s+all\s+127\.0\.0\.1\/32\s+(ident|md5|trust)/host all all 127.0.0.1\/32 scram-sha-256/' "${PG_HBA}" || true
    sed -i -E 's/host\s+all\s+all\s+::1\/128\s+(ident|md5|trust)/host all all ::1\/128 scram-sha-256/' "${PG_HBA}" || true
    if ! grep -q "127.0.0.1/32.*scram-sha-256" "${PG_HBA}"; then
        echo "host all all 127.0.0.1/32 scram-sha-256" >> "${PG_HBA}"
    fi
    systemctl restart "${PG_SERVICE}"
fi

# ------------------------------------------------------------------------------
# 4. Provision PostgreSQL Database & User
# ------------------------------------------------------------------------------
echo "[3/8] Provisioning database 'notes_db' and user 'notes_user'..."
USER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='notes_user'" || echo "0")
if [ "${USER_EXISTS}" != "1" ]; then
    sudo -u postgres psql -v v_pass="${DB_PASS}" -c "CREATE USER notes_user WITH PASSWORD :'v_pass';"
else
    sudo -u postgres psql -v v_pass="${DB_PASS}" -c "ALTER USER notes_user WITH PASSWORD :'v_pass';"
fi

DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='notes_db'" || echo "0")
if [ "${DB_EXISTS}" != "1" ]; then
    sudo -u postgres psql -c "CREATE DATABASE notes_db OWNER notes_user;"
fi

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE notes_db TO notes_user;"
sudo -u postgres psql -d notes_db -c "GRANT ALL ON SCHEMA public TO notes_user;" || true
sudo -u postgres psql -d notes_db -c "ALTER SCHEMA public OWNER TO notes_user;" || true

# ------------------------------------------------------------------------------
# 5. Set Up Application Directory & Files
# ------------------------------------------------------------------------------
echo "[4/8] Setting up application files at /var/www/notes-app..."
APP_DIR="/var/www/notes-app"
mkdir -p "${APP_DIR}/backend"
mkdir -p "${APP_DIR}/frontend/dist"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Copy backend files
if [ -d "${PROJECT_ROOT}/backend" ]; then
    cp -a "${PROJECT_ROOT}/backend/." "${APP_DIR}/backend/"
elif [ -d "$(pwd)/backend" ]; then
    cp -a "$(pwd)/backend/." "${APP_DIR}/backend/"
else
    echo "[ERROR] backend directory not found!"
    exit 1
fi

# Copy frontend/dist files
if [ -d "${PROJECT_ROOT}/frontend/dist" ]; then
    cp -a "${PROJECT_ROOT}/frontend/dist/." "${APP_DIR}/frontend/dist/"
elif [ -d "${SCRIPT_DIR}/frontend/dist" ]; then
    cp -a "${SCRIPT_DIR}/frontend/dist/." "${APP_DIR}/frontend/dist/"
elif [ -d "$(pwd)/frontend/dist" ]; then
    cp -a "$(pwd)/frontend/dist/." "${APP_DIR}/frontend/dist/"
else
    echo "[ERROR] frontend/dist directory not found! Run build before deploying."
    exit 1
fi

# Set proper filesystem ownership and permissions (Nginx readable, backend protected)
chown -R ec2-user:ec2-user "${APP_DIR}"
chmod 755 "${APP_DIR}"
chmod 755 "${APP_DIR}/frontend"
chmod -R 755 "${APP_DIR}/frontend/dist"
chmod 750 "${APP_DIR}/backend"

# ------------------------------------------------------------------------------
# 6. Set Up Python Virtual Environment & Alembic Migrations
# ------------------------------------------------------------------------------
echo "[5/8] Setting up Python 3.11 virtual environment and dependencies..."
cd "${APP_DIR}/backend"

sudo -u ec2-user python3.11 -m venv venv
sudo -u ec2-user ./venv/bin/pip install --upgrade pip
sudo -u ec2-user ./venv/bin/pip install -r requirements.txt

# Determine host public IP for CORS origin configuration
PUBLIC_IP=$(curl -s --max-time 3 http://checkip.amazonaws.com | tr -d '\r\n ' || echo "")
if [ -z "${PUBLIC_IP}" ]; then
    IMDS_TOKEN=$(curl -s --max-time 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || echo "")
    if [ -n "${IMDS_TOKEN}" ]; then
        PUBLIC_IP=$(curl -s --max-time 2 -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    fi
fi

CORS_ORIGIN_LIST="http://localhost,http://127.0.0.1"
if [ -n "${PUBLIC_IP}" ]; then
    CORS_ORIGIN_LIST="${CORS_ORIGIN_LIST},http://${PUBLIC_IP}"
fi

# URL-encode database password to safely handle special characters in DATABASE_URL
ENCODED_DB_PASS=$(python3.11 -c "import urllib.parse, sys; print(urllib.parse.quote_plus(sys.argv[1]))" "${DB_PASS}")

# Write backend .env with 0600 permissions
cat <<EOF > "${APP_DIR}/backend/.env"
DATABASE_URL=postgresql://notes_user:${ENCODED_DB_PASS}@127.0.0.1:5432/notes_db
HOST=127.0.0.1
PORT=8000
ENVIRONMENT=production
CORS_ORIGINS=${CORS_ORIGIN_LIST}
EOF

chown ec2-user:ec2-user "${APP_DIR}/backend/.env"
chmod 600 "${APP_DIR}/backend/.env"

echo "[6/8] Running Alembic database migrations..."
sudo -u ec2-user ./venv/bin/alembic upgrade head

# ------------------------------------------------------------------------------
# 7. Configure Systemd Service for FastAPI API
# ------------------------------------------------------------------------------
echo "[7/8] Configuring systemd service for notes-api..."
mkdir -p /etc/systemd/system

if [ -f "${SCRIPT_DIR}/api.service" ]; then
    cp "${SCRIPT_DIR}/api.service" /etc/systemd/system/notes-api.service
    sed -i -E "s/postgresql(-16)?\.service/${PG_SERVICE}\.service/g" /etc/systemd/system/notes-api.service
else
    cat <<EOF > /etc/systemd/system/notes-api.service
[Unit]
Description=Notes Application FastAPI Backend Service
After=network.target ${PG_SERVICE}.service
Wants=${PG_SERVICE}.service

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=/var/www/notes-app/backend
EnvironmentFile=/var/www/notes-app/backend/.env
ExecStart=/var/www/notes-app/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=notes-api

# Security Hardening Sandbox
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload
systemctl enable --now notes-api
systemctl is-active --quiet notes-api || {
    echo "[ERROR] notes-api service failed to start! Check: journalctl -u notes-api -n 30"
    exit 1
}

# ------------------------------------------------------------------------------
# 8. Configure Nginx Reverse Proxy
# ------------------------------------------------------------------------------
echo "[8/8] Configuring Nginx reverse proxy..."
mkdir -p /etc/nginx/conf.d

# Remove default Welcome server block from nginx.conf if present
if [ -f /etc/nginx/nginx.conf ]; then
    sed -i '/default_server/s/default_server//g' /etc/nginx/nginx.conf || true
fi

if [ -f "${SCRIPT_DIR}/nginx.conf" ]; then
    cp "${SCRIPT_DIR}/nginx.conf" /etc/nginx/conf.d/notes-app.conf
fi

nginx -t
systemctl enable --now nginx
systemctl restart nginx

# ------------------------------------------------------------------------------
# Verification & Output
# ------------------------------------------------------------------------------
sleep 3
echo ""
echo "===================================================================="
echo " Verification Checks"
echo "===================================================================="

# Check 1: API Direct Loopback Health Check
if curl -s -f http://127.0.0.1:8000/health >/dev/null; then
    echo "✔ [OK] API Service listening on 127.0.0.1:8000 (/health: 200 OK)"
else
    echo "✖ [FAIL] API Service failed health probe. Check: journalctl -u notes-api -n 30"
    exit 1
fi

# Check 2: Database Connectivity Health Check
if curl -s -f http://127.0.0.1:8000/health/db >/dev/null; then
    echo "✔ [OK] Database connectivity probe verified (/health/db: 200 OK)"
else
    echo "✖ [FAIL] Database connectivity probe failed. Check PostgreSQL logs"
    exit 1
fi

# Check 3: Nginx Proxy Health Check
if curl -s -f http://127.0.0.1/health >/dev/null; then
    echo "✔ [OK] Nginx reverse proxy routing successfully on port 80"
else
    echo "✖ [FAIL] Nginx proxy failed. Check: nginx -t"
    exit 1
fi

if [ -z "${PUBLIC_IP}" ]; then
    PUBLIC_IP="<EC2_PUBLIC_IP>"
fi

echo ""
echo "===================================================================="
echo " 🎉 Step 1 Deployment Complete!"
echo " Access your Notes app in your browser at:"
echo " http://${PUBLIC_IP}/"
echo "===================================================================="
