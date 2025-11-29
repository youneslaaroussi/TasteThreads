import os
from sqlalchemy import create_engine, Column, String, Boolean, DateTime, Text, Integer
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.mutable import MutableList
from datetime import datetime
from typing import Generator
import json

# Database URL from environment
DATABASE_URL = os.getenv("DATABASE_URL")

# Fix postgres:// to postgresql:// for SQLAlchemy compatibility
if DATABASE_URL and DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

if not DATABASE_URL:
    print("WARNING: DATABASE_URL not set. Database operations will fail.")
    DATABASE_URL = "postgresql://localhost/tastethreads"

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# --- Database Models ---

class RoomDB(Base):
    __tablename__ = "rooms"
    
    id = Column(String, primary_key=True, index=True)
    name = Column(String, nullable=False)
    is_public = Column(Boolean, default=False)
    join_code = Column(String, unique=True, nullable=False, index=True)
    owner_id = Column(String, nullable=False)
    members = Column(MutableList.as_mutable(JSONB), default=list)  # List of user objects
    messages = Column(MutableList.as_mutable(JSONB), default=list)  # List of message objects
    itinerary = Column(MutableList.as_mutable(JSONB), default=list)  # List of itinerary items
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class UserDB(Base):
    __tablename__ = "users"
    
    id = Column(String, primary_key=True, index=True)
    name = Column(String, nullable=False)
    avatar_url = Column(String, nullable=True)
    whatsapp_id = Column(String, nullable=True, unique=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class ChatSessionDB(Base):
    __tablename__ = "chat_sessions"
    
    room_id = Column(String, primary_key=True, index=True)
    chat_id = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class SavedLocationDB(Base):
    """User's saved/favorited locations"""
    __tablename__ = "saved_locations"
    
    id = Column(String, primary_key=True, index=True)  # user_id + yelp_id combined
    user_id = Column(String, nullable=False, index=True)
    yelp_id = Column(String, nullable=False)
    location_data = Column(JSONB, nullable=False)  # Full Location object as JSON
    created_at = Column(DateTime, default=datetime.utcnow)


class AIDiscoveryDB(Base):
    """AI-suggested locations from chat conversations"""
    __tablename__ = "ai_discoveries"
    
    id = Column(String, primary_key=True, index=True)  # user_id + yelp_id combined
    user_id = Column(String, nullable=False, index=True)
    yelp_id = Column(String, nullable=False)
    location_data = Column(JSONB, nullable=False)  # Full Location object as JSON
    ai_remark = Column(Text, nullable=True)  # The AI's comment about this place
    room_id = Column(String, nullable=True)  # Which room this came from
    created_at = Column(DateTime, default=datetime.utcnow)


# --- Database initialization ---

def init_db():
    """Create all tables in the database"""
    Base.metadata.create_all(bind=engine)
    print("Database tables created successfully")

def get_db() -> Generator[Session, None, None]:
    """
    Dependency function to get a database session.
    Use this in FastAPI endpoints with Depends(get_db)
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

