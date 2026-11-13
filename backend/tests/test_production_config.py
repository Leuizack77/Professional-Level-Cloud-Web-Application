import pytest
from app.config import Settings
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_discrete_db_parameters_resolution():
    """Verify that discrete DB_* variables assemble into a valid PostgreSQL connection string."""
    cfg = Settings(
        DATABASE_URL="",
        DB_HOST="rds-notes-postgres.cluster-custom.ap-southeast-2.rds.amazonaws.com",
        DB_PORT=5432,
        DB_NAME="notes_db",
        DB_USER="cloud_admin",
        DB_PASSWORD="P@ssw0rd!#Secret$",
        DB_SSLMODE="require",
        CORS_ORIGINS="http://localhost:5173",
    )
    # Password should be URL-encoded: P%40ssw0rd%21%23Secret%24
    expected_url = (
        "postgresql://cloud_admin:P%40ssw0rd%21%23Secret%24"
        "@rds-notes-postgres.cluster-custom.ap-southeast-2.rds.amazonaws.com:5432/notes_db"
        "?sslmode=require"
    )
    assert cfg.DATABASE_URL == expected_url


def test_postgres_url_scheme_normalization():
    """Verify legacy postgres:// scheme is normalized to modern postgresql://."""
    cfg = Settings(
        DATABASE_URL="postgres://user:pass@db-host:5432/mydb",
        CORS_ORIGINS="http://localhost:5173",
    )
    assert cfg.DATABASE_URL == "postgresql://user:pass@db-host:5432/mydb"


def test_connection_pool_configuration():
    """Verify connection pool defaults are sized safely for production RDS."""
    cfg = Settings(CORS_ORIGINS="http://localhost:5173")
    assert cfg.DB_POOL_SIZE == 10
    assert cfg.DB_MAX_OVERFLOW == 5
    assert cfg.DB_POOL_TIMEOUT == 30
    assert cfg.DB_POOL_RECYCLE == 1800
    assert cfg.DB_POOL_PRE_PING is True


def test_readiness_probe_returns_ready():
    """Verify the /health/ready probe returns 200 OK with connectivity details."""
    response = client.get("/health/ready")
    assert response.status_code == 200
    payload = response.json()
    assert payload["ready"] is True
    assert payload["status"] == "ready"
    assert payload["database"] == "connected"
    assert "dialect" in payload
    assert "timestamp" in payload


def test_deep_database_health_check_enhanced_metrics():
    """Verify /health/db includes dialect and latency metrics."""
    response = client.get("/health/db")
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "healthy"
    assert payload["database"] == "connected"
    assert "dialect" in payload
    assert "latency_ms" in payload
    assert isinstance(payload["latency_ms"], (int, float))
