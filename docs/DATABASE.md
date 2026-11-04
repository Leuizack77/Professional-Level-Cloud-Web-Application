# Database Design & Operations Specification

## 1. Overview & Engine Specification

The application utilizes **PostgreSQL 16** as its relational database. In production, this runs as a managed **Amazon RDS PostgreSQL** instance; for local development, it runs as an identical containerized **PostgreSQL 16 Alpine** service.

* **Engine:** PostgreSQL 16.x
* **Default Encoding:** `UTF-8`
* **Collation / Ctype:** `en_US.UTF-8`
* **Time Zone:** `UTC` (all timestamps stored in UTC with timezone)
* **Access Mode:** Read / Write (with synchronous Multi-AZ standby replica in production)

---

## 2. Table Schema & Data Types

The data model is currently centered on the `notes` entity:

### Table: `notes`

| Column Name | SQL Data Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | `INTEGER` / `SERIAL` | **NO** | `autoincrement` | Unique synthetic primary key. |
| `title` | `VARCHAR(255)` | **NO** | *None* | Short descriptive headline of the note. |
| `content` | `TEXT` | **NO** | *None* | Full body text of the note (arbitrary length). |
| `created_at` | `TIMESTAMPTZ` | **NO** | `CURRENT_TIMESTAMP` | UTC timestamp when the note was created. |
| `updated_at` | `TIMESTAMPTZ` | **NO** | `CURRENT_TIMESTAMP` | UTC timestamp when the note was last modified. |

### DDL Representation
```sql
CREATE TABLE IF NOT EXISTS notes (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
```

---

## 3. Indexes & Query Optimization

Indexes are specifically mapped to application query patterns:

| Index Name | Target Column(s) | Index Type | Query Served | Rationale |
|---|---|---|---|---|
| `notes_pkey` | `id` | **B-Tree** (Unique) | `SELECT * FROM notes WHERE id = :id;`<br>`UPDATE notes SET ... WHERE id = :id;`<br>`DELETE FROM notes WHERE id = :id;` | Enforces primary key uniqueness and provides instantaneous $O(\log N)$ single-record lookups and mutations. |
| `ix_notes_title` | `title` | **B-Tree** | `SELECT * FROM notes WHERE title = :title;` | Speeds up exact match lookups or prefix filtering by title. |
| `ix_notes_updated_at` *(Recommended for Scale)* | `updated_at DESC` | **B-Tree** | `SELECT * FROM notes ORDER BY updated_at DESC;` | Eliminates expensive in-memory sort operations when serving the default note list ordered by recency. |
| `ix_notes_search_trgm` *(Recommended for Search)* | `(title, content)` | **GIN** (`pg_trgm`) | `SELECT * FROM notes WHERE title ILIKE '%term%' OR content ILIKE '%term%';` | Speeds up fuzzy search filtering across titles and bodies once note count exceeds thousands of rows. |

---

## 4. Database Migration Strategy

To guarantee zero-downtime deployments and version-controlled schema evolution, migrations are managed with **Alembic**:

### Migration Workflow
1. **Schema Modifications:** Changes are made to Python declarative models in `backend/app/models.py`.
2. **Revision Generation:**
   ```bash
   alembic revision --autogenerate -m "add_category_to_notes"
   ```
3. **Review & Verification:** The generated migration script in `backend/alembic/versions/` is reviewed to ensure:
   - Table locks are minimized (e.g. adding columns with defaults uses PostgreSQL 11+ fast column addition).
   - Indexes are created concurrently (`CREATE INDEX CONCURRENTLY`) for production.
4. **Execution in Pipeline:**
   - **Local:** `alembic upgrade head`
   - **Production:** Migrations execute as a discrete step in the CI/CD pipeline (e.g., via a one-off ECS migration task or EC2 SSM automation) **prior** to shifting traffic to new application instances.

---

## 5. Amazon RDS Backup & Recovery Plan

Production data resilience is architected around multi-layered backup strategies:

### 1. Automated Continuous Backups (PITR)
* **Retention Window:** 30 days.
* **Mechanism:** RDS continuously records database storage volume snapshots and streams transaction write-ahead logs (WAL) to Amazon S3.
* **Point-in-Time Recovery (PITR):** Enables restoring the database to any specific second within the retention window (RPO: ~5 minutes).

### 2. Automated Daily Snapshots
* Taken during an off-peak maintenance window (e.g. `03:00 - 04:00 UTC`).
* Multi-AZ deployment ensures snapshot I/O pauses affect only the standby replica, eliminating latency spikes on the primary database.

### 3. Manual Pre-Deployment Snapshots
* A manual DB snapshot (`notes-db-pre-deploy-vX.Y.Z`) is triggered via automated pipeline prior to applying any database migration or deploying major code releases.
* Manual snapshots do not expire automatically and persist until explicitly pruned.

