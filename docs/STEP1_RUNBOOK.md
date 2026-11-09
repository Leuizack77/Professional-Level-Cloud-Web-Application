# Step 1 Runbook: Single-Server EC2 Deployment Guide (AWS Console — ap-south-1)

A step-by-step AWS Console and Windows PowerShell walkthrough to deploy the Notes application onto a single **Amazon Linux 2023 EC2 instance** (`t3.micro`) in **Asia Pacific (Mumbai) `ap-south-1`**, running Nginx, FastAPI, and PostgreSQL 16.

> [!IMPORTANT]
> **Prerequisites & Security Rules:**
> 1. An active AWS account with administrative access.
> 2. AWS Region set to **Asia Pacific (Mumbai) `ap-south-1`** in the AWS Console.
> 3. Zero cloud CLI commands (`aws`, `az`, `gcloud`) or Terraform commands in this step; execute provisioning strictly via the AWS Console and SSH/SCP.
> 4. Never commit `.pem` key pairs or `.env` files to git. Keep keys secured on your local workstation.
> 5. Ingress restriction: Port 22 (SSH) must strictly allow **My IP only**; Port 80 (HTTP) is open to `0.0.0.0/0`. Ports 8000 (FastAPI) and 5432 (PostgreSQL) are never exposed to the internet.

---

