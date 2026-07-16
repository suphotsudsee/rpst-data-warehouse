"""initial schema

Revision ID: 0001
Revises:
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

role = sa.Enum("viewer", "editor", "approver", "super_admin", name="role")
mapping_status = sa.Enum("draft", "pending", "approved", "published", "rejected", name="mappingstatus")
approval_action = sa.Enum("submit", "approve", "reject", "publish", name="approvalaction")


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("username", sa.String(80), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("role", role, nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("username"),
        sa.UniqueConstraint("email"),
    )
    op.create_index("ix_users_username", "users", ["username"])
    op.create_index("ix_users_email", "users", ["email"])
    op.create_index("ix_users_role", "users", ["role"])
    op.create_table(
        "mappings",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column("benefit_code", sa.String(50), nullable=False),
        sa.Column("benefit_name", sa.String(255), nullable=False),
        sa.Column("account_code", sa.String(50), nullable=False),
        sa.Column("account_name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text()),
        sa.Column("effective_date", sa.Date(), nullable=False),
        sa.Column("expiry_date", sa.Date()),
        sa.Column("status", mapping_status, nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), nullable=False),
        sa.Column("created_by", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("updated_by", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("benefit_code", "account_code", "effective_date", name="uq_mapping_business_key"),
    )
    for column in ("sequence", "benefit_code", "account_code", "status", "is_deleted"):
        op.create_index(f"ix_mappings_{column}", "mappings", [column])
    op.create_table(
        "audit_logs",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id")),
        sa.Column("action", sa.String(80), nullable=False),
        sa.Column("entity_type", sa.String(80), nullable=False),
        sa.Column("entity_id", sa.String(36)),
        sa.Column("old_value", sa.JSON()),
        sa.Column("new_value", sa.JSON()),
        sa.Column("ip_address", sa.String(64)),
        sa.Column("user_agent", sa.String(512)),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    for column in ("user_id", "action", "entity_type", "entity_id", "created_at"):
        op.create_index(f"ix_audit_logs_{column}", "audit_logs", [column])
    op.create_table(
        "approvals",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("mapping_id", sa.String(36), sa.ForeignKey("mappings.id"), nullable=False),
        sa.Column("action", approval_action, nullable=False),
        sa.Column("comment", sa.Text()),
        sa.Column("acted_by", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_approvals_mapping_id", "approvals", ["mapping_id"])
    op.create_table(
        "backups",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("label", sa.String(255), nullable=False),
        sa.Column("reason", sa.String(255), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("record_count", sa.Integer(), nullable=False),
        sa.Column("created_by", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_backups_created_at", "backups", ["created_at"])


def downgrade() -> None:
    op.drop_table("backups")
    op.drop_table("approvals")
    op.drop_table("audit_logs")
    op.drop_table("mappings")
    op.drop_table("users")