### 4. Disaster Recovery & Restoration Procedure
```mermaid
flowchart LR
    A["Trigger Recovery Event"] --> B["Select Snapshot / PITR Timestamp"]
    B --> C["Restore to New RDS Instance (e.g. notes-db-restored)"]
    C --> D["Run Smoke Queries & Integrity Checks"]
    D --> E["Update Secrets Manager DB Host Endpoint"]
    E --> F["Restart Backend Instances (Rolling Restart)"]
```
* Restoring does not overwrite the existing instance; it provisions a new RDS instance with a clean storage volume.
* Update `DATABASE_URL` in AWS Secrets Manager to point to the new RDS endpoint.
* Trigger a rolling restart of the EC2 Auto Scaling Group targets.

---

## 6. Secrets & Credential Management

Under no circumstances are database usernames, passwords, or hostnames hardcoded into source code or tracked in version control.

### Local Development
* Stored in `.env` at the project root / backend directory:
  ```env
  DATABASE_URL=postgresql://notes_user:notes_password@localhost:5433/notes_db
  ```
* Enforced in `.gitignore` to prevent accidental Git commits.

### Production Environment (AWS Secrets Manager)
* Database credentials reside in **AWS Secrets Manager** under the secret path:
  `prod/notes-app/database`
  ```json
  {
    "engine": "postgres",
    "host": "notes-db-prod.c123456789.us-east-1.rds.amazonaws.com",
    "port": 5432,
    "username": "notes_admin",
    "password": "<cryptographically_random_32_char_password>",
    "dbname": "notes_db"
  }
  ```
* **Credential Retrieval:**
  1. EC2 instances in the Auto Scaling Group assume an **IAM Role** with a policy strictly scoped to `secretsmanager:GetSecretValue` on that specific ARN.
  2. At application boot, the configuration module constructs the SQLAlchemy connection string dynamically from the retrieved secret.
* **Automated Rotation:** Secrets Manager coordinates with RDS to automatically rotate the master password every 30 days without application downtime.

---

## 7. Network Access & Security Boundaries

The database has zero public internet exposure:

```text
[Public Internet] 
       │ 
       ▼ (Blocked)
[Internet Gateway] ──x──> [Private DB Subnets (10.0.20.0/24, 10.0.21.0/24)]
                                   │
                                   ▼
                      [RDS PostgreSQL (Port 5432)]
                                   ▲
                                   │ (Allowed TCP 5432)
                       [Security Group: sg-app]
                    (EC2 Backend Auto Scaling Group)
```

1. **Subnet Placement:** RDS DB instances reside exclusively in private database subnets with no route to an Internet Gateway (`0.0.0.0/0 -> igw` does not exist in their route tables).
2. **Public Accessibility:** The RDS attribute `PubliclyAccessible` is set to `false`.
3. **Security Group Ingress:** The RDS Security Group (`sg-db`) allows incoming traffic strictly on port `5432` where the source is the application security group ID (`sg-app`).
4. **Administrative Access:** Direct database maintenance is conducted via AWS Systems Manager Session Manager (SSM) using a temporary private bastion or port-forwarding session; no SSH keys or open ports are permitted.

---

## 8. Row-Level Security (RLS) Status

* **Status:** **Skipped by Design.**
* **Justification:** The current release operates as an unauthenticated single-tenant application where all records are accessible to any viewer. Implementing RLS policies without user identities or tenant IDs introduces unnecessary overhead without security value.

---

## 9. Current Schema Limitations & Future Extensibility

The current minimal schema does not support the following features (deferred to future milestones):

1. **User Authentication & Multi-Tenancy:**
   - *Limitation:* No `user_id` or `tenant_id` foreign keys exist. Every note is global.
   - *Future Solution:* Add a `users` table and `user_id UUID REFERENCES users(id)`.
2. **Soft Deletions:**
   - *Limitation:* Notes are permanently deleted (`DELETE FROM notes WHERE id = :id`).
   - *Future Solution:* Add `deleted_at TIMESTAMPTZ NULL` and filter queries with `WHERE deleted_at IS NULL`.
3. **Revision History & Audit Logs:**
   - *Limitation:* Overwriting a note destroys previous versions.
   - *Future Solution:* Introduce an append-only `note_revisions` table or database audit triggers.
4. **Rich Media & File Attachments:**
   - *Limitation:* Only plain text bodies can be stored; uploading images, PDFs, or binary files is unsupported.
   - *Future Solution:* Add an `attachments` table storing S3 object keys, presigned URLs, and MIME types.
5. **Tags & Categorization:**
   - *Limitation:* Notes cannot be tagged or grouped into folders.
   - *Future Solution:* Introduce `tags` and `note_tags` many-to-many junction tables.
6. **Vector Search / Semantic Retrieval:**
   - *Limitation:* Search relies on string matching (`ILIKE`); semantic queries like "find notes about cloud security" cannot match without exact keywords.
   - *Future Solution:* Enable `pgvector` extension and add `embedding vector(1536)` column with an HNSW index.

