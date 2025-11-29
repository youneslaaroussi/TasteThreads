import os
import firebase_admin
from firebase_admin import auth, credentials, firestore
from fastapi import HTTPException, Security, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Optional

# Initialize Firebase Admin SDK
# Check if already initialized to avoid errors during reload
if not firebase_admin._apps:
    # Build Firebase credentials from individual environment variables
    firebase_config = {
        "type": os.getenv("FIREBASE_TYPE", "service_account"),
        "project_id": os.getenv("FIREBASE_PROJECT_ID"),
        "private_key_id": os.getenv("FIREBASE_PRIVATE_KEY_ID"),
        "private_key": os.getenv("FIREBASE_PRIVATE_KEY"),
        "client_email": os.getenv("FIREBASE_CLIENT_EMAIL"),
        "client_id": os.getenv("FIREBASE_CLIENT_ID"),
        "auth_uri": os.getenv("FIREBASE_AUTH_URI", "https://accounts.google.com/o/oauth2/auth"),
        "token_uri": os.getenv("FIREBASE_TOKEN_URI", "https://oauth2.googleapis.com/token"),
        "auth_provider_x509_cert_url": os.getenv("FIREBASE_AUTH_PROVIDER_CERT_URL", "https://www.googleapis.com/oauth2/v1/certs"),
        "client_x509_cert_url": os.getenv("FIREBASE_CLIENT_CERT_URL"),
    }
    
    # Check required fields
    required_fields = ["project_id", "private_key", "client_email"]
    missing_fields = [field for field in required_fields if not firebase_config.get(field)]
    
    if missing_fields:
        error_msg = f"Missing required Firebase environment variables: {', '.join([f'FIREBASE_{field.upper()}' for field in missing_fields])}"
        print(f"ERROR: {error_msg}")
        raise ValueError(error_msg)
    
    # Fix private key formatting (Railway might escape newlines)
    if firebase_config["private_key"]:
        firebase_config["private_key"] = firebase_config["private_key"].replace("\\n", "\n")
    
    try:
        cred = credentials.Certificate(firebase_config)
        firebase_admin.initialize_app(cred)
        print(f"Firebase initialized for project: {firebase_config['project_id']}")
    except Exception as e:
        print(f"ERROR: Failed to initialize Firebase: {e}")
        raise ValueError(f"Failed to initialize Firebase: {e}") 

# Initialize Firestore client
db = firestore.client()
print("Firestore client initialized")

def get_firestore():
    """Get Firestore client instance"""
    return db

def write_message_to_firestore(room_id: str, message_data: dict):
    """Write a message to Firestore for real-time sync"""
    try:
        doc_ref = db.collection("rooms").document(room_id).collection("messages").document(message_data["id"])
        doc_ref.set({
            "senderId": message_data["sender_id"],
            "content": message_data["content"],
            "timestamp": message_data["timestamp"],
            "type": message_data.get("type", "text"),
            "businesses": message_data.get("businesses")
        })
        print(f"Firestore: Message {message_data['id']} written to room {room_id}")
    except Exception as e:
        print(f"Firestore: Error writing message: {e}")

def update_typing_status(room_id: str, user_id: str, is_typing: bool, user_name: str = "User"):
    """Update typing status in Firestore"""
    try:
        doc_ref = db.collection("rooms").document(room_id).collection("typing").document(user_id)
        doc_ref.set({
            "isTyping": is_typing,
            "timestamp": firestore.SERVER_TIMESTAMP,
            "userName": user_name
        })
    except Exception as e:
        print(f"Firestore: Error updating typing status: {e}")

security = HTTPBearer()

async def get_current_user(credentials: HTTPAuthorizationCredentials = Security(security)) -> dict:
    """
    Verifies the Firebase ID token and returns the decoded token (user info).
    """
    token = credentials.credentials
    try:
        # Verify the token
        decoded_token = auth.verify_id_token(token)
        return decoded_token
    except Exception as e:
        print(f"Auth Error: {e}")
        raise HTTPException(
            status_code=401,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

async def get_optional_user(credentials: Optional[HTTPAuthorizationCredentials] = Security(security, use_cache=False)) -> Optional[dict]:
    """
    Verifies token if present, otherwise returns None.
    """
    if not credentials:
        return None
        
    try:
        token = credentials.credentials
        decoded_token = auth.verify_id_token(token)
        return decoded_token
    except:
        return None
