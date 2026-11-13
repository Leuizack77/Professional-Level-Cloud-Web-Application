# Project Memory & Context State Tracker

**Project Name:** Professional-Level Cloud Web Application (Cloud Notes)  
**Last Updated:** 2026-11-13  
**Current Phase:** Step 1 Live & Verified $\to$ Step 2 Stage 1 (Network Foundation) Completed & Verified  
**Status:** Stage 1 Network 100% Provisioned & Verified; Codebase 100% Production-Ready (16/16 Pytest, 5/5 Frontend, Clean Vite Build)  

---

## 1. Project Identity & Architecture Snapshot

* **Application Type:** Decoupled 3-Tier Notes Web Application.
* **Target Cloud:** Amazon Web Services (AWS) in **Asia Pacific (Sydney) `ap-southeast-2`** (Active Step 1 EC2 server / Multi-AZ architecture ready).
* **Frontend Tier:** React 18 + Vite Single Page Application, compiled to static assets (`frontend/dist/`) with CloudFront OAC & S3 immutable asset caching. Configurable via `VITE_API_URL` with relative fallback.
* **Backend Tier:** Stateless **FastAPI** (Python 3.11) REST API with discrete RDS parameters, URL encoding, connection pooling (`QueuePool` with 1800s recycle and pre-ping), and non-wildcard CORS validation.
* **Database Tier:** Relational **PostgreSQL 16** (Active local systemd on Step 1 EC2; Amazon RDS `db.t3.micro` ready for Step 2).
* **Triple Health Probes:**
  - `GET /health`: Shallow check (HTTP 200, zero DB queries) strictly independent of database for reverse proxy and ALB target group health checks.
  - `GET /health/ready`: Readiness probe verifying FastAPI application state and active DB connection pool before ASG instance warm-up completes.
  - `GET /health/db`: Deep check executing `SELECT 1` with latency telemetry in ms.

---

## 2. Completed Milestones & Accomplishments

### ✅ Prep Phase: Local Full-Stack Prototype, Tests & Security Hardening
- **Local Application Architecture:** Developed FastAPI REST API with SQLAlchemy models (`Note`), Pydantic v2 schemas, and CRUD endpoints (`/api/notes`).
- **Static Frontend Bundle:** Built React 18 + Vite SPA with responsive card grid, modal form, real-time search, and live health status badges. Compiles to pure static assets in `frontend/dist/` in $< 1.0\text{ s}$.
- **Containerized Database:** Configured Docker Compose PostgreSQL 16 Alpine bound strictly to loopback interface `127.0.0.1:5433:5432`.
- **Security Audit Remediation:** Resolved all 7 audit vulnerabilities from docs/SECURITY.md (safe error messages, 50,000 char content limit, 100 char search limit, strict non-wildcard CORS, credential fallback elimination, loopback port binding, and defensive security headers).

### ✅ Step 1 Deliverables & Deployment Verification (COMPLETED & LIVE)
- **SSM Session Manager Transfer:** Automated Base64 deployment archive chunked transfer directly via authenticated AWS Systems Manager Session Manager terminal.
- **Archive Integrity Verification:** Remote SHA-256 computed on EC2 and matched target checksum bit-for-bit (`f8e180f5449795d673cc24984260749891b183ebc7f86636f2a91ecd77668819`).
- **PostgreSQL 16 Engine Provisioning:** Initialized and running via systemd (`postgresql.service`), bound strictly to loopback (`127.0.0.1:5432`) with SCRAM-SHA-256 authentication. Database `notes_db` and user `notes_user` provisioned with dedicated schema permissions.
- **Backend Service Setup:** Python 3.11 virtual environment installed with all dependencies, Alembic database migrations applied (`001_initial_notes_table`), and `notes-api.service` active under systemd sandbox.
- **Nginx Reverse Proxy:** Configured on port 80 routing `/api` and `/health` to backend, serving React static build from `/var/www/notes-app/frontend/dist` with immutable asset caching and defensive security headers (`nosniff`, `DENY`, `X-XSS-Protection`).
- **Live Verification:** Step 1 server active and healthy. All CRUD cycles and health checks passed.

