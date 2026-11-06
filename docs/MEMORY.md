# Project Memory & Context State Tracker

**Project Name:** Professional-Level Cloud Web Application (Cloud Notes)  
**Last Updated:** 2026-11-06  
**Current Phase:** Phase 2 Complete (Security Hardened & Verified) $\to$ Phase 4 Runbook Ready  
**Status:** In Active Development (Awaiting Cloud Execution Approval)  

---

## 1. Project Identity & Architecture Snapshot

* **Application Type:** Decoupled 3-Tier Notes Web Application.
* **Target Cloud:** Amazon Web Services (AWS) in **Asia Pacific (Mumbai) `ap-south-1`**.
* **Frontend Tier:** React 18 + Vite Single Page Application, compiled to static assets (`frontend/dist/`) for **Amazon S3** behind **CloudFront CDN**.
* **Backend Tier:** Stateless **FastAPI** (Python 3.11) REST API designed for **EC2 Auto Scaling Group** behind an **Application Load Balancer** in private VPC subnets.
* **Database Tier:** Relational **PostgreSQL 16** (local Docker on `127.0.0.1:5433:5432`; **Amazon RDS `db.t3.micro` Single-AZ** in cloud).
* **Dual Health Probes:**
  - `GET /health`: Shallow check (HTTP 200) strictly independent of database for ALB viability.
  - `GET /health/db`: Deep check executing `SELECT 1` to monitor PostgreSQL connectivity.

---

## 2. Completed Milestones & Accomplishments

### ✅ Milestone 1: Local Full-Stack Application Scaffolded & Operational
- Created Docker Compose definition (`docker-compose.yml`) for isolated PostgreSQL 16 Alpine on mapped port `5433`.
- Developed FastAPI backend with models (`Note`), Pydantic schemas, and CRUD routes (`/api/notes`).
- Developed React + Vite frontend with clean card layout, modal edit/create dialog, real-time search, and health badges.
- Configured Vite dev proxy to seamlessly route `/api` and `/health` requests to `localhost:8000`.

### ✅ Milestone 2: Comprehensive Test Harness Implemented
- Backend: Implemented `pytest` suite testing shallow health, deep DB health, CRUD lifecycle, search queries, and validation errors.
- Frontend: Implemented native Node.js test runner suite (`frontend/src/api.test.js`) testing API URL construction, query handling, and payload formatting.
- Static Build: Verified `npm run build` cleanly outputs static assets (`dist/`) in $< 1.2\text{ s}$.

### ✅ Milestone 3: Architectural & Operational Documentation Suite Created
- `docs/ARCHITECTURE.md`: Complete cloud topology in `ap-south-1`, sequence diagrams, dual-origin CloudFront routing (`*` $\to$ S3, `/api/*` and `/health` $\to$ ALB), security group chains, and learning budget calculations (~$90/mo).
- `docs/DATABASE.md`: Data types, B-Tree & GIN indexes, Alembic migration process, RDS PITR backup strategy, and credential injection.
- `docs/SECURITY.md`: Data classification, network boundaries, OWASP Top 10 pre-merge checklist, and vulnerability audit.
- `docs/TESTING.md`: Test pyramid, execution commands, and three chaos infrastructure proofs (instance termination, load scaling, DB isolation).
- `AGENTS.md`: AI agent guidelines, strict hard rules (no cloud/terraform commands without approval, no secrets), and 5-step workflow (under 120 lines).

### ✅ Milestone 4: Security Remediation (All 7 Identified Violations Resolved)
- **1. Error Disclosure in `health.py`:** Replaced `str(exc)` with generic message; raw trace logged server-side.
- **2. Unbounded Content in `schemas.py`:** Enforced `max_length=50000` on note bodies.
- **3. Unconstrained Search in `notes.py`:** Constrained query parameter `q` to `max_length=100`.
- **4. Wildcard CORS in `main.py`:** Removed wildcard defaults; loaded explicit origins from `CORS_ORIGINS`; restricted verbs and headers.
- **5. Plaintext Fallback Credentials in `config.py` & `docker-compose.yml`:** Removed hardcoded credentials; bound database port strictly to `127.0.0.1`.
- **6. Security Response Headers Middleware:** Added `X-Content-Type-Options`, `X-Frame-Options`, `X-XSS-Protection`, `Referrer-Policy`, and `HSTS`.
- **7. Regression Tests:** Expanded test suite to **11 passing backend tests** and **2 passing frontend tests**.

