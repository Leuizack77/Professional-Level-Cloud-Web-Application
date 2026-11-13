import os
import time
import logging
from typing import Dict, Any, Generator
from sqlalchemy import create_engine, text
from sqlalchemy.orm import declarative_base, sessionmaker, Session
from app.config import settings

logger = logging.getLogger(__name__)

# Resolve connection URL, defaulting to local zero-credential SQLite for test/local fallbacks
db_url = settings.DATABASE_URL or os.environ.get("DATABASE_URL", "sqlite:///./local_fallback.db")

# Configure connection pooling and engine parameters based on database dialect
is_sqlite = db_url.startswith("sqlite")

if is_sqlite:
    engine = create_engine(
        db_url,
        connect_args={"check_same_thread": False},
        pool_pre_ping=settings.DB_POOL_PRE_PING,
    )
else:
    # Production PostgreSQL connection pool configuration
    engine = create_engine(
        db_url,
        pool_size=settings.DB_POOL_SIZE,
        max_overflow=settings.DB_MAX_OVERFLOW,
        pool_timeout=settings.DB_POOL_TIMEOUT,
        pool_recycle=settings.DB_POOL_RECYCLE,
        pool_pre_ping=settings.DB_POOL_PRE_PING,
    )

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency for database sessions."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def check_db_connection() -> Dict[str, Any]:
    """
    Executes a lightweight query to verify connectivity to the relational database.
    Returns latency metrics and dialect without exposing raw database credentials.
    """
    start_time = time.perf_counter()
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    latency_ms = round((time.perf_counter() - start_time) * 1000, 2)

    dialect_name = engine.dialect.name
    return {
        "connected": True,
        "dialect": dialect_name,
        "latency_ms": latency_ms,
    }


def init_db() -> None:
    """Initializes tables if they do not exist (useful for test isolation)."""
    import app.models  # noqa: F401
    Base.metadata.create_all(bind=engine)
