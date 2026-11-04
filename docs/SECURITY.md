# Security Review & Architecture Specification

## 1. Security Reviewer Persona & Executive Summary

* **Role:** Senior Cloud Security Architect & Application Security Reviewer
* **System Reviewed:** Professional-Level Cloud Web Application (Notes App)
* **Scope:** 3-Tier Architecture (S3/CloudFront, ALB, EC2 ASG, RDS PostgreSQL) & Current Codebase
* **Assessment Status:** Baseline Functional — Remediation Required Prior to Production Deployment

---

## 2. Data Classification & Inventory

| Data Element | Classification Level | Storage Location | Sensitivity & Impact |
|---|---|---|---|
| **Note Titles** | Internal / Confidential | RDS PostgreSQL (`notes.title`) | User-generated content; may contain project names or business context. |
| **Note Content** | Internal / Confidential | RDS PostgreSQL (`notes.content`) | Arbitrary user text; may contain confidential notes, operational instructions, or credentials if pasted by users. |
| **Timestamps & IDs** | Public / Internal | RDS PostgreSQL (`notes.id`, `created_at`, `updated_at`) | Low sensitivity metadata. |
| **Database Credentials** | Restricted / Secret | AWS Secrets Manager (`prod/notes-app/database`) | Highest severity. Compromise grants full read/write database access. |
| **Application Logs** | Internal | Amazon CloudWatch Logs | Must never contain database credentials, access tokens, or sensitive payload bodies. |

---

## 3. Network Security & Subnet Architecture

The application enforces a multi-tier defense-in-depth network topology:

```text
[ Internet ]
     │
     ▼ (HTTPS:443 only)
[ Public Subnets: ALB ] (10.0.1.0/24, 10.0.2.0/24)
     │
     ▼ (HTTP:8000 only via Security Group chaining)
[ Private App Subnets: EC2 ASG ] (10.0.10.0/24, 10.0.11.0/24)
     │
     ▼ (TCP:5432 only via Security Group chaining)
[ Private DB Subnets: RDS PostgreSQL ] (10.0.20.0/24, 10.0.21.0/24)
```

1. **Subnet Isolation:**
   - **Public Subnets:** Contain only internet-facing load balancers and NAT Gateways. No application compute or database instances reside here.
   - **Private App Subnets:** Contain backend EC2 instances. Route table routes outbound internet traffic through NAT Gateways for package downloads; instances have no public IPv4 addresses.
   - **Private DB Subnets:** Fully isolated subnets with no route to the Internet Gateway or NAT Gateway.
2. **Security Group Chaining:**
   - Security groups reference the IDs of peer security groups rather than IP CIDR ranges, ensuring that only traffic originating from legitimate upstream tiers is admitted.

---

## 4. Secrets Management & Credential Lifecycle

1. **Zero Hardcoded Secrets:** No passwords, private keys, API secrets, or certificates are permitted in Git.
2. **AWS Secrets Manager:**
   - Production database credentials are automatically rotated every 30 days via AWS Secrets Manager with RDS integration.
   - Credentials are never serialized to disk in production; they are fetched into application memory at process launch.
3. **Local Development Isolation:**
   - Local environments use `.env` files that are strictly excluded in `.gitignore`.
   - `.env.example` provides non-sensitive dummy placeholders.

---

## 5. IAM Least Privilege & Instance Profiles

