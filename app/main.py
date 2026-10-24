from fastapi import FastAPI

app = FastAPI(
    title="TaskForge API",
    description="API for the TaskForge DevOps platform.",
    version="0.1.0",
)


@app.get("/health", tags=["health"])
def health_check() -> dict[str, str]:
    """Return the health status of the API."""
    return {"status": "ok"}