### ✅ Phase 2 Application Code Development (COMPLETED)
- **Backend External RDS Support:** Added discrete environment parameters (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_SSLMODE`) with URL encoding and `postgres://` scheme normalization.
- **Database Connection Pooling:** Implemented `QueuePool` with `pool_size=10`, `max_overflow=5`, `pool_timeout=30`, `pool_recycle=1800` (drops stale NAT connections), and `pool_pre_ping=True`.
- **Stateless App & Probes:** Added `/health/ready` probe and enhanced `/health/db` with dialect and `latency_ms` telemetry without credential leakage.
- **Frontend Cloud Readiness:** Added `VITE_API_URL` base path configuration, 15-second `AbortController` timeout, human-readable gateway error mappings (502/503/504), and `api.checkReadiness()`.
- **Deployment Automation:**
  - Audited and updated `deploy/user-data.sh` (eliminated wildcard CORS bug, added dynamic IMDSv2 region detection, multi-source code staging, and SSM Parameter Store / Secrets Manager fallback).
  - Created `deploy/step2/migrate-data-to-rds.sh` for zero-downtime data migration from Step 1 to RDS.
  - Created `deploy/step2/deploy-frontend-s3.ps1` for static asset builds and S3 sync with immutable caching headers.
- **Testing Suite Expansion:** Created `backend/tests/test_production_config.py` with 5 new unit tests. 100% test pass rate across backend and frontend.

### ✅ Phase 2, Stage 1 Network Foundation Provisioning (COMPLETED & VERIFIED)
- **VPC Provisioned:** `notes-vpc` (`vpc-054255999fbcd9aea`, CIDR `10.0.0.0/16`, state `available`) with DNS hostnames and DNS resolution enabled.
- **6 Subnets Created Across 2 AZs:**
  - `notes-subnet-public1` (`subnet-0bc86c806d902fbb1`, `10.0.1.0/24`, `ap-southeast-2a`)
  - `notes-subnet-public2` (`subnet-0f22c526c9766b062`, `10.0.2.0/24`, `ap-southeast-2b`)
  - `notes-subnet-app1` (`subnet-0902ed1c8c66eb80d`, `10.0.10.0/24`, `ap-southeast-2a`)
  - `notes-subnet-app2` (`subnet-039071a6c0a9357e3`, `10.0.11.0/24`, `ap-southeast-2b`)
  - `notes-subnet-db1` (`subnet-0887479ad73933903`, `10.0.20.0/24`, `ap-southeast-2a`)
  - `notes-subnet-db2` (`subnet-0eaf434b2aac6ae7a`, `10.0.21.0/24`, `ap-southeast-2b`)
- **Internet Gateway Attached:** `notes-igw` (`igw-04e8420ca2838b484`) attached to `notes-vpc`.
- **Route Tables Configured & Associated:**
  - `notes-rtb-public` (`rtb-0a03844e7faea4dd5`): Route `0.0.0.0/0` $\to$ `notes-igw`; associated with `public1` and `public2`.
  - `notes-rtb-app` (`rtb-0fb17a96f164be5cb`): Local VPC route only; associated with `app1` and `app2`.
  - `notes-rtb-db` (`rtb-0b156673637dab8b4`): Local VPC route only (isolated, zero internet egress); associated with `db1` and `db2`.
- **Security Groups Configured:**
  - `notes-sg-alb` (`sg-02ba97cf136f6f550`): Ingress TCP 80 & 443 from `0.0.0.0/0`.
  - `notes-sg-app` (`sg-0cdd234f68a059f4a`): Ingress TCP 8000 strictly from `notes-sg-alb`.
  - `notes-sg-db` (`sg-051a95b1322bbb1c5`): Ingress TCP 5432 strictly from `notes-sg-app`; all outbound rules revoked.
- **Zero Billable Resources Verified:** 0 NAT Gateways, 0 Elastic IPs, 0 EC2 instances, 0 RDS instances in `notes-vpc` (\$0.00 incurred).
- **Phase 1 EC2 Integrity Confirmed:** Step 1 EC2 instance and its security group remain completely untouched and operational (health probes 200 OK).

---

## 3. Active Working Files & Registry

| File Path | Role | Current Status |
|---|---|---|
| `BRAIN.md` | Master Codebase Intelligence & Architectural Memory | Comprehensive Master Index |
| `docs/PRD.md` | Product Requirements Document | Complete & Approved |
| `docs/PHASES.md` | Project Execution Phases & Roadmap | Complete |
| `docs/RULES.md` | Coding Standards & Security Constraints | Complete & Approved |
| `docs/DESIGN.md` | UI/UX & Design System Tokens | Complete & Approved |
| `docs/MEMORY.md` | Living Context & State Tracker (this file) | Complete & Up-to-Date |
| `docs/ARCHITECTURE.md` | Target Cloud Architecture & Cost Model | Updated for ap-southeast-2 & Triple Probes |
| `docs/DATABASE.md` | PostgreSQL Schema & Operational Specs | Complete & Up-to-Date |
| `docs/SECURITY.md` | Security Review & Audit History | Complete & Remediated |
| `docs/TESTING.md` | Testing Guide & Infrastructure Proofs | Complete & Up-to-Date |
| `docs/STEP1_RUNBOOK.md` | Step 1 EC2 Console Manual Guide | Complete & Aligned |
| `docs/STEP2_RUNBOOK.md` | Step 2 AWS Console Manual Guide | Updated for ap-southeast-2 & Triple Probes |
| `AGENTS.md` | Repository Manual for AI Agents | Complete |
| `deploy/step1/setup-server.sh` | AL2023 Single-Server Setup Script | Audited, Hardened & Verified Live |
| `deploy/step1/nginx.conf` | Step 1 Nginx Proxy Configuration | Audited, Hardened & Verified Live |
| `deploy/step1/api.service` | Step 1 Systemd Unit File | Audited, Hardened & Verified Live |
| `deploy/step1/build-and-package.ps1` | Windows Packaging Script | Audited & Generates Clean ZIP |
| `deploy/user-data.sh` | Step 2 EC2 ASG User-Data Bootstrap | Audited, Hardened & Tested |
| `deploy/step2/migrate-data-to-rds.sh` | Step 2 RDS Data Migration Script | Complete & Tested |
| `deploy/step2/deploy-frontend-s3.ps1` | Step 2 S3 Frontend Deployment Script | Complete & Tested |
| `backend/app/config.py` | App Config with Discrete RDS & Pool Params | Complete & Verified |
| `backend/app/database.py` | Engine Factory with QueuePool & Latency Ping | Complete & Verified |
| `backend/app/routes/health.py` | Triple Health Probes (/health, /health/ready, /health/db) | Complete & Verified |
| `backend/tests/test_api.py` | Pytest Integration Test Suite | 11/11 Passing |
| `backend/tests/test_production_config.py` | Pytest Production Config Suite | 5/5 Passing |
| `frontend/src/api.js` | Frontend API Client with Timeout & Gateway Handlers | Complete & Verified |
| `frontend/src/api.test.js` | Frontend Unit Test Suite | 5/5 Passing |

---

## 4. Current Test & Verification Status

```text
Phase 1 EC2 Host:
  ✔ Systemd notes-api.service: active (listening on 127.0.0.1:8000)
  ✔ Systemd nginx.service: active (listening on 0.0.0.0:80)
  ✔ Systemd postgresql.service: active (listening on 127.0.0.1:5432)
  ✔ GET /health: 200 OK (shallow viability check)
  ✔ GET /health/db: 200 OK (deep database connectivity check)
  ✔ GET /: 200 OK (React static assets with caching and security headers)
  ✔ Full CRUD cycle verified (create, list, get, update, delete)

Phase 2 Stage 1 AWS Network Tier (ap-southeast-2):
  ✔ VPC: notes-vpc (vpc-054255999fbcd9aea) — 10.0.0.0/16, DNS hostnames & support enabled
  ✔ Subnets (6/6 across 2 AZs): public1/2, app1/2, db1/2 mapped to correct CIDRs & route tables
  ✔ Internet Gateway: notes-igw (igw-04e8420ca2838b484) attached to notes-vpc
  ✔ Route Tables: notes-rtb-public (igw route), notes-rtb-app (isolated), notes-rtb-db (zero internet egress)
  ✔ Security Groups: notes-sg-alb (80/443), notes-sg-app (8000 from ALB), notes-sg-db (5432 from APP, zero egress)
  ✔ Exclusions & Billable Checks: 0 NAT Gateways, 0 EIPs, 0 EC2 instances, 0 RDS instances ($0.00 cost limit met)

Local Test Suites:
  ✔ Backend (pytest -v): 16 passed in 2.00s (in-memory SQLite + config tests)
  ✔ Frontend (npm test): 5 passed in 551ms (native node:test)
  ✔ Frontend Build (npm run build): Built dist/ in 4.65s (0 errors)
```

---

## 5. Next Planned Actions

* **Phase 2 Cloud Infrastructure Provisioning (Stage 2 — Database Tier):**
  - Stage 1: VPC, 6 subnets, IGW, route tables, and security groups. (COMPLETED & VERIFIED)
  - Stage 2: Provision RDS DB Subnet Group (`notes-dbsng` across `notes-subnet-db1` and `notes-subnet-db2`), provision Single-AZ Amazon RDS PostgreSQL 16 (`db.t3.micro`, identifier `notes-db`) in `notes-sg-db`, and store connection string in AWS Systems Manager Parameter Store (`/notes-app/DATABASE_URL`). **(AWAITING USER APPROVAL)**
  - Stage 3: Launch Template (`notes-api-template`), Target Group (`notes-api-tg`), and Internet-Facing ALB (`notes-alb`).
  - Stage 4: Auto Scaling Group (`notes-asg`, min 2, max 4, target CPU 65%) in private app subnets.
  - Stage 5: S3 Bucket + CloudFront Distribution with Origin Access Control and dual-origin routing (`/*` $\to$ S3, `/api/*` & `/health*` $\to$ ALB).
  - Stage 6: Migrate Step 1 database data to RDS via `deploy/step2/migrate-data-to-rds.sh`.

---

## 6. Open Issues & Blockers

* **Stage 2 Approval Gateway:** Stage 1 network foundation is 100% complete and verified with zero billable charges ($0.00). Awaiting user approval before proceeding to Stage 2 (Amazon RDS PostgreSQL instance provisioning).
* **Phase 1 EC2 Integrity:** Intact, running, and completely isolated from Phase 2 custom VPC. Health checks 200 OK.
