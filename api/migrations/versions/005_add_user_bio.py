"""Add bio field to users table

Revision ID: 005_add_user_bio
Revises: 004_add_user_contact_fields
Create Date: 2025-11-30

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '005_add_user_bio'
down_revision = '004_add_user_contact_fields'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add bio column to users table
    op.add_column('users', sa.Column('bio', sa.String(), nullable=True))


def downgrade() -> None:
    # Remove bio column from users table
    op.drop_column('users', 'bio')

