from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from typing import Optional
import json
from firebase_admin import auth
from redis_manager import get_redis_manager, get_connection_manager

router = APIRouter()

@router.websocket("/ws/{room_id}")
async def websocket_endpoint(websocket: WebSocket, room_id: str, token: Optional[str] = Query(None)):
    """
    WebSocket endpoint for real-time room communication.
    Requires 'token' query parameter for authentication.
    Uses Redis for pub/sub across multiple server instances.
    """
    room_id = room_id.lower()
    
    # Authenticate
    user_id = None
    try:
        if token:
            decoded_token = auth.verify_id_token(token)
            user_id = decoded_token['uid']
            print(f"WebSocket: Authenticated user {user_id}")
        else:
            print("WebSocket: No token provided")
            await websocket.close(code=4001)
            return
    except Exception as e:
        print(f"WebSocket: Authentication failed: {e}")
        await websocket.close(code=4001)
        return

    # Get Redis manager
    manager = await get_redis_manager()
    await manager.connect(websocket, room_id)
    
    try:
        while True:
            # Receive message from client
            data = await websocket.receive_json()
            
            # Broadcast to all clients in the room (via Redis)
            await manager.broadcast_to_room(room_id, data)
            
    except WebSocketDisconnect:
        manager.disconnect(websocket, room_id)
    except Exception as e:
        print(f"WebSocket error: {e}")
        manager.disconnect(websocket, room_id)
