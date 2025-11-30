"""Add profile_image_url to users table

Revision ID: 003_add_profile_image_url
Revises: 002_user_collections
Create Date: 2025-11-30

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '003_add_profile_image_url'
down_revision = '002_user_collections'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add profile_image_url column to users table
    op.add_column('users', sa.Column('profile_image_url', sa.String(), nullable=True))


def downgrade() -> None:
    # Remove profile_image_url column from users table
    op.drop_column('users', 'profile_image_url')

