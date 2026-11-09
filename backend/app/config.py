from typing import List, Union
from pydantic import field_validator, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
import os


class Settings(BaseSettings):
    # Database connection URL must be supplied via environment variable (e.g. .env or cloud secret).
    # No plaintext credentials are permitted as default values in code.
    DATABASE_URL: str = Field(
        default="",
        description="Database connection URL. Must be supplied via environment variable.",
    )
    HOST: str = "127.0.0.1"
    PORT: int = 8000
    ENVIRONMENT: str = "development"

    # CORS origins must come strictly from environment variables with NO wildcard '*' default.
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


settings = Settings()