## 📋 Table of Contents
1. [Architecture & Component Layout](#1-architecture--component-layout)
2. [Step 1: Create SSH Key Pair](#step-1-create-ssh-key-pair)
3. [Step 2: Create Security Group (`notes-step1-sg`)](#step-2-create-security-group-notes-step1-sg)
4. [Step 3: Launch Amazon Linux 2023 EC2 Instance](#step-3-launch-amazon-linux-2023-ec2-instance)
5. [Step 4: Package & Transfer Deployment Bundle (PowerShell)](#step-4-package--transfer-deployment-bundle-powershell)
6. [Step 5: Run Server Provisioning Script via SSH](#step-5-run-server-provisioning-script-via-ssh)
7. [Step 6: Functional & Health Verification](#step-6-functional--health-verification)
8. [Step 7: Troubleshooting Runbook](#step-7-troubleshooting-runbook)
9. [Step 8: Teardown Checklist (Reverse Order)](#step-8-teardown-checklist-reverse-order)

---

## 1. Architecture & Component Layout

In Step 1, all application components reside on a single virtual server to validate functionality before decoupling across managed services in Step 2:

```
[ Web Browser ]
      |
      | HTTP (Port 80)
      v
+-----------------------------------------------------------------------+
| EC2 Instance (Amazon Linux 2023 - t3.micro - ap-south-1)             |
|                                                                       |
|  +-----------------------------------------------------------------+  |
|  | Nginx Web Server (Port 80)                                      |  |
|  |   * Serves static React bundle: /var/www/notes-app/frontend/dist|  |
|  |   * Proxies /api/*  -----> http://127.0.0.1:8000                |  |
|  |   * Proxies /health -----> http://127.0.0.1:8000/health         |  |
|  +-----------------------------------------------------------------+  |
|            |                                                          |
|            v (Loopback TCP)                                           |
|  +-----------------------------------------------------------------+  |
|  | FastAPI Backend (systemd: notes-api.service)                   |  |
|  |   * Listens on 127.0.0.1:8000 (Stateless REST API)              |  |
|  |   * Managed by systemd with auto-restart                        |  |
|  +-----------------------------------------------------------------+  |
|            |                                                          |
|            v (Loopback TCP)                                           |
|  +-----------------------------------------------------------------+  |
|  | PostgreSQL 16 Service (systemd: postgresql-16.service)          |  |
|  |   * Listens on 127.0.0.1:5432                                   |  |
|  |   * Database: notes_db | User: notes_user                       |  |
|  +-----------------------------------------------------------------+  |
+-----------------------------------------------------------------------+
```

---

## Step 1: Create SSH Key Pair

1. Open the **EC2 Console** at [https://ap-south-1.console.aws.amazon.com/ec2/home?region=ap-south-1](https://ap-south-1.console.aws.amazon.com/ec2/home?region=ap-south-1).
2. In the left navigation pane under **Network & Security**, click **Key Pairs**.
3. Click **Create key pair** (orange button in top right).
4. Configure key parameters:
   - **Name:** `notes-step1-key`
   - **Key pair type:** `RSA`
   - **Private key file format:** `.pem` (for use with OpenSSH on Windows PowerShell and Linux/macOS)
5. Click **Create key pair**.
6. The file `notes-step1-key.pem` downloads to your local machine.
7. Move the key file to your preferred secure directory (for example `C:\Users\<YourUser>\.ssh\` or the project root).
   > [!WARNING]
   > Ensure `notes-step1-key.pem` is ignored by Git. The repository `.gitignore` has `*.pem` configured. Never commit this file.

### Lock Down Key Permissions (Windows PowerShell)
Windows OpenSSH requires restrictive permissions on `.pem` private key files:
```powershell
# Run in PowerShell where notes-step1-key.pem is located:
icacls.exe notes-step1-key.pem /inheritance:r
icacls.exe notes-step1-key.pem /grant:r "$($env:USERNAME):(R)"
```

### 🔍 How to Verify
In EC2 Console $\to$ **Key Pairs**, confirm `notes-step1-key` is listed with type `RSA`.

---

## Step 2: Create Security Group (`notes-step1-sg`)

1. In the EC2 Console left navigation pane under **Network & Security**, click **Security Groups**.
2. Click **Create security group**.
3. Configure details:
   - **Security group name:** `notes-step1-sg`
   - **Description:** `Step 1 single-server security group - SSH from operator IP, HTTP from all`
   - **VPC:** Select your default VPC (or target VPC).
4. **Inbound rules:**
   - **Rule 1 (SSH Access):**
     - Type: `SSH`
     - Protocol: `TCP`
     - Port range: `22`
     - Source: Select **My IP** (auto-populates your public IP as `x.x.x.x/32`).
     - Description: `SSH ingress restricted strictly to operator IP`
   - **Rule 2 (HTTP Web Access):**
     - Type: `HTTP`
     - Protocol: `TCP`
     - Port range: `80`
     - Source: Select **Anywhere-IPv4** (`0.0.0.0/0`).
     - Description: `Public HTTP access to Nginx web proxy`
5. **Outbound rules:**
   - Keep default: `All traffic`, `0.0.0.0/0` (required for system packages `dnf` and Python packages via pip).
6. Click **Create security group**.

> [!NOTE]
> Ports 8000 and 5432 do NOT have inbound rules. Because FastAPI and PostgreSQL bind strictly to loopback (`127.0.0.1`), they are physically unreachable from the public internet.

### 🔍 How to Verify
Select `notes-step1-sg` $\to$ **Inbound rules** tab:
- Confirm Port 22 source is strictly your IP (`x.x.x.x/32`).
- Confirm Port 80 source is `0.0.0.0/0`.
- Confirm no other ports are open.

---

## Step 3: Launch Amazon Linux 2023 EC2 Instance

1. In the EC2 Console, navigate to **Instances** and click **Launch instances**.
2. Configure instance settings:
   - **Name:** `notes-step1-server`
   - **Application and OS Images (Amazon Machine Image):**
     - Select **Amazon Linux**.
     - AMI: **Amazon Linux 2023 AMI** (`al2023-ami-*-x86_64`) — Free tier eligible.
   - **Instance type:**
     - Select `t3.micro` (2 vCPU, 1 GiB Memory — Free tier eligible).
   - **Key pair (login):**
     - Key pair name: Select `notes-step1-key`.
   - **Network settings:**
     - Click **Edit**.
     - **VPC:** Select default VPC (same VPC as `notes-step1-sg`).
     - **Auto-assign public IP:** Select **Enable**.
     - **Firewall (security groups):** Select **Select existing security group**.
     - Common security groups: Choose `notes-step1-sg`.
   - **Configure storage:**
     - 1x 8 GiB or 20 GiB `gp3` root volume (default 8 GiB is sufficient).
   - **Advanced details:**
     - Leave user data blank (we will run the deployment interactively to inspect output).
3. Review Summary panel on the right and click **Launch instance**.
4. Click **View all instances** and wait until the instance state changes from `Pending` to `Running` and Status check shows `2/2 checks passed`.
5. Select the instance and note its **Public IPv4 address** (referred to below as `<EC2_PUBLIC_IP>`).

### 🔍 How to Verify
In EC2 Console:
- Instance state is **Running**.
- Status check displays **2/2 checks passed**.
- Public IPv4 address is assigned and displayed.

---

## Step 4: Package & Transfer Deployment Bundle (PowerShell)

On your local Windows machine, use the automated packaging script to build the React frontend and bundle all files into `deploy.zip`.

### 4.1 Build and Package
Open Windows PowerShell in the root directory of the repository:
```powershell
# Navigate to repository root
cd "e:\PROJECTS\Professional-Level Cloud Web Application"

# Execute packaging script
powershell -ExecutionPolicy Bypass -File .\deploy\step1\build-and-package.ps1
```

The script automatically:
1. Runs `npm run build` in `frontend/` to generate production static assets.
2. Stages `backend/`, `frontend/dist/`, and `deploy/step1/`.
3. Strips out `venv/`, `.env`, `node_modules/`, `*.pem`, `*.key`, and cache files.
4. Generates `deploy.zip` (~67 KB) at the repository root.

### 4.2 Transfer Archive to EC2
Upload `deploy.zip` to the instance using `scp`:
```powershell
# Replace <path-to-key.pem> and <EC2_PUBLIC_IP> with your actual values:
scp -i notes-step1-key.pem deploy.zip ec2-user@<EC2_PUBLIC_IP>:~/
```

### 🔍 How to Verify
The terminal displays file transfer progress reaching `100%`:
```text
deploy.zip              100%   67KB   1.2MB/s   00:00
```

---

## Step 5: Run Server Provisioning Script via SSH

### 5.1 Connect via SSH
```powershell
ssh -i notes-step1-key.pem ec2-user@<EC2_PUBLIC_IP>
```

### 5.2 Extract Archive & Run Setup Script
Once logged into the Amazon Linux 2023 terminal:
```bash
# Unpack the deployment bundle
unzip deploy.zip

# Grant execute permissions to the setup script
chmod +x deploy/step1/setup-server.sh

# Execute the setup script as root
sudo ./deploy/step1/setup-server.sh
```

> [!TIP]
> You can pass a specific database password via the `-p` parameter:
> `sudo ./deploy/step1/setup-server.sh -p "YourStrongPasswordHere!"`
> If run without `-p`, the script interactively prompts you to enter a password or press Enter to generate a secure 24-character cryptographic password automatically.

### What the Script Performs Automatically:
1. **Installs System Packages:** `python3.11`, `python3.11-pip`, `gcc`, `nginx`, `unzip`, and `postgresql16-server`.
2. **Initializes PostgreSQL:** Runs `postgresql-16-setup initdb`, enables systemd service, and sets `scram-sha-256` authentication in `pg_hba.conf`.
3. **Provisions Database:** Creates `notes_user` and database `notes_db` with granted privileges.
4. **Installs Application:** Copies backend to `/var/www/notes-app/backend` and frontend static bundle to `/var/www/notes-app/frontend/dist`.
5. **Configures Virtual Environment:** Creates Python 3.11 venv, upgrades pip, and installs `requirements.txt`.
6. **Executes Alembic Migration:** Runs `alembic upgrade head` to generate the `notes` table schema and index.
7. **Writes Secure `.env`:** Sets `DATABASE_URL`, `HOST=127.0.0.1`, `PORT=8000`, `ENVIRONMENT=production`, and restricts permissions to `chmod 600`.
8. **Configures Systemd:** Deploys `notes-api.service`, reloads systemd, and starts the FastAPI service.
9. **Configures Nginx:** Deploys `notes-app.conf` to `/etc/nginx/conf.d/`, validates syntax with `nginx -t`, and restarts Nginx.
10. **Runs In-Line Probes:** Executes loopback curls against `/health`, `/health/db`, and Nginx port 80.

### 🔍 How to Verify
The script concludes with:
```text
====================================================================
 Verification Checks
====================================================================
✔ [OK] API Service listening on 127.0.0.1:8000 (/health: 200 OK)
✔ [OK] Database connectivity probe verified (/health/db: 200 OK)
✔ [OK] Nginx reverse proxy routing successfully on port 80

====================================================================
 🎉 Step 1 Deployment Complete!
 Access your Notes app in your browser at:
 http://<EC2_PUBLIC_IP>/
====================================================================
```

---

## Step 6: Functional & Health Verification

### 6.1 CLI Verification (from Local PowerShell or Remote SSH)
Run curl checks against the public IP:
```powershell
# 1. Shallow Health Check (Checks FastAPI process via Nginx)
curl -i http://<EC2_PUBLIC_IP>/health
# Expected: HTTP/1.1 200 OK -> {"status":"healthy","service":"notes-api","timestamp":"..."}

# 2. Deep Health Check (Checks PostgreSQL database connectivity via Nginx)
curl -i http://<EC2_PUBLIC_IP>/health/db
# Expected: HTTP/1.1 200 OK -> {"status":"healthy","database":"connected","timestamp":"..."}

# 3. List Notes API Endpoint
curl -i http://<EC2_PUBLIC_IP>/api/notes
# Expected: HTTP/1.1 200 OK -> [] (empty JSON array initially)
```

### 6.2 Browser Verification
1. Open your web browser and navigate to:
   `http://<EC2_PUBLIC_IP>/`
2. **Verify UI Load:**
   - The dark-themed Notes Application interface loads cleanly.
   - The top header displays:
     - `API: Online` (green status badge)
     - `DB: Connected` (green status badge)
3. **Verify Note Creation:**
   - In the "Create Note" form, enter:
     - **Title:** `Step 1 Single Server Test`
     - **Content:** `FastAPI, Nginx, and PostgreSQL 16 verified on Amazon Linux 2023.`
   - Click **Save Note**.
   - Confirm the note appears in the grid with creation timestamp.
4. **Verify Note Edit:**
   - Click **Edit** on the note card.
   - Modify the title or content.
   - Click **Update Note**.
   - Confirm changes persist on screen.
5. **Verify Search Functionality:**
   - Type `Single Server` in the search bar.
   - Confirm only matching notes are filtered and displayed.
6. **Verify Note Deletion:**
   - Click **Delete** on the note card.
   - Confirm the note is removed from the UI and database.

---

## Step 7: Troubleshooting Runbook

If any component fails to start or responds with an error, execute these diagnostic commands on the EC2 instance via SSH:

### 7.1 FastAPI Backend Diagnostics (`notes-api`)
```bash
# Check service status
sudo systemctl status notes-api

# View recent service logs with active streaming
sudo journalctl -u notes-api -n 50 -e -f

# Manually test FastAPI loopback binding
curl -v http://127.0.0.1:8000/health

# Verify environment file and file permissions
ls -la /var/www/notes-app/backend/.env
sudo cat /var/www/notes-app/backend/.env
```
* **Common Cause for 502 Bad Gateway:** If `notes-api` service crashed on startup, check `journalctl -u notes-api`. Typically caused by database connection issues or missing Python dependencies.
* **Fix:** Manually run alembic or check database credentials:
  ```bash
  cd /var/www/notes-app/backend
  sudo -u ec2-user ./venv/bin/alembic upgrade head
  ```

### 7.2 Nginx Web Proxy Diagnostics
```bash
# Test Nginx configuration file syntax
sudo nginx -t

# Check Nginx service status
sudo systemctl status nginx

# View Nginx error log
sudo tail -n 50 -f /var/log/nginx/error.log

# View Nginx access log
sudo tail -n 50 -f /var/log/nginx/access.log
```
* **Common Cause for 403 Forbidden on static assets:** SELinux or file permissions preventing Nginx from reading `/var/www/notes-app/frontend/dist`.
* **Fix:**
  ```bash
  sudo chown -R ec2-user:ec2-user /var/www/notes-app
  sudo chmod 755 /var/www/notes-app
  sudo chmod -R 755 /var/www/notes-app/frontend/dist
  ```

### 7.3 PostgreSQL Database Diagnostics
```bash
# Check PostgreSQL service status
sudo systemctl status postgresql-16 || sudo systemctl status postgresql

# Connect directly to database using psql
sudo -u postgres psql -d notes_db -c "\dt"

# Inspect PostgreSQL authentication configuration
sudo grep -E "127.0.0.1" /var/lib/pgsql/data/pg_hba.conf || sudo grep -E "127.0.0.1" /var/lib/pgsql/16/data/pg_hba.conf

# Check PostgreSQL error logs
sudo tail -n 50 /var/lib/pgsql/data/log/*.log 2>/dev/null || sudo journalctl -u postgresql-16 -n 50
```
* **Common Cause for "FATAL: password authentication failed":** `pg_hba.conf` had `ident` instead of `scram-sha-256`.
* **Fix:** Re-run line 83 from `setup-server.sh`:
  ```bash
  PG_HBA=$(find /var/lib/pgsql -name "pg_hba.conf" 2>/dev/null | head -n 1)
  sudo sed -i -E 's/host\s+all\s+all\s+127\.0\.0\.1\/32\s+ident/host all all 127.0.0.1\/32 scram-sha-256/' "${PG_HBA}"
  sudo systemctl reload postgresql-16 || sudo systemctl reload postgresql
  ```

### 7.4 Listening Ports & Network Verification
Verify all three internal listening sockets on the instance:
```bash
sudo ss -tulpn | grep -E '80|8000|5432|22'
```
Expected output:
- `0.0.0.0:22` (sshd)
- `0.0.0.0:80` (nginx)
- `127.0.0.1:8000` (python / uvicorn)
- `127.0.0.1:5432` (postgres)

---

## Step 8: Teardown Checklist (Reverse Order)

To ensure zero ongoing cloud costs when testing of Step 1 is finished, tear down the AWS resources in reverse order:

### 8.1 Terminate the EC2 Instance
1. Open the **EC2 Console** $\to$ **Instances**.
2. Select `notes-step1-server`.
3. Click **Instance state** $\to$ **Terminate instance**.
4. In the confirmation dialog, click **Terminate**.
5. Wait ~60 seconds until the instance state displays **Terminated**.

### 8.2 Delete Security Group
1. In the EC2 Console left navigation, select **Security Groups**.
2. Select `notes-step1-sg`.
3. Click **Actions** $\to$ **Delete security groups**.
4. Confirm deletion.

### 8.3 Delete Key Pair (Optional)
1. In the EC2 Console left navigation, select **Key Pairs**.
2. Select `notes-step1-key`.
3. Click **Actions** $\to$ **Delete**.
4. Type `Delete` to confirm.

### 8.4 Clean Up Local Artifacts
On your local Windows machine:
```powershell
# Delete local deployment zip and downloaded key pair (if desired)
Remove-Item -Path "deploy.zip" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "notes-step1-key.pem" -Force -ErrorAction SilentlyContinue
```
