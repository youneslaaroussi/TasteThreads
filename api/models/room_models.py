from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel


class User(BaseModel):
    id: str
    name: str
    avatar_url: Optional[str] = None
    profile_image_url: Optional[str] = None  # User's profile picture
    is_current_user: bool = False  # Helper for frontend, backend ignores


class Message(BaseModel):
    model_config = {
        "json_encoders": {
            datetime: lambda v: v.isoformat() + "Z" if v.tzinfo is None else v.isoformat()
        }
    }

    id: str
    sender_id: str
    content: str
    timestamp: datetime
    type: str = "text"
    related_item_id: Optional[str] = None
    reactions: Dict[str, List[str]] = {}
    quick_replies: Optional[List[str]] = None
    map_coordinates: Optional[dict] = None
    businesses: Optional[List[dict]] = None
    actions: Optional[List[dict]] = None  # Reservation actions for special UI


class Room(BaseModel):
    model_config = {
        "json_encoders": {
            datetime: lambda v: v.isoformat() + "Z" if v.tzinfo is None else v.isoformat()
        }
    }

    id: str
    name: str
    members: List[User]
    messages: List[Message] = []
    itinerary: List[dict] = []
    is_public: bool
    join_code: str
    owner_id: str


class CreateRoomRequest(BaseModel):
    name: str
    is_public: bool


class JoinRoomRequest(BaseModel):
    code: str


class SendMessageRequest(BaseModel):
    content: str
    type: str = "text"
    user_context: Optional[Dict[str, Any]] = None  # Contextual data for AI (location, preferences, etc.)



