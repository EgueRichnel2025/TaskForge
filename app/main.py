from fastapi import FastAPI, HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.database import engine

app = FastAPI(
    title="TaskForge API",
    description="API for the TaskForge DevOps platform.",
    version="0.1.0",
)


@app.get("/health", tags=["health"])
def health_check() -> dict[str, str]:
    """Check whether the API is running."""
    return {"status": "ok"}


@app.get("/health/ready", tags=["health"])
def readiness_check() -> dict[str, str]:
    """Check whether the API can access its database."""
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database unavailable",
        ) from exc

    return {
        "status": "ok",
        "database": "connected",
    }
