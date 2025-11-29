import os
import logging
import asyncio
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import httpx
import logfire
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from auth import get_current_user, update_typing_status
from database import (
    ChatSessionDB,
    SavedLocationDB,
    AIDiscoveryDB,
    RoomDB,
    get_db,
)

from pydantic_ai import Agent, RunContext

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

if not YELP_API_KEY:
    logger.warning("YELP_API_KEY not set. Yelp AI and Reservations tools will fail.")

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


# ================================================================
# 1. Orchestrated Chat (Tess) - uses Yelp AI + Reservations tools
# ================================================================


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
    actions: List[Dict[str, Any]] = Field(
        default_factory=list,
        description="Optional high-level actions (e.g. reservation intents).",
    )


@dataclass
class OrchestratorDeps:
    """Per-run dependencies for the chat agent."""
    
    user_id: str
    room_id: Optional[str]
    db: Session
    user_context: Dict[str, Any]
    chat_id: Optional[str]
    last_yelp_response: Optional[Dict[str, Any]] = None


chat_agent = Agent[OrchestratorDeps, OrchestratorChatOutput](
    OPENAI_MODEL,
    deps_type=OrchestratorDeps,
    output_type=OrchestratorChatOutput,
    instructions=(
        "You are Tess, an AI assistant that helps groups plan outings using Yelp.\n"
        "- You ALWAYS think step-by-step using the tools you have.\n"
        "- The user_context describes their location, saved places, and preferences; use it to personalize tone and picks.\n"
        "- For any request that involves finding, recommending, or searching for places, YOU MUST call `yelp_ai_search` at least once before answering.\n"
        "- You MUST NEVER fabricate or guess business objects. Do not invent JSON for businesses or their fields.\n"
        "- The backend will attach real Yelp businesses based on your tool calls; focus on the natural-language reply and high-level actions only.\n"
        "- Leave the `businesses` array EMPTY in your output. The backend handles it.\n"
        "- When the user clearly wants to check reservation availability for a specific business and time, "
        "call `yelp_reservation_openings` and include the best options in your reply.\n"
        "- ALWAYS return a valid OrchestratorChatOutput as your final result. `text` is required; `businesses` should be empty.\n"
        "- If you call `yelp_ai_search`, set `yelp_chat_id` in your final output equal to the `chat_id` field from the last tool result.\n"
    ),
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
        logfire.info("Tool called: yelp_ai_search", query=query)
        logger.info("[yelp_ai_search] TOOL CALLED with query=%s", query)
        if not YELP_API_KEY:
            logfire.error("YELP_API_KEY not configured")
            logger.error("[yelp_ai_search] YELP_API_KEY is not configured!")
            raise RuntimeError("YELP_API_KEY is not configured on the server.")

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

        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(url, json=payload, headers=headers)
            logfire.info("Yelp AI HTTP response", status_code=resp.status_code)
            logger.debug("[yelp_ai_search] Yelp AI HTTP status: %s", resp.status_code)
            resp.raise_for_status()
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
        date: Reservation date in YYYY-MM-DD.
        time: Desired time in HH:MM (24h).
        covers: Party size from 1–10.
    Returns:
        Raw JSON from GET /v3/bookings/{business_id}/openings.
    """
    with logfire.span("yelp_reservation_openings_tool", business_id=business_id, date=date, time=time, covers=covers):
        logfire.info("Tool called: yelp_reservation_openings", business_id=business_id, date=date, time=time, covers=covers)
        logger.info(
            "[yelp_reservation_openings] TOOL CALLED business_id=%s date=%s time=%s covers=%d",
            business_id,
            date,
            time,
            covers,
        )
        if not YELP_API_KEY:
            logfire.error("YELP_API_KEY not configured")
            logger.error("[yelp_reservation_openings] YELP_API_KEY is not configured!")
            raise RuntimeError("YELP_API_KEY is not configured on the server.")

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
            resp.raise_for_status()
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

            deps = OrchestratorDeps(
                user_id=user_id,
                room_id=room_id,
                db=db,
                user_context=user_context or {},
                chat_id=chat_id,
            )

            with logfire.span("run_chat_agent"):
                logfire.info("Calling chat_agent.run()")
                logger.info("[run_orchestrator_chat] Calling chat_agent.run() ...")
                result = await chat_agent.run(user_prompt, deps=deps)
                output = result.output

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


