# Professional-Level Cloud Web Application — Notes App

A production-ready, decoupled full-stack Notes web application engineered to be deployed to a high-availability cloud architecture.

---

## 🏛️ Target Cloud Architecture

The application is structured into decoupled tiers, adhering to modern cloud-native best practices:

```text
                  +-----------------------+
                  |         Users         |
                  +-----------+-----------+
                              |
               +--------------+--------------+
               |                             |
      (Static Assets)                 (API Requests)
               |                             |
               v                             v
     +-------------------+         +-------------------+
     |   Cloud CDN /     |         |    Application    |
     |   CloudFront      |         |   Load Balancer   |
     +---------+---------+         +---------+---------+
               |                             |
               v                             v
     +-------------------+         +-------------------+
     | S3 / Blob Storage |         | Auto Scaling Group|
     | (Static Frontend) |         | (FastAPI on EC2)  |
     +-------------------+         +---------+---------+
                                             |
                                             v
                                   +-------------------+
                                   |  Managed Database |
                                   | (RDS PostgreSQL)  |
                                   +-------------------+
```

### Decoupled Layers
1. **Frontend Tier (Static Hosting):**
   - Built with **React + Vite** as a Single Page Application (SPA).
   - Compiles into pure static assets (`dist/`) suitable for hosting on **AWS S3** / **Azure Blob Storage** fronted by a **CDN (AWS CloudFront)** for low latency worldwide.
2. **API Tier (Stateless Compute):**
   - Built with **FastAPI (Python)**.
   - Stateless REST API designed to run on **Amazon EC2 / Virtual Machines** managed by an **Auto Scaling Group** inside a private **VPC**.
   - Fronted by an **Application Load Balancer (ALB)**.
   - Provides a fast, DB-independent `/health` check for the ALB, and a deep `/health/db` probe for infrastructure monitoring.
3. **Database Tier (Relational Data):**
   - Managed relational database (**AWS RDS PostgreSQL** / **Azure Database**).
   - In local development, an identical containerized **PostgreSQL 16** instance runs via Docker Compose.

---

## 🛡️ Critical Rules for Developers & AI Agents

> [!CAUTION]
> **1. Never Run Cloud Commands or Terraform Apply/Destroy:**
> All infrastructure-as-code and cloud deployment steps are deferred until the application is finalized. Never execute `aws`, `az`, `gcloud`, or `terraform apply`/`terraform destroy` commands in this phase.

> [!WARNING]
> **2. Never Commit Secrets or `.env` Files:**
> Production passwords, tokens, private keys, and `.env` files must NEVER be committed to Git. Always use `.env.example` as a sanitised template.

> [!IMPORTANT]
> **3. Ask Before Adding New Tools:**
> Do not introduce unapproved third-party dependencies, packages, CLI tools, or external services without explicit user approval.

---

## 🚀 Local Run Instructions

### Prerequisites
- **Python 3.11+** installed
- **Node.js 18+ & npm** installed
- **Docker Desktop** (or Docker Engine) running

---

### Step 1: Start the Local PostgreSQL Database
Run Docker Compose from the project root:
```bash
docker compose up -d
```
*(Runs PostgreSQL on mapped port `localhost:5433` to prevent conflicts with any host database services).*
Verify the container is healthy:
```bash
docker compose ps
```

---

### Step 2: Start the Backend API Server
1. Navigate to `backend/`:
   ```bash
   cd backend
   ```
2. Create and activate a Python virtual environment:
   - **Windows (PowerShell):**
     ```powershell
     python -m venv venv
     .\venv\Scripts\Activate.ps1
     ```
   - **Linux / macOS:**
     ```bash
     python3 -m venv venv
     source venv/bin/activate
     ```
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
4. Copy the environment configuration:
   - **Windows:**
     ```powershell
     Copy-Item ..\.env.example .env
     ```
   - **Linux / macOS:**
     ```bash
     cp ../.env.example .env
     ```
5. Start the backend:
   ```bash
   python run.py
   ```
   * **API Root:** [http://localhost:8000](http://localhost:8000)
   * **ALB Health Probe (Independent of DB):** [http://localhost:8000/health](http://localhost:8000/health)
   * **Database Health Probe:** [http://localhost:8000/health/db](http://localhost:8000/health/db)
   * **Interactive Swagger UI:** [http://localhost:8000/docs](http://localhost:8000/docs)

---

### Step 3: Start the Frontend Application
1. In a new terminal, navigate to `frontend/`:
   ```bash
   cd frontend
   ```
2. Install frontend dependencies:
   ```bash
   npm install
   ```
3. Start the Vite development server:
   ```bash
   npm run dev
   ```
   * **Frontend UI:** [http://localhost:5173](http://localhost:5173)

---

### Step 4: Build Static Frontend for Cloud Deployment
To compile the frontend into static files ready for AWS S3:
```bash
cd frontend
npm run build
```
The production bundle will be generated in `frontend/dist/`.

---

## 🧪 Running Automated Tests

Run backend tests using `pytest` inside the `backend/` directory:
```bash
cd backend
pytest -v
```

---

## 📡 API Specification

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Shallow health check (ALB probe; returns 200 OK without touching DB) |
| `GET` | `/health/db` | Deep database health check (verifies PostgreSQL connection) |
| `GET` | `/api/notes` | List all notes (ordered by latest updated) |
| `POST` | `/api/notes` | Create a new note (`title`, `content`) |
| `GET` | `/api/notes/{id}` | Retrieve a specific note by ID |
| `PUT` | `/api/notes/{id}` | Update note title and/or content |
| `DELETE` | `/api/notes/{id}` | Delete a note by ID |

---

## 📚 Complete Project Documentation

| Document | Description |
|---|---|
| [**`docs/PRD.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/PRD.md) | Product Requirements Document: user stories, acceptance criteria, and feature specifications. |
| [**`docs/PHASES.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/PHASES.md) | Project Execution Phases & Roadmap: Phase 0 through Phase 5 transition gates. |
| [**`docs/RULES.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/RULES.md) | Engineering Rules, Coding Standards & Constraints: Mandatory stack, prohibitions, security rules. |
| [**`docs/DESIGN.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/DESIGN.md) | Design System & UI/UX Specification: Color palette, typography tokens, component geometry. |
| [**`docs/MEMORY.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/MEMORY.md) | Project Memory & Context State Tracker: Living record of completed work and active focus. |
| [**`docs/ARCHITECTURE.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/ARCHITECTURE.md) | Target Cloud Architecture: 3-tier AWS topology in `ap-south-1`, dual-origin CloudFront, and cost breakdown. |
| [**`docs/STEP2_RUNBOOK.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/STEP2_RUNBOOK.md) | Manual AWS Console Runbook: Click-by-click provisioning guide with verification checks and teardown. |
| [**`docs/DATABASE.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/DATABASE.md) | Database Specification: PostgreSQL schemas, query-specific indexes, migrations, and PITR backup plans. |
| [**`docs/SECURITY.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/SECURITY.md) | Security Review & Audit History: Data classification, network boundaries, OWASP Top 10 checklist, and remediations. |
| [**`docs/TESTING.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/TESTING.md) | Testing Strategy: Test pyramid, execution commands, and three chaos infrastructure proofs. |
| [**`AGENTS.md`**](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/AGENTS.md) | AI Agent Guidelines: Quick-reference repository manual, commands, hard rules, and 5-step workflow. |
