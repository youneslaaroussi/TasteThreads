# Database Migrations

Run migrations to set up your database schema.

## Quick Start

```bash
# Apply all migrations
python migrate.py
```

Or use alembic directly:

```bash
# Apply all migrations
alembic upgrade head

# Rollback one migration
alembic downgrade -1

# Show current version
alembic current

# Show migration history
alembic history
```

## Creating New Migrations

```bash
# Auto-generate migration from model changes
alembic revision --autogenerate -m "description"

# Create empty migration
alembic revision -m "description"
```

## Railway Deployment

Migrations run automatically on deploy via the Dockerfile.

