"""add user collections tables for saved locations and AI discoveries

Revision ID: 002_user_collections
Revises: 9895890f44d5
Create Date: 2025-11-29

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '002_user_collections'
down_revision = '9895890f44d5'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create saved_locations table for user favorites
    op.create_table(
        'saved_locations',
        sa.Column('id', sa.String(), nullable=False),
        sa.Column('user_id', sa.String(), nullable=False),
        sa.Column('yelp_id', sa.String(), nullable=False),
        sa.Column('location_data', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_saved_locations_id'), 'saved_locations', ['id'], unique=False)
    op.create_index(op.f('ix_saved_locations_user_id'), 'saved_locations', ['user_id'], unique=False)

    # Create ai_discoveries table for AI-suggested locations
    op.create_table(
        'ai_discoveries',
        sa.Column('id', sa.String(), nullable=False),
        sa.Column('user_id', sa.String(), nullable=False),
        sa.Column('yelp_id', sa.String(), nullable=False),
        sa.Column('location_data', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('ai_remark', sa.Text(), nullable=True),
        sa.Column('room_id', sa.String(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_discoveries_id'), 'ai_discoveries', ['id'], unique=False)
    op.create_index(op.f('ix_ai_discoveries_user_id'), 'ai_discoveries', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_ai_discoveries_user_id'), table_name='ai_discoveries')
    op.drop_index(op.f('ix_ai_discoveries_id'), table_name='ai_discoveries')
    op.drop_table('ai_discoveries')
    
    op.drop_index(op.f('ix_saved_locations_user_id'), table_name='saved_locations')
    op.drop_index(op.f('ix_saved_locations_id'), table_name='saved_locations')
    op.drop_table('saved_locations')

