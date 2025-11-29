from dotenv import load_dotenv
load_dotenv()

import os
import logfire

# Configure Logfire BEFORE importing anything else that uses pydantic-ai
# Only send to Logfire if LOGFIRE_TOKEN is set (production) or user is authenticated (local dev)
try:
    logfire.configure()
    logfire.instrument_pydantic_ai()
    logfire.instrument_httpx(capture_all=True)
    print("Logfire configured successfully")
except Exception as e:
    print(f"Logfire not configured (running without observability): {e}")
    # Configure with send_to_logfire=False so spans still work locally but don't require auth
    logfire.configure(send_to_logfire=False)
    logfire.instrument_pydantic_ai()
    logfire.instrument_httpx(capture_all=True)

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routers import yelp, rooms, websocket, whatsapp, user_collections, orchestrator
import os
import auth # Initialize Firebase Admin SDK
from database import init_db
from redis_manager import get_redis_manager
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan event handler for startup and shutdown
    """
    # Startup
    print("Initializing Redis manager...")
    await get_redis_manager()
    logfire.info("TasteThreads API started successfully")
    
    yield
    
    # Shutdown
    logfire.info("Shutting down TasteThreads API...")

app = FastAPI(
    title="TasteThreads API",
    description="Backend API for TasteThreads with Postgres and Redis",
    version="2.0.0",
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Routers
app.include_router(yelp.router, prefix="/api/v1/yelp", tags=["yelp"])
app.include_router(rooms.router, prefix="/api/v1/rooms", tags=["rooms"])
app.include_router(websocket.router, prefix="/api/v1/rooms", tags=["websocket"])
app.include_router(whatsapp.router, prefix="/api/v1/whatsapp", tags=["whatsapp"])
app.include_router(user_collections.router, prefix="/api/v1/user", tags=["user-collections"])
app.include_router(orchestrator.router, prefix="/api/v1/ai", tags=["ai"])

@app.get("/")
async def root():
    return {
        "message": "TasteThreads API",
        "status": "running"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
    }
