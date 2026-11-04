import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session
from app.database import get_db

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Health"])


@router.get("/health", status_code=status.HTTP_200_OK)
def shallow_health_check():
    """
    Shallow health check for Application Load Balancer (ALB).
    Must remain strictly independent of the database to ensure the ALB can
    detect compute/process viability without overloading or failing during DB hiccups.
    """
    return {
        "status": "healthy",
        "service": "notes-api",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/health/db", status_code=status.HTTP_200_OK)
def deep_database_health_check(db: Session = Depends(get_db)):
    """
    Deep database health check.
    Verifies actual connectivity to PostgreSQL / relational database by executing a ping query.
    Logs error details internally without exposing raw database exceptions to callers.
    """
    try:
        db.execute(text("SELECT 1"))
        return {
            "status": "healthy",
            "database": "connected",
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
