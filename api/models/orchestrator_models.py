from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field
from sqlalchemy.orm import Session


class OrchestratorBusiness(BaseModel):
    """Simplified business payload that matches the iOS `YelpBusiness` decoder shape."""

    id: str
    name: str
    image_url: Optional[str] = None
    url: Optional[str] = None
    rating: Optional[float] = None
    review_count: Optional[int] = None
    price: Optional[str] = None
    categories: Optional[List[Dict[str, Any]]] = None
    location: Optional[Dict[str, Any]] = None
    coordinates: Optional[Dict[str, Any]] = None
    phone: Optional[str] = None
    display_phone: Optional[str] = None


class ReservationTimeSlot(BaseModel):
    """A single available reservation time slot."""

    date: str  # YYYY-MM-DD
    time: str  # HH:MM
    credit_card_required: bool = False


class ReservationCoversRange(BaseModel):
    """Party size range supported by the restaurant."""

    min_party_size: int = 1
    max_party_size: int = 10


class ReservationAction(BaseModel):
    """
    Structured reservation action that triggers special UI in the iOS app.

    Types:
    - "reservation_prompt": Show available times for user to select
    - "reservation_confirmed": Show confirmation card with details
    """

    type: str = Field(description="Action type: 'reservation_prompt' or 'reservation_confirmed'")
    business_id: str
    business_name: str
    business_image_url: Optional[str] = None
    business_address: Optional[str] = None
    business_phone: Optional[str] = None
    business_rating: Optional[float] = None
    business_url: Optional[str] = None

    # For reservation_prompt
    available_times: Optional[List[ReservationTimeSlot]] = None
    covers_range: Optional[ReservationCoversRange] = None
    requested_date: Optional[str] = None  # Original date user asked for
    requested_time: Optional[str] = None  # Original time user asked for
    requested_covers: Optional[int] = None  # Party size

    # For reservation_confirmed
    hold_id: Optional[str] = None
    reservation_id: Optional[str] = None
    confirmation_url: Optional[str] = None
    confirmed_date: Optional[str] = None
    confirmed_time: Optional[str] = None
    confirmed_covers: Optional[int] = None


class OrchestratorChatOutput(BaseModel):
    """
    Structured response returned to the backend caller.

    This is what `rooms.trigger_ai_response` consumes to create the Tess message.
    """

    text: str = Field(description="Natural-language reply Tess should send into the room.")
    businesses: List[OrchestratorBusiness] = Field(
        default_factory=list,
        description="Optional businesses to attach to the Tess message.",
    )
    yelp_chat_id: Optional[str] = Field(
        default=None,
        description="Yelp AI chat_id to persist for conversation continuity.",
    )
    actions: List[ReservationAction] = Field(
        default_factory=list,
        description="Reservation actions that trigger special UI in the app.",
    )


MAX_TOOL_ERRORS = 10  # Max consecutive tool errors before stopping


@dataclass
class OrchestratorDeps:
    """Per-run dependencies for the chat agent."""

    user_id: str
    room_id: Optional[str]
    db: Session
    user_context: Dict[str, Any]
    chat_id: Optional[str]
    last_yelp_response: Optional[Dict[str, Any]] = None
    tool_error_count: int = 0  # Track consecutive tool errors



