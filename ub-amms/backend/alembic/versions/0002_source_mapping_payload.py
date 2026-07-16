"""add source mapping payload

Revision ID: 0002
Revises: 0001
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("mappings", sa.Column("source_sheet", sa.String(255), nullable=True))
    op.add_column("mappings", sa.Column("source_row", sa.Integer(), nullable=True))
    op.add_column("mappings", sa.Column("source_data", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("mappings", "source_data")
    op.drop_column("mappings", "source_row")
    op.drop_column("mappings", "source_sheet")
