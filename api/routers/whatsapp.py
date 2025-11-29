import os
import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from typing import List, Optional, Callable, Awaitable
from sqlalchemy.orm import Session
from database import get_db, UserDB, RoomDB
from routers.rooms import send_message as send_room_message, trigger_ai_response, CreateRoomRequest, SendMessageRequest
import uuid
import asyncio

router = APIRouter()

VERIFY_TOKEN = os.environ.get("WHATSAPP_VERIFY_TOKEN")
WHATSAPP_API_TOKEN = os.environ.get("WHATSAPP_API_TOKEN")
WHATSAPP_PHONE_NUMBER_ID = os.environ.get("WHATSAPP_PHONE_NUMBER_ID")

class WhatsAppValue(BaseModel):
    messaging_product: str
    metadata: dict
    contacts: List[dict]
    messages: List[dict]

class WhatsAppEntry(BaseModel):
    id: str
    changes: List[dict]

class WhatsAppRequest(BaseModel):
    object: str
    entry: List[WhatsAppEntry]

async def send_whatsapp_message(to: str, text: str):
    """Sends a message to a WhatsApp user."""
    if not all([WHATSAPP_API_TOKEN, WHATSAPP_PHONE_NUMBER_ID]):
        print("WhatsApp API credentials not set. Cannot send message.")
        return

    url = f"https://graph.facebook.com/v15.0/{WHATSAPP_PHONE_NUMBER_ID}/messages"
    headers = {
        "Authorization": f"Bearer {WHATSAPP_API_TOKEN}",
        "Content-Type": "application/json",
    }
    data = {
        "messaging_product": "whatsapp",
        "to": to,
        "text": {"body": text},
    }
    async with httpx.AsyncClient() as client:
        response = await client.post(url, headers=headers, json=data)
        if response.status_code != 200:
            print(f"Error sending WhatsApp message: {response.text}")

@router.get("")
async def verify_webhook(request: Request):
    """Verifies the webhook with Meta."""
    if request.query_params.get("hub.mode") == "subscribe" and request.query_params.get("hub.verify_token") == VERIFY_TOKEN:
        return Response(content=request.query_params.get("hub.challenge"), media_type="text/plain")
    raise HTTPException(status_code=403, detail="Forbidden")

@router.post("")
async def webhook(request: WhatsAppRequest, db: Session = Depends(get_db)):
    """Handles incoming WhatsApp messages."""
    for entry in request.entry:
        for change in entry.changes:
            value = change.get("value", {})
            if "messages" in value:
                for message in value.get("messages", []):
                    from_whatsapp_id = message.get("from")
                    msg_type = message.get("type")

                    user = db.query(UserDB).filter(UserDB.whatsapp_id == from_whatsapp_id).first()
                    if not user:
                        user_id = str(uuid.uuid4())
                        user = UserDB(id=user_id, name="WhatsApp User", whatsapp_id=from_whatsapp_id)
                        db.add(user)
                        db.commit()
                        db.refresh(user)

                    room = db.query(RoomDB).filter(RoomDB.owner_id == user.id).first()
                    if not room:
                        room_request = CreateRoomRequest(name=f"WhatsApp Chat", is_public=False)
                        mock_user = {"uid": user.id, "name": user.name}
                        from routers.rooms import create_room
                        new_room = await create_room(room_request, mock_user, db)
                        room = db.query(RoomDB).filter(RoomDB.id == new_room.id).first()

                    content = None
                    if msg_type == "text":
                        content = message.get("text", {}).get("body")
                    elif msg_type == "interactive":
                        interactive = message.get("interactive", {})
                        if interactive.get("type") == "button_reply":
                            content = interactive.get("button_reply", {}).get("title")
                    
                    if content and room:
                        # Use asyncio.create_task to run in the background
                        asyncio.create_task(handle_message(user, room.id, content, db))

    return Response(status_code=200)

async def handle_message(user: UserDB, room_id: str, content: str, db: Session):
    """Handles the message content and triggers AI response."""
    mock_user = {"uid": user.id}
    message_request = SendMessageRequest(content=content)
    
    await send_room_message(room_id, message_request, mock_user, db)
    
    # Define the callback
    async def response_callback(response_text: str):
        await send_whatsapp_message(user.whatsapp_id, response_text)

    await trigger_ai_response(room_id, content, response_callback)

