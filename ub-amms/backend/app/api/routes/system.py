from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.auth.security import get_current_user, require_roles
from app.core.database import get_db
from app.models.entities import AuditLog, Backup, Mapping, MappingStatus, Role, User
from app.schemas.common import AuditRead, BackupRequest, RestoreRequest
from app.services.audit import write_audit
from app.services.mappings import create_backup, parse_date

router = APIRouter(tags=["Audit / Backup"])


@router.get("/history", response_model=list[AuditRead])
def history(
    limit: int = 100,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> list[AuditLog]:
    return list(db.scalars(select(AuditLog).order_by(AuditLog.created_at.desc()).limit(min(limit, 1000))).all())


@router.get("/backups")
def backups(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(Role.super_admin)),
) -> list[dict]:
    items = db.scalars(select(Backup).order_by(Backup.created_at.desc()).limit(100)).all()
    return [
        {
            "id": item.id,
            "label": item.label,
            "reason": item.reason,
            "record_count": item.record_count,
            "created_by": item.created_by,
            "created_at": item.created_at,
        }
        for item in items
    ]


@router.post("/backup")
def backup(
    payload: BackupRequest,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(Role.super_admin)),
) -> dict:
    item = create_backup(db, user, "manual", payload.label)
    write_audit(db, request, user, "backup", "system", item.id, new_value={"record_count": item.record_count})
    db.commit()
    return {"id": item.id, "label": item.label, "record_count": item.record_count}


@router.post("/restore")
def restore(
    payload: RestoreRequest,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(Role.super_admin)),
) -> dict:
    source = db.get(Backup, payload.backup_id)
    if not source:
        raise HTTPException(status_code=404, detail="Backup not found")
    safety = create_backup(db, user, f"before-restore:{source.id}")
    db.execute(delete(Mapping))
    for row in source.payload:
        db.add(
            Mapping(
                id=row["id"],
                sequence=row["sequence"],
                benefit_code=row["benefit_code"],
                benefit_name=row["benefit_name"],
                account_code=row["account_code"],
                account_name=row["account_name"],
                description=row.get("description"),
                source_sheet=row.get("source_sheet"),
                source_row=row.get("source_row"),
                source_data=row.get("source_data"),
                effective_date=parse_date(row["effective_date"]),
                expiry_date=parse_date(row.get("expiry_date")),
                status=MappingStatus(row["status"]),
                version=row["version"],
                is_deleted=row["is_deleted"],
                created_by=row["created_by"],
                updated_by=user.id,
                created_at=datetime.fromisoformat(row["created_at"]),
                updated_at=datetime.now().astimezone(),
            )
        )
    write_audit(
        db,
        request,
        user,
        "restore",
        "system",
        source.id,
        new_value={"restored_records": source.record_count, "safety_backup_id": safety.id},
    )
    db.commit()
    return {"restored_records": source.record_count, "safety_backup_id": safety.id}