1. **Role-Based Access:** EC2 instances are assigned an **IAM Instance Profile** (Instance Role) with least-privilege policies.
2. **Strictly Prohibited:** Permanent AWS Access Keys (`AKIA...`) must never be placed on EC2 instances or in code.
3. **Scoped Policy Example:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["secretsmanager:GetSecretValue"],
         "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/notes-app/database-*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "logs:CreateLogStream",
           "logs:PutLogEvents",
           "logs:DescribeLogStreams"
         ],
         "Resource": "arn:aws:logs:us-east-1:123456789012:log-group:/aws/ec2/notes-api:*"
       }
     ]
   }
   ```

---

## 6. HTTPS & Cryptographic Standards

1. **Edge & Load Balancer Encryption:**
   - CloudFront enforces `ViewerProtocolPolicy: redirect-to-https`.
   - ALB listener enforces HTTP to HTTPS (port 80 redirect to 443).
   - TLS certificates provisioned and auto-renewed via **AWS Certificate Manager (ACM)** using TLS 1.3 / 1.2 with modern cipher suites.
2. **Data-at-Rest Encryption:**
   - RDS PostgreSQL encrypted using AWS Key Management Service (**AWS KMS** - `aws/rds`).
   - S3 bucket encrypted with SSE-S3 or KMS (`aws/s3`).
   - EBS volumes attached to EC2 instances encrypted by default with KMS.

---

## 7. Input Validation & Injection Defenses

1. **SQL Injection Defense:** All queries must traverse the SQLAlchemy ORM using parameterized queries. Raw string concatenation (`text(f"SELECT * FROM notes WHERE title = '{title}'")`) is strictly prohibited.
2. **Type and Length Validation:** Pydantic schemas (`NoteCreate`, `NoteUpdate`) enforce type boundaries, string stripping, and maximum lengths on incoming JSON bodies.
3. **Cross-Site Scripting (XSS):** React automatically escapes JSX string interpolation (`{note.title}`, `{note.content}`), neutralizing script injection vectors.

---

## 8. Rate Limiting & Load Balancer Protection

1. **AWS WAF Integration:**
   - An **AWS WAF WebACL** is associated with the Application Load Balancer.
   - **Rate-Based Rule:** Limits any individual client IP address to a maximum of 500 requests per 5-minute rolling window.
   - **AWS Managed Rule Sets:** Includes `AWSManagedRulesCommonRuleSet` and `AWSManagedRulesKnownBadInputsRuleSet` to mitigate automated scans, path traversals, and HTTP flood attacks.

---

## 9. Dependency Governance & Supply Chain Security

1. **Pinned Versions:** All packages in `backend/requirements.txt` and `frontend/package.json` must be version-pinned.
2. **Automated Vulnerability Audits:**
   - Backend: `pip-audit` runs in CI to verify that installed wheels have no known CVEs.
   - Frontend: `npm audit --production` verifies JavaScript packages.
3. **Minimal Dependency Footprint:** No unapproved packages or duplicate libraries are permitted without explicit evaluation.

---

## 10. Logging, Monitoring & Incident Readiness

1. **Sanitized Logs:** Loggers must never capture raw request bodies, authentication tokens, passwords, or connection strings.
2. **Structured JSON Output:** Application logs are formatted as structured JSON for ingestion into Amazon CloudWatch Logs.
3. **Security Alarms:** CloudWatch metric filters trigger SNS alerts for spikes in HTTP 5xx responses, failed database pings, or repeated 404/422 anomalies.

---

## 11. Pre-Merge Checklist Mapped to OWASP Top 10

| OWASP Top 10 Category | Verification Requirement | Pass Criteria |
|---|---|---|
| **A01: Broken Access Control** | Verify that API endpoints only expose allowed HTTP verbs and do not leak administrative capabilities. | No unauthenticated admin endpoints exist. |
| **A02: Cryptographic Failures** | Ensure all traffic uses TLS 1.3/1.2; verify database and storage encryption at rest. | KMS enabled on RDS, EBS, S3; HTTPS enforced on ALB and CDN. |
| **A03: Injection** | Inspect all database queries for string formatting or raw unescaped SQL. | 100% of queries use SQLAlchemy ORM or bound parameters. |
| **A04: Insecure Design** | Verify threat modeling for compute isolation and separation of health probes. | `/health` is independent of DB to prevent cascading DoS. |
| **A05: Security Misconfiguration** | Check CORS origins, security response headers, and default ports. | No wildcard `*` CORS in production; default passwords eliminated. |
| **A06: Vulnerable Components** | Run dependency vulnerability scanners. | Zero high/critical CVEs reported by `pip-audit` and `npm audit`. |
| **A07: Identification Failures** | Validate credential retrieval mechanisms. | AWS Secrets Manager utilized; zero hardcoded passwords. |
| **A08: Software & Data Integrity** | Ensure package checksums and container image digests are verified. | Pinned dependencies and verified official base images. |
| **A09: Logging & Monitoring** | Confirm exceptions are handled without leaking internal stack traces. | 500/503 errors return generic messages; details logged internally. |
| **A10: SSRF** | Confirm the backend does not make unvalidated outbound HTTP calls to user-supplied URLs. | No arbitrary user URL fetching allowed in application code. |

---

## 12. Codebase Security Audit: Identified Violations

A line-by-line inspection of the current code reveals the following violations. *(Per instruction, these are cataloged for remediation and not yet altered)*:

### 1. `backend/app/routes/health.py`
* **Line 41 — CWE-209: Generation of Error Message Containing Sensitive Information:**
  ```python
  detail={"status": "unhealthy", "database": "disconnected", "error": str(exc)}
  ```
  *Violation:* Leaking `str(exc)` in an HTTP 503 response exposes internal database hostnames, IP addresses, port numbers, and usernames to unauthenticated public callers when a connection fails.
  *Remediation Required:* Replace `str(exc)` with a generic string (`"Database connectivity check failed"`) and log the full exception internally.

### 2. `backend/app/schemas.py`
* **Line 7 & Line 16 — CWE-400: Uncontrolled Resource Consumption (Missing Length Limits):**
  ```python
  content: str = Field(..., description="Main content or body of the note")
  ```
  *Violation:* While `title` enforces `max_length=255`, the `content` field has no maximum length constraint. An attacker could transmit multi-megabyte payloads in a loop to exhaust PostgreSQL storage and memory.
  *Remediation Required:* Constrain `content` with a reasonable maximum length (e.g. `max_length=50000`).

### 3. `backend/app/routes/notes.py`
* **Line 27 — CWE-400: Unbounded Query Parameter:**
  ```python
  q: Optional[str] = Query(None, description="Optional search query filter...")
  ```
  *Violation:* The search parameter `q` has no `max_length` parameter, allowing unbounded strings in `ILIKE` database queries.
  *Remediation Required:* Restrict `q` with `Query(None, max_length=100)`.

### 4. `backend/app/main.py`
* **Lines 28-31 — CWE-942: Overly Permissive CORS Policy:**
  ```python
  allow_methods=["*"],
  allow_headers=["*"],
  ```
  *Violation:* Wildcard methods and headers weaken Cross-Origin Resource Sharing protections.
  *Remediation Required:* Explicitly define allowed verbs (`["GET", "POST", "PUT", "DELETE", "OPTIONS"]`) and headers (`["Content-Type", "Authorization"]`).
* **Lines 35-41 — CWE-200: Unnecessary Information Exposure on Root Route:**
  ```python
  @app.get("/", tags=["Root"])
  def root():
      return {"message": "Notes API is running", "documentation": "/docs", "health": "/health"}
  ```
  *Violation:* Exposes internal documentation URLs and service banners to arbitrary crawlers.
  *Remediation Required:* Disable or restrict `/docs` in production via FastAPI `docs_url=None if settings.ENVIRONMENT == "production" else "/docs"`.
* **Line 14 — CWE-532: Use of Standard Print for System Errors:**
  ```python
  print(f"[WARNING] Database initialization deferred: {exc}")
  ```
  *Violation:* Emits raw unformatted text to standard output instead of using a structured security logger.

### 5. `backend/app/config.py`
* **Line 8 — CWE-259: Hardcoded Fallback Credentials:**
  ```python
  DATABASE_URL: str = "postgresql://notes_user:notes_password@localhost:5433/notes_db"
  ```
  *Violation:* Plaintext fallback password embedded in source code.
  *Remediation Required:* Default to empty or enforce requirement via Pydantic without committing credentials to repository code.

### 6. `docker-compose.yml`
* **Line 8-9 & Line 11 — CWE-276 / CWE-259: Insecure Port Binding and Plaintext Credentials:**
  ```yaml
  POSTGRES_PASSWORD: notes_password
  ports:
    - "5433:5432"
  ```
  *Violation:* Exposes database port on all host interfaces (`0.0.0.0:5433`) rather than loopback (`127.0.0.1:5433`), potentially opening the database to the local network.
  *Remediation Required:* Bind explicitly to `127.0.0.1:5433:5432`.

### 7. Missing Security Headers
* *Violation:* The FastAPI backend does not emit essential HTTP defense headers:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  *Remediation Required:* Add a lightweight security headers middleware to FastAPI.

