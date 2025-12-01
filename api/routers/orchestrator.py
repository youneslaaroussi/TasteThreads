import os
import logging
import asyncio
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

import httpx
import logfire
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from auth import get_current_user, update_typing_status
from database import ChatSessionDB, SavedLocationDB, AIDiscoveryDB, RoomDB, UserDB, get_db

from pydantic_ai import Agent, RunContext

from models.orchestrator_models import (
    MAX_TOOL_ERRORS,
    OrchestratorBusiness,
    ReservationAction,
    ReservationCoversRange,
    ReservationTimeSlot,
    OrchestratorChatOutput,
    OrchestratorDeps,
)

# ============================================
# Logging setup
# ============================================
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)
logger = logging.getLogger("orchestrator")

router = APIRouter()

OPENAI_MODEL = os.getenv("OPENAI_MODEL", "openai:gpt-4o-mini")
YELP_API_KEY = os.getenv("YELP_API_KEY")
AI_USER_ID = "00000000-0000-0000-0000-000000000001"

# Test mode for Yelp Reservations API (disabled by default)
# Enable with YELP_RESERVATIONS_TEST_MODE=true to use simulated reservation responses
YELP_RESERVATIONS_TEST_MODE = os.getenv("YELP_RESERVATIONS_TEST_MODE", "false").lower() == "true"

if not YELP_API_KEY:
    logger.warning("YELP_API_KEY not set. Yelp AI and Reservations tools will fail.")

if YELP_RESERVATIONS_TEST_MODE:
    logger.info("YELP_RESERVATIONS_TEST_MODE is ENABLED - using test reservation responses")

AI_USER_NAME = "Tess (AI)"


# --- Typing Indicator Helper ---

async def keep_typing_alive(room_id: str, user_id: str, stop_event: asyncio.Event):
    """
    Refresh typing status every 3 seconds to keep the indicator visible.
    The iOS client checks for a 5-second timeout, so refreshing every 3s ensures it stays active.
    """
    while not stop_event.is_set():
        try:
            update_typing_status(room_id, user_id, True, AI_USER_NAME)
            logfire.debug("Refreshed typing indicator", room_id=room_id)
        except Exception as e:
            logfire.error("Error refreshing typing status", error=str(e))
        await asyncio.sleep(3)


async def fetch_business_details(business_id: str) -> Optional[Dict[str, Any]]:
    """
    Fetch full business details from Yelp API to get photos/thumbnails.
    """
    if not YELP_API_KEY:
        return None
    
    url = f"https://api.yelp.com/v3/businesses/{business_id}"
    headers = {
        "Authorization": f"Bearer {YELP_API_KEY}",
        "Accept": "application/json",
    }
    
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                return resp.json()
    except Exception as e:
        logfire.error("Error fetching business details", business_id=business_id, error=str(e))
    
    return None


