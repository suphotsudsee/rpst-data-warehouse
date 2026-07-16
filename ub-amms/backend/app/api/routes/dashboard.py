from sqlalchemy import distinct, func, select
from sqlalchemy.orm import Session
from fastapi import APIRouter, Depends

from app.auth.security import get_current_user
from app.core.database import get_db
from app.models.entities import AuditLog, Mapping, MappingStatus, User
from app.schemas.common import DashboardStats
from app.services.mappings import validation_errors

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])


@router.get("", response_model=DashboardStats)
def dashboard(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> DashboardStats:
    active = Mapping.is_deleted.is_(False)
    mappings = db.scalars(select(Mapping).where(active)).all()
    duplicate_rows = db.execute(
        select(Mapping.benefit_code, Mapping.account_code, func.count(Mapping.id))
        .where(active)
        .group_by(Mapping.benefit_code, Mapping.account_code)
        .having(func.count(Mapping.id) > 1)
    ).all()
    recent = db.scalars(select(AuditLog).order_by(AuditLog.created_at.desc()).limit(10)).all()
    return DashboardStats(
        mappings=len(mappings),
        benefits=db.scalar(select(func.count(distinct(Mapping.benefit_code))).where(active)) or 0,
        account_codes=db.scalar(select(func.count(distinct(Mapping.account_code))).where(active)) or 0,
        duplicates=len(duplicate_rows),
        validation_errors=sum(bool(validation_errors(item)) for item in mappings),
        pending_approval=sum(item.status == MappingStatus.pending for item in mappings),
        latest_version=max((item.version for item in mappings), default=0),
        recent_activity=[
            {
                "action": item.action,
                "entity_type": item.entity_type,
                "entity_id": item.entity_id,
                "created_at": item.created_at.isoformat(),
            }
            for item in recent
        ],
    )
