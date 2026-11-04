import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.database import init_db
from app.routes.health import router as health_router
from app.routes.notes import router as notes_router

logging.basicConfig(
    level=logging.INFO if settings.ENVIRONMENT == "production" else logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize database tables on startup
    try:
        init_db()
        logger.info("Database schema initialized successfully.")
    except Exception as exc:
        logger.warning("Database initialization deferred: %s", exc)
    yield


# Restrict Swagger and ReDoc documentation in production environments
docs_url = "/docs" if settings.ENVIRONMENT != "production" else None
redoc_url = "/redoc" if settings.ENVIRONMENT != "production" else None
openapi_url = "/openapi.json" if settings.ENVIRONMENT != "production" else None

app = FastAPI(
    title="Notes API",
    description="Stateless CRUD API for Notes Application - Designed for Cloud Deployment",
    version="1.0.0",
    docs_url=docs_url,
    redoc_url=redoc_url,
    openapi_url=openapi_url,
    lifespan=lifespan,
)

# Enforce Security Headers Middleware
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response: Response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    if settings.ENVIRONMENT == "production":
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


# CORS middleware with explicit origins from environment variable (NO WILDCARD)
origins = settings.CORS_ORIGINS if isinstance(settings.CORS_ORIGINS, list) else [settings.CORS_ORIGINS]
origins = [o for o in origins if o]

if origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Content-Type", "Authorization", "Accept", "X-Requested-With"],
    )
else:
    logger.warning("No CORS_ORIGINS configured. Cross-origin browser requests will be blocked.")

# Include Routers
app.include_router(health_router)
app.include_router(notes_router)


@app.get("/", tags=["Root"])
def root():
    return {
        "status": "online",
        "service": "Notes API",
    }
