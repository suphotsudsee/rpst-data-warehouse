from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth.security import get_current_user, require_roles
from app.core.database import get_db
from app.models.entities import Mapping, MappingStatus, Role, User
from app.schemas.common import MappingCreate, MappingPage, MappingRead, MappingUpdate
from app.services.audit import write_audit
from app.services.mappings import create_backup, serialize_mapping

router = APIRouter(prefix="/mappings", tags=["Mappings"])
editor = require_roles(Role.editor, Role.approver, Role.super_admin)


@router.get("", response_model=MappingPage)
def list_mappings(
    search: str | None = None,
    status: MappingStatus | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> MappingPage:
    filters = [Mapping.is_deleted.is_(False)]
    if search:
        value = f"%{search.strip()}%"
        filters.append(
            or_(
                Mapping.benefit_code.like(value),
                Mapping.benefit_name.like(value),
                Mapping.account_code.like(value),
                Mapping.account_name.like(value),
            )
        )
    if status:
        filters.append(Mapping.status == status)
    total = db.scalar(select(func.count()).select_from(Mapping).where(*filters)) or 0
    items = db.scalars(
        select(Mapping)
        .where(*filters)
        .order_by(Mapping.sequence, Mapping.benefit_code)
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    return MappingPage(items=items, total=total, page=page, page_size=page_size)


@router.post("", response_model=MappingRead, status_code=201)
def create_mapping(
    payload: MappingCreate,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(editor),
) -> Mapping:
    create_backup(db, user, "before-create")
    item = Mapping(**payload.model_dump(), created_by=user.id, updated_by=user.id)
    db.add(item)
    db.flush()
    write_audit(db, request, user, "create", "mapping", item.id, new_value=serialize_mapping(item))
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail="Duplicate mapping business key") from exc
    db.refresh(item)
    return item


@router.put("/{mapping_id}", response_model=MappingRead)
def update_mapping(
    mapping_id: str,
    payload: MappingUpdate,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(editor),
) -> Mapping:
    item = db.scalar(select(Mapping).where(Mapping.id == mapping_id, Mapping.is_deleted.is_(False)))
    if not item:
        raise HTTPException(status_code=404, detail="Mapping not found")
    if item.version != payload.version:
        raise HTTPException(status_code=409, detail="Mapping was changed by another user; refresh and retry")
    if item.status == MappingStatus.published and user.role != Role.super_admin:
        raise HTTPException(status_code=403, detail="Published mappings can only be changed by Super Admin")
    create_backup(db, user, "before-update")
    old_value = serialize_mapping(item)
    changes = payload.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in changes.items():
        setattr(item, field, value)
    item.version += 1
    item.status = MappingStatus.draft
    item.updated_by = user.id
    db.flush()
    write_audit(db, request, user, "update", "mapping", item.id, old_value, serialize_mapping(item))
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail="Duplicate mapping business key") from exc
    db.refresh(item)
    return item


@router.delete("/{mapping_id}", status_code=204)
def delete_mapping(
    mapping_id: str,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(editor),
) -> None:
    item = db.scalar(select(Mapping).where(Mapping.id == mapping_id, Mapping.is_deleted.is_(False)))
    if not item:
        raise HTTPException(status_code=404, detail="Mapping not found")
    if item.status == MappingStatus.published and user.role != Role.super_admin:
        raise HTTPException(status_code=403, detail="Published mappings can only be deleted by Super Admin")
    create_backup(db, user, "before-delete")
    old_value = serialize_mapping(item)
    item.is_deleted = True
    item.version += 1
    item.updated_by = user.id
    write_audit(db, request, user, "delete", "mapping", item.id, old_value, serialize_mapping(item))
    db.commit()
