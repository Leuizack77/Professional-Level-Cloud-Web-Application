# Project Memory & Context State Tracker

**Project Name:** Professional-Level Cloud Web Application (Cloud Notes)  
**Last Updated:** 2026-11-06  
**Current Phase:** Step 1 Packaging & Console Runbook Complete $\to$ Step 1 Deployment Execution Ready  
**Status:** In Active Development (Awaiting Cloud Execution Approval)  

---

## 1. Project Identity & Architecture Snapshot

* **Application Type:** Decoupled 3-Tier Notes Web Application.
* **Target Cloud:** Amazon Web Services (AWS) in **Asia Pacific (Mumbai) `ap-south-1`**.
* **Frontend Tier:** React 18 + Vite Single Page Application, compiled to static assets (`frontend/dist/`) for **Amazon S3** behind **CloudFront CDN** (or Nginx in Step 1).
* **Backend Tier:** Stateless **FastAPI** (Python 3.11) REST API designed for **EC2 Auto Scaling Group** behind an **Application Load Balancer** in private VPC subnets (or local loopback behind Nginx in Step 1).
* **Database Tier:** Relational **PostgreSQL 16** (local Docker on loopback port `5433:5432`; local PostgreSQL 16 on loopback `127.0.0.1:5432` in Step 1; **Amazon RDS `db.t3.micro` Single-AZ** in Step 2).
* **Dual Health Probes:**
  - `GET /health`: Shallow check (HTTP 200) strictly independent of database for ALB/Nginx viability.
  - `GET /health/db`: Deep check executing `SELECT 1` to monitor PostgreSQL connectivity.

---

## 2. Completed Milestones & Accomplishments

### ✅ Prep Phase: Local Full-Stack Prototype, Tests & Security Hardening
- **Local Application Architecture:** Developed FastAPI REST API with SQLAlchemy models (`Note`), Pydantic v2 schemas, and CRUD endpoints (`/api/notes`).
- **Static Frontend Bundle:** Built React 18 + Vite SPA with responsive card grid, modal form, real-time search, and live health status badges. Compiles to pure static assets in `frontend/dist/` in $< 1.0\text{ s}$.
- **Containerized Database:** Configured Docker Compose PostgreSQL 16 Alpine bound strictly to loopback interface `127.0.0.1:5433:5432`.
- **Test Harness (100% Pass Rate):**
  - Backend: 11 `pytest` tests using in-memory SQLite isolation (shallow health, deep DB health, CRUD lifecycle, search queries, security headers, input bounds, and wildcard CORS rejection).
  - Frontend: 2 `node:test` unit tests validating API client URL construction, query parsing, and payload submission.
- **Security Audit Remediation:** Resolved all 7 audit vulnerabilities from [docs/SECURITY.md](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/SECURITY.md) (safe error messages, 50,000 char content limit, 100 char search limit, strict non-wildcard CORS, credential fallback elimination, loopback port binding, and defensive security headers).
- **Core Documentation Suite:** Created PRD.md, RULES.md, DESIGN.md, ARCHITECTURE.md, DATABASE.md, SECURITY.md, TESTING.md, STEP2_RUNBOOK.md, and AGENTS.md.

