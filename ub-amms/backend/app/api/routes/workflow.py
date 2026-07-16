from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.security import require_roles
from app.core.database import get_db
from app.models.entities import Approval, ApprovalAction, Mapping, MappingStatus, Role, User
from app.schemas.common import WorkflowRequest
from app.services.audit import write_audit
from app.services.mappings import create_backup, serialize_mapping, validation_errors

router = APIRouter(prefix="/workflow", tags=["Approval Workflow"])

TRANSITIONS = {
    "submit": (MappingStatus.draft, MappingStatus.pending, ApprovalAction.submit),
    "approve": (MappingStatus.pending, MappingStatus.approved, ApprovalAction.approve),
    "reject": (MappingStatus.pending, MappingStatus.rejected, ApprovalAction.reject),
    "publish": (MappingStatus.approved, MappingStatus.published, ApprovalAction.publish),
}


@router.post("")
def workflow(
    payload: WorkflowRequest,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(Role.editor, Role.approver, Role.super_admin)),
) -> dict:
    transition = TRANSITIONS.get(payload.action)
    if not transition:
        raise HTTPException(status_code=400, detail="Unsupported workflow action")
    source, target, approval_action = transition
    if payload.action in {"approve", "reject"} and user.role not in {Role.approver, Role.super_admin}:
        raise HTTPException(status_code=403, detail="Approver role required")
    if payload.action == "publish" and user.role != Role.super_admin:
        raise HTTPException(status_code=403, detail="Only Super Admin can publish")
    mappings = db.scalars(
        select(Mapping).where(Mapping.id.in_(payload.mapping_ids), Mapping.is_deleted.is_(False))
    ).all()
    if len(mappings) != len(set(payload.mapping_ids)):
        raise HTTPException(status_code=404, detail="One or more mappings were not found")
    invalid_status = [item.id for item in mappings if item.status != source]
    if invalid_status:
        raise HTTPException(status_code=409, detail={"message": f"Mappings must be {source.value}", "ids": invalid_status})
    invalid_data = {item.id: validation_errors(item) for item in mappings if validation_errors(item)}
    if invalid_data:
        raise HTTPException(status_code=422, detail={"validation_errors": invalid_data})
    create_backup(db, user, f"before-workflow:{payload.action}")
    for item in mappings:
        old_value = serialize_mapping(item)
        item.status = target
        item.version += 1
        item.updated_by = user.id
        db.add(Approval(mapping_id=item.id, action=approval_action, comment=payload.comment, acted_by=user.id))
        write_audit(db, request, user, payload.action, "mapping", item.id, old_value, serialize_mapping(item))
    db.commit()
    return {"action": payload.action, "updated": len(mappings), "status": target.value}
