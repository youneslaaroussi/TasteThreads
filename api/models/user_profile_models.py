from datetime import datetime, timezone
from typing import List, Optional

from pydantic import BaseModel, field_serializer


class UserProfileResponse(BaseModel):
    id: str
    name: str
    bio: Optional[str] = None
    profile_image_url: Optional[str] = None
    preferences: Optional[List[str]] = None  # Simple list of preference strings for LLM context
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone_number: Optional[str] = None
    email: Optional[str] = None
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True

    @field_serializer("created_at")
    def serialize_datetime(self, value: datetime) -> Optional[str]:
        if value is None:
            return None
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.strftime("%Y-%m-%dT%H:%M:%SZ")


class UpdateProfileRequest(BaseModel):
    name: Optional[str] = None
    bio: Optional[str] = None
    profile_image_url: Optional[str] = None  # Base64 data URL or remote URL
    preferences: Optional[List[str]] = None  # Simple list of preference strings
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone_number: Optional[str] = None
    email: Optional[str] = None



