"""
User Collections API - Saved Locations & AI Discoveries & User Profile
"""
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, field_serializer
from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from datetime import datetime, timezone

from database import get_db, SavedLocationDB, AIDiscoveryDB, UserDB, RoomDB, ChatSessionDB
from auth import get_current_user
from models.user_profile_models import UserProfileResponse, UpdateProfileRequest

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


# --- User Profile Endpoints ---


@router.get("/profile", response_model=UserProfileResponse)
async def get_user_profile(user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Get the current user's profile"""
    db_user = db.query(UserDB).filter(UserDB.id == user["uid"]).first()
    
    if not db_user:
        # Create user if doesn't exist
        db_user = UserDB(
            id=user["uid"],
            name=user.get("name", user.get("email", "User")),
            email=user.get("email")
        )
        db.add(db_user)
        db.commit()
        db.refresh(db_user)
    
    return UserProfileResponse(
        id=db_user.id,
        name=db_user.name,
        bio=db_user.bio,
        profile_image_url=db_user.profile_image_url,
        preferences=db_user.preferences,  # Already a list of strings
        first_name=db_user.first_name,
        last_name=db_user.last_name,
        phone_number=db_user.phone_number,
        email=db_user.email,
        created_at=db_user.created_at
    )


@router.put("/profile", response_model=UserProfileResponse)
async def update_user_profile(
    request: UpdateProfileRequest, 
    user: dict = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    """Update the current user's profile (name, profile picture, and contact info)"""
    db_user = db.query(UserDB).filter(UserDB.id == user["uid"]).first()
    
    if not db_user:
        # Create user if doesn't exist
        db_user = UserDB(
            id=user["uid"],
            name=user.get("name", user.get("email", "User")),
            email=user.get("email")
        )
        db.add(db_user)
        db.commit()
        db.refresh(db_user)
    
    # Update fields if provided
    if request.name is not None:
        db_user.name = request.name
    
    if request.bio is not None:
        db_user.bio = request.bio
    
    if request.profile_image_url is not None:
        db_user.profile_image_url = request.profile_image_url
    
    if request.preferences is not None:
        db_user.preferences = request.preferences  # Already a list of strings
    
    if request.first_name is not None:
        db_user.first_name = request.first_name
    
    if request.last_name is not None:
        db_user.last_name = request.last_name
    
    if request.phone_number is not None:
        db_user.phone_number = request.phone_number
    
    if request.email is not None:
        db_user.email = request.email
    
    db.commit()
    db.refresh(db_user)
    
    print(f"API: Updated profile for user {user['uid']}")
    
    return UserProfileResponse(
        id=db_user.id,
        name=db_user.name,
        bio=db_user.bio,
        profile_image_url=db_user.profile_image_url,
        preferences=db_user.preferences,  # Already a list of strings
        first_name=db_user.first_name,
        last_name=db_user.last_name,
        phone_number=db_user.phone_number,
        email=db_user.email,
        created_at=db_user.created_at
    )


@router.delete("/account")
async def delete_account(
    user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Permanently delete the current user's account and associated server-side data.

    This will:
    - Delete the user's profile row (`UserDB`)
    - Delete all saved locations for the user
    - Delete all AI discoveries for the user
    - Remove the user from all rooms' member lists
    - Reassign room ownership where possible; delete empty rooms the user owned
    - Delete chat sessions for any rooms that are deleted

    NOTE: Messages the user previously sent in rooms are preserved so that
    conversations remain readable for other participants.
    """
    user_id = user["uid"]

    # Delete saved locations and AI discoveries
    deleted_saved = (
        db.query(SavedLocationDB)
        .filter(SavedLocationDB.user_id == user_id)
        .delete(synchronize_session=False)
    )
    deleted_discoveries = (
        db.query(AIDiscoveryDB)
        .filter(AIDiscoveryDB.user_id == user_id)
        .delete(synchronize_session=False)
    )

    # Clean up room memberships and ownership
    rooms = db.query(RoomDB).all()
    rooms_updated = 0
    rooms_deleted = 0

    # Constant AI user id used elsewhere in the app
    AI_USER_ID = "00000000-0000-0000-0000-000000000001"

    for room in rooms:
        changed = False

        # Remove user from members list
        members = room.members or []
        new_members = [m for m in members if m.get("id") != user_id]
        if len(new_members) != len(members):
            room.members = new_members
            changed = True

        # If the user owned this room, transfer ownership or delete the room
        if room.owner_id == user_id:
            # Find a new owner among remaining (non-AI) members
            new_owner_id = None
            for m in new_members:
                mid = m.get("id")
                if mid and mid != AI_USER_ID:
                    new_owner_id = mid
                    break

            if new_owner_id:
                room.owner_id = new_owner_id
                changed = True
            else:
                # No suitable new owner -> delete room and its chat session
                chat_session = (
                    db.query(ChatSessionDB)
                    .filter(ChatSessionDB.room_id == room.id)
                    .first()
                )
                if chat_session:
                    db.delete(chat_session)

                db.delete(room)
                rooms_deleted += 1
                continue

        if changed:
            rooms_updated += 1

    # Delete user profile row
    db_user = db.query(UserDB).filter(UserDB.id == user_id).first()
    if db_user:
        db.delete(db_user)

    db.commit()

    # Best-effort cleanup of the Firestore user document (if it exists)
    try:
        from auth import db as firestore_db  # type: ignore

        firestore_db.collection("users").document(user_id).delete()
    except Exception as e:
        # Do not fail the request if Firestore cleanup fails
        print(f"Warning: failed to delete Firestore user document for {user_id}: {e}")

    return {
        "success": True,
        "deleted_saved": deleted_saved,
        "deleted_discoveries": deleted_discoveries,
        "rooms_updated": rooms_updated,
        "rooms_deleted": rooms_deleted,
    }

