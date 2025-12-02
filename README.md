# TasteThreads Whitepaper

<div align="center">
<table>
  <tr>
    <th>Chat with Agent</th>
    <th>Reservation Flow</th>
    <th>Group Chat Invitation</th>
    <th>Map & Itinerary</th>
  </tr>
  <tr>
    <td><img src="./media/Screenshot 2025-12-02 at 3.49.28 PM.png" alt="TasteThreads Demo" height="400" /></td>
    <td><img src="./media/Screenshot 2025-12-02 at 3.38.09 PM.png" alt="Map & Itinerary Screenshot" height="400" /></td>
    <td><img src="./media/Screenshot 2025-12-02 at 3.38.17 PM.png" alt="Group Chat Screenshot" height="400" /></td>
    <td><img src="./media/Screenshot 2025-12-02 at 3.35.30 PM.png" alt="Reservation Flow" height="400" /></td>
  </tr>
</table>

**Group-first dining planning powered by Yelp AI's conversational + agentic APIs**

**Real-time collaboration · GPT-4o-mini orchestration · End-to-end reservations**

![iOS](https://img.shields.io/badge/iOS-SwiftUI-0c84ff?logo=apple&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-Backend-009485?logo=fastapi&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-4169e1?logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-WebSockets-dc382d?logo=redis&logoColor=white)
![Yelp AI API](https://img.shields.io/badge/Yelp-AI%20API-fa4454?logo=yelp&logoColor=white)
![Pydantic AI](https://img.shields.io/badge/Pydantic-AI%20Tools-ef6f53)
![MapKit](https://img.shields.io/badge/MapKit-Custom%20Markers-34c759)
![License](https://img.shields.io/badge/License-MIT-blue)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Design Notes](#design-notes)
  - [Constraints & Solutions](#the-constraints)
  - [AI Orchestrator](#ai-orchestrator)
  - [Real-Time Collaboration](#real-time-collaboration)
  - [Maps & Itinerary](#map-centric-collaboration)
  - [Taste Graph Context](#taste-graph-context)
  - [Reservation Flow](#agentic-reservations)
- [Tech Stack](#tech-stack)
- [Contributing](#contributing)
- [Testing](#testing)

---

## Overview

We built TasteThreads to showcase what happens when Yelp's new conversational + agentic APIs become the brain of a group-planning app. Instead of sprinkling recommendations on top of static feeds, Tess (our orchestrator powered by GPT-4o-mini) routes every natural-language message through Yelp AI Chat, reads the structured replies, and decides whether to continue the dialog, pull Fusion details, or fire the reservation action stack. The human interface looks like a friendly group chat; the backend is an AI workflow engine tuned specifically for Yelp's endpoints.

**Yelp AI as the execution engine:** Tess never guesses. Discovery queries drop straight into `/ai/chat/v2` with live `chat_id` continuity per room, ensuring multi-turn understanding of preferences, budgets, and past feedback. When Yelp returns candidate businesses, the agent fuses them with Fusion metadata, annotates Tess's responses with rationale, and creates structured cards the iOS client can render instantly.

**Agentic reservations front and center:** Yelp's new action APIs unlock a full conversational booking flow, so we lean hard into them. When Tess detects intent, she chains `openings → holds → reservations`, sending intermediate state (available slots, hold IDs, confirmation numbers) back to the chat in under 10 seconds. Users stay inside the same thread while the AI negotiates availability directly with Yelp.

**AI-native collaboration loop:** Redis-backed WebSockets keep humans in sync, but Tess plays alongside them like another teammate. Inspired by ChatGPT’s group chat beta, she automatically replies whenever someone types `@ai`, `@tess`, or `@yelp`, and she also jumps in after every five human-only messages to keep the flow unblocked. Each response includes the entire chat transcript + itinerary context so she speaks for the group, not just the last message.

**Performance tuned for AI latency:** The FastAPI orchestrator streams Yelp AI responses the moment tokens arrive, so users see Tess typing within ~500 ms even when full answers take 2–5 s. Reservation flows acknowledge each API hop, and Logfire traces track every tool call so the AI's reasoning stays legible to judges and teammates.

**Shared agency:** Everyone in the room can tag Tess, reference earlier decisions, or even paste whole checklists—the orchestrator feeds her the complete conversation, itinerary JSON, and user metadata on every turn. That shared context plus the timed auto-responses give TasteThreads the same “AI in the room” feel that ChatGPT’s latest group feature pioneered, but tuned to Yelp’s APIs and the needs of dining crews.

TasteThreads is deliberately AI-forward: the app exists to prove that a single, well-instrumented agent plus Yelp's APIs can replace the messy "copy Yelp link → argue → open OpenTable" dance with something conversational, verifiable, and instantly actionable.

<div align="center">
<img src="./media/TasteThreads Architectural Diagram.png" alt="TasteThreads AI Overview"/>
</div>

---

## Setup

TasteThreads ships as two tightly-coupled pieces: a FastAPI orchestrator that talks to Yelp AI APIs, and a SwiftUI client that streams every message through that orchestrator. Because Yelp must stay the single source of truth, we front-load credential collection and keep configuration explicit—judges can recreate our stack in under 15 minutes.

### Prerequisites

| Role | Requirement | Why it matters |
|------|-------------|----------------|
| Backend | Python 3.11+, `pip`, PostgreSQL 14+, Redis 6+ | Async FastAPI stack with task fan-out |
| Frontend | macOS + Xcode 15+, iOS 17 simulator/device | SwiftUI + Combine targets iOS 17 |
| AI Credentials | Yelp AI API key (Chat + Reservations), Firebase Admin JSON, OpenAI-compatible key for GPT-4o-mini proxy | Tess orchestration + auth |

### 1. Backend (FastAPI + Tess Orchestrator)

1. **Install dependencies**

```bash
cd api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. **Create `.env` with Yelp + infra credentials**

```bash
cat > .env <<'EOF'
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/tastethreads
REDIS_URL=redis://localhost:6379
YELP_API_KEY=your_yelp_ai_api_key
YELP_RESERVATIONS_TEST_MODE=true        # switch to false in production
OPENAI_MODEL=openai:gpt-4o-mini
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CLIENT_EMAIL=service-account@your-project.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
EOF
```

3. **Apply migrations and launch FastAPI**

```bash
alembic upgrade head
uvicorn main:app --reload
```

The server mounts REST + WebSocket routers under `/api/v1/*`, streams Tess responses over Redis pub/sub, and logs traces to Logfire (if configured).

### 2. iOS Client (SwiftUI + Firebase Auth)

1. Download `GoogleService-Info.plist` from your Firebase project and replace `app/TasteThreads/GoogleService-Info.plist`.
2. Point the app at your backend:

```swift
// app/TasteThreads/Config.swift
// static let apiBaseURL = "http://127.0.0.1:8000"   // Uncomment for local dev
```

3. Open `app/TasteThreads.xcodeproj` in Xcode 15+, select an iOS 17 simulator, and press **Run**. Swift Package Manager resolves dependencies automatically; no CocoaPods required.

The client signs in via Firebase Auth (email link or SMS), opens a WebSocket to `/api/v1/rooms/ws/{room_id}`, and streams Tess + user messages with typing indicators.

<div align="center">
<img src="./media/Screen Recording 2025-12-02 at 5.22.56 PM.gif" alt="Onboarding & Auth Screenshot" height="400" />
</div>

### 3. First-Run Checklist

1. Create a room in the app → confirm `rooms` table updates in Postgres.
2. Send "Find tacos" → watch the backend log a `/ai/chat/v2` call with a persisted `chat_id`.
3. Ask Tess to "Hold dinner for four at 7pm" → verify `openings → hold → reservation` tool chain hits Yelp's reservation APIs.
4. Tap a suggestion card → confirm the map renders Yelp Fusion imagery + metadata.
5. Tag Tess with `@ai book sushi` and confirm she replies instantly; then send five human messages without mentions to see the timed auto-reply kick in.

<div align="center">
<img src="./media/Screenshot 2025-12-02 at 5.24.55 PM.png" alt="First Run Checklist Screenshot" height="360" />
</div>

---

## Logfire Tracing 

Every agent turn produces a Logfire trace capturing:

- The incoming trigger (`mention`, `auto_every_5`, or `system`)
- Full dependency payload (chat transcript hash, itinerary diff, `chat_id`)
- Each Yelp tool span with latency, status, and `test_mode` flag
- Streaming duration from first token to completion

We’ll drop the annotated screenshot here before final submission to highlight the discovery → reservation pipeline.

<div align="center">
  <img src="./media/logfire-us.pydantic.dev_youneslaaroussi_starter-project.png" alt="Logfire Trace Screenshot" height="400" />
</div>

---

## Design Notes

We designed TasteThreads around the hackathon’s scoring pillars: deep Yelp AI usage, thoughtful UX, real impact, and a creative idea. Each subsystem starts with the constraint we had to live with, then walks through the solution, technical decisions, and measurable impact.

### The Constraints

**Problem:** Yelp’s AI APIs are powerful but opinionated. Chat responses are natural language with embedded metadata, reservations require multi-step action calls, and everything needs to stay inside Yelp’s data boundary. Meanwhile, small language models (GPT-4o-mini) have finite context and occasionally hallucinate tool usage.

**Solution:** We treat Yelp as the execution engine and the LLM as a planner. Tess only moves through three tool families: `yelp_ai_search` (Chat API), `yelp_reservation_*` (reservations stack), and `yelp_fusion_business` (enrichment). All other behavior (room state, map updates, messaging) happens deterministically in FastAPI/SwiftUI. This keeps the AI focused on decisions, not mutations.

**Impact Comparison:**

| Approach | Yelp API Usage | Tool Errors | Dev Effort |
|----------|----------------|-------------|------------|
| Generic RAG over Yelp data | Scraped/stitched responses, inaccurate | Frequent hallucinated businesses | Low initial effort, poor scoring |
| **TasteThreads orchestration** | ✅ Direct `/ai/chat/v2`, `/bookings/*`, Fusion | < 2% tool retries (tracked) | Higher upfront work, meets judging criteria |

We’re honest about trade-offs: Tess waits ~2 s for Yelp Chat responses, but in return we get judge-verifiable logs showing exactly how the AI reached each recommendation or reservation.

### Yelp API Coverage

| Capability | Endpoint | How we use it | Logfire span |
|------------|----------|---------------|--------------|
| Conversational discovery | `/ai/chat/v2` | Tess sends every natural-language prompt with per-room `chat_id` so Yelp maintains context | `yelp_ai_search_tool` |
| Reservations lifecycle | `/v3/bookings/{id}/openings`, `/holds`, `/reservations` | Openings → hold → booking flow with interactive cards | `yelp_reservation_openings_tool`, `yelp_reservation_hold_tool`, `yelp_reservation_book_tool` |
| Business enrichment | `/v3/businesses/{id}` | Fetches photos, hours, dietary tags for map + itinerary cards | `yelp_fusion_business_tool` |

Each span captures latency, parameters, `chat_id`, and whether `YELP_RESERVATIONS_TEST_MODE` is active. Judges can open Logfire and see every call’s provenance.

### AI Orchestrator

**Problem:** GPT-4o-mini needs strict guardrails to call Yelp APIs correctly, persist `chat_id` per room, and stop after reservation failures—all while streaming partial results so the chat doesn’t feel dead.

**Solution:** The orchestrator in `api/routers/orchestrator.py` wraps Pydantic AI. It injects per-room dependencies (user context, chat IDs, itinerary state), declares typed tools for each Yelp endpoint, and listens for Tess’s tool calls. Every tool result is logged via Logfire spans with reasons (success, validation error, rate limit).

**Technical Implementation:**

```python
# api/routers/orchestrator.py
agent = Agent(
    model="openai:gpt-4o-mini",
    deps=AgentDeps(chat_id=chat_session.chat_id, user_context=db_user.to_context()),
    tools=[yelp_ai_search, yelp_reservation_openings, yelp_reservation_hold, yelp_reservation_book]
)
```

- **Loop control:** We cap retries at 10 per tool (configurable). If Yelp responds with malformed JSON, Tess gets a structured error telling her to rephrase instead of blindly retrying.
- **Streaming UX:** FastAPI relays Tess’s tokens over Server-Sent Events, so iOS renders “Tess is typing…” within ~500 ms even before Yelp finishes responding.
- **Observability:** Logfire spans include latency per Yelp call, total tokens, and reservation status. Judges can inspect the trace to verify real API usage.
- **Location-aware context:** The iOS app provides user location via `LocationContext` (rounded to ~100m precision for privacy), which gets passed to Yelp's AI Chat API as `user_context` with `latitude` and `longitude` fields. This enables Tess to understand spatial queries like "find places near me" or "suggest restaurants nearby"—Yelp's AI uses these coordinates to bias search results toward the user's current area. The location context is extracted from the rich user context payload via `_extract_yelp_user_context()` and included in every `/ai/chat/v2` call when available.

Before every turn we compute `AgentTrigger` (`mention`, `auto_every_5`, `direct`) so Tess knows why she was summoned. The orchestrator also streams the whole chat history (summarized if >2k tokens) along with itinerary deltas so she can reference anything anyone said. Logfire tags each turn with that trigger, making it easy to filter “auto responses” versus explicit summons.

**Location privacy & security:** User location is handled with multiple privacy safeguards:

- **Precision reduction:** Coordinates are rounded to ~100m precision (multiplying by 1000, rounding, then dividing by 1000) before being sent to Yelp, preventing exact location tracking while still providing useful proximity context.
- **iOS location manager:** Uses `kCLLocationAccuracyHundredMeters` accuracy setting and only updates when the user moves more than 500m (`distanceFilter`), minimizing unnecessary location updates.
- **Context isolation:** Location data is only included in Yelp API calls when explicitly needed (search queries and AI chat requests). It's never stored in our database or logged in plaintext—only approximate coordinates are passed to Yelp's APIs.
- **User control:** Location permissions are requested via iOS's standard `CLLocationManager` authorization flow, and users can revoke access at any time through system settings.

**Before vs After:**

| Metric | Naive LLM proxy | **Tess orchestrator** |
|--------|-----------------|-----------------------|
| Chat continuity | Lost after each message | ✅ `chat_id` persisted per room |
| Reservation flow | Manual links | ✅ Agentic openings → holds → book |
| Tool error recovery | None | ✅ Retry budget + structured guidance |
| Location awareness | None | ✅ Privacy-preserving coordinates passed to Yelp AI |

<div align="center">
<img src="./diagrams/TasteThreadsOrchestrator.png" alt="Tess Orchestrator Diagram" height="420" />
</div>

### Agentic Workflow

Tess’s autonomy boils down to typed tools defined in `api/routers/orchestrator.py`. Each wraps a specific Yelp API call and includes guardrails:

| Tool | Yelp API | Purpose | Logfire instrumentation |
|------|----------|---------|-------------------------|
| `yelp_ai_search` | `/ai/chat/v2` | Multi-turn discovery with room-level `chat_id` continuity | `logfire.span("yelp_ai_search_tool", …)` captures query, latency, status (see `api/routers/orchestrator.py:608-618`) |
| `yelp_reservation_openings` | `/bookings/{id}/openings` | Fetches actionable slots for a business/date/time | Span includes party size, `test_mode` flag, and response summary (`api/routers/orchestrator.py:608-642`) |
| `yelp_reservation_hold` | `/bookings/{id}/holds` | Locks a slot once a user taps a card | Spans annotate `hold_id` and failure reasons (`api/routers/orchestrator.py:749-781`) |
| `yelp_reservation_book` | `/bookings/{id}/reservations` | Finalizes the booking after user confirmation | Logs confirmation payload + handoff to itinerary (`api/routers/orchestrator.py:901-934`) |
| `yelp_fusion_business` | `/v3/businesses/{id}` | Hydrates cards with imagery/hours | Span notes caching and photo counts |

Every span streams to Logfire with consistent naming, so we can filter by tool, room, or error type. If GPT-4o-mini misuses a tool, the orchestrator returns a structured error and the span marks it as `status="error"`, giving us immediate visibility.

### Real-Time Collaboration

**Problem:** Yelp AI responses take seconds, but humans expect sub-100 ms chat sync. We couldn’t let Tess’s latency block human banter, and we needed to show judges a balanced front/back split.

**Solution:** WebSockets run separately from the AI loop. Human messages hit FastAPI, persist to Postgres, fan out through Redis, and render instantly. Tess joins the same stream when her response is ready. Typing indicators and message reactions never wait on AI results, and the mention watcher listens for `@ai`, `@tess`, and `@yelp` plus an auto-timer that fires after five human-only messages—mirroring the cadence we love in ChatGPT’s new group feature.

**Key Details:**

- `api/routers/rooms.py` handles REST + WebSocket endpoints with Firebase JWT auth.
- Redis pub/sub keeps multiple FastAPI instances in sync (Railway-friendly horizontal scaling).
- SwiftUI uses Combine publishers to keep the chat, itinerary drawer, and map in sync.

**Performance Snapshot:**

| Event | Latency |
|-------|---------|
| Human → human message fan-out | 40–80 ms |
| Mention/auto trigger detection | < 10 ms (in FastAPI) |
| Human → Tess response first token | ~500 ms (streaming) |
| Full Tess response | 2–5 s (depends on Yelp) |

We deliberately expose Tess’s intermediate status (“Checking openings…”, “Creating hold…”) so the AI feels active even when Yelp takes longer.

<div align="center">
<img src="./diagrams/TasteThreadsRealtime.png" alt="Real-Time Collaboration Flow" height="390" />
</div>

### Map-Centric Collaboration

**Problem:** Yelp's AI returns rich metadata, but most chat bots collapse it into text. Judges expect design excellence, so we needed a spatial interface that stayed truthful to Yelp data (no custom search).

**Solution:** Every Tess recommendation carries the original Yelp business payload. The iOS app drops markers onto MapKit with layered styling:

- AI suggestions → sparkle aura + lighter pins
- Itinerary commitments → bold pins with time labels
- Saved spots → heart icon overlay

Tapping a marker opens a SwiftUI sheet showing Yelp photos, hours, dietary info, and Tess's rationale. Users can add notes, assign vote counts, or trigger a reservation follow-up without retyping context.

**Location-based search:** When users search in the map screen, the app automatically uses the current map center coordinates (`region.center.latitude` and `region.center.longitude`) to query Yelp's Fusion API. This ensures search results are always relevant to the user's current view—if they're exploring a neighborhood, results appear nearby. The coordinates are passed directly to Yelp's `/v3/businesses/search` endpoint with `latitude` and `longitude` parameters, so Yelp handles the proximity filtering server-side.

**Why it matters:** Late arrivals can glance at the map and see the entire decision history. Judges can watch the demo video and verify that every card traces back to Yelp metadata we received (no made-up content).

<div align="center">
<img src="./diagrams/TasteThreadsMap.png" alt="Map + Itinerary Layers" height="360" />
</div>

### Taste Graph Context

**Problem:** Group taste isn’t just “likes sushi.” Each person brings their own price comfort, vibe preferences, and historical favorites. Without a structured view, GPT-4o-mini defaults to the loudest message and misses subtle preferences—hurting real collaboration.

**Solution:** We maintain a **Taste Graph** per user: a lightweight knowledge graph built from saved places, AI discoveries, current location, and preference signals. It’s rendered in the iOS `TasteGraphView` (Charts + persona cards) and fed into Tess via the context provider.

- **Data ingestion:** `UserContextProvider` registers `SavedPlacesContext`, `LocationContext`, `PreferencesContext`, etc., so every AI call carries `taste_profile` metadata like categories, price range, and recent AI wins.
- **LLM summarization:** The `/taste-persona` endpoint runs `taste_persona_agent`, which first calls `get_user_taste_data` (see `api/routers/orchestrator.py:1568-1599`) to pull DB-backed saved places + AI discoveries. GPT-4o-mini then emits a persona nickname + bio. Logfire spans (`taste_persona_endpoint`, `get_user_taste_data_tool`) record each run.
- **Graph nodes:** On-device charts (SwiftUI Charts) compute cuisine distribution, price tiers, and rating variance. These stats + persona feed back into `taste_profile`, so Tess knows “Ava loves izakayas under $$” while Sam might favor rooftop patios.
- **Group context:** When a user speaks (or tags `@ai`), FastAPI injects both the speaker’s Taste Graph and the room-level itinerary summary into `AgentDeps`. Tess can mention “Ava usually leans toward $$ ramen, while Jordan saved three steak spots” and suggest compromises.

**Result:** Tess acts like the neutral facilitator we wanted from ChatGPT’s group mode—except she references each person’s taste when nudged, leading to faster consensus. And because the entire chat + itinerary stream accompanies every turn, anyone—from the friend who found a new spot to the one coordinating votes—can nudge her with `@ai` and instantly get context-aware help.

<div align="center">
<img src="./diagrams/TasteThreadsTasteGraph.png" alt="Taste Graph Flow" height="360" />
</div>

### Agentic Reservations

**Problem:** Booking via Yelp Reservations API isn’t a single call. We have to interpret natural language, request openings, create holds, confirm bookings, and gracefully handle failures—all while staying conversational.

**Solution:** Tess watches for reservation intent, then chains tools:

1. `yelp_reservation_openings(business_id, date, time, covers)` → returns slot list
2. Tess summarizes options and sends an action card
3. When a user taps a slot, iOS calls `/api/v1/ai/reservations/hold`
4. Backend executes `yelp_reservation_hold` and caches `hold_id`
5. User confirms → `/reserve` endpoint calls `yelp_reservation_book`
6. Tess posts the confirmation payload back into chat + itinerary

**Comparison Table:**

| Scenario | Without agentic flow | **With TasteThreads** |
|----------|---------------------|-----------------------|
| User intent | Copy/paste “Can someone book this?” | Natural language → Tess detects intent |
| Availability | Manual Safari tab | AI card with live slots |
| Booking | Switch apps | One tap → hold → confirm |
| Failure handling | None | Tess surfaces Yelp error + next steps |

**Real-world example:**

1. **Scenario:** “Need a patio table for six tomorrow 7 pm in Hayes Valley.”
   - Tess calls `/ai/chat/v2` with location bias, returns 4 options.
2. **User action:** “Lock the best one.”
   - Tess picks the top Yelp rating, calls `openings`.
3. **System response:** Card shows 6:30 pm, 7:00 pm, 7:30 pm slots.
4. **Result:** User taps 7 pm → hold + book complete in 8.4 s, confirmation card drops into chat + itinerary.

If Yelp returns `NO_AVAILABILITY`, Tess explains that and suggests alternative times pulled from the API, keeping the conversation realistic.

> **Reservations partner toggle:** Yelp’s Reservations API requires partner access. Until our credentials are fully provisioned, we expose `YELP_RESERVATIONS_TEST_MODE=true` (see `api/routers/orchestrator.py:45-57`) to switch the reservation tools over to deterministic test responses. When the flag is `false`, the same tools hit the live `/openings → /holds → /reservations` endpoints with no code changes.

Each stage writes a Logfire span (`openings`, `hold`, `book`, `make_reservation`) so we can trace the exact slot Tess picked, how long Yelp took, and whether the response came from test mode or the live partner API.

<div align="center">
<img src="./diagrams/TasteThreadsReservations.png" alt="Reservation Tool Chain" height="360" />
</div>

---

## Tech Stack

| Category | Technologies | Why we chose them |
|----------|--------------|-------------------|
| Frontend | SwiftUI, Combine, MapKit, Firebase Auth SDK | Native feel, reactive data flows, secure social login |
| Backend | FastAPI, Pydantic, SQLAlchemy, Redis, Alembic | Async orchestration + typed models + horizontal fan-out |
| AI & Tools | GPT-4o-mini (OpenAI-compatible), Pydantic AI, Yelp AI Chat, Yelp Reservations, Yelp Fusion | Deterministic tool routing with first-class Yelp endpoints |
| Storage | PostgreSQL (rooms, itinerary, chat sessions), Redis (pub/sub), Firebase (identity) | Durable chat history + instant signaling |
| Observability & Deploy | Logfire tracing, Railway Docker deploys | Judge-verifiable spans (trigger type + tool latency) + fast redeploys with managed Postgres/Redis |
| Mobile Tooling | Xcode 15, Swift Package Manager, TestFlight | Zero-Pods setup + easy distribution |

---

## Contributing

TasteThreads is structured so judges (or future teammates) can dive into either side quickly.

### Repo Layout

```
TasteThreads/
├── api/                # FastAPI backend + Tess orchestrator
│   ├── routers/        # rooms, ai, reservations, websocket
│   ├── models/         # Pydantic + SQLAlchemy schemas
│   ├── migrations/     # Alembic scripts
│   └── redis_manager.py# Pub/sub helpers
├── app/                # SwiftUI iOS client
│   ├── Views/          # Chat, map, itinerary, reservation cards
│   ├── ViewModels/     # Combine-powered state
│   └── Services/       # REST + WebSocket clients
```

### How to Contribute

1. **Backend tweaks**
   - Install dev env (`python3 -m venv`, `pip install -r api/requirements.txt`)
   - Run `uvicorn main:app --reload` and `pytest` for any new modules
   - Add Logfire spans for new Yelp tool calls so judges keep visibility

2. **iOS features**
   - Use Xcode previews for SwiftUI components
   - Keep Config.swift pointing at staging URLs so Tess interactions remain real
   - Verify WebSocket + REST clients stay in sync (message ordering tests)

3. **AI behavior**
   - Update `api/routers/orchestrator.py` tool specs with docstrings + examples
   - Extend `AgentDeps` if new context (dietary prefs, languages) is needed

Pull requests should include demo notes or screenshots so reviewers can replay scenarios quickly. We prefer incremental changes that keep Yelp AI API usage transparent and testable.

---

## Testing

Judges asked for real, working software, so we keep verification lightweight but thorough—covering fast backend checks, AI traces, and iOS interaction tests.

### 1. Backend Smoke + Tool Routing

```bash
cd api
source .venv/bin/activate
pytest                      # unit/route tests (fast)
uvicorn main:app --reload   # keep running in another terminal
```

- Hit `GET /health` (returns `{"status":"ok"}`) to confirm FastAPI + Postgres + Redis connectivity.
- Send a sample message via HTTPie:

```bash
http POST :8000/api/v1/ai/messages \
  room_id=demo-room text="Find ramen in SF" \
  Authorization:"Bearer <firebase-jwt>"
```

Watch Logfire for spans named `yelp_ai_search` and ensure `chat_id` persists between calls.

### 2. Reservation Flow Regression

1. In the iOS app (simulator is fine), ask Tess “Hold dinner for four at 7pm tomorrow.”
2. Confirm Tess surfaces slots → tap one → verify hold confirmation toast.
3. Tap **Confirm**; backend should log `yelp_reservation_book` with `status=confirmed`.
4. Inspect Postgres `rooms` JSONB to ensure itinerary item gained `reservation.confirmation_code`.

If Yelp returns an error, Tess should send an explanatory message referencing the API response code—treat silent failures as bugs.

### 3. Real-Time Sync

1. Launch two simulators (or simulator + physical device).
2. Join the same room; type simultaneously and ensure messages arrive <100 ms apart (watch Redis pub/sub logs).
3. Drag a pin on the map to the itinerary; confirm both devices see the change instantly.
4. Trigger a Tess response and ensure humans keep chatting while she’s “typing”.
5. Open Logfire and filter by the room ID—you should see a new trace stamped with `trigger="auto_every_5"` or `trigger="mention"` depending on how Tess was invoked.
