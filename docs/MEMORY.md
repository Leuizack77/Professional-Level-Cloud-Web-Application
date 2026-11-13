# Project Memory & Context State Tracker

**Project Name:** Professional-Level Cloud Web Application (Cloud Notes)  
**Last Updated:** 2026-11-11  
**Current Phase:** Step 1 Deployment Verified & Closed $\to$ Step 2 Cloud Migration Ready  
**Status:** Step 1 Production-Ready on EC2 (All Acceptance Criteria Verified)  

---

## 1. Project Identity & Architecture Snapshot

* **Application Type:** Decoupled 3-Tier Notes Web Application.
* **Target Cloud:** Amazon Web Services (AWS) in **Asia Pacific (Sydney) `ap-southeast-2`** (Active Step 1 EC2) / Multi-AZ architecture ready.
* **Frontend Tier:** React 18 + Vite Single Page Application, compiled to static assets (`frontend/dist/`) served via Nginx with immutable caching and defensive HTTP security headers.
* **Backend Tier:** Stateless **FastAPI** (Python 3.11) REST API running as a hardened systemd service (`notes-api.service`) bound strictly to loopback (`127.0.0.1:8000`).
* **Database Tier:** Relational **PostgreSQL 16** initialized and running via systemd (`postgresql.service`), strictly bound to loopback interface `127.0.0.1:5432` with SCRAM-SHA-256 authentication.
* **Dual Health Probes:**
  - `GET /health`: Shallow check (HTTP 200) strictly independent of database for reverse proxy and load balancer viability.
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
- **Security Audit Remediation:** Resolved all 7 audit vulnerabilities from docs/SECURITY.md (safe error messages, 50,000 char content limit, 100 char search limit, strict non-wildcard CORS, credential fallback elimination, loopback port binding, and defensive security headers).

### ✅ Step 1 Deliverables & Deployment Verification (COMPLETED)
- **SSM Session Manager Transfer:** Automated Base64 deployment archive chunked transfer directly via authenticated AWS Systems Manager Session Manager terminal.
- **Archive Integrity Verification:** Remote SHA-256 computed on EC2 and matched target checksum bit-for-bit (`f8e180f5449795d673cc24984260749891b183ebc7f86636f2a91ecd77668819`).
- **PostgreSQL 16 Engine Provisioning:** Initialized and running via systemd (`postgresql.service`), bound strictly to loopback (`127.0.0.1:5432`) with SCRAM-SHA-256 authentication. Database `notes_db` and user `notes_user` provisioned with dedicated schema permissions.
- **Backend Service Setup:** Python 3.11 virtual environment installed with all dependencies, Alembic database migrations applied (`001_initial_notes_table`), and `notes-api.service` active under systemd sandbox.
- **Nginx Reverse Proxy:** Configured on port 80 routing `/api` and `/health` to backend, serving React static build from `/var/www/notes-app/frontend/dist` with immutable asset caching and defensive security headers (`nosniff`, `DENY`, `X-XSS-Protection`).
- **Full-Stack Acceptance Tests Verified:**
  - Systemd services (`notes-api`, `nginx`, `postgresql`): All `active`.
  - Shallow API health probe (`GET /health`): `200 OK` (independent of database).
  - Deep database health probe (`GET /health/db`): `200 OK` (`{"status":"healthy","database":"connected"}`).
  - Static frontend asset delivery (`GET /`): `200 OK` with complete security header envelope.
  - End-to-end CRUD lifecycle: Note created (POST `201`), listed (GET `200`), read (GET `200`), updated (PUT `200`), deleted (DELETE `204`), and confirmed deleted (GET `404`) from both local loopback and external internet.

---

## 3. Active Working Files & Registry

