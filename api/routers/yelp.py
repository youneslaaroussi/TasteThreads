from fastapi import APIRouter, HTTPException, Header, Body
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
import httpx
import os

router = APIRouter()

YELP_API_KEY = os.getenv("YELP_API_KEY")
YELP_BASE_URL = "https://api.yelp.com"

class ChatRequest(BaseModel):
    query: str
    chat_id: Optional[str] = None
    user_context: Optional[Dict[str, Any]] = None
    request_context: Optional[Dict[str, Any]] = None

class SearchRequest(BaseModel):
    term: str
    location: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    radius: Optional[int] = None
    categories: Optional[str] = None
    price: Optional[str] = None
    open_now: Optional[bool] = None
    sort_by: Optional[str] = "best_match"
    limit: Optional[int] = 20
    offset: Optional[int] = 0

@router.post("/chat")
async def chat_with_yelp(request: ChatRequest):
    """
    Interact with Yelp AI API (Search & Chat)
    """
    api_key = os.getenv("YELP_API_KEY")
    if not api_key:
        print("Error: YELP_API_KEY is missing")
        raise HTTPException(status_code=500, detail="Yelp API Key not configured")

    url = f"{YELP_BASE_URL}/ai/chat/v2"
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Accept": "application/json"
    }
    
    payload = {
        "query": request.query
    }
    
    if request.chat_id:
        payload["chat_id"] = request.chat_id
    
    # Transform user_context to Yelp's expected format
    # Yelp expects: { "latitude": float, "longitude": float }
    if request.user_context:
        yelp_user_context = _transform_user_context(request.user_context)
        if yelp_user_context:
            payload["user_context"] = yelp_user_context
            print(f"Yelp user_context: {yelp_user_context}")
    
    if request.request_context:
        payload["request_context"] = request.request_context

    print(f"Sending request to Yelp AI: {url}")
    print(f"Payload: {payload}")
    
    async with httpx.AsyncClient(timeout=60.0) as client:
        try:
            response = await client.post(url, json=payload, headers=headers)
            response.raise_for_status()
            response_json = response.json()
            print(f"Received response from Yelp: {response_json}")
            return response_json
        except httpx.HTTPStatusError as e:
            print(f"Yelp API Error: {e.response.text}")
            raise HTTPException(status_code=e.response.status_code, detail=str(e.response.text))
        except Exception as e:
            print(f"Internal Error: {e}")
            raise HTTPException(status_code=500, detail=str(e))


def _transform_user_context(context: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Transform our rich user context into Yelp's expected format.
    
    Yelp AI API user_context expects:
    - latitude (float): User's approximate latitude
    - longitude (float): User's approximate longitude
    
    We extract coordinates from our location context and pass them to Yelp.
    Other context (preferences, taste profile) enriches the query but isn't
    passed directly to Yelp's user_context.
    """
    yelp_context = {}
    
    # Extract location coordinates
    location = context.get("location", {})
    
    # Check for approximate_area (our privacy-preserving coordinates)
    approx_area = location.get("approximate_area", {})
    if approx_area:
        if "latitude" in approx_area:
            yelp_context["latitude"] = approx_area["latitude"]
        if "longitude" in approx_area:
            yelp_context["longitude"] = approx_area["longitude"]
    
    # Fallback: check for direct lat/lon in location
    if "latitude" not in yelp_context and "latitude" in location:
        yelp_context["latitude"] = location["latitude"]
    if "longitude" not in yelp_context and "longitude" in location:
        yelp_context["longitude"] = location["longitude"]
    
    return yelp_context if yelp_context else None

@router.get("/search")
async def search_businesses(
    term: str,
    location: Optional[str] = None,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    radius: Optional[int] = None,
    categories: Optional[str] = None,
    price: Optional[str] = None,
    open_now: Optional[bool] = None,
    sort_by: str = "best_match",
    limit: int = 20,
    offset: int = 0
):
    """
    Search for businesses using Yelp Fusion API
    """
    if not YELP_API_KEY:
        raise HTTPException(status_code=500, detail="Yelp API Key not configured")

    url = f"{YELP_BASE_URL}/v3/businesses/search"
    
    headers = {
        "Authorization": f"Bearer {YELP_API_KEY}",
        "Accept": "application/json"
    }
    
    params = {
        "term": term,
        "sort_by": sort_by,
        "limit": limit,
        "offset": offset
    }
    
    if location: params["location"] = location
    
    if latitude: params["latitude"] = latitude
    if longitude: params["longitude"] = longitude
    if radius: params["radius"] = radius
    if categories: params["categories"] = categories
    if price: params["price"] = price
    if open_now is not None: params["open_now"] = open_now

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(url, params=params, headers=headers)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=str(e.response.text))
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

@router.get("/business/{business_id}")
async def get_business_details(business_id: str):
    """
    Get detailed business information using Yelp Fusion API
    """
    api_key = os.getenv("YELP_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="Yelp API Key not configured")

    url = f"{YELP_BASE_URL}/v3/businesses/{business_id}"
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json"
    }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(url, headers=headers)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=str(e.response.text))
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

@router.get("/reviews/{business_id}")
async def get_business_reviews(
    business_id: str,
    limit: int = 3,
    sort_by: str = "yelp_sort"
):
    """
    Get reviews for a business using Yelp Fusion API
    """
    api_key = os.getenv("YELP_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="Yelp API Key not configured")

    url = f"{YELP_BASE_URL}/v3/businesses/{business_id}/reviews"
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json"
    }
    
    params = {
        "limit": limit,
        "sort_by": sort_by
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(url, params=params, headers=headers)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=str(e.response.text))
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

@router.get("/review_highlights/{business_id}")
async def get_business_review_highlights(
    business_id: str,
    count: int = 3
):
    """
    Get review highlights for a business using Yelp Fusion API
    """
    api_key = os.getenv("YELP_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="Yelp API Key not configured")

    url = f"{YELP_BASE_URL}/v3/businesses/{business_id}/review_highlights"
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json"
    }
    
    params = {
        "count": count
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(url, params=params, headers=headers)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=str(e.response.text))
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))


@router.get("/business/{business_id}/full")
async def get_full_business_details(business_id: str, review_limit: int = 5):
    """
    Get comprehensive business details including reviews in a single call.
    Combines Business Details API + Reviews API for efficiency.
    """
    api_key = os.getenv("YELP_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="Yelp API Key not configured")
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json"
    }
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Fetch business details and reviews in parallel
        details_url = f"{YELP_BASE_URL}/v3/businesses/{business_id}"
        reviews_url = f"{YELP_BASE_URL}/v3/businesses/{business_id}/reviews"
        
        try:
            details_task = client.get(details_url, headers=headers)
            reviews_task = client.get(reviews_url, params={"limit": review_limit, "sort_by": "yelp_sort"}, headers=headers)
            
            details_response, reviews_response = await details_task, await reviews_task
            
            details_response.raise_for_status()
            business_data = details_response.json()
            
            # Reviews might fail for some businesses, handle gracefully
            reviews_data = {"reviews": [], "total": 0}
            if reviews_response.status_code == 200:
                reviews_data = reviews_response.json()
            
            # Combine into enriched response
            return {
                **business_data,
                "reviews": reviews_data.get("reviews", []),
                "total_reviews": reviews_data.get("total", business_data.get("review_count", 0))
            }
            
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=str(e.response.text))
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))
