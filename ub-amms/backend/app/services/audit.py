from typing import Any

from fastapi import Request
from sqlalchemy.orm import Session

from app.models.entities import AuditLog, User


def write_audit(
    db: Session,
    request: Request,
    user: User | None,
    action: str,
    entity_type: str,
    entity_id: str | None = None,
    old_value: dict[str, Any] | None = None,
    new_value: dict[str, Any] | None = None,
) -> None:
    forwarded = request.headers.get("x-forwarded-for")
    ip_address = forwarded.split(",")[0].strip() if forwarded else (request.client.host if request.client else None)
    db.add(
        AuditLog(
            user_id=user.id if user else None,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            old_value=old_value,
            new_value=new_value,
            ip_address=ip_address,
            user_agent=request.headers.get("user-agent"),
        )
    )
