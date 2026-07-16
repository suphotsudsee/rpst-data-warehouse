from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.auth.security import get_current_user
from app.core.database import get_db
from app.models.entities import Mapping, MappingStatus, User
from app.schemas.common import MappingRead

router = APIRouter(prefix="/master-data", tags=["Master Data API"])


@router.get("/mappings", response_model=list[MappingRead])
def published_mappings(
    as_of: date | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> list[Mapping]:
    target_date = as_of or date.today()
    return list(
        db.scalars(
            select(Mapping)
            .where(
                Mapping.is_deleted.is_(False),
                Mapping.status == MappingStatus.published,
                Mapping.effective_date <= target_date,
                or_(Mapping.expiry_date.is_(None), Mapping.expiry_date >= target_date),
            )
            .order_by(Mapping.sequence, Mapping.benefit_code)
        ).all()
    )
