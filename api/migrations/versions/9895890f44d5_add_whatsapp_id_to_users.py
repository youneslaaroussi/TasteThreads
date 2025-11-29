"""add whatsapp_id to users

Revision ID: 9895890f44d5
Revises: 001
Create Date: 2025-11-29 15:11:07.778317

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '9895890f44d5'
down_revision = '001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('whatsapp_id', sa.String(), nullable=True))
    op.create_unique_constraint('uq_users_whatsapp_id', 'users', ['whatsapp_id'])


def downgrade() -> None:
    op.drop_constraint('uq_users_whatsapp_id', 'users', type_='unique')
    op.drop_column('users', 'whatsapp_id')
