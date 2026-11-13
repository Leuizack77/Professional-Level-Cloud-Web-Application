import logging
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, status
from app.config import settings
from app.database import check_db_connection

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Health"])


@router.get("/health", status_code=status.HTTP_200_OK)
def shallow_health_check():
    """
    Shallow health check for Application Load Balancer (ALB).
    Must remain strictly independent of the database to ensure the ALB can
    detect compute/process viability without failing during DB maintenance.
    """
    return {
        "status": "healthy",
        "service": "notes-api",
        "version": settings.APP_VERSION,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/health/db", status_code=status.HTTP_200_OK)
def deep_database_health_check():
    """
    Deep database health check.
    Verifies actual connectivity to PostgreSQL / relational database by executing a ping query.
    Logs error details internally without exposing raw database credentials or internal traces.
    """
    try:
        db_info = check_db_connection()
        return {
            "status": "healthy",
            "database": "connected",
            "dialect": db_info.get("dialect", "unknown"),
            "latency_ms": db_info.get("latency_ms", 0.0),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as exc:
        logger.error("Database connectivity health probe failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "status": "unhealthy",
                "database": "disconnected",
                "error": "Database connectivity check failed",
            },
        )


@router.get("/health/ready", status_code=status.HTTP_200_OK)
def readiness_probe():
    """
    Readiness probe for zero-downtime deployments.
    Verifies both process responsiveness and relational database connectivity
    before an instance receives live client traffic from the ALB.
    """
    try:
        db_info = check_db_connection()
        return {
            "ready": True,
            "status": "ready",
            "service": "notes-api",
            "database": "connected",
            "dialect": db_info.get("dialect", "unknown"),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as exc:
        logger.warning("Readiness probe not ready: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "ready": False,
                "status": "not_ready",
                "service": "notes-api",
                "database": "disconnected",
            },
        )