| File Path | Role | Current Status |
|---|---|---|
| `BRAIN.md` | Master Codebase Intelligence & Architectural Memory | Comprehensive Master Index |
| `docs/PRD.md` | Product Requirements Document | Complete & Approved |
| `docs/PHASES.md` | Project Execution Phases & Roadmap | Restructured around 3 steps |
| `docs/RULES.md` | Coding Standards & Security Constraints | Complete & Approved |
| `docs/DESIGN.md` | UI/UX & Design System Tokens | Complete & Approved |
| `docs/MEMORY.md` | Living Context & State Tracker (this file) | Complete & Up-to-Date |
| `docs/ARCHITECTURE.md` | Target Cloud Architecture & Cost Model | Complete & Up-to-Date |
| `docs/DATABASE.md` | PostgreSQL Schema & Operational Specs | Complete & Up-to-Date |
| `docs/SECURITY.md` | Security Review & Audit History | Complete & Remediated |
| `docs/TESTING.md` | Testing Guide & Infrastructure Proofs | Complete & Up-to-Date |
| `docs/STEP1_RUNBOOK.md` | Step 1 EC2 Console Manual Guide | Complete & Aligned |
| `docs/STEP2_RUNBOOK.md` | Step 2 AWS Console Manual Guide | Complete & Up-to-Date |
| `AGENTS.md` | Repository Manual for AI Agents | Updated with Step 1 runbook |
| `deploy/step1/setup-server.sh` | AL2023 Single-Server Setup Script | Audited, Hardened & Verified |
| `deploy/step1/nginx.conf` | Step 1 Nginx Proxy Configuration | Audited, Hardened & Verified |
| `deploy/step1/api.service` | Step 1 Systemd Unit File | Audited, Hardened & Verified |
| `deploy/step1/build-and-package.ps1` | Windows Packaging Script | Audited & Generates Clean ZIP |
| `backend/app/config.py` | Application Configuration (HOST=127.0.0.1) | Audited & Hardened |
| `backend/app/main.py` | FastAPI Entrypoint & Scheme-Aware HSTS | Audited & Hardened |
| `backend/tests/test_api.py` | Pytest Integration Test Suite | 11/11 Passing |
| `frontend/src/App.jsx` | React SPA UI View | Complete & Functional |
| `frontend/src/api.js` | Frontend API Client (Relative Paths) | Complete & Verified |
| `frontend/src/api.test.js` | Frontend Unit Test Suite | 2/2 Passing |

---

## 4. Current Test & Verification Status

```text
EC2 Server Production Acceptance Verification:
  ✔ Systemd notes-api.service: active (listening on 127.0.0.1:8000)
  ✔ Systemd nginx.service: active (listening on 0.0.0.0:80)
  ✔ Systemd postgresql.service: active (listening on 127.0.0.1:5432)
  ✔ GET /health: 200 OK (shallow viability check)
  ✔ GET /health/db: 200 OK (deep database connectivity check)
  ✔ GET /: 200 OK (React static assets with caching and security headers)
  ✔ POST /api/notes: 201 Created
  ✔ GET /api/notes: 200 OK (notes list returned)
  ✔ GET /api/notes/{id}: 200 OK (single note retrieval)
  ✔ PUT /api/notes/{id}: 200 OK (note content update)
  ✔ DELETE /api/notes/{id}: 204 No Content (note deletion)
  ✔ GET /api/notes/{id}: 404 Not Found (verified removal)

Local Test Suites:
  ✔ Backend (pytest -v): 11 passed in 1.43s (in-memory SQLite)
  ✔ Frontend (npm test): 2 passed in 115ms (native node:test)
  ✔ Frontend Build (npm run build): Built dist/ in 785ms
```

---

## 5. Next Planned Actions

* **Step 2: Cloud Decoupling & High-Availability Migration:**
  - Provision Custom VPC across 2 Availability Zones (public, private app, private db subnets).
  - Deploy Amazon RDS PostgreSQL 16 Single-AZ (`db.t3.micro`) in private database subnets.
  - Migrate data from Step 1 local PostgreSQL to Amazon RDS via `pg_dump`/`pg_restore`.
  - Configure Application Load Balancer (ALB) with path-based routing and health checks (`/health`).
  - Configure EC2 Launch Template & Auto Scaling Group (ASG) min 2, max 4 instances in private app subnets.
  - Deploy static frontend to Amazon S3 bucket with CloudFront Origin Access Control (OAC).

---

## 6. Open Issues & Blockers

* **None.** Step 1 is 100% verified, stable, and closed. Ready for Step 2 execution planning and approval.
