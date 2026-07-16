from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.entities import MappingStatus, Role


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: "UserRead"


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    username: str
    email: str
    role: Role
    is_active: bool


class MappingBase(BaseModel):
    sequence: int = Field(ge=1)
    benefit_code: str = Field(min_length=1, max_length=50)
    benefit_name: str = Field(min_length=1, max_length=255)
    account_code: str = Field(min_length=1, max_length=50)
    account_name: str = Field(min_length=1, max_length=255)
    description: str | None = None
    effective_date: date
    expiry_date: date | None = None

    @model_validator(mode="after")
    def validate_dates(self) -> "MappingBase":
        if self.expiry_date and self.expiry_date < self.effective_date:
            raise ValueError("expiry_date must not be earlier than effective_date")
        return self


class MappingCreate(MappingBase):
    pass


class MappingUpdate(BaseModel):
    sequence: int | None = Field(default=None, ge=1)
    benefit_code: str | None = Field(default=None, min_length=1, max_length=50)
    benefit_name: str | None = Field(default=None, min_length=1, max_length=255)
    account_code: str | None = Field(default=None, min_length=1, max_length=50)
    account_name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    effective_date: date | None = None
    expiry_date: date | None = None
    version: int = Field(ge=1)


class MappingRead(MappingBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    status: MappingStatus
    version: int
    created_by: str
    updated_by: str
    created_at: datetime
    updated_at: datetime


class MappingPage(BaseModel):
    items: list[MappingRead]
    total: int
    page: int
    page_size: int


class WorkflowRequest(BaseModel):
    mapping_ids: list[str] = Field(min_length=1)
    action: str
    comment: str | None = Field(default=None, max_length=2000)


class BackupRequest(BaseModel):
    label: str = Field(min_length=1, max_length=255)


class RestoreRequest(BaseModel):
    backup_id: str


class DashboardStats(BaseModel):
    mappings: int
    benefits: int
    account_codes: int
    duplicates: int
    validation_errors: int
    pending_approval: int
    latest_version: int
    recent_activity: list[dict]


class AuditRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str | None
    action: str
    entity_type: str
    entity_id: str | None
    old_value: dict | None
    new_value: dict | None
    ip_address: str | None
    user_agent: str | None
    created_at: datetime
