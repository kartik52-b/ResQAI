from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
from config import settings
from database import init_db, close_db
from routes.emergency import router as emergency_router
from routes.incident import router as incident_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handle startup and shutdown events."""
    # Startup
    print(f"Starting {settings.APP_NAME} v{settings.VERSION}")
    await init_db()
    print("Database initialized")
    yield
    # Shutdown
    await close_db()
    print("Server shut down")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.VERSION,
    description="ResQ AI - Intelligent Emergency Detection Backend",
    lifespan=lifespan,
)

# CORS middleware for dashboard and mobile app
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Return 400 (not FastAPI's default 422) for invalid request bodies.

    The API contract (and the tests) expect a 400 for malformed payloads.
    """
    errors = []
    for err in exc.errors():
        err = dict(err)
        # ``ctx`` may hold non-JSON-serializable exception objects
        err.pop("ctx", None)
        err.pop("url", None)
        errors.append(err)
    return JSONResponse(status_code=400, content={"detail": errors})


# Include routers
app.include_router(emergency_router)
app.include_router(incident_router)


@app.get("/")
async def root():
    return {
        "name": settings.APP_NAME,
        "version": settings.VERSION,
        "status": "running",
        "docs": "/docs",
    }


@app.get("/health")
async def health():
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
    )
