"""
User Collections API - Saved Locations & AI Discoveries
"""
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, field_serializer
from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from datetime import datetime, timezone

from database import get_db, SavedLocationDB, AIDiscoveryDB
from auth import get_current_user

router = APIRouter()


# --- Request/Response Models ---

class LocationData(BaseModel):
    name: str
    address: str
    latitude: float
    longitude: float
    rating: float
    image_url: Optional[str] = None
    yelp_id: Optional[str] = None
    yelp_details: Optional[Dict[str, Any]] = None
    ai_remark: Optional[str] = None


class SaveLocationRequest(BaseModel):
    location: LocationData


class AIDiscoveryRequest(BaseModel):
    location: LocationData
    ai_remark: Optional[str] = None
    room_id: Optional[str] = None


class SavedLocationResponse(BaseModel):
    id: str
    yelp_id: str
    location: Dict[str, Any]
    created_at: datetime

    class Config:
        from_attributes = True
    
    @field_serializer('created_at')
    def serialize_datetime(self, value: datetime) -> str:
        """Serialize datetime to ISO8601 format with Z suffix for Swift compatibility"""
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.strftime('%Y-%m-%dT%H:%M:%SZ')


class AIDiscoveryResponse(BaseModel):
    id: str
    yelp_id: str
    location: Dict[str, Any]
    ai_remark: Optional[str]
    room_id: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True
    
    @field_serializer('created_at')
    def serialize_datetime(self, value: datetime) -> str:
        """Serialize datetime to ISO8601 format with Z suffix for Swift compatibility"""
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.strftime('%Y-%m-%dT%H:%M:%SZ')


# --- Saved Locations Endpoints ---