async def enrich_businesses_with_photos(businesses: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Fetch full details for businesses that are missing photos.
    Returns enriched business list with image_url populated.
    """
    if not businesses:
        logfire.debug("enrich_businesses_with_photos: No businesses to enrich")
        return businesses
    
    # TRACE: Log what each business has before enrichment
    for b in businesses:
        ctx_info = b.get("contextual_info") or {}
        photos = ctx_info.get("photos") or []
        logfire.info(
            "Business photo status BEFORE enrichment",
            business_id=b.get("id"),
            business_name=b.get("name"),
            has_image_url=bool(b.get("image_url")),
            image_url_value=b.get("image_url"),
            has_contextual_info=bool(ctx_info),
            contextual_info_keys=list(ctx_info.keys()) if ctx_info else [],
            has_photos_in_ctx=bool(photos),
            photos_count=len(photos) if photos else 0,
        )
    
    # Filter businesses that need photo fetching
    needs_photos = []
    for b in businesses:
        ctx_info = b.get("contextual_info") or {}
        photos = ctx_info.get("photos") or []
        if not photos and not b.get("image_url"):
            needs_photos.append(b["id"])
            logfire.info("Business needs photo fetching", business_id=b["id"], business_name=b.get("name"))
    
    if not needs_photos:
        logfire.info("All businesses already have photos - skipping enrichment", count=len(businesses))
        return businesses
    
    logfire.info("Fetching photos for businesses missing them", 
                 needs_count=len(needs_photos), 
                 total_count=len(businesses),
                 business_ids=needs_photos)
    
    # Fetch details in parallel (limit concurrency to 5)
    semaphore = asyncio.Semaphore(5)
    
    async def fetch_with_limit(bid: str):
        async with semaphore:
            logfire.debug("Fetching business details from Yelp API", business_id=bid)
            details = await fetch_business_details(bid)
            logfire.info(
                "Fetched business details",
                business_id=bid,
                success=details is not None,
                has_image_url=bool(details.get("image_url")) if details else False,
                image_url=details.get("image_url") if details else None,
                photos_count=len(details.get("photos", [])) if details else 0,
            )
            return bid, details
    
    tasks = [fetch_with_limit(bid) for bid in needs_photos]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    # Build a lookup of fetched details
    details_map: Dict[str, Dict[str, Any]] = {}
    for result in results:
        if isinstance(result, tuple):
            bid, details = result
            if details:
                details_map[bid] = details
        elif isinstance(result, Exception):
            logfire.error("Exception fetching business details", error=str(result))
    
    logfire.info("Built details map from Yelp API", 
                 fetched_count=len(details_map),
                 requested_count=len(needs_photos))
    
    # Enrich businesses with fetched photos
    for b in businesses:
        if b["id"] in details_map:
            details = details_map[b["id"]]
            # Get image_url from business details
            if details.get("image_url"):
                b["image_url"] = details["image_url"]
                logfire.info(
                    "Enriched business with image_url",
                    business_id=b["id"],
                    image_url=details["image_url"],
                )
            # Also get photos array if available
            if details.get("photos"):
                if "contextual_info" not in b or b["contextual_info"] is None:
                    b["contextual_info"] = {}
                b["contextual_info"]["photos"] = [
                    {"original_url": url} for url in details["photos"][:3]
                ]
                logfire.info(
                    "Enriched business with photos array",
                    business_id=b["id"],
                    photos_added=len(details["photos"][:3]),
                )
    
    logfire.info("Enriched businesses with photos", enriched_count=len(details_map))
    return businesses


# --- Shared helper ---

def _extract_yelp_user_context(full_context: Dict[str, Any]) -> Optional[Dict[str, float]]:
    """
    Extract just the latitude/longitude for Yelp AI user_context from our rich iOS context.
    Mirrors logic from the /yelp router but kept local to avoid circular imports.
    """
    location = full_context.get("location", {}) if full_context else {}
    yelp_ctx: Dict[str, float] = {}

    approx = location.get("approximate_area") or {}
    if "latitude" in approx:
        yelp_ctx["latitude"] = approx["latitude"]
    if "longitude" in approx:
        yelp_ctx["longitude"] = approx["longitude"]

    if "latitude" not in yelp_ctx and "latitude" in location:
        yelp_ctx["latitude"] = location["latitude"]
    if "longitude" not in yelp_ctx and "longitude" in location:
        yelp_ctx["longitude"] = location["longitude"]

    return yelp_ctx or None


def _get_system_instructions() -> str:
    """Build system instructions with current date/time context."""
    now = datetime.now()
    today_str = now.strftime("%Y-%m-%d")
    tomorrow_str = (now + timedelta(days=1)).strftime("%Y-%m-%d")
    day_of_week = now.strftime("%A")
    current_time = now.strftime("%H:%M")
    
    return (
        "You are Tess, an AI assistant that helps groups plan outings using Yelp.\n\n"
        
        "## CURRENT DATE & TIME CONTEXT (CRITICAL)\n"
        f"- **Today's date**: {today_str} ({day_of_week})\n"
        f"- **Tomorrow's date**: {tomorrow_str}\n"
        f"- **Current time**: {current_time}\n"
        "- ALWAYS use these dates when the user says 'today', 'tonight', 'tomorrow', etc.\n"
        "- NEVER use dates from 2023 or any past year. We are in 2025.\n"
        "- For reservations, dates MUST be today or in the future. Past dates will fail.\n\n"
        
        "## ERROR HANDLING (CRITICAL)\n"
        "- If a tool returns an error, DO NOT retry the same tool again. Respond to the user with what you know.\n"
        "- If you receive an error with 'stop_retrying': true, you MUST immediately respond to the user without calling any more tools.\n"
        "- If Yelp is unavailable, tell the user: 'I'm having trouble searching right now. Please try again in a moment.'\n"
        "- NEVER call the same tool more than once if it returns an error.\n\n"
        
        "## GENERAL INSTRUCTIONS\n"
        "- You ALWAYS think step-by-step using the tools you have.\n"
        "- The user_context contains:\n"
        "  - `user_name`: The user's display name\n"
        "  - `user_bio`: A short bio about the user\n"
        "  - `user_preferences`: A list of preference strings (e.g., 'vegetarian', 'loves Italian food', 'budget-friendly', 'outdoor seating')\n"
        "  - `location`: Their current location with coordinates\n"
        "  Use these to personalize your recommendations! If they prefer vegetarian, prioritize veggie-friendly places. If they love a cuisine, suggest it.\n"
        "- For any request that involves finding, recommending, or searching for places, call `yelp_ai_search` once. If it fails, respond gracefully.\n"
        "- You MUST NEVER fabricate or guess business objects. Do not invent JSON for businesses or their fields.\n"
        "- The backend will attach real Yelp businesses based on your tool calls; focus on the natural-language reply and high-level actions only.\n"
        "- Leave the `businesses` array EMPTY in your output. The backend handles it.\n"
        "- ALWAYS return a valid OrchestratorChatOutput as your final result. `text` is required; `businesses` should be empty.\n"
        "- If you call `yelp_ai_search`, set `yelp_chat_id` in your final output equal to the `chat_id` field from the last tool result.\n\n"
        
        "## RESERVATION FLOW\n"
        "When users want to book a table, follow this flow:\n\n"
        
        "1. **Detect booking intent**: Words like 'book', 'reserve', 'reservation', 'get a table', 'make a booking'.\n"
        "2. **Get availability**: Call `yelp_reservation_openings` with the business_id, date (YYYY-MM-DD), time (HH:MM), and covers.\n"
        f"   - If user says 'tonight', use today's date: {today_str}\n"
        f"   - If user says 'tomorrow', use: {tomorrow_str}\n"
        "   - Default time to 19:00 if not specified. Default covers to 2 if not specified.\n"
        "   - **IMPORTANT**: Date must be today or future. NEVER use past dates.\n"
        "   - The response may include a `business` object with image_url, location, phone, rating, etc. Use this data!\n"
        "3. **Return a reservation_prompt action**: After getting openings, include a ReservationAction in your `actions` array:\n"
        "   ```\n"
        "   {\n"
        "     'type': 'reservation_prompt',\n"
        "     'business_id': '<id>',\n"
        "     'business_name': '<name>',\n"
        "     'business_image_url': '<image_url from business object if available>',\n"
        "     'business_address': '<formatted address from business.location.display_address if available>',\n"
        "     'business_phone': '<display_phone from business object if available>',\n"
        "     'business_rating': <rating from business object if available>,\n"
        "     'business_url': '<url from business object if available>',\n"
        "     'available_times': [{'date': 'YYYY-MM-DD', 'time': 'HH:MM', 'credit_card_required': false}, ...],\n"
        "     'covers_range': {'min_party_size': 1, 'max_party_size': 8},\n"
        "     'requested_date': '<date user asked for>',\n"
        "     'requested_time': '<time user asked for>',\n"
        "     'requested_covers': <party size>\n"
        "   }\n"
        "   ```\n"
        "   The iOS app will render this as a booking card with time slots, business image, and contact info.\n\n"
        
        "4. **Write friendly text**: Your `text` should be conversational, e.g.:\n"
        "   'Great choice! I found some available times at [restaurant]. Pick a slot below or tap More Options for more dates.'\n\n"
        
        "5. **If openings fail or no availability**: Suggest trying a different time/date or checking Yelp directly.\n\n"
        
        "6. **Do NOT complete the booking yourself**: The iOS app handles hold creation and booking confirmation.\n"
        "   Just return the reservation_prompt action with available times.\n"
        
        "7. **For reservation_confirmed actions**: Include the same business details (image_url, address, phone, rating, url).\n"
    )


chat_agent = Agent[OrchestratorDeps, OrchestratorChatOutput](
    OPENAI_MODEL,
    deps_type=OrchestratorDeps,
    output_type=OrchestratorChatOutput,
    instructions=_get_system_instructions,
)


@chat_agent.tool
async def yelp_ai_search(
    ctx: RunContext[OrchestratorDeps],
    query: str,
) -> Dict[str, Any]:
    """
    Call Yelp AI chat for local business discovery.

    Args:
        query: Short English query describing what to look for, e.g. "fun birthday dinner in SF with cocktails".
    Returns:
        The raw JSON response from https://api.yelp.com/ai/chat/v2.
    """
    with logfire.span("yelp_ai_search_tool", query=query):
        logfire.info("Tool called: yelp_ai_search", query=query, error_count=ctx.deps.tool_error_count)
        logger.info("[yelp_ai_search] TOOL CALLED with query=%s (error_count=%d)", query, ctx.deps.tool_error_count)
        
        # Check if we've hit max errors - tell AI to stop retrying
        if ctx.deps.tool_error_count >= MAX_TOOL_ERRORS:
            logfire.warn("Max tool errors reached, stopping retries", error_count=ctx.deps.tool_error_count)
            return {
                "error": True,
                "error_code": "MAX_ERRORS_REACHED",
                "message": "I've encountered multiple issues with the search service. Please respond to the user with what you know, or suggest they try again later. DO NOT call this tool again.",
                "stop_retrying": True,
            }
        
        if not YELP_API_KEY:
            ctx.deps.tool_error_count += 1
            logfire.error("YELP_API_KEY not configured")
            logger.error("[yelp_ai_search] YELP_API_KEY is not configured!")
            return {"error": True, "error_code": "CONFIG_ERROR", "message": "Yelp API is not configured on the server. Please respond to the user without search results."}

        url = "https://api.yelp.com/ai/chat/v2"
        headers = {
            "Authorization": f"Bearer {YELP_API_KEY}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

        payload: Dict[str, Any] = {"query": query}
        if ctx.deps.chat_id:
            payload["chat_id"] = ctx.deps.chat_id

        yelp_ctx = _extract_yelp_user_context(ctx.deps.user_context)
        if yelp_ctx:
            payload["user_context"] = yelp_ctx

        logfire.debug("Sending payload to Yelp AI", payload=payload)
        logger.debug("[yelp_ai_search] Sending payload to Yelp AI: %s", payload)

        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                resp = await client.post(url, json=payload, headers=headers)
                logfire.info("Yelp AI HTTP response", status_code=resp.status_code)
                logger.debug("[yelp_ai_search] Yelp AI HTTP status: %s", resp.status_code)
                
                # Handle HTTP errors gracefully
                if resp.status_code >= 400:
                    ctx.deps.tool_error_count += 1
                    error_body = resp.text
                    logfire.error("Yelp AI API error", status_code=resp.status_code, body=error_body, error_count=ctx.deps.tool_error_count)
                    logger.error("[yelp_ai_search] Error %d: %s (error_count=%d)", resp.status_code, error_body, ctx.deps.tool_error_count)
                    
                    if resp.status_code >= 500:
                        return {"error": True, "error_code": "YELP_SERVER_ERROR", "message": "Yelp's service is temporarily unavailable. Do not retry - respond to the user and let them know you're having trouble searching right now."}
                    elif resp.status_code == 429:
                        return {"error": True, "error_code": "RATE_LIMITED", "message": "Too many requests to Yelp. Do not retry - respond to the user based on what you already know."}
                    elif resp.status_code == 401:
                        return {"error": True, "error_code": "AUTH_ERROR", "message": "Yelp API authentication failed. Do not retry - respond to the user without search results."}
                    else:
                        return {"error": True, "error_code": "API_ERROR", "message": f"Yelp returned an error ({resp.status_code}). Do not retry - respond to the user."}
                
                # Success! Reset error count
                ctx.deps.tool_error_count = 0
                
                data = resp.json()
                # Stash the last Yelp AI response so we can normalize businesses/chat_id
                # in Python instead of relying on the model to copy everything.
                ctx.deps.last_yelp_response = data

                entities = data.get("entities") or []
                biz_count = 0
                if entities:
                    biz_count = len((entities[0] or {}).get("businesses") or [])
                logfire.info("Yelp AI returned", chat_id=data.get("chat_id"), business_count=biz_count)
                logger.info(
                    "[yelp_ai_search] Yelp AI returned chat_id=%s, %d businesses",
                    data.get("chat_id"),
                    biz_count,
                )
                return data
        except httpx.TimeoutException:
            ctx.deps.tool_error_count += 1
            logfire.error("Yelp AI request timed out", query=query, error_count=ctx.deps.tool_error_count)
            logger.error("[yelp_ai_search] Request timed out for query: %s (error_count=%d)", query, ctx.deps.tool_error_count)
            return {"error": True, "error_code": "TIMEOUT", "message": "The search took too long. Do not retry - respond to the user and suggest they try again later."}
        except httpx.RequestError as e:
            ctx.deps.tool_error_count += 1
            logfire.error("Yelp AI request error", error=str(e), query=query, error_count=ctx.deps.tool_error_count)
            logger.error("[yelp_ai_search] Request error: %s (error_count=%d)", str(e), ctx.deps.tool_error_count)
            return {"error": True, "error_code": "NETWORK_ERROR", "message": "Unable to connect to Yelp. Do not retry - respond to the user and let them know you're having connection issues."}
        except Exception as e:
            ctx.deps.tool_error_count += 1
            logfire.error("Unexpected error in yelp_ai_search", error=str(e), query=query, error_count=ctx.deps.tool_error_count)
            logger.exception("[yelp_ai_search] Unexpected error: %s (error_count=%d)", str(e), ctx.deps.tool_error_count)
            return {"error": True, "error_code": "UNKNOWN_ERROR", "message": "An unexpected error occurred. Do not retry - respond to the user."}


async def _fetch_business_for_test(business_id: str) -> Optional[Dict[str, Any]]:
    """
    Fetch real business details from Yelp for test mode.
    Returns business data including image_url, name, location, etc.
    """
    if not YELP_API_KEY:
        return None
    
    url = f"https://api.yelp.com/v3/businesses/{business_id}"
    headers = {
        "Authorization": f"Bearer {YELP_API_KEY}",
        "Accept": "application/json",
    }
    
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                logfire.info("Fetched real business for test mode", 
                           business_id=business_id, 
                           name=data.get("name"),
                           has_image=bool(data.get("image_url")))
                return data
    except Exception as e:
        logfire.error("Error fetching business for test mode", business_id=business_id, error=str(e))
    
    return None


async def _generate_test_openings(business_id: str, date: str, time: str, covers: int) -> Dict[str, Any]:
    """
    Generate test reservation openings data with real business info.
    Used when YELP_RESERVATIONS_TEST_MODE is enabled.
    """
    # Fetch real business details
    business = await _fetch_business_for_test(business_id)
    
    # Parse the requested time to generate times around it
    try:
        hour, minute = map(int, time.split(":"))
    except:
        hour, minute = 19, 0
    
    # Generate available times: requested time plus 30 min before/after intervals
    times = []
    for offset in [-60, -30, 0, 30, 60, 90]:
        slot_hour = hour + (minute + offset) // 60
        slot_minute = (minute + offset) % 60
        if 11 <= slot_hour <= 22:  # Restaurant hours
            times.append({
                "date": date,
                "time": f"{slot_hour:02d}:{slot_minute:02d}",
                "credit_card_required": False,
            })
    
    result = {
        "reservation_times": times,
        "covers_range": {
            "min_party_size": 1,
            "max_party_size": 10,
        },
        "is_test_mode": True,
    }
    
    # Add real business data if available
    if business:
        result["business"] = {
            "id": business.get("id"),
            "name": business.get("name"),
            "image_url": business.get("image_url"),
            "url": business.get("url"),
            "phone": business.get("phone"),
            "display_phone": business.get("display_phone"),
            "rating": business.get("rating"),
            "review_count": business.get("review_count"),
            "price": business.get("price"),
            "location": business.get("location"),
            "coordinates": business.get("coordinates"),
            "categories": business.get("categories"),
            "photos": business.get("photos", [])[:3],
        }
    
    return result


async def _generate_test_hold(business_id: str, date: str, time: str, covers: int, unique_id: str) -> Dict[str, Any]:
    """
    Generate test hold data with real business info.
    Used when YELP_RESERVATIONS_TEST_MODE is enabled.
    """
    import uuid
    
    # Fetch real business details
    business = await _fetch_business_for_test(business_id)
    
    hold_id = f"TEST-{uuid.uuid4().hex[:16].upper()}"
    expires_at = (datetime.now() + timedelta(minutes=5)).timestamp()
    
    result = {
        "hold_id": hold_id,
        "expires_at": expires_at,
        "credit_card_hold": False,
        "cancellation_policy": "Free cancellation up to 1 hour before your reservation.",
        "reserve_url": f"https://www.yelp.com/reservations/{business_id}/checkout/{date}/{time.replace(':', '')}/{covers}?hold_id={hold_id}",
        "is_editable": True,
        "is_test_mode": True,
    }
    
    # Add real business data if available
    if business:
        result["business"] = {
            "id": business.get("id"),
            "name": business.get("name"),
            "image_url": business.get("image_url"),
            "url": business.get("url"),
            "phone": business.get("phone"),
            "display_phone": business.get("display_phone"),
            "rating": business.get("rating"),
            "location": business.get("location"),
            "coordinates": business.get("coordinates"),
            "photos": business.get("photos", [])[:3],
        }
    
    return result


async def _generate_test_reservation(business_id: str, hold_id: str, date: str, time: str, covers: int, first_name: str, notes: str = "") -> Dict[str, Any]:
    """
    Generate test reservation confirmation data with real business info.
    Used when YELP_RESERVATIONS_TEST_MODE is enabled.
    """
    import uuid
    
    # Fetch real business details
    business = await _fetch_business_for_test(business_id)
    
    reservation_id = f"TEST-RES-{uuid.uuid4().hex[:12].upper()}"
    
    result = {
        "reservation_id": reservation_id,
        "confirmation_url": f"https://www.yelp.com/reservations/{business_id}/confirmed/{reservation_id}",
        "notes": notes or f"Table for {covers} on {date} at {time}",
        "is_test_mode": True,
    }
    
    # Add real business data if available
    if business:
        result["business"] = {
            "id": business.get("id"),
            "name": business.get("name"),
            "image_url": business.get("image_url"),
            "url": business.get("url"),
            "phone": business.get("phone"),
            "display_phone": business.get("display_phone"),
            "rating": business.get("rating"),
            "location": business.get("location"),
            "coordinates": business.get("coordinates"),
            "photos": business.get("photos", [])[:3],
        }
    
    return result


@chat_agent.tool_plain
async def yelp_reservation_openings(
    business_id: str,
    date: str,
    time: str,
    covers: int = 2,
) -> Dict[str, Any]:
    """
    Look up reservation openings for a Yelp Reservations business.

    Args:
        business_id: Yelp business id or alias (must support Yelp Reservations).
        date: Reservation date in YYYY-MM-DD. MUST be today or a future date.
        time: Desired time in HH:MM (24h).
        covers: Party size from 1–10.
    Returns:
        Raw JSON from GET /v3/bookings/{business_id}/openings, or an error dict if the request fails.
    """
    with logfire.span("yelp_reservation_openings_tool", business_id=business_id, date=date, time=time, covers=covers, test_mode=YELP_RESERVATIONS_TEST_MODE):
        logfire.info("Tool called: yelp_reservation_openings", business_id=business_id, date=date, time=time, covers=covers, test_mode=YELP_RESERVATIONS_TEST_MODE)
        logger.info(
            "[yelp_reservation_openings] TOOL CALLED business_id=%s date=%s time=%s covers=%d test_mode=%s",
            business_id,
            date,
            time,
            covers,
            YELP_RESERVATIONS_TEST_MODE,
        )
        
        # Validate date is not in the past
        try:
            requested_date = datetime.strptime(date, "%Y-%m-%d").date()
            today = datetime.now().date()
            if requested_date < today:
                error_msg = f"Cannot book reservations for past dates. You requested {date} but today is {today.isoformat()}. Please use today's date or a future date."
                logfire.warn("Reservation date in past", requested=date, today=today.isoformat())
                logger.warning("[yelp_reservation_openings] Date %s is in the past (today=%s)", date, today.isoformat())
                return {"error": True, "error_code": "DATE_IN_PAST", "message": error_msg}
        except ValueError as e:
            error_msg = f"Invalid date format: {date}. Expected YYYY-MM-DD format."
            logfire.error("Invalid date format", date=date, error=str(e))
            return {"error": True, "error_code": "INVALID_DATE_FORMAT", "message": error_msg}
        
        # Return test data if test mode is enabled
        if YELP_RESERVATIONS_TEST_MODE:
            logfire.info("Using test mode for reservation openings", business_id=business_id)
            logger.info("[yelp_reservation_openings] TEST MODE - returning simulated openings")
            return await _generate_test_openings(business_id, date, time, covers)
        
        if not YELP_API_KEY:
            logfire.error("YELP_API_KEY not configured")
            logger.error("[yelp_reservation_openings] YELP_API_KEY is not configured!")
            return {"error": True, "error_code": "CONFIG_ERROR", "message": "Yelp API is not configured on the server."}

        url = f"https://api.yelp.com/v3/bookings/{business_id}/openings"
        params = {
            "covers": covers,
            "date": date,
            "time": time,
            "get_covers_range": True,
        }
        headers = {
            "Authorization": f"Bearer {YELP_API_KEY}",
            "Accept": "application/json",
        }

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(url, params=params, headers=headers)
            logfire.info("Yelp Reservations HTTP response", status_code=resp.status_code)
            logger.debug("[yelp_reservation_openings] HTTP status: %s", resp.status_code)
            
            # Handle errors gracefully instead of raising
            if resp.status_code >= 400:
                error_body = resp.text
                logfire.error("Yelp Reservations API error", status_code=resp.status_code, body=error_body)
                logger.error("[yelp_reservation_openings] Error %d: %s", resp.status_code, error_body)
                
                # Parse common Yelp error codes
                error_msg = f"Yelp returned an error ({resp.status_code})"
                try:
                    error_json = resp.json()
                    error_code = error_json.get("error", {}).get("code", "UNKNOWN")
                    error_description = error_json.get("error", {}).get("description", error_body)
                    error_msg = f"{error_code}: {error_description}"
                except Exception:
                    pass
                
                if resp.status_code == 404:
                    return {"error": True, "error_code": "BUSINESS_NOT_FOUND", "message": f"This restaurant ({business_id}) doesn't support Yelp Reservations or wasn't found."}
                elif resp.status_code == 400:
                    return {"error": True, "error_code": "INVALID_REQUEST", "message": f"Invalid reservation request: {error_msg}. Check the date, time, and party size."}
                else:
                    return {"error": True, "error_code": "API_ERROR", "message": error_msg}
            
            data = resp.json()
            reservation_count = len(data.get("reservation_times") or [])
            logfire.info("Yelp Reservations returned", reservation_times_count=reservation_count)
            logger.info("[yelp_reservation_openings] returned %d reservation_times entries", reservation_count)
            return data


class ReservationOpeningsRequest(BaseModel):
    business_id: str = Field(description="Yelp business id or alias that supports Yelp Reservations")
    date: str = Field(description="Reservation date in YYYY-MM-DD")
    time: str = Field(description="Desired time in HH:MM (24h)")
    covers: int = Field(default=2, ge=1, le=10, description="Party size from 1 to 10")


@router.get("/reservations/openings")
async def get_reservation_openings(
    business_id: str,
    date: str,
    time: str,
    covers: int = 2,
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Thin wrapper around Yelp Reservations openings endpoint.

    iOS can call this directly when a user taps "Check reservations" on a business.
    Returns the raw Yelp JSON so the client can render available dates and times.
    """
    try:
        data = await yelp_reservation_openings(
            business_id=business_id,
            date=date,
            time=time,
            covers=covers,
        )
        return data
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=str(e.response.text))
    except Exception as e:
        print(f"Reservations openings error: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch reservation openings")