### ✅ Step 1 Deliverables: Single-Server Artifacts & Operational Runbook
- **Frontend Relative URLs:** Configured `/api/...`, `/health`, and `/health/db` relative paths in `frontend/src/api.js` with Vite proxy preserved for local dev.
- **Automated Server Provisioning:** Created `deploy/step1/setup-server.sh` for Amazon Linux 2023 installing Python 3.11, Nginx, PostgreSQL 16, user setup with prompted/CLI password, Alembic migrations, 0600 `.env` generation, and verification probes.
- **Service & Proxy Templates:** Created `deploy/step1/nginx.conf` (SPA routing fallback, security headers, proxying) and `deploy/step1/api.service` (systemd service with auto-restart).
- **Automated Packaging:** Created and verified `deploy/step1/build-and-package.ps1` in Windows PowerShell, compiling frontend static assets and packaging clean `deploy.zip` (~67 KB) excluding `.env`, `venv`, `node_modules`, `*.pem`, `*.key`.
- **Operational Runbook:** Published [docs/STEP1_RUNBOOK.md](file:///e:/PROJECTS/Professional-Level%20Cloud%20Web%20Application/docs/STEP1_RUNBOOK.md) with exact AWS Console steps, key pair permissions lockdown, security group rules (SSH from My IP only, HTTP 80 from all), SCP/SSH execution, browser verification, diagnostic troubleshooting commands, and teardown checklist.
- **Git Protection:** Verified `*.pem`, `*.key`, `deploy.zip`, `*.zip`, and `.env` in `.gitignore`.

---

## 3. Active Working Files & Registry

| File Path | Role | Current Status |
|---|---|---|
| `docs/PRD.md` | Product Requirements Document | Complete (local targets updated) |
| `docs/PHASES.md` | Project Execution Phases & Roadmap | Restructured around 3 steps |
| `docs/RULES.md` | Coding Standards & Security Constraints | Complete & Approved |
| `docs/DESIGN.md` | UI/UX & Design System Tokens | Complete & Approved |
| `docs/MEMORY.md` | Living Context & State Tracker (this file) | Complete & Up-to-Date |
| `docs/ARCHITECTURE.md` | Target Cloud Architecture & Cost Model | Complete & Up-to-Date |
| `docs/DATABASE.md` | PostgreSQL Schema & Operational Specs | Complete & Up-to-Date |
| `docs/SECURITY.md` | Security Review & Audit History | Complete & Remediated |
| `docs/TESTING.md` | Testing Guide & Infrastructure Proofs | Complete & Up-to-Date |
| `docs/STEP1_RUNBOOK.md` | Step 1 EC2 Console Manual Guide | Complete & Verified |
| `docs/STEP2_RUNBOOK.md` | Step 2 AWS Console Manual Guide | Complete & Up-to-Date |
| `AGENTS.md` | Repository Manual for AI Agents | Updated with Step 1 runbook |
| `deploy/step1/setup-server.sh` | AL2023 Single-Server Setup Script | Complete & Hardened |
| `deploy/step1/nginx.conf` | Step 1 Nginx Proxy Configuration | Complete & Verified |
| `deploy/step1/api.service` | Step 1 Systemd Unit File | Complete & Verified |
| `deploy/step1/build-and-package.ps1` | Windows Packaging Script | Tested & Generates deploy.zip |
| `backend/app/main.py` | FastAPI Entrypoint & Middleware | Complete & Hardened |
| `backend/tests/test_api.py` | Pytest Integration Test Suite | 11/11 Passing |
| `frontend/src/App.jsx` | React SPA UI View | Complete & Functional |
| `frontend/src/api.js` | Frontend API Client (Relative Paths) | Complete & Verified |
| `frontend/src/api.test.js` | Frontend Unit Test Suite | 2/2 Passing |

---

## 4. Current Test & Verification Status

```text
Backend Test Suite (pytest -v):
  ✔ 11 passed in 1.15s (in-memory SQLite test isolation)

Frontend Test Suite (npm test):
  ✔ 2 passed in 110ms (native node:test runner)

Frontend Static Compilation (npm run build):
  ✔ Built static bundle in frontend/dist/ in 992ms

Step 1 Packaging (build-and-package.ps1):
  ✔ Generated clean deploy.zip (66.68 KB) with zero secrets or dev dependencies
```

---

## 5. Next Planned Actions

* finish Step 1 deployment

---

## 6. Open Issues & Blockers

* **None.** Step 1 deployment package, configuration templates, server setup script, and console runbook are completely built, tested, and ready for operator execution in the AWS Console.
