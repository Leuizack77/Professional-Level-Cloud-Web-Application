import os
import urllib.parse
from typing import List, Union
from pydantic import field_validator, model_validator, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Application Metadata
    APP_NAME: str = "Notes API"
    APP_VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development"
    HOST: str = "127.0.0.1"
    PORT: int = 8000

    # Monolithic Database URL (optional if discrete fields are provided)
    DATABASE_URL: str = Field(
        default="",
        description="Database connection URL. Can be supplied directly or assembled from discrete DB_* vars.",
    )

    # Discrete Database Connection Variables for RDS / Secrets Manager
    DB_HOST: str = Field(default="", description="Database host (e.g. RDS endpoint or 127.0.0.1).")
    DB_PORT: int = Field(default=5432, description="Database port.")
    DB_NAME: str = Field(default="", description="Database name.")
    DB_USER: str = Field(default="", description="Database username.")
    DB_PASSWORD: str = Field(default="", description="Database password.")
    DB_SSLMODE: str = Field(default="", description="Database SSL mode (e.g. require, verify-full, prefer).")

    # Production Database Connection Pooling Settings
    # Sized conservatively for Amazon RDS db.t3.micro across multiple EC2 instances
    DB_POOL_SIZE: int = Field(
        default=10,
        description="Maximum number of persistent connections in the SQLAlchemy connection pool.",
    )
    DB_MAX_OVERFLOW: int = Field(
        default=5,
        description="Maximum number of temporary overflow connections above DB_POOL_SIZE.",
    )
    DB_POOL_TIMEOUT: int = Field(
        default=30,
        description="Seconds to wait before timing out on pool connection request.",
    )
    DB_POOL_RECYCLE: int = Field(
        default=1800,
        description="Seconds after which idle connections are recycled (prevents dropped connections in AWS RDS/NAT).",
    )
    DB_POOL_PRE_PING: bool = Field(
        default=True,
        description="Enables connection health check ping before each checkout from the pool.",
    )

    # CORS Configuration - Strict Non-Wildcard Policy
    CORS_ORIGINS: Union[str, List[str]] = Field(
        default="",
        description="Allowed CORS origins comma-separated. Must come from environment; no wildcard default.",
    )

    model_config = SettingsConfigDict(
        env_file=os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @field_validator("CORS_ORIGINS", mode="after")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str):
            origins = [origin.strip() for origin in v.split(",") if origin.strip()]
        elif isinstance(v, list):
            origins = [origin.strip() for origin in v if isinstance(origin, str) and origin.strip()]
        else:
            origins = []

        # Enforce hard security rule: zero wildcard '*' CORS origins permitted
        if "*" in origins:
            raise ValueError("Wildcard '*' CORS origin is strictly forbidden for security.")

        return origins

    @model_validator(mode="after")
    def resolve_database_url(self) -> "Settings":
        """
        Resolves DATABASE_URL from either the direct setting or discrete DB_* components.
        Normalizes postgres:// to postgresql:// and safely handles URL encoding for passwords.
        """
        url = self.DATABASE_URL.strip()

        # If DATABASE_URL is not directly provided but discrete parameters are present, construct it
        if not url and self.DB_HOST and self.DB_USER:
            encoded_password = urllib.parse.quote_plus(self.DB_PASSWORD) if self.DB_PASSWORD else ""
            auth = f"{self.DB_USER}:{encoded_password}@" if encoded_password else f"{self.DB_USER}@"
            port_part = f":{self.DB_PORT}" if self.DB_PORT else ":5432"
            db_name = self.DB_NAME or "notes_db"
            url = f"postgresql://{auth}{self.DB_HOST}{port_part}/{db_name}"

            if self.DB_SSLMODE:
                url = f"{url}?sslmode={self.DB_SSLMODE}"

        # Normalize postgres:// -> postgresql:// (common in cloud providers & older libraries)
        if url.startswith("postgres://"):
            url = url.replace("postgres://", "postgresql://", 1)

        self.DATABASE_URL = url
        return self


settings = Settings()
