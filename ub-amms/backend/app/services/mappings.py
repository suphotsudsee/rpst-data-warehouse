from datetime import date, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.entities import Backup, Mapping, User


def serialize_mapping(mapping: Mapping) -> dict[str, Any]:
    return {
        "id": mapping.id,
        "sequence": mapping.sequence,
        "benefit_code": mapping.benefit_code,
        "benefit_name": mapping.benefit_name,
        "account_code": mapping.account_code,
        "account_name": mapping.account_name,
        "description": mapping.description,
        "source_sheet": mapping.source_sheet,
        "source_row": mapping.source_row,
        "source_data": mapping.source_data,
        "effective_date": mapping.effective_date.isoformat(),
        "expiry_date": mapping.expiry_date.isoformat() if mapping.expiry_date else None,
        "status": mapping.status.value,
        "version": mapping.version,
        "is_deleted": mapping.is_deleted,
        "created_by": mapping.created_by,
        "updated_by": mapping.updated_by,
        "created_at": mapping.created_at.isoformat(),
        "updated_at": mapping.updated_at.isoformat(),
    }


def create_backup(db: Session, user: User, reason: str, label: str | None = None) -> Backup:
    mappings = db.scalars(select(Mapping)).all()
    payload = [serialize_mapping(item) for item in mappings]
    backup = Backup(
        label=label or f"Automatic backup {datetime.now().isoformat(timespec='seconds')}",
        reason=reason,
        payload=payload,
        record_count=len(payload),
        created_by=user.id,
    )
    db.add(backup)
    db.flush()
    return backup


def validation_errors(mapping: Mapping) -> list[str]:
    errors: list[str] = []
    if mapping.sequence < 1:
        errors.append("sequence must be greater than zero")
    for field in ("benefit_code", "benefit_name", "account_code", "account_name"):
        if not getattr(mapping, field, "").strip():
            errors.append(f"{field} is required")
    if mapping.expiry_date and mapping.expiry_date < mapping.effective_date:
        errors.append("expiry_date must not be earlier than effective_date")
    if mapping.source_data:
        if not str(mapping.source_data.get("namepttype") or "").strip():
            errors.append("namepttype is required")
    return errors


def parse_date(value: str | None) -> date | None:
    return date.fromisoformat(value) if value else None
