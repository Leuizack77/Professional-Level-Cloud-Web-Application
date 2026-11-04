import os
import logging
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from app.config import settings

logger = logging.getLogger(__name__)

# Resolve connection URL, defaulting to local zero-credential SQLite for local fallbacks
db_url = settings.DATABASE_URL or os.environ.get("DATABASE_URL", "sqlite:///./local_fallback.db")

connect_args = {}
if db_url.startswith("sqlite"):
    connect_args["check_same_thread"] = False

engine = create_engine(
    db_url,
    connect_args=connect_args,
    pool_pre_ping=True,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    import app.models  # Ensure models are imported so tables are created
    Base.metadata.create_all(bind=engine)
