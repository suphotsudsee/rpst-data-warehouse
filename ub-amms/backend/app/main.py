from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from app.api.router import api_router
from app.auth.security import hash_password
from app.core.config import settings
from app.core.database import SessionLocal
from app.models.entities import Role, User


def bootstrap() -> None:
    Path(settings.upload_dir).mkdir(parents=True, exist_ok=True)
    Path(settings.backup_dir).mkdir(parents=True, exist_ok=True)
    with SessionLocal() as db:
        existing = db.scalar(select(User).where(User.username == settings.initial_admin_username))
        if not existing:
            db.add(
                User(
                    username=settings.initial_admin_username,
                    email=settings.initial_admin_email,
                    password_hash=hash_password(settings.initial_admin_password),
                    role=Role.super_admin,
                )
            )
            db.commit()


@asynccontextmanager
async def lifespan(_: FastAPI):
    bootstrap()
    yield


app = FastAPI(
    title="UB-AMMS API",
    version="0.1.0",
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(api_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": settings.app_name, "environment": settings.environment}
