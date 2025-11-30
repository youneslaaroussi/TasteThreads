"""Add preferences field to users table

Revision ID: 006_add_user_preferences
Revises: 005_add_user_bio
Create Date: 2025-11-30

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB


# revision identifiers, used by Alembic.
revision = '006_add_user_preferences'
down_revision = '005_add_user_bio'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add preferences column to users table (JSONB for flexible structure)
    op.add_column('users', sa.Column('preferences', JSONB, nullable=True))


def downgrade() -> None:
    # Remove preferences column from users table
    op.drop_column('users', 'preferences')