@router.get("/saved", response_model=List[SavedLocationResponse])
async def get_saved_locations(user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Get all saved/favorited locations for the current user"""
    saved = db.query(SavedLocationDB).filter(SavedLocationDB.user_id == user["uid"]).order_by(SavedLocationDB.created_at.desc()).all()
    
    return [
        SavedLocationResponse(
            id=s.id,
            yelp_id=s.yelp_id,
            location=s.location_data,
            created_at=s.created_at
        )
        for s in saved
    ]


@router.post("/saved", response_model=SavedLocationResponse)
async def save_location(request: SaveLocationRequest, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Save/favorite a location"""
    yelp_id = request.location.yelp_id or f"custom_{request.location.name}_{request.location.latitude}"
    record_id = f"{user['uid']}_{yelp_id}"
    
    # Check if already saved
    existing = db.query(SavedLocationDB).filter(SavedLocationDB.id == record_id).first()
    if existing:
        # Update existing
        existing.location_data = request.location.model_dump()
        db.commit()
        db.refresh(existing)
        return SavedLocationResponse(
            id=existing.id,
            yelp_id=existing.yelp_id,
            location=existing.location_data,
            created_at=existing.created_at
        )
    
    # Create new
    saved = SavedLocationDB(
        id=record_id,
        user_id=user["uid"],
        yelp_id=yelp_id,
        location_data=request.location.model_dump()
    )
    db.add(saved)
    db.commit()
    db.refresh(saved)
    
    print(f"API: Saved location {request.location.name} for user {user['uid']}")
    
    return SavedLocationResponse(
        id=saved.id,
        yelp_id=saved.yelp_id,
        location=saved.location_data,
        created_at=saved.created_at
    )


@router.delete("/saved/{yelp_id}")
async def unsave_location(yelp_id: str, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Remove a location from saved/favorites"""
    record_id = f"{user['uid']}_{yelp_id}"
    
    saved = db.query(SavedLocationDB).filter(SavedLocationDB.id == record_id).first()
    if not saved:
        raise HTTPException(status_code=404, detail="Saved location not found")
    
    db.delete(saved)
    db.commit()
    
    print(f"API: Removed saved location {yelp_id} for user {user['uid']}")
    
    return {"success": True, "message": "Location removed from saved"}


# --- AI Discoveries Endpoints ---

@router.get("/discoveries", response_model=List[AIDiscoveryResponse])
async def get_ai_discoveries(user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Get all AI-discovered locations for the current user"""
    discoveries = db.query(AIDiscoveryDB).filter(AIDiscoveryDB.user_id == user["uid"]).order_by(AIDiscoveryDB.created_at.desc()).all()
    
    return [
        AIDiscoveryResponse(
            id=d.id,
            yelp_id=d.yelp_id,
            location=d.location_data,
            ai_remark=d.ai_remark,
            room_id=d.room_id,
            created_at=d.created_at
        )
        for d in discoveries
    ]


@router.post("/discoveries", response_model=AIDiscoveryResponse)
async def add_ai_discovery(request: AIDiscoveryRequest, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Add an AI-discovered location"""
    yelp_id = request.location.yelp_id or f"custom_{request.location.name}_{request.location.latitude}"
    record_id = f"{user['uid']}_{yelp_id}"
    
    # Check if already exists
    existing = db.query(AIDiscoveryDB).filter(AIDiscoveryDB.id == record_id).first()
    if existing:
        # Update with new remark if provided
        if request.ai_remark:
            existing.ai_remark = request.ai_remark
        existing.location_data = request.location.model_dump()
        db.commit()
        db.refresh(existing)
        return AIDiscoveryResponse(
            id=existing.id,
            yelp_id=existing.yelp_id,
            location=existing.location_data,
            ai_remark=existing.ai_remark,
            room_id=existing.room_id,
            created_at=existing.created_at
        )
    
    # Create new
    discovery = AIDiscoveryDB(
        id=record_id,
        user_id=user["uid"],
        yelp_id=yelp_id,
        location_data=request.location.model_dump(),
        ai_remark=request.ai_remark,
        room_id=request.room_id
    )
    db.add(discovery)
    db.commit()
    db.refresh(discovery)
    
    print(f"API: Added AI discovery {request.location.name} for user {user['uid']}")
    
    return AIDiscoveryResponse(
        id=discovery.id,
        yelp_id=discovery.yelp_id,
        location=discovery.location_data,
        ai_remark=discovery.ai_remark,
        room_id=discovery.room_id,
        created_at=discovery.created_at
    )


@router.post("/discoveries/batch")
async def add_ai_discoveries_batch(
    discoveries: List[AIDiscoveryRequest], 
    user: dict = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    """Add multiple AI-discovered locations at once (from message processing)"""
    added = []
    
    for request in discoveries:
        yelp_id = request.location.yelp_id or f"custom_{request.location.name}_{request.location.latitude}"
        record_id = f"{user['uid']}_{yelp_id}"
        
        # Check if already exists
        existing = db.query(AIDiscoveryDB).filter(AIDiscoveryDB.id == record_id).first()
        if existing:
            if request.ai_remark:
                existing.ai_remark = request.ai_remark
            existing.location_data = request.location.model_dump()
            added.append(existing.id)
        else:
            discovery = AIDiscoveryDB(
                id=record_id,
                user_id=user["uid"],
                yelp_id=yelp_id,
                location_data=request.location.model_dump(),
                ai_remark=request.ai_remark,
                room_id=request.room_id
            )
            db.add(discovery)
            added.append(record_id)
    
    db.commit()
    print(f"API: Added {len(added)} AI discoveries for user {user['uid']}")
    
    return {"success": True, "added_count": len(added), "ids": added}


@router.delete("/discoveries/{yelp_id}")
async def remove_ai_discovery(yelp_id: str, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Remove an AI discovery"""
    record_id = f"{user['uid']}_{yelp_id}"
    
    discovery = db.query(AIDiscoveryDB).filter(AIDiscoveryDB.id == record_id).first()
    if not discovery:
        raise HTTPException(status_code=404, detail="Discovery not found")
    
    db.delete(discovery)
    db.commit()
    
    return {"success": True, "message": "Discovery removed"}


@router.delete("/discoveries")
async def clear_ai_discoveries(user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Clear all AI discoveries for the current user"""
    deleted = db.query(AIDiscoveryDB).filter(AIDiscoveryDB.user_id == user["uid"]).delete()
    db.commit()
    
    print(f"API: Cleared {deleted} AI discoveries for user {user['uid']}")
    
    return {"success": True, "deleted_count": deleted}

