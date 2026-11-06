# Engineering Rules, Coding Standards & Constraints

**Project Name:** Professional-Level Cloud Web Application (Cloud Notes)  
**Document Version:** 1.0.0  
**Status:** Approved Source of Truth  
**Author:** Software Architect & Principal Security Engineer  

---

## 1. Core Engineering Tenets

Every architectural decision and line of code in this project must adhere to the following principles:

1. **Simplicity Over Cleverness:** Prefer explicit, maintainable code over hyper-abstracted layers or custom mini-frameworks.
2. **Zero Trust Networking & Least Privilege:** No component should have more network or cloud permissions than strictly needed. All ingress must use security group chaining, not open IP CIDRs.
3. **Fail Securely & Gracefully:** Errors must never expose database connection strings, internal hostnames, ports, passwords, or raw stack traces to clients.
4. **Strict Health Probe Decoupling:** `GET /health` must remain independent of the database to ensure the Application Load Balancer can evaluate compute health without overloading or tripping on database latency spikes.
5. **Decoupled Tier Integrity:** The frontend must compile into pure static assets for Amazon S3 hosting; the backend must remain a stateless REST API designed for an Auto Scaling Group.

---

## 2. Mandatory Technology Stack

| Tier | Approved Technology | Version / Spec | Justification & Guardrails |
|---|---|---|---|
| **Frontend Framework** | React | 18.x | Vite 5 bundler. Single Page Application (SPA). |
| **Frontend Styling** | Pure CSS3 / Modular CSS | Custom Tokens | Responsive card grid, modal design, CSS variables. Zero runtime CSS overhead. |
| **Backend Runtime** | Python | 3.11+ | Standard LTS Python with typed annotations. |
| **API Framework** | FastAPI | 0.110+ | Asynchronous REST endpoints, automatic OpenAPI documentation at `/docs`. |
| **ASGI Server** | Uvicorn | 0.28+ | High-performance ASGI server with uvloop support. |
| **Schema Validation** | Pydantic v2 | 2.6+ (`pydantic-settings`) | Strict request/response boundary enforcement. |
| **ORM & DB Driver** | SQLAlchemy 2.0 + Psycopg | SQLAlchemy 2.0, Psycopg 3 | Parameterized queries with connection pooling (`pool_pre_ping=True`). |
| **Relational Database** | PostgreSQL | 16.x | Relational ACID storage. Containerized locally, Amazon RDS in cloud. |
| **Local Container** | Docker Compose | Compose v2+ | PostgreSQL 16 Alpine mapped to loopback port `127.0.0.1:5433:5432`. |
| **Target Cloud** | AWS (`ap-south-1`) | Cloud-Native | S3, CloudFront, ALB, EC2 ASG, RDS PostgreSQL, VPC. |

---

## 3. Strictly Prohibited Anti-Patterns & Technologies

To maintain architectural integrity, cloud safety, and security boundaries, the following are **strictly forbidden**:

- ❌ **NO Unapproved Cloud or Terraform Actions:** Under no circumstances should an AI agent or automated script run cloud CLI mutations (`aws`, `az`, `gcloud`) or `terraform apply`/`terraform destroy` without explicit user consent.
- ❌ **NO Hardcoded Secrets or Credentials:** Never write passwords, tokens, API keys, or private connection strings in source code, configuration files, or Git commits.
- ❌ **NO Database Queries in Shallow Health Checks:** `GET /health` must NEVER execute SQL queries, establish new database connections, or import the database session. Reserve DB verification strictly for `GET /health/db`.
- ❌ **NO Wildcard `*` CORS Origins:** Never allow wildcard `*` origins in production. CORS origins must be parsed from environment variables (`CORS_ORIGINS`) and validated.
- ❌ **NO Raw Unparameterized SQL:** Never construct SQL queries via Python f-strings, string formatting, or concatenation. Always use parameterized SQLAlchemy ORM methods.
- ❌ **NO Node.js Runtime in Production Frontend:** The frontend must build to pure static files (`index.html`, JS, CSS) in `frontend/dist/`. No Next.js server runtime, Express static server, or Node process is permitted in production.
- ❌ **NO Unbounded Request Payloads:** Never accept unbounded text fields. Note titles are capped at 255 characters; note bodies are capped at 50,000 characters; search queries are capped at 100 characters.
- ❌ **NO Unapproved Tool Ingestion:** Do not install third-party packages, libraries, or external services without explicit justification and user approval.

---

## 4. Security & Error Handling Standards

### 4.1 Safe Exception Responses
- **Public API Rule:** When a database or internal service failure occurs, the API must return a clean, generic HTTP error:
  ```json
  {
    "status": "unhealthy",
    "database": "disconnected",
    "error": "Database connectivity check failed"
  }
  ```
- **Internal Logging:** The full traceback and exception object must be logged server-side via Python's standard `logging` module (`logger.error("... %s", exc, exc_info=True)`), never exposed in the HTTP response body.

### 4.2 Security Response Headers
Every HTTP response emitted by FastAPI must include standard defense-in-depth headers:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Strict-Transport-Security: max-age=31536000; includeSubDomains` (in production)

---

## 5. Local Development & Docker Rules

1. **Loopback Port Isolation:** Local Docker services must bind exclusively to `127.0.0.1` (e.g. `127.0.0.1:5433:5432`) to prevent accidental LAN exposure.
2. **Port Conflict Avoidance:** PostgreSQL container runs on host port `5433` to prevent collision with any existing host PostgreSQL installations on port `5432`.
3. **Environment Parity:** The application reads database configuration via `DATABASE_URL`. Changing from local Docker PostgreSQL to AWS RDS PostgreSQL requires zero code changes—only updating the environment variable.

---

## 6. Testing & Definition-of-Done (DoD)

1. **Zero Regressions:** Every PR, change, or release must pass both `pytest` (backend) and `npm test` (frontend).
2. **Static Compilation Gate:** `npm run build` must compile into `dist/` without build errors or missing dependencies.
3. **Self-Contained Unit Tests:** Backend tests must utilize isolated test fixtures (e.g., in-memory SQLite) so tests can execute reliably in CI environments without requiring external running containers.
