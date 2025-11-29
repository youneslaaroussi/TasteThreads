import os
import json
import redis.asyncio as redis
from typing import Dict, Set
from fastapi import WebSocket
import asyncio

# Redis connection from environment
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")

class RedisConnectionManager:
    def __init__(self):
        # Local tracking of WebSocket connections per room
        self.active_connections: Dict[str, Set[WebSocket]] = {}
        self.redis_client = None
        self.pubsub = None
        self.listener_task = None
        
    async def initialize(self):
        """Initialize Redis connection and pub/sub"""
        print(f"Redis: Attempting to connect to {REDIS_URL}")
        try:
            self.redis_client = await redis.from_url(
                REDIS_URL,
                encoding="utf-8",
                decode_responses=True
            )
            self.pubsub = self.redis_client.pubsub()
            # Test the connection
            await self.redis_client.ping()
            print(f"Redis: Connected successfully to {REDIS_URL}")
        except Exception as e:
            print(f"Redis: WARNING - Connection failed: {e}")
            print(f"Redis: REDIS_URL was: {REDIS_URL}")
            print("Redis: WebSocket will work locally but not across multiple instances")
            self.redis_client = None
            self.pubsub = None
    
    async def connect(self, websocket: WebSocket, room_id: str):
        """Connect a WebSocket to a room"""
        await websocket.accept()
        print(f"WebSocket: Accepting new connection for room {room_id}")
        if room_id not in self.active_connections:
            self.active_connections[room_id] = set()
            print(f"WebSocket: Created new room entry for {room_id}")
            # Subscribe to Redis channel for this room
            if self.pubsub:
                await self.pubsub.subscribe(f"room:{room_id}")
                # Start listener if not already running
                if not self.listener_task:
                    self.listener_task = asyncio.create_task(self._listen_to_redis())
        
        self.active_connections[room_id].add(websocket)
        print(f"WebSocket: Client connected to room {room_id}. Total local connections: {len(self.active_connections[room_id])}")
        print(f"WebSocket: All rooms with connections: {list(self.active_connections.keys())}")
    
    def disconnect(self, websocket: WebSocket, room_id: str):
        """Disconnect a WebSocket from a room"""
        if room_id in self.active_connections:
            self.active_connections[room_id].discard(websocket)
            if not self.active_connections[room_id]:
                del self.active_connections[room_id]
                # Unsubscribe from Redis channel
                if self.pubsub:
                    asyncio.create_task(self.pubsub.unsubscribe(f"room:{room_id}"))
        print(f"WebSocket: Client disconnected from room {room_id}")
    
    async def broadcast_to_room(self, room_id: str, message: dict):
        """
        Broadcast a message to all clients in a room.
        Uses Redis pub/sub to reach clients across multiple server instances.
        """
        message_str = json.dumps(message)
        
        # Publish to Redis so all server instances receive it
        if self.redis_client:
            try:
                await self.redis_client.publish(f"room:{room_id}", message_str)
            except Exception as e:
                print(f"Redis publish error: {e}")
                # Fallback to local broadcast only
                await self._broadcast_locally(room_id, message)
        else:
            # No Redis, just broadcast locally
            await self._broadcast_locally(room_id, message)
    
    async def _broadcast_locally(self, room_id: str, message: dict):
        """Broadcast message to locally connected clients only"""
        print(f"WebSocket: Broadcasting locally to room {room_id}")
        if room_id in self.active_connections:
            connections = self.active_connections[room_id]
            print(f"WebSocket: Found {len(connections)} connections in room {room_id}")
            disconnected = set()
            for i, connection in enumerate(connections):
                try:
                    print(f"WebSocket: Sending to connection {i+1}/{len(connections)}")
                    await connection.send_json(message)
                    print(f"WebSocket: Successfully sent to connection {i+1}")
                except Exception as e:
                    print(f"WebSocket: Error sending to client {i+1}: {e}")
                    disconnected.add(connection)
            
            # Clean up disconnected clients
            for conn in disconnected:
                self.active_connections[room_id].discard(conn)
                print(f"WebSocket: Removed disconnected client from room {room_id}")
        else:
            print(f"WebSocket: No connections found for room {room_id}")
    
    async def _listen_to_redis(self):
        """
        Background task that listens to Redis pub/sub messages
        and broadcasts them to locally connected WebSocket clients
        """
        if not self.pubsub:
            return
        
        print("Redis listener task started")
        try:
            async for message in self.pubsub.listen():
                if message["type"] == "message":
                    # Extract room_id from channel name (format: "room:room_id")
                    channel = message["channel"]
                    if channel.startswith("room:"):
                        room_id = channel[5:]  # Remove "room:" prefix
                        try:
                            data = json.loads(message["data"])
                            await self._broadcast_locally(room_id, data)
                        except json.JSONDecodeError as e:
                            print(f"Redis: Invalid JSON received: {e}")
        except Exception as e:
            print(f"Redis listener error: {e}")
            self.listener_task = None
    
    async def close(self):
        """Close Redis connections"""
        if self.listener_task:
            self.listener_task.cancel()
        if self.pubsub:
            await self.pubsub.close()
        if self.redis_client:
            await self.redis_client.close()

# Global instance
manager = None

async def get_redis_manager() -> RedisConnectionManager:
    """Get or create the Redis connection manager"""
    global manager
    if manager is None:
        manager = RedisConnectionManager()
        await manager.initialize()
    return manager

def get_connection_manager():
    """Synchronous getter for backwards compatibility"""
    return manager

