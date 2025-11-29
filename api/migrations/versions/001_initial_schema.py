"""initial schema

Revision ID: 001
Revises: 
Create Date: 2025-11-29

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create users table
    op.create_table(
        'users',
        sa.Column('id', sa.String(), nullable=False),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('avatar_url', sa.String(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('updated_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_users_id'), 'users', ['id'], unique=False)

    # Create rooms table
    op.create_table(
        'rooms',
        sa.Column('id', sa.String(), nullable=False),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('is_public', sa.Boolean(), nullable=True),
        sa.Column('join_code', sa.String(), nullable=False),
        sa.Column('owner_id', sa.String(), nullable=False),
        sa.Column('members', sa.JSON(), nullable=True),
        sa.Column('messages', sa.JSON(), nullable=True),
        sa.Column('itinerary', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('updated_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_rooms_id'), 'rooms', ['id'], unique=False)
    op.create_index(op.f('ix_rooms_join_code'), 'rooms', ['join_code'], unique=True)

    # Create chat_sessions table
    op.create_table(
        'chat_sessions',
        sa.Column('room_id', sa.String(), nullable=False),
        sa.Column('chat_id', sa.String(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('updated_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('room_id')
    )
    op.create_index(op.f('ix_chat_sessions_room_id'), 'chat_sessions', ['room_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_chat_sessions_room_id'), table_name='chat_sessions')
    op.drop_table('chat_sessions')
    op.drop_index(op.f('ix_rooms_join_code'), table_name='rooms')
    op.drop_index(op.f('ix_rooms_id'), table_name='rooms')
    op.drop_table('rooms')
    op.drop_index(op.f('ix_users_id'), table_name='users')
    op.drop_table('users')

