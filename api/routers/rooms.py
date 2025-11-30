from fastapi import APIRouter, HTTPException, Body, Depends
from typing import List, Optional, Dict, Callable, Awaitable, Any
from datetime import datetime
from sqlalchemy.orm import Session
import uuid
import auth
from auth import get_current_user, get_optional_user, write_message_to_firestore, update_typing_status
from database import get_db, RoomDB, UserDB, ChatSessionDB
from models.room_models import (
    User,
    Message,
    Room,
    CreateRoomRequest,
    JoinRoomRequest,
    SendMessageRequest,
)
from routers.orchestrator import run_orchestrator_chat

router = APIRouter()

# AI User ID (consistent across the app)
AI_USER_ID = "00000000-0000-0000-0000-000000000001"

# --- Helper Functions ---

def db_room_to_pydantic(db_room: RoomDB, db: Session = None) -> Room:
    """Convert database Room to Pydantic Room model"""
    # Convert message timestamps from ISO strings to datetime objects
    messages = []
    for msg in db_room.messages:
        try:
            msg_data = dict(msg)  # Create a proper dict copy
            if isinstance(msg_data.get('timestamp'), str):
                # Parse ISO timestamp string to datetime
                timestamp_str = msg_data['timestamp'].rstrip('Z')
                msg_data['timestamp'] = datetime.fromisoformat(timestamp_str)
            messages.append(Message(**msg_data))
        except Exception as e:
            print(f"Error parsing message in room {db_room.id}: {e}")
            # Skip malformed messages instead of failing entirely
            continue
    
    # Refresh member info from database to get up-to-date names and profile images
    members = []
    for member in db_room.members:
        member_data = dict(member)
        if db and member_data.get('id') != AI_USER_ID:
            # Look up current user info from database
            db_user = db.query(UserDB).filter(UserDB.id == member_data['id']).first()
            if db_user:
                # Update name if the stored one is generic or outdated
                if db_user.name and db_user.name != "User":
                    member_data['name'] = db_user.name
                # Update profile image URL
                if db_user.profile_image_url:
                    member_data['profile_image_url'] = db_user.profile_image_url
        members.append(User(**member_data))
    
    return Room(
        id=db_room.id,
        name=db_room.name,
        members=members,
        messages=messages,
        itinerary=db_room.itinerary,
        is_public=db_room.is_public,
        join_code=db_room.join_code,
        owner_id=db_room.owner_id
    )

def ensure_user_exists(db: Session, user_id: str, user_name: str, avatar_url: Optional[str] = None):
    """Ensure user exists in database and return their profile info"""
    user = db.query(UserDB).filter(UserDB.id == user_id).first()
    if not user:
        user = UserDB(id=user_id, name=user_name, avatar_url=avatar_url)
        db.add(user)
        db.commit()
    return user

def get_user_profile_image(db: Session, user_id: str) -> Optional[str]:
    """Get user's profile image URL from database"""
    user = db.query(UserDB).filter(UserDB.id == user_id).first()
    return user.profile_image_url if user else None

def get_user_display_name(db: Session, user_id: str, fallback: str = "User") -> str:
    """Get user's display name from database, with fallback"""
    user = db.query(UserDB).filter(UserDB.id == user_id).first()
    if user and user.name and user.name != "User":
        return user.name
    return fallback

# --- Endpoints ---

@router.get("/debug/connections")
async def debug_connections():
    """Debug endpoint to check WebSocket connections"""
    from redis_manager import get_connection_manager
    manager = get_connection_manager()
    if not manager:
        return {"error": "No WebSocket manager", "manager_exists": False}
    
    connections = {}
    for room_id, sockets in manager.active_connections.items():
        connections[room_id] = len(sockets)
    
    return {
        "manager_exists": True,
        "redis_connected": manager.redis_client is not None,
        "rooms": connections,
        "total_connections": sum(connections.values())
    }

