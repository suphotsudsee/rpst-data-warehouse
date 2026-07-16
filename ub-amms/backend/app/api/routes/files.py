from io import BytesIO

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import StreamingResponse
from openpyxl import Workbook, load_workbook
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth.security import get_current_user, require_roles
from app.core.config import settings
from app.core.database import get_db
from app.models.entities import Mapping, Role, User
from app.services.audit import write_audit
from app.services.mappings import create_backup, serialize_mapping

router = APIRouter(tags=["Import / Export"])
HEADERS = [
    "ลำดับ",
    "รหัสสิทธิ",
    "ชื่อสิทธิ",
    "รหัสบัญชี",
    "ชื่อบัญชี",
    "รายละเอียด",
    "วันที่เริ่มใช้",
    "วันที่สิ้นสุด",
    "สถานะ",
]


@router.post("/import")
async def import_excel(
    request: Request,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(Role.editor, Role.approver, Role.super_admin)),
) -> dict:
    if not file.filename or not file.filename.lower().endswith(".xlsx"):
        raise HTTPException(status_code=400, detail="Only .xlsx files are supported")
    content = await file.read(settings.max_upload_mb * 1024 * 1024 + 1)
    if len(content) > settings.max_upload_mb * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Uploaded file is too large")
    try:
        workbook = load_workbook(BytesIO(content), data_only=False, read_only=True)
        sheet = workbook.active
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid Excel file") from exc
    headers = [str(cell.value).strip() if cell.value is not None else "" for cell in next(sheet.iter_rows())]
    missing = [header for header in HEADERS[:5] if header not in headers]
    if missing:
        raise HTTPException(status_code=422, detail={"missing_headers": missing, "required_headers": HEADERS})
    index = {name: headers.index(name) for name in headers}
    create_backup(db, user, f"before-import:{file.filename}")
    imported = 0
    errors: list[dict] = []
    for row_number, cells in enumerate(sheet.iter_rows(values_only=True), start=2):
        if not any(value is not None for value in cells):
            continue
        try:
            item = Mapping(
                sequence=int(cells[index["ลำดับ"]]),
                benefit_code=str(cells[index["รหัสสิทธิ"]]).strip(),
                benefit_name=str(cells[index["ชื่อสิทธิ"]]).strip(),
                account_code=str(cells[index["รหัสบัญชี"]]).strip(),
                account_name=str(cells[index["ชื่อบัญชี"]]).strip(),
                description=str(cells[index["รายละเอียด"]]).strip()
                if "รายละเอียด" in index and cells[index["รายละเอียด"]] is not None
                else None,
                effective_date=cells[index["วันที่เริ่มใช้"]]
                if "วันที่เริ่มใช้" in index and cells[index["วันที่เริ่มใช้"]] is not None
                else __import__("datetime").date.today(),
                expiry_date=cells[index["วันที่สิ้นสุด"]]
                if "วันที่สิ้นสุด" in index and cells[index["วันที่สิ้นสุด"]] is not None
                else None,
                created_by=user.id,
                updated_by=user.id,
            )
            db.add(item)
            db.flush()
            imported += 1
        except (ValueError, TypeError, IntegrityError) as exc:
            db.rollback()
            errors.append({"row": row_number, "error": str(exc).splitlines()[0][:300]})
            if len(errors) >= 100:
                break
    if errors:
        db.rollback()
        raise HTTPException(status_code=422, detail={"message": "Import aborted; no rows were saved", "errors": errors})
    write_audit(
        db,
        request,
        user,
        "import",
        "mapping",
        new_value={"filename": file.filename, "record_count": imported},
    )
    db.commit()
    return {"filename": file.filename, "imported": imported}


@router.get("/export")
def export_excel(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> StreamingResponse:
    items = db.scalars(
        select(Mapping).where(Mapping.is_deleted.is_(False)).order_by(Mapping.sequence)
    ).all()
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Account Mapping"
    sheet.append(HEADERS)
    for item in items:
        sheet.append(
            [
                item.sequence,
                item.benefit_code,
                item.benefit_name,
                item.account_code,
                item.account_name,
                item.description,
                item.effective_date,
                item.expiry_date,
                item.status.value,
            ]
        )
    sheet.freeze_panes = "A2"
    sheet.auto_filter.ref = sheet.dimensions
    widths = [10, 18, 32, 18, 36, 40, 16, 16, 14]
    for column, width in zip("ABCDEFGHI", widths, strict=True):
        sheet.column_dimensions[column].width = width
    output = BytesIO()
    workbook.save(output)
    output.seek(0)
    return StreamingResponse(
        output,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": 'attachment; filename="ub-amms-mappings.xlsx"'},
    )
