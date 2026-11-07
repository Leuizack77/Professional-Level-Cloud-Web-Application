# Product Requirements Document (PRD)

**Project Name:** Professional-Level Cloud Web Application (Cloud Notes)  
**Document Version:** 1.0.0  
**Status:** Approved Source of Truth  
**Author:** Cloud Software Architect & Lead Engineer  

---

## 1. Executive Summary & Purpose

The **Professional-Level Cloud Web Application** is a decoupled full-stack Notes system engineered specifically to demonstrate production-grade cloud architecture on **Amazon Web Services (AWS)** in the **Asia Pacific (Mumbai) region (`ap-south-1`)**.

While conventional tutorial applications are deployed as monolithic scripts on a single virtual machine with a co-located database, this project implements an enterprise-grade, high-availability architecture featuring:
- Static Single Page Application (SPA) frontend hosted on **Amazon S3** and globally distributed via **Amazon CloudFront CDN**.
- Stateless REST API backend built with **FastAPI** running in an **Auto Scaling Group** of **Amazon EC2** instances behind an **Application Load Balancer (ALB)** in private VPC subnets.
- Fully managed relational database using **Amazon RDS PostgreSQL**.

---

## 2. Target Users & Persona

1. **Cloud & DevOps Engineers:** Professionals building portfolio proof of VPC network segmentation, Auto Scaling, security group chaining, and zero-downtime health checking.
2. **Software Architects:** Teams evaluating decoupled 3-tier patterns where frontend assets are completely isolated from compute runtimes and databases.
3. **Technical Interviewers & Reviewers:** Evaluators looking for measurable architectural maturity, clean separation of concerns, and rigorous security practices.

---

## 3. Core Functional Requirements (User Stories)

| ID | Feature | User Story | Acceptance Criteria |
|---|---|---|---|
| **FR-01** | **Create Note** | As a user, I want to create a new note with a title and body text so that I can store important information. | Submitting the form issues `POST /api/notes`. Title (1–255 chars) and Content (1–50,000 chars) are required. Returns HTTP 201 Created with generated `id`, `created_at`, and `updated_at`. |
| **FR-02** | **List & View Notes** | As a user, I want to view all my saved notes in a clean grid so that I can browse my saved information. | Issuing `GET /api/notes` returns a JSON array of all notes ordered by `updated_at DESC`. Frontend renders cards showing title, content, formatted timestamp, and ID. |
| **FR-03** | **Search Notes** | As a user, I want to filter notes in real time by typing keywords so that I can find specific topics quickly. | Typing in search input issues `GET /api/notes?q={query}` (max 100 chars). Case-insensitive search matches against both `title` and `content`. Empty result state displayed if no matches. |
| **FR-04** | **Edit Note** | As a user, I want to edit an existing note's title or content so that I can keep information up to date. | Clicking "Edit" populates the modal. Submitting sends `PUT /api/notes/{id}`. The database updates `updated_at` to the current UTC timestamp and returns HTTP 200 OK. |
| **FR-05** | **Delete Note** | As a user, I want to delete a note I no longer need so that my workspace stays tidy. | Clicking "Delete" prompts for confirmation. Confirming issues `DELETE /api/notes/{id}`. Returns HTTP 204 No Content. Note disappears from UI immediately. |
| **FR-06** | **Dual Health Probes** | As a cloud load balancer and operator, I need independent shallow and deep health checks so that compute failures and DB outages are distinguished. | `GET /health` returns HTTP 200 without querying the database (for ALB target health). `GET /health/db` executes `SELECT 1` and verifies active database connectivity. |

---

## 4. Non-Functional Requirements (NFRs)

### 4.1 Performance & Latency (Local Targets, Not Guarantees)
- **Shallow Health Check:** `GET /health` local target $< 10\text{ ms}$ under baseline conditions (designed as an engineering target to prevent ALB health check timeouts, not an absolute cloud SLA guarantee).
- **API Response Time:** CRUD operations local target $< 50\text{ ms}$ under normal database load (engineering target, not a guarantee).
- **Frontend Asset Loading:** First Contentful Paint (FCP) local target $< 1.0\text{ s}$ via CloudFront edge distribution (target, dependent on client network and edge proximity).

### 4.2 High Availability & Resilience
- **Multi-AZ Readiness:** Architecture must support distribution across at least two Availability Zones (`ap-south-1a`, `ap-south-1b`).
- **Stateless API:** No session state, uploaded files, or persistent caches stored on EC2 instances. Any instance can be terminated without user data loss.
- **Self-Healing:** If an EC2 instance fails or terminates, the Auto Scaling Group must launch a replacement within 3 minutes while the ALB routes around the failure.

### 4.3 Security & Least Privilege
- **Zero Public DB Exposure:** The RDS PostgreSQL database must reside in private subnets with `PubliclyAccessible = false` and ingress restricted to `sg-app`.
- **Zero Hardcoded Secrets:** Credentials must never be committed to Git. Local dev uses `.env` (git-ignored); production uses AWS SSM Parameter Store / Secrets Manager.
- **Input Boundaries:** Hard maximum limits enforced on all user inputs (50,000 characters for content, 100 characters for search queries).
- **Defensive Headers:** API must emit `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `X-XSS-Protection`, and `Referrer-Policy`.

### 4.4 Cost Governance (Learning Budget)
- **Monthly Spend Cap:** Total infrastructure cost must stay under **~\$95/month** in `ap-south-1` using Single-AZ `db.t3.micro`, 1 NAT Gateway, and burstable EC2 instances.

---

## 5. Technology Stack Summary

| Layer | Technology | Version | Purpose |
|---|---|---|---|
| **Frontend** | React + Vite | React 18, Vite 5 | Static SPA compiled to pure HTML/CSS/JS for S3. |
| **Backend API** | FastAPI | 0.110+ (Python 3.11) | Asynchronous, typed REST API with OpenAPI auto-docs. |
| **ORM & Driver** | SQLAlchemy + Psycopg | SQLAlchemy 2.0, Psycopg 3 | Parameterized ORM queries with connection pooling. |
| **Relational Database** | PostgreSQL | 16-alpine (Local), RDS (AWS) | ACID-compliant relational data store. |
| **Local Containerization** | Docker Compose | Compose v2+ | Local isolated PostgreSQL on loopback port 5433. |
| **Target Cloud** | Amazon Web Services | `ap-south-1` | S3, CloudFront, ALB, EC2 ASG, RDS, VPC. |

---

## 6. Out of Scope (Deferred to Future Iterations)
- User authentication and multi-tenancy (Clerk, Cognito, or JWT).
- File/Image uploads to S3 buckets.
- AI features (embeddings, vector retrieval, LLM summarization).
- Terraform IaC scripts (deferred until Step 3).
