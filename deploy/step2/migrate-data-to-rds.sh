#!/usr/bin/env bash
# ==============================================================================
# migrate-data-to-rds.sh — Step 1 to Step 2 Database Data Migration Tool
# Exports notes data from Step 1 local PostgreSQL and imports into Amazon RDS.
# ==============================================================================

set -euo pipefail

echo "===================================================================="
echo " Cloud Notes: Step 1 Local PostgreSQL -> Step 2 Amazon RDS Migration"
echo " Date: $(date -u)"
echo "===================================================================="

RDS_HOST="${1:-}"
RDS_USER="${2:-notes_user}"
RDS_DB="${3:-notes_db}"

if [ -z "${RDS_HOST}" ]; then
    echo "Usage: $0 <rds_endpoint_host> [rds_user] [rds_dbname]"
    echo "Example: $0 notes-rds.xxxxxx.ap-southeast-2.rds.amazonaws.com notes_user notes_db"
    exit 1
fi

DUMP_FILE="/tmp/notes_db_backup_$(date +%Y%m%d_%H%M%S).sql"

echo "[1/4] Dumping data and schema from local PostgreSQL (127.0.0.1:5432)..."
PGPASSWORD="${LOCAL_DB_PASS:-}" pg_dump -h 127.0.0.1 -p 5432 -U "${RDS_USER}" -d "${RDS_DB}" --no-owner --no-acl --clean --if-exists -f "${DUMP_FILE}"

echo "[2/4] Verifying dump file integrity..."
if [ ! -s "${DUMP_FILE}" ]; then
    echo "[ERROR] Dump file is empty or missing: ${DUMP_FILE}"
    exit 1
fi
echo "✔ Exported $(wc -l < "${DUMP_FILE}") SQL statements into ${DUMP_FILE}"

echo "[3/4] Restoring schema and data into Amazon RDS (${RDS_HOST})..."
PGPASSWORD="${RDS_DB_PASS:-}" psql -h "${RDS_HOST}" -p 5432 -U "${RDS_USER}" -d "${RDS_DB}" -f "${DUMP_FILE}"

echo "[4/4] Verifying target row counts in Amazon RDS..."
LOCAL_COUNT=$(PGPASSWORD="${LOCAL_DB_PASS:-}" psql -h 127.0.0.1 -p 5432 -U "${RDS_USER}" -d "${RDS_DB}" -tAc "SELECT count(*) FROM notes;")
RDS_COUNT=$(PGPASSWORD="${RDS_DB_PASS:-}" psql -h "${RDS_HOST}" -p 5432 -U "${RDS_USER}" -d "${RDS_DB}" -tAc "SELECT count(*) FROM notes;")

echo "Source Row Count: ${LOCAL_COUNT}"
echo "Target Row Count: ${RDS_COUNT}"

if [ "${LOCAL_COUNT}" -eq "${RDS_COUNT}" ]; then
    echo "===================================================================="
    echo " ✔ Migration SUCCESSFUL! Row counts match: ${RDS_COUNT} records."
    echo "===================================================================="
    rm -f "${DUMP_FILE}"
else
    echo "===================================================================="
    echo " ✖ Migration MISMATCH! Source: ${LOCAL_COUNT} vs Target: ${RDS_COUNT}"
    echo " Inspect dump file at: ${DUMP_FILE}"
    echo "===================================================================="
    exit 1
fi