# --- Reservation Hold Tool & Endpoint ---

@chat_agent.tool_plain
async def yelp_reservation_hold(
    business_id: str,
    date: str,
    time: str,
    covers: int,
    unique_id: str,
) -> Dict[str, Any]:
    """
    Create a temporary hold on a reservation slot (expires in ~5 minutes).
    
    Args:
        business_id: Yelp business id or alias.
        date: Reservation date in YYYY-MM-DD.
        time: Reservation time in HH:MM (24h).
        covers: Party size from 1-10.
        unique_id: Device/user unique identifier for Yelp API.
    Returns:
        Raw JSON from POST /v3/bookings/{business_id}/holds including hold_id and reserve_url.
    """
    with logfire.span("yelp_reservation_hold_tool", business_id=business_id, date=date, time=time, covers=covers, test_mode=YELP_RESERVATIONS_TEST_MODE):
        logfire.info("Tool called: yelp_reservation_hold", business_id=business_id, date=date, time=time, covers=covers, test_mode=YELP_RESERVATIONS_TEST_MODE)
        logger.info(
            "[yelp_reservation_hold] TOOL CALLED business_id=%s date=%s time=%s covers=%d test_mode=%s",
            business_id, date, time, covers, YELP_RESERVATIONS_TEST_MODE,
        )
        
        # Return test data if test mode is enabled
        if YELP_RESERVATIONS_TEST_MODE:
            logfire.info("Using test mode for reservation hold", business_id=business_id)
            logger.info("[yelp_reservation_hold] TEST MODE - returning simulated hold")
            return await _generate_test_hold(business_id, date, time, covers, unique_id)
        
        if not YELP_API_KEY:
            logfire.error("YELP_API_KEY not configured")
            return {"error": True, "error_code": "CONFIG_ERROR", "message": "Yelp API is not configured on the server."}

        url = f"https://api.yelp.com/v3/bookings/{business_id}/holds"
        headers = {
            "Authorization": f"Bearer {YELP_API_KEY}",
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        }
        
        data = {
            "date": date,
            "time": time,
            "covers": covers,
            "unique_id": unique_id,
        }

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(url, data=data, headers=headers)
                logfire.info("Yelp Hold HTTP response", status_code=resp.status_code)
                logger.debug("[yelp_reservation_hold] HTTP status: %s", resp.status_code)
                
                # Handle HTTP errors gracefully
                if resp.status_code >= 400:
                    error_body = resp.text
                    logfire.error("Yelp Hold API error", status_code=resp.status_code, body=error_body)
                    logger.error("[yelp_reservation_hold] Error %d: %s", resp.status_code, error_body)
                    
                    error_msg = f"Unable to hold this reservation slot"
                    try:
                        error_json = resp.json()
                        error_code = error_json.get("error", {}).get("code", "UNKNOWN")
                        error_description = error_json.get("error", {}).get("description", "")
                        if error_description:
                            error_msg = error_description
                    except Exception:
                        pass
                    
                    if resp.status_code == 404:
                        return {"error": True, "error_code": "BUSINESS_NOT_FOUND", "message": f"This restaurant doesn't support Yelp Reservations."}
                    elif resp.status_code >= 500:
                        return {"error": True, "error_code": "YELP_SERVER_ERROR", "message": "Yelp's reservation service is temporarily unavailable. Please try again."}
                    else:
                        return {"error": True, "error_code": "HOLD_FAILED", "message": error_msg}
                
                result = resp.json()
                logfire.info("Yelp Hold created", hold_id=result.get("hold_id"))
                logger.info("[yelp_reservation_hold] Created hold_id=%s", result.get("hold_id"))
                return result
        except httpx.TimeoutException:
            logfire.error("Yelp Hold request timed out", business_id=business_id)
            return {"error": True, "error_code": "TIMEOUT", "message": "The request timed out. Please try again."}
        except httpx.RequestError as e:
            logfire.error("Yelp Hold request error", error=str(e), business_id=business_id)
            return {"error": True, "error_code": "NETWORK_ERROR", "message": "Unable to connect to Yelp. Please check your connection."}
        except Exception as e:
            logfire.error("Unexpected error in yelp_reservation_hold", error=str(e), business_id=business_id)
            return {"error": True, "error_code": "UNKNOWN_ERROR", "message": "An unexpected error occurred. Please try again."}


