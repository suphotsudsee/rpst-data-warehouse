from fastapi import APIRouter

from app.api.routes import auth, dashboard, files, mappings, master_data, system, workflow

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(dashboard.router)
api_router.include_router(mappings.router)
api_router.include_router(master_data.router)
api_router.include_router(files.router)
api_router.include_router(workflow.router)
api_router.include_router(system.router)
