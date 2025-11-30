"""Add contact fields to users table for reservations

Revision ID: 004_add_user_contact_fields
Revises: 003_add_profile_image_url
Create Date: 2025-11-30

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '004_add_user_contact_fields'
down_revision = '003_add_profile_image_url'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add contact fields to users table for reservations
    op.add_column('users', sa.Column('first_name', sa.String(), nullable=True))
    op.add_column('users', sa.Column('last_name', sa.String(), nullable=True))
    op.add_column('users', sa.Column('phone_number', sa.String(), nullable=True))
    op.add_column('users', sa.Column('email', sa.String(), nullable=True))


def downgrade() -> None:
    # Remove contact fields from users table
    op.drop_column('users', 'email')
    op.drop_column('users', 'phone_number')
    op.drop_column('users', 'last_name')
    op.drop_column('users', 'first_name')