class ReservationHoldRequest(BaseModel):
    business_id: str = Field(description="Yelp business id or alias")
    date: str = Field(description="Reservation date in YYYY-MM-DD")
    time: str = Field(description="Reservation time in HH:MM (24h)")
    covers: int = Field(default=2, ge=1, le=10, description="Party size from 1 to 10")
    unique_id: str = Field(description="Device/user unique identifier")


class HoldResponse(BaseModel):
    hold_id: str
    reserve_url: Optional[str] = None
    expiration: Optional[str] = None


@router.post("/reservations/hold", response_model=HoldResponse)
async def create_reservation_hold(
    request: ReservationHoldRequest,
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Create a temporary hold on a reservation slot.
    The hold expires in approximately 5 minutes.
    """
    try:
        data = await yelp_reservation_hold(
            business_id=request.business_id,
            date=request.date,
            time=request.time,
            covers=request.covers,
            unique_id=request.unique_id,
        )
        return HoldResponse(
            hold_id=data.get("hold_id", ""),
            reserve_url=data.get("reserve_url"),
            expiration=data.get("expiration"),
        )
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=str(e.response.text))
    except Exception as e:
        print(f"Reservation hold error: {e}")
        raise HTTPException(status_code=500, detail="Failed to create reservation hold")


# --- Reservation Booking Tool & Endpoint ---

@chat_agent.tool_plain
async def yelp_reservation_book(
    business_id: str,
    hold_id: str,
    date: str,
    time: str,
    covers: int,
    first_name: str,
    last_name: str,
    email: str,
    phone: str,
    unique_id: str,
    notes: str = "",
) -> Dict[str, Any]:
    """
    Complete a reservation booking using a hold_id.
    
    Args:
        business_id: Yelp business id or alias.
        hold_id: The hold_id from a previous hold request.
        date: Reservation date in YYYY-MM-DD (must match hold).
        time: Reservation time in HH:MM (must match hold).
        covers: Party size (must match hold).
        first_name: Guest's first name.
        last_name: Guest's last name.
        email: Guest's email address.
        phone: Guest's phone number.
        unique_id: Device/user unique identifier (must match hold).
        notes: Optional special requests or notes.
    Returns:
        Raw JSON from POST /v3/bookings/{business_id}/reservations including reservation_id.
    """
    with logfire.span("yelp_reservation_book_tool", business_id=business_id, hold_id=hold_id, test_mode=YELP_RESERVATIONS_TEST_MODE):
        logfire.info("Tool called: yelp_reservation_book", business_id=business_id, hold_id=hold_id, test_mode=YELP_RESERVATIONS_TEST_MODE)
        logger.info(
            "[yelp_reservation_book] TOOL CALLED business_id=%s hold_id=%s test_mode=%s",
            business_id, hold_id, YELP_RESERVATIONS_TEST_MODE,
        )
        
        # Return test data if test mode is enabled
        if YELP_RESERVATIONS_TEST_MODE:
            logfire.info("Using test mode for reservation booking", business_id=business_id, hold_id=hold_id)
            logger.info("[yelp_reservation_book] TEST MODE - returning simulated reservation")
            return await _generate_test_reservation(business_id, hold_id, date, time, covers, first_name, notes)
        
        if not YELP_API_KEY:
            logfire.error("YELP_API_KEY not configured")
            return {"error": True, "error_code": "CONFIG_ERROR", "message": "Yelp API is not configured on the server."}

        url = f"https://api.yelp.com/v3/bookings/{business_id}/reservations"
        headers = {
            "Authorization": f"Bearer {YELP_API_KEY}",
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        }
        
        data = {
            "date": date,
            "time": time,
            "covers": covers,
            "hold_id": hold_id,
            "unique_id": unique_id,
            "first_name": first_name,
            "last_name": last_name,
            "email": email,
            "phone": phone,
        }
        if notes:
            data["notes"] = notes

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(url, data=data, headers=headers)
                logfire.info("Yelp Reservation HTTP response", status_code=resp.status_code)
                logger.debug("[yelp_reservation_book] HTTP status: %s", resp.status_code)
                
                # Handle HTTP errors gracefully
                if resp.status_code >= 400:
                    error_body = resp.text
                    logfire.error("Yelp Reservation API error", status_code=resp.status_code, body=error_body)
                    logger.error("[yelp_reservation_book] Error %d: %s", resp.status_code, error_body)
                    
                    error_msg = "Unable to complete the reservation"
                    error_code = "BOOKING_FAILED"
                    try:
                        error_json = resp.json()
                        api_error_code = error_json.get("error", {}).get("code", "UNKNOWN")
                        error_description = error_json.get("error", {}).get("description", "")
                        if error_description:
                            error_msg = error_description
                        
                        # Map specific Yelp error codes to user-friendly messages
                        if "CREDIT_CARD_REQUIRED" in api_error_code:
                            return {"error": True, "error_code": "CREDIT_CARD_REQUIRED", "message": "This reservation requires a credit card. Please book directly on Yelp."}
                        elif "SLOT_NO_LONGER_AVAILABLE" in api_error_code:
                            return {"error": True, "error_code": "SLOT_UNAVAILABLE", "message": "This time slot is no longer available. Please try another time."}
                        elif "HOLD_NOT_FOUND" in api_error_code or "INVALID_HOLD_ID" in api_error_code:
                            return {"error": True, "error_code": "HOLD_EXPIRED", "message": "Your hold has expired. Please start over and select a new time."}
                    except Exception:
                        pass
                    
                    return {"error": True, "error_code": error_code, "message": error_msg}
                
                result = resp.json()
                logfire.info("Yelp Reservation created", reservation_id=result.get("reservation_id"))
                logger.info("[yelp_reservation_book] Created reservation_id=%s", result.get("reservation_id"))
                return result
        except httpx.TimeoutException:
            logfire.error("Yelp Reservation request timed out", business_id=business_id)
            return {"error": True, "error_code": "TIMEOUT", "message": "The request timed out. Please try again."}
        except httpx.RequestError as e:
            logfire.error("Yelp Reservation request error", error=str(e), business_id=business_id)
            return {"error": True, "error_code": "NETWORK_ERROR", "message": "Unable to connect to Yelp. Please check your connection."}
        except Exception as e:
            logfire.error("Unexpected error in yelp_reservation_book", error=str(e), business_id=business_id)
            return {"error": True, "error_code": "UNKNOWN_ERROR", "message": "An unexpected error occurred. Please try again."}


class ReservationBookRequest(BaseModel):
    business_id: str = Field(description="Yelp business id or alias")
    hold_id: str = Field(description="Hold ID from the hold endpoint")
    date: str = Field(description="Reservation date in YYYY-MM-DD")
    time: str = Field(description="Reservation time in HH:MM (24h)")
    covers: int = Field(default=2, ge=1, le=10, description="Party size from 1 to 10")
    first_name: str = Field(description="Guest's first name")
    last_name: str = Field(description="Guest's last name")
    email: str = Field(description="Guest's email address")
    phone: str = Field(description="Guest's phone number")
    unique_id: str = Field(description="Device/user unique identifier")
    notes: Optional[str] = Field(default="", description="Special requests or notes")


class ReservationResponse(BaseModel):
    reservation_id: str
    confirmation_url: Optional[str] = None
    notes: Optional[str] = None


@router.post("/reservations/book", response_model=ReservationResponse)
async def complete_reservation(
    request: ReservationBookRequest,
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Complete a reservation using a hold_id.
    Must be called within ~5 minutes of creating the hold.
    """
    try:
        data = await yelp_reservation_book(
            business_id=request.business_id,
            hold_id=request.hold_id,
            date=request.date,
            time=request.time,
            covers=request.covers,
            first_name=request.first_name,
            last_name=request.last_name,
            email=request.email,
            phone=request.phone,
            unique_id=request.unique_id,
            notes=request.notes or "",
        )
        return ReservationResponse(
            reservation_id=data.get("reservation_id", ""),
            confirmation_url=data.get("confirmation_url"),
            notes=data.get("notes"),
        )
    except httpx.HTTPStatusError as e:
        error_detail = str(e.response.text)
        # Parse common Yelp error codes
        if "CREDIT_CARD_REQUIRED" in error_detail:
            raise HTTPException(status_code=402, detail="This reservation requires a credit card. Please book directly on Yelp.")
        elif "SLOT_NO_LONGER_AVAILABLE" in error_detail:
            raise HTTPException(status_code=409, detail="This time slot is no longer available. Please try another time.")
        elif "HOLD_NOT_FOUND" in error_detail or "INVALID_HOLD_ID" in error_detail:
            raise HTTPException(status_code=404, detail="Hold expired or not found. Please start over.")
        raise HTTPException(status_code=e.response.status_code, detail=error_detail)
    except Exception as e:
        print(f"Reservation booking error: {e}")
        raise HTTPException(status_code=500, detail="Failed to complete reservation")


class OrchestratorChatRequest(BaseModel):
    room_id: Optional[str] = None
    message: str
    user_context: Dict[str, Any] = Field(
        default_factory=dict,
        description="Rich iOS context from UserContextProvider.buildContext().",
    )


@router.post("/chat", response_model=OrchestratorChatOutput)
async def orchestrator_chat_endpoint(
    request: OrchestratorChatRequest,
    user: Dict[str, Any] = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Public HTTP endpoint for orchestrated chat.

    The rooms router calls the agent directly, but this endpoint lets other
    clients (e.g. WhatsApp, future UIs) talk to Tess with full orchestration.
    """
    chat_session = None
    if request.room_id:
        chat_session = (
            db.query(ChatSessionDB)
            .filter(ChatSessionDB.room_id == request.room_id)
            .first()
        )

    try:
        result = await run_orchestrator_chat(
            db=db,
            user_id=user["uid"],
            room_id=request.room_id,
            message=request.message,
            user_context=request.user_context,
            chat_id=chat_session.chat_id if chat_session else None,
        )
    except Exception as e:
        print(f"Orchestrator chat error: {e}")
        raise HTTPException(status_code=500, detail="Failed to run orchestrator chat")

    return result


async def run_orchestrator_chat(
    *,
    db: Session,
    user_id: str,
    room_id: Optional[str],
    message: str,
    user_context: Optional[Dict[str, Any]],
    chat_id: Optional[str],
) -> OrchestratorChatOutput:
    """
    Internal helper used by rooms.trigger_ai_response to run Tess via the agent
    without going through HTTP.
    """
    # Start typing indicator refresh task if we have a room_id
    stop_typing_event = asyncio.Event()
    typing_task = None
    if room_id:
        typing_task = asyncio.create_task(
            keep_typing_alive(room_id, AI_USER_ID, stop_typing_event)
        )
    
    try:
        with logfire.span("orchestrator_chat", user_id=user_id, room_id=room_id, chat_id=chat_id):
            logfire.info("Starting orchestrator chat", message_preview=message[:100] if message else None)
            logger.info(
                "[run_orchestrator_chat] START user_id=%s room_id=%s chat_id=%s message=%s",
                user_id,
                room_id,
                chat_id,
                message[:100] if message else None,
            )
            logger.debug("[run_orchestrator_chat] user_context keys: %s", list((user_context or {}).keys()))

            # Build lightweight conversation history for additional context
            user_prompt = message
            if room_id:
                with logfire.span("build_conversation_history"):
                    try:
                        room = db.query(RoomDB).filter(RoomDB.id == room_id).first()
                        if room and room.messages:
                            history_messages = room.messages[-15:]
                            lines = []
                            for m in history_messages:
                                sender_id = m.get("sender_id")
                                role = "Tess" if sender_id == AI_USER_ID else "User"
                                content = m.get("content", "")
                                lines.append(f"{role}: {content}")
                            history_block = "\n".join(lines)
                            user_prompt = (
                                "Here is the recent conversation in this room (oldest first):\n"
                                f"{history_block}\n\n"
                                f"User's latest message (respond to this):\n{message}"
                            )
                            logfire.info("Built conversation history", message_count=len(history_messages))
                            logger.debug("[run_orchestrator_chat] Built history with %d messages", len(history_messages))
                    except Exception as e:
                        logfire.error("Error building history", error=str(e), room_id=room_id)
                        logger.exception("[run_orchestrator_chat] Error building history for room %s", room_id)

            # Fetch user preferences from database
            db_user = db.query(UserDB).filter(UserDB.id == user_id).first()
            user_preferences = []
            user_name = None
            user_bio = None
            if db_user:
                user_preferences = db_user.preferences or []
                user_name = db_user.name
                user_bio = db_user.bio
            
            # Enrich user_context with preferences
            enriched_context = user_context or {}
            enriched_context["user_name"] = user_name
            enriched_context["user_bio"] = user_bio
            enriched_context["user_preferences"] = user_preferences
            
            deps = OrchestratorDeps(
                user_id=user_id,
                room_id=room_id,
                db=db,
                user_context=enriched_context,
                chat_id=chat_id,
            )

            try:
                with logfire.span("run_chat_agent"):
                    logfire.info("Calling chat_agent.run()")
                    logger.info("[run_orchestrator_chat] Calling chat_agent.run() ...")
                    result = await chat_agent.run(user_prompt, deps=deps)
                    output = result.output
            except Exception as agent_error:
                # Catch any errors from the agent (including tool errors) and return a friendly message
                logfire.error("Agent execution error", error=str(agent_error), error_type=type(agent_error).__name__)
                logger.exception("[run_orchestrator_chat] Agent execution error: %s", agent_error)
                
                # Return a user-friendly error message instead of crashing
                error_message = "I ran into a temporary issue while searching. Please try again in a moment."
                
                # Provide more specific messages for known error types
                error_str = str(agent_error).lower()
                if "timeout" in error_str:
                    error_message = "The search took too long. Please try again with a simpler request."
                elif "connection" in error_str or "network" in error_str:
                    error_message = "I'm having trouble connecting to my search service. Please try again in a moment."
                elif "rate limit" in error_str or "429" in error_str:
                    error_message = "I've been getting a lot of requests. Please wait a moment and try again."
                elif "500" in error_str or "server error" in error_str:
                    error_message = "My search service is temporarily unavailable. Please try again in a moment."
                
                return OrchestratorChatOutput(
                    text=error_message,
                    businesses=[],
                    actions=[],
                    yelp_chat_id=None,
                )

            logfire.info(
                "Agent returned",
                text_length=len(output.text) if output.text else 0,
                businesses_from_model=len(output.businesses),
                yelp_chat_id=output.yelp_chat_id,
            )
            logger.info(
                "[run_orchestrator_chat] Agent returned text length=%d, businesses from model=%d, yelp_chat_id=%s",
                len(output.text) if output.text else 0,
                len(output.businesses),
                output.yelp_chat_id,
            )

            # ALWAYS ignore any businesses the model tried to generate. We only use real Yelp data.
            output.businesses = []

            # If Yelp AI was called, normalize businesses from the raw response.
            yelp_raw = deps.last_yelp_response or {}
            if yelp_raw:
                with logfire.span("normalize_yelp_response"):
                    logfire.debug("Normalizing Yelp response")
                    logger.debug("[run_orchestrator_chat] last_yelp_response exists, normalizing...")

                    # Ensure chat_id is propagated
                    if not output.yelp_chat_id and "chat_id" in yelp_raw:
                        output.yelp_chat_id = yelp_raw["chat_id"]
                        logfire.debug("Backfilled yelp_chat_id", chat_id=output.yelp_chat_id)
                        logger.debug("[run_orchestrator_chat] Backfilled yelp_chat_id=%s", output.yelp_chat_id)

                    entities = yelp_raw.get("entities") or []
                    businesses_data: List[Dict[str, Any]] = []
                    if isinstance(entities, list) and entities:
                        first = entities[0] or {}
                        businesses_data = first.get("businesses") or []

                    logfire.info("Building businesses from Yelp entities", raw_count=len(businesses_data))
                    logger.info(
                        "[run_orchestrator_chat] Building businesses from Yelp entities: %d raw businesses",
                        len(businesses_data),
                    )

                    # Enrich businesses with photos from the business details API
                    # This ensures we have thumbnails even if Yelp AI doesn't return contextual_info.photos
                    with logfire.span("enrich_businesses_with_photos"):
                        businesses_data = await enrich_businesses_with_photos(businesses_data)

                    normalized: List[OrchestratorBusiness] = []
                    for idx, b in enumerate(businesses_data):
                        try:
                            biz_id = b.get("id", "unknown")
                            biz_name = b.get("name", "unknown")
                            
                            # TRACE: Log raw business data for debugging photos
                            ctx_info = b.get("contextual_info") or {}
                            ctx_keys = list(ctx_info.keys()) if ctx_info else []
                            photos = ctx_info.get("photos") or []
                            raw_image_url = b.get("image_url")
                            
                            logfire.info(
                                "Processing business",
                                index=idx,
                                business_id=biz_id,
                                business_name=biz_name,
                                has_contextual_info=bool(ctx_info),
                                contextual_info_keys=ctx_keys,
                                photos_count=len(photos) if photos else 0,
                                raw_image_url=raw_image_url,
                            )
                            
                            # Determine final image_url
                            image_url = raw_image_url  # May have been enriched
                            if not image_url and photos and isinstance(photos, list):
                                first_photo = photos[0] if photos else {}
                                image_url = first_photo.get("original_url") if isinstance(first_photo, dict) else None
                                logfire.info(
                                    "Using photo from contextual_info",
                                    business_id=biz_id,
                                    photo_url=image_url,
                                )
                            
                            logfire.info(
                                "Final image_url for business",
                                business_id=biz_id,
                                business_name=biz_name,
                                final_image_url=image_url,
                                source="enriched" if raw_image_url else ("contextual_info" if image_url else "none"),
                            )

                            # Categories as list of dicts – matches iOS Category struct
                            raw_categories = b.get("categories") or []
                            categories: List[Dict[str, Any]] = (
                                raw_categories if isinstance(raw_categories, list) else []
                            )

                            # Location: fall back from top-level fields
                            location = b.get("location") or {
                                "address1": b.get("address1"),
                                "city": b.get("city"),
                                "zip_code": b.get("zip_code"),
                                "country": b.get("country"),
                                "state": b.get("state"),
                                "display_address": b.get("display_address"),
                                "formatted_address": b.get("formatted_address"),
                            }

                            # Coordinates: must have both lat & lon, otherwise skip
                            coords_dict = b.get("coordinates") or {}
                            lat = coords_dict.get("latitude", b.get("latitude"))
                            lon = coords_dict.get("longitude", b.get("longitude"))
                            if lat is None or lon is None:
                                logfire.warn("Skipping business with missing coordinates", business_id=biz_id)
                                continue
                            coordinates = {"latitude": float(lat), "longitude": float(lon)}

                            rating = float(b.get("rating") or 0.0)
                            review_count = int(b.get("review_count") or 0)

                            normalized.append(
                                OrchestratorBusiness(
                                    id=biz_id,
                                    name=biz_name,
                                    image_url=image_url,
                                    url=b.get("url"),
                                    rating=rating,
                                    review_count=review_count,
                                    price=b.get("price"),
                                    categories=categories,
                                    location=location,
                                    coordinates=coordinates,
                                    phone=str(b.get("phone")) if b.get("phone") is not None else None,
                                    display_phone=b.get("display_phone"),
                                )
                            )
                        except Exception as e:
                            logfire.error("Error normalizing business", error=str(e), business_id=b.get("id"))
                            logger.exception("[run_orchestrator_chat] Error normalizing business: %s", e)
                            continue

                    output.businesses = normalized
                    logfire.info("Built normalized businesses from Yelp", count=len(normalized))
                    logger.info("[run_orchestrator_chat] Built %d normalized businesses from Yelp", len(normalized))
            else:
                # No Yelp AI call this turn → no cards.
                output.businesses = []
                logfire.debug("No Yelp AI call this turn; no businesses")
                logger.debug("[run_orchestrator_chat] No last_yelp_response; Yelp AI was NOT called this turn")

            logfire.info(
                "Orchestrator chat complete",
                text_length=len(output.text) if output.text else 0,
                businesses_count=len(output.businesses),
                yelp_chat_id=output.yelp_chat_id,
            )
            logger.info(
                "[run_orchestrator_chat] DONE returning text length=%d, businesses=%d, yelp_chat_id=%s",
                len(output.text) if output.text else 0,
                len(output.businesses),
                output.yelp_chat_id,
            )
            return output
    finally:
        # Stop typing indicator refresh task
        if typing_task:
            stop_typing_event.set()
            typing_task.cancel()
            try:
                await typing_task
            except asyncio.CancelledError:
                pass
            # Ensure typing indicator is cleared
            if room_id:
                update_typing_status(room_id, AI_USER_ID, False, AI_USER_NAME)


# ============================================
# 2. Taste Persona (no Yelp AI, local only)
# ============================================


class TastePersonaOutput(BaseModel):
    title: str
    bio: str


@dataclass
class TastePersonaDeps:
    user_id: str
    db: Session


taste_persona_agent = Agent[TastePersonaDeps, TastePersonaOutput](
    OPENAI_MODEL,
    deps_type=TastePersonaDeps,
    output_type=TastePersonaOutput,
    instructions=(
        "You are Tess, summarizing a user's food and going-out taste.\n"
        "You will first call `get_user_taste_data` to retrieve the user's saved locations "
        "and AI discoveries from our database.\n"
        "Then you must return a fun 2–3 word nickname as `title` and a short, human-friendly paragraph as `bio`.\n"
        "If there is very little or no data, encourage them to explore in a positive way."
    ),
)


@taste_persona_agent.tool
def get_user_taste_data(ctx: RunContext[TastePersonaDeps]) -> Dict[str, Any]:
    """
    Fetch the user's saved places and AI-discovered locations from our own DB.

    Returns a JSON blob with:
    - saved_locations: list of Location JSON objects
    - ai_discoveries: list of Location JSON objects (from AI)
    """
    with logfire.span("get_user_taste_data_tool", user_id=ctx.deps.user_id):
        db = ctx.deps.db
        user_id = ctx.deps.user_id

        saved = (
            db.query(SavedLocationDB)
            .filter(SavedLocationDB.user_id == user_id)
            .order_by(SavedLocationDB.created_at.desc())
            .all()
        )
        discoveries = (
            db.query(AIDiscoveryDB)
            .filter(AIDiscoveryDB.user_id == user_id)
            .order_by(AIDiscoveryDB.created_at.desc())
            .all()
        )

        logfire.info("Fetched user taste data", saved_count=len(saved), discoveries_count=len(discoveries))

        return {
            "saved_locations": [s.location_data for s in saved],
            "ai_discoveries": [d.location_data for d in discoveries],
        }


@router.get("/taste-persona", response_model=TastePersonaOutput)
async def get_taste_persona(
    user: Dict[str, Any] = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Generate a concise taste persona for the current user based on their
    saved locations + AI discoveries. This does NOT call Yelp AI.
    """
    with logfire.span("taste_persona_endpoint", user_id=user["uid"]):
        logfire.info("Generating taste persona", user_id=user["uid"])
        deps = TastePersonaDeps(user_id=user["uid"], db=db)
        try:
            result = await taste_persona_agent.run(
                "Generate a fun taste persona for this user from their history.",
                deps=deps,
            )
            logfire.info("Taste persona generated", title=result.output.title)
        except Exception as e:
            logfire.error("Taste persona error", error=str(e))
            print(f"Taste persona error: {e}")
            raise HTTPException(status_code=500, detail="Failed to generate taste persona")

        return result.output