### ✅ Milestone 5: Step 2 AWS Console Manual Runbook & Bootstrap Script
- Created `deploy/user-data.sh`: Amazon Linux 2023 bootstrap script configuring Python 3.11, systemd service, and dynamic credential retrieval from AWS SSM Parameter Store with zero hardcoded secrets.
- Created `docs/STEP2_RUNBOOK.md`: Click-by-click console guide covering VPC, Subnets, Security Groups, RDS, Launch Templates, Target Groups, ALB, ASG, S3, CloudFront, and a 10-step reverse teardown checklist.

---

## 3. Active Working Files & Registry

| File Path | Role | Current Status |
|---|---|---|
| `docs/PRD.md` | Product Requirements Document | Complete & Approved |
| `docs/PHASES.md` | Project Execution Phases & Roadmap | Complete & Approved |
| `docs/RULES.md` | Coding Standards & Security Constraints | Complete & Approved |
| `docs/DESIGN.md` | UI/UX & Design System Tokens | Complete & Approved |
| `docs/MEMORY.md` | Living Context & State Tracker (this file) | Complete & Up-to-Date |
| `docs/ARCHITECTURE.md` | Target Cloud Architecture & Cost Model | Complete & Up-to-Date |
| `docs/DATABASE.md` | PostgreSQL Schema & Operational Specs | Complete & Up-to-Date |
| `docs/SECURITY.md` | Security Review & Audit History | Complete & Remediated |
| `docs/TESTING.md` | Testing Guide & Infrastructure Proofs | Complete & Up-to-Date |
| `docs/STEP2_RUNBOOK.md` | Step 2 AWS Console Manual Guide | Complete & Up-to-Date |
| `AGENTS.md` | Repository Manual for AI Agents | Complete (73 lines) |
| `deploy/user-data.sh` | EC2 Launch Template User-Data Bootstrap | Complete & Tested |
| `backend/app/main.py` | FastAPI Entrypoint & Middleware | Complete & Hardened |
| `backend/tests/test_api.py` | Pytest Integration Test Suite | 11/11 Passing |
| `frontend/src/App.jsx` | React SPA UI View | Complete & Functional |
| `frontend/src/api.test.js` | Frontend Unit Test Suite | 2/2 Passing |

---

## 4. Current Test & Verification Status

```text
Backend Test Suite (pytest -v):
  ✔ test_shallow_health_check PASSED
  ✔ test_deep_database_health_check PASSED
  ✔ test_security_headers_present PASSED
  ✔ test_crud_note_lifecycle PASSED
  ✔ test_create_note_validation_error PASSED
  ✔ test_unbounded_content_rejected PASSED
  ✔ test_unconstrained_search_query_rejected PASSED
  ✔ test_wildcard_cors_rejected PASSED
  ✔ test_update_nonexistent_note_404 PASSED
  ✔ test_delete_nonexistent_note_404 PASSED
  ✔ test_example_shallow_health_check PASSED
  Total: 11 passed in 0.47s

Frontend Test Suite (npm test):
  ✔ frontend api client: listNotes constructs expected search URL and parses response
  ✔ frontend api client: createNote sends POST with JSON payload
  Total: 2 passed in 124ms

Frontend Static Build (npm run build):
  ✔ Generated static bundle in frontend/dist/ (HTML: 1.14 kB, CSS: 7.93 kB, JS: 151.65 kB) in 843ms
```

---

## 5. Next Planned Actions (When User Authorizes Cloud Steps)

1. **Step 1 Cloud Deployment (Single-Server MVP):** Deploy backend and frontend to a single `t3.micro` EC2 instance in `ap-south-1` to verify public internet routing and DNS.
2. **Step 2 Cloud Deployment (Decoupled Production Baseline):** Follow `docs/STEP2_RUNBOOK.md` in the AWS Console to provision the VPC, RDS, ALB, ASG, S3, and CloudFront dual-origin setup.
3. **Execute Chaos Proofs:** Execute the 3 infrastructure checks outlined in `docs/TESTING.md` (Instance termination, ASG load scaling, RDS internet isolation).
4. **Step 3 Automation (Terraform):** Codify the verified console architecture into modular Terraform configurations.