@router.get("/public", response_model=List[Room])
async def get_public_rooms(user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Get all public rooms. Requires authentication.
    """
    print(f"API: get_public_rooms called by {user.get('uid')}")
    public_rooms = db.query(RoomDB).filter(RoomDB.is_public == True).all()
    print(f"API: Returning {len(public_rooms)} public rooms")
    return [db_room_to_pydantic(room, db) for room in public_rooms]

@router.get("/mine", response_model=List[Room])
async def get_my_rooms(user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Get rooms for the authenticated user.
    """
    user_id = user['uid']
    print(f"API: get_my_rooms called for user_id={user_id}")
    
    # Query rooms where user is a member
    all_rooms = db.query(RoomDB).all()
    my_rooms = [room for room in all_rooms if any(m['id'] == user_id for m in room.members)]
    
    print(f"API: Returning {len(my_rooms)} rooms for user {user_id}")
    return [db_room_to_pydantic(room, db) for room in my_rooms]

@router.get("/", response_model=List[Room])
async def get_rooms(user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Get all rooms the user is a member of.
    """
    user_id = user['uid']
    print(f"API: get_rooms called by user_id={user_id}")
    
    all_rooms = db.query(RoomDB).all()
    filtered_rooms = [room for room in all_rooms if any(m['id'] == user_id for m in room.members)]
    
    print(f"API: Returning {len(filtered_rooms)} rooms for user {user_id}")
    return [db_room_to_pydantic(room, db) for room in filtered_rooms]

@router.post("/", response_model=Room)
async def create_room(request: CreateRoomRequest, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Create a new room. Requires authentication.
    """
    owner_id = user['uid']
    fallback_name = user.get('name', user.get('email', 'User'))
    
    print(f"API: create_room called with name='{request.name}', owner_id='{owner_id}'")
    
    # Ensure owner exists in database
    ensure_user_exists(db, owner_id, fallback_name)
    
    # Get owner's actual display name from profile (not Firebase token)
    owner_name = get_user_display_name(db, owner_id, fallback_name)
    
    # Get owner's profile image
    owner_profile_image = get_user_profile_image(db, owner_id)
    
    room_id = str(uuid.uuid4())
    join_code = str(uuid.uuid4())[:6].upper()
    
    # Create member objects
    owner = User(id=owner_id, name=owner_name, profile_image_url=owner_profile_image, is_current_user=True)
    ai_user = User(id=AI_USER_ID, name="Tess (AI)", is_current_user=False)
    
    # Create system message
    system_msg = Message(
        id=str(uuid.uuid4()),
        sender_id=AI_USER_ID,
        content="Tess joined the chat",
        timestamp=datetime.utcnow().replace(microsecond=0),
        type="system"
    )
    
    # Create room in database
    new_room = RoomDB(
        id=room_id,
        name=request.name,
        members=[owner.model_dump(), ai_user.model_dump()],
        messages=[system_msg.model_dump(mode='json')],
        itinerary=[],
        is_public=request.is_public,
        join_code=join_code,
        owner_id=owner_id
    )
    
    db.add(new_room)
    db.commit()
    db.refresh(new_room)
    
    # Write initial system message to Firestore
    write_message_to_firestore(room_id, {
        "id": system_msg.id,
        "sender_id": system_msg.sender_id,
        "content": system_msg.content,
        "timestamp": system_msg.timestamp,
        "type": "system",
        "businesses": None
    })
    
    print(f"API: Created room {room_id} with join_code {join_code}")
    return db_room_to_pydantic(new_room, db)

@router.post("/join", response_model=Room)
async def join_room(request: JoinRoomRequest, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Join a room by code. Requires authentication.
    """
    user_id = user['uid']
    fallback_name = user.get('name', user.get('email', 'User'))
    
    print(f"API: join_room called with code='{request.code}', user_id='{user_id}'")
    
    # Ensure user exists in database
    ensure_user_exists(db, user_id, fallback_name)
    
    # Get user's actual display name from profile
    user_name = get_user_display_name(db, user_id, fallback_name)
    
    room = db.query(RoomDB).filter(RoomDB.join_code == request.code).first()
    if not room:
        print("API: Room not found or invalid code")
        raise HTTPException(status_code=404, detail="Room not found or invalid code")
    
    # Check if user is already a member
    is_member = any(m['id'] == user_id for m in room.members)
    
    if not is_member:
        # Get user's profile image
        user_profile_image = get_user_profile_image(db, user_id)
        
        # Add user to members
        user_obj = User(id=user_id, name=user_name, profile_image_url=user_profile_image, is_current_user=True)
        room.members.append(user_obj.model_dump())
        
        # Add join message
        SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000"
        join_msg = Message(
            id=str(uuid.uuid4()),
            sender_id=SYSTEM_USER_ID,
            content=f"{user_name} joined the chat",
            timestamp=datetime.utcnow().replace(microsecond=0),
            type="system"
        )
        room.messages.append(join_msg.model_dump(mode='json'))
        
        db.commit()
        db.refresh(room)
        
        # Write system message to Firestore
        write_message_to_firestore(room.id, {
            "id": join_msg.id,
            "sender_id": join_msg.sender_id,
            "content": join_msg.content,
            "timestamp": join_msg.timestamp,
            "type": "system",
            "businesses": None
        })
        
        print(f"API: Added user {user_id} to room {room.id}")
    else:
        print(f"API: User {user_id} already in room {room.id}")
    
    return db_room_to_pydantic(room, db)

@router.get("/{room_id}", response_model=Room)
async def get_room(room_id: str, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    room_id = room_id.lower()
    room = db.query(RoomDB).filter(RoomDB.id == room_id).first()
    
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    # Check membership
    user_id = user['uid']
    is_member = any(m['id'] == user_id for m in room.members)
    
    if not room.is_public and not is_member:
        raise HTTPException(status_code=403, detail="Not a member of this room")
    
    return db_room_to_pydantic(room, db)

@router.delete("/{room_id}")
async def delete_room(room_id: str, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Delete a room. Only the room owner can delete a room.
    """
    room_id = room_id.lower()
    user_id = user['uid']
    
    print(f"API: delete_room called for room_id={room_id} by user_id={user_id}")
    
    room = db.query(RoomDB).filter(RoomDB.id == room_id).first()
    
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    # Check if user is the owner
    if room.owner_id != user_id:
        raise HTTPException(status_code=403, detail="Only the room owner can delete this room")
    
    # Delete associated chat session if exists
    chat_session = db.query(ChatSessionDB).filter(ChatSessionDB.room_id == room_id).first()
    if chat_session:
        db.delete(chat_session)
    
    # Delete the room
    db.delete(room)
    db.commit()
    
    print(f"API: Deleted room {room_id}")
    return {"message": "Room deleted successfully", "room_id": room_id}

@router.post("/{room_id}/leave")
async def leave_room(room_id: str, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Leave a room. If you're the owner, you must delete the room instead.
    """
    room_id = room_id.lower()
    user_id = user['uid']
    
    print(f"API: leave_room called for room_id={room_id} by user_id={user_id}")
    
    room = db.query(RoomDB).filter(RoomDB.id == room_id).first()
    
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    # Check if user is a member
    is_member = any(m['id'] == user_id for m in room.members)
    if not is_member:
        raise HTTPException(status_code=403, detail="You are not a member of this room")
    
    # If owner, they should delete instead
    if room.owner_id == user_id:
        raise HTTPException(status_code=400, detail="Room owner cannot leave. Delete the room instead.")
    
    # Get user name BEFORE removing from members
    user_name = next((m['name'] for m in room.members if m['id'] == user_id), "User")
    
    # Remove user from members
    room.members = [m for m in room.members if m['id'] != user_id]
    
    # Add leave message
    SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000"
    leave_msg = Message(
        id=str(uuid.uuid4()),
        sender_id=SYSTEM_USER_ID,
        content=f"{user_name} left the chat",
        timestamp=datetime.utcnow().replace(microsecond=0),
        type="system"
    )
    room.messages.append(leave_msg.model_dump(mode='json'))
    
    db.commit()
    
    # Write system message to Firestore
    write_message_to_firestore(room_id, {
        "id": leave_msg.id,
        "sender_id": leave_msg.sender_id,
        "content": leave_msg.content,
        "timestamp": leave_msg.timestamp,
        "type": "system",
        "businesses": None
    })
    
    print(f"API: User {user_id} left room {room_id}")
    return {"message": "Left room successfully", "room_id": room_id}

@router.post("/{room_id}/messages", response_model=Message)
async def send_message(room_id: str, request: SendMessageRequest, user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    room_id = room_id.lower()
    room = db.query(RoomDB).filter(RoomDB.id == room_id).first()
    
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    sender_id = user['uid']
    fallback_name = user.get('name', user.get('email', 'User'))
    
    # Ensure user exists and get their actual display name from profile
    ensure_user_exists(db, sender_id, fallback_name)
    sender_name = get_user_display_name(db, sender_id, fallback_name)
    
    print(f"API: send_message called - room_id={room_id}, sender_id={sender_id}, is_public={room.is_public}")
    
    # Check membership
    is_member = any(m['id'] == sender_id for m in room.members)
    print(f"API: User {sender_id} is_member={is_member}, room has {len(room.members)} members")
    
    # Auto-add user to public rooms if they're not a member
    if not is_member and room.is_public:
        print(f"API: Auto-adding user {sender_id} to public room {room_id}")
        # Get user's profile image
        sender_profile_image = get_user_profile_image(db, sender_id)
        user_obj = User(id=sender_id, name=sender_name, profile_image_url=sender_profile_image, is_current_user=True)
        room.members.append(user_obj.model_dump())
        
        # Add join message
        SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000"
        join_msg = Message(
            id=str(uuid.uuid4()),
            sender_id=SYSTEM_USER_ID,
            content=f"{sender_name} joined the chat",
            timestamp=datetime.utcnow().replace(microsecond=0),
            type="system"
        )
        room.messages.append(join_msg.model_dump(mode='json'))
        db.commit()
        
        # Write system message to Firestore
        write_message_to_firestore(room_id, {
            "id": join_msg.id,
            "sender_id": join_msg.sender_id,
            "content": join_msg.content,
            "timestamp": join_msg.timestamp,
            "type": "system",
            "businesses": None
        })
        
        is_member = True
    
    if not is_member:
        raise HTTPException(status_code=403, detail="Not a member of this room")
    
    # Create user message
    new_message = Message(
        id=str(uuid.uuid4()),
        sender_id=sender_id,
        content=request.content,
        timestamp=datetime.utcnow().replace(microsecond=0),
        type=request.type
    )
    
    # Add message to room
    room.messages.append(new_message.model_dump(mode='json'))
    db.commit()
    db.refresh(room)
    
    print(f"API: Message sent to room {room_id} by {sender_id}")
    
    # Write to Firestore for real-time sync
    write_message_to_firestore(room_id, {
        "id": new_message.id,
        "sender_id": new_message.sender_id,
        "content": new_message.content,
        "timestamp": new_message.timestamp,
        "type": new_message.type,
        "businesses": None
    })
    
    # Trigger AI if message mentions @Tess or if 5 consecutive user messages
    should_trigger_ai = False
    
    # Check for @mention - support @tess, @ai, @yelp
    ai_triggers = ['@tess', '@ai', '@yelp']
    if request.type == "text" and any(trigger in request.content.lower() for trigger in ai_triggers):
        should_trigger_ai = True
        print(f"API: AI triggered by @mention in room {room_id}")
    
    # Check for 5 consecutive non-AI messages
    if not should_trigger_ai and len(room.messages) >= 5:
        last_five = room.messages[-5:]
        if all(msg['sender_id'] != AI_USER_ID for msg in last_five):
            should_trigger_ai = True
            print(f"API: AI triggered by 5 consecutive user messages in room {room_id}")
    
    if should_trigger_ai:
        # Trigger AI response asynchronously with user context and user id
        import asyncio
        asyncio.create_task(
            trigger_ai_response(
                room_id,
                request.content,
                user_id=sender_id,
                user_context=request.user_context,
            )
        )
    
    return new_message

def _build_enriched_query(user_message: str, user_context: Optional[Dict[str, Any]]) -> str:
    """
    Build an enriched query that includes user preferences and context.
    
    Since Yelp API only accepts lat/lon in user_context, we inject other
    contextual information (taste profile, preferences) as a natural language
    prefix to help the AI provide personalized recommendations.
    """
    if not user_context:
        return user_message
    
    context_parts = []
    
    # Add user info
    user_info = user_context.get("user", {})
    if user_info.get("first_name"):
        context_parts.append(f"My name is {user_info['first_name']}.")
    
    # Add location context
    location = user_context.get("location", {})
    if location.get("city"):
        city_state = location.get("city")
        if location.get("state"):
            city_state += f", {location['state']}"
        context_parts.append(f"I'm in {city_state}.")
    
    # Add taste profile
    taste = user_context.get("taste_profile", {})
    if taste:
        if taste.get("preferred_categories"):
            categories = taste["preferred_categories"][:5]  # Top 5
            context_parts.append(f"I usually enjoy {', '.join(categories)} food.")
        
        if taste.get("preferred_price_range"):
            context_parts.append(f"I typically prefer {taste['preferred_price_range']} price range.")
        
        if taste.get("favorite_places"):
            places = taste["favorite_places"][:3]  # Top 3
            context_parts.append(f"Some of my favorite spots are {', '.join(places)}.")
    
    # Add time context
    prefs = user_context.get("preferences", {})
    if prefs.get("current_meal_time"):
        meal_time = prefs["current_meal_time"]
        if meal_time not in ["afternoon"]:  # Skip generic times
            context_parts.append(f"I'm looking for {meal_time} options.")
    
    # Build the enriched query
    if context_parts:
        context_prefix = " ".join(context_parts)
        # Clean up the user message (remove @mentions for cleaner query)
        clean_message = user_message
        for mention in ['@tess', '@ai', '@yelp', '@Tess', '@AI', '@Yelp']:
            clean_message = clean_message.replace(mention, '').strip()
        
        enriched = f"[Context: {context_prefix}] {clean_message}"
        print(f"API: Enriched query: {enriched[:200]}...")
        return enriched
    
    return user_message


async def trigger_ai_response(
    room_id: str,
    user_message: str,
    user_id: Optional[str] = None,
    callback: Optional[Callable[[str], Awaitable[None]]] = None,
    user_context: Optional[Dict[str, Any]] = None,
):
    """
    Trigger AI response, write to Firestore for real-time sync.
    This runs asynchronously so the user's message returns immediately.
    
    Args:
        room_id: The room to send the AI response to
        user_message: The user's message to respond to
        callback: Optional callback for WhatsApp integration
        user_context: Optional contextual data (location, preferences, taste profile, etc.)
    """
    # Create a new database session for this async task
    from database import SessionLocal
    db = SessionLocal()
    
    try:
        # Note: Typing indicator is now managed by the orchestrator with periodic refresh
        # to keep it alive during long-running tool calls
        
        # Get existing Yelp AI chat_id for this room (if any) so Tess can keep context
        chat_session = (
            db.query(ChatSessionDB).filter(ChatSessionDB.room_id == room_id).first()
        )
        chat_id = chat_session.chat_id if chat_session else None

        # Build enriched query with user context (taste profile, preferences, etc.)
        enriched_message = _build_enriched_query(user_message, user_context)
        
        # Call orchestrator agent (Pydantic AI) to decide how to use Yelp AI / reservations
        # The orchestrator handles typing indicator internally with periodic refresh
        orchestrator_result = await run_orchestrator_chat(
            db=db,
            user_id=user_id or "unknown",
            room_id=room_id,
            message=enriched_message,
            user_context=user_context,
            chat_id=chat_id,
        )

        # Store the (possibly new) Yelp chat_id for future messages
        if orchestrator_result.yelp_chat_id:
            if chat_session:
                chat_session.chat_id = orchestrator_result.yelp_chat_id
            else:
                chat_session = ChatSessionDB(
                    room_id=room_id, chat_id=orchestrator_result.yelp_chat_id
                )
                db.add(chat_session)
            db.commit()
            print(
                f"API: Stored chat_id {orchestrator_result.yelp_chat_id} for room {room_id}"
            )
        
        # Use businesses already normalized by the orchestrator (if any)
        businesses = [b.model_dump() for b in orchestrator_result.businesses]

        # Create AI message with businesses
        ai_message = Message(
            id=str(uuid.uuid4()),
            sender_id=AI_USER_ID,
            content=orchestrator_result.text,
            timestamp=datetime.utcnow().replace(microsecond=0),
            type="text",
            businesses=businesses if businesses else None,
        )
        
        # Add to room in database
        room = db.query(RoomDB).filter(RoomDB.id == room_id).first()
        if room:
            room.messages.append(ai_message.model_dump(mode='json'))
            db.commit()
        
        # Write AI message to Firestore for real-time sync
        write_message_to_firestore(room_id, {
            "id": ai_message.id,
            "sender_id": ai_message.sender_id,
            "content": ai_message.content,
            "timestamp": ai_message.timestamp,
            "type": ai_message.type,
            "businesses": businesses if businesses else None
        })
        
        print(f"API: AI responded in room {room_id} with {len(businesses)} businesses")

        # If a callback is provided, call it with the response text
        if callback:
            await callback(ai_message.content)
        
    except Exception as e:
        print(f"API: Error triggering AI response: {e}")
        import traceback
        traceback.print_exc()
        # Typing indicator cleanup is handled by orchestrator's finally block
    finally:
        # Close the database session
        db.close()
