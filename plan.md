# ResQ AI — Complete Development Plan

> **Smart India Hackathon 2026**

---

## 1. Project Objective

ResQ AI is an intelligent emergency detection and assistance system that automatically detects possible emergencies using smartphone sensor data, verifies the emergency, and provides useful information to responders — even when the victim is unconscious, incapacitated, or separated from their phone.

---

## 2. Problem Statement

During an emergency, the victim may be:
- Unconscious or incapacitated
- Unable to press an SOS button
- Separated from their phone

The system should automatically:
1. Detect a possible emergency
2. Understand the situation
3. Verify the emergency
4. Provide useful emergency information to responders

---

## 3. Core Concept Flow

```
SENSE → FUSE → SCORE → VERIFY → ASSIST
```

---

## 4. Features

### Core Features
- Automatic emergency detection via smartphone sensors
- Sensor fusion engine combining accelerometer, gyroscope, GPS, and speed
- Configurable emergency scoring system
- Context engine to distinguish normal vs. suspicious vs. emergency activity
- Emergency verification with user timeout
- Life Replay timeline of recent sensor events
- Backend API for incident management
- Responder dashboard with map and incident details
- Emergency notification system

### Secondary Features
- Test Emergency mode
- Protection status toggle
- Sensor health monitoring
- Incident history

---

## 5. Technology Stack

| Component       | Technology                          |
|----------------|--------------------------------------|
| Mobile App      | Flutter (Dart)                       |
| Backend         | Python, FastAPI                      |
| Database        | MongoDB                              |
| Frontend (Dashboard) | HTML, CSS, JavaScript, Leaflet.js |
| ML (Future)     | TensorFlow Lite                      |
| Notifications   | Mock/SMS Fallback                    |

---

## 6. System Architecture

```
┌─────────────────────────────────────────────┐
│                MOBILE APP                    │
│  ┌─────────┐ ┌──────────┐ ┌──────────┐     │
│  │Accelerom│ │Gyroscope │ │   GPS    │     │
│  └────┬────┘ └────┬─────┘ └────┬─────┘     │
│       └───────────┼────────────┘            │
│                   ▼                          │
│         ┌──────────────────┐                │
│         │  Sensor Fusion   │                │
│         │  Engine          │                │
│         └────────┬─────────┘                │
│                  ▼                           │
│         ┌──────────────────┐                │
│         │ Context Engine   │                │
│         │ + Emergency Score│                │
│         └────────┬─────────┘                │
│                  ▼                           │
│         ┌──────────────────┐                │
│         │ Verification     │                │
│         │ System           │                │
│         └────────┬─────────┘                │
│                  ▼                           │
│         ┌──────────────────┐                │
│         │ Life Replay      │                │
│         │ Buffer           │                │
│         └────────┬─────────┘                │
└──────────────────┼──────────────────────────┘
                   ▼
         ┌──────────────────┐
         │   FastAPI        │
         │   Backend        │
         └────────┬─────────┘
                  ▼
         ┌──────────────────┐
         │    MongoDB       │
         └──────────────────┘
                  ▼
         ┌──────────────────┐
         │   Responder      │
         │   Dashboard      │
         └──────────────────┘
```

---

## 7. Folder Structure

```
resq_ai/
├── plan.md
├── mobile_app/                   # Flutter mobile application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── home_screen.dart
│   │   │   ├── emergency_screen.dart
│   │   │   └── settings_screen.dart
│   │   ├── sensors/
│   │   │   ├── sensor_manager.dart
│   │   │   ├── accelerometer_service.dart
│   │   │   ├── gyroscope_service.dart
│   │   │   └── gps_service.dart
│   │   ├── engine/
│   │   │   ├── sensor_fusion.dart
│   │   │   ├── emergency_scorer.dart
│   │   │   ├── context_engine.dart
│   │   │   ├── verification_system.dart
│   │   │   └── life_replay.dart
│   │   ├── models/
│   │   │   ├── sensor_data.dart
│   │   │   ├── emergency_event.dart
│   │   │   └── incident.dart
│   │   ├── services/
│   │   │   ├── api_service.dart
│   │   │   └── notification_service.dart
│   │   ├── config/
│   │   │   └── thresholds.dart
│   │   └── widgets/
│   │       ├── sensor_status_card.dart
│   │       ├── emergency_button.dart
│   │       └── protection_toggle.dart
│   ├── pubspec.yaml
│   └── android/
├── backend/                      # FastAPI backend
│   ├── main.py
│   ├── requirements.txt
│   ├── config.py
│   ├── database.py
│   ├── models/
│   │   ├── user.py
│   │   ├── incident.py
│   │   └── sensor_event.py
│   ├── routes/
│   │   ├── emergency.py
│   │   ├── location.py
│   │   └── incident.py
│   ├── services/
│   │   ├── notification_service.py
│   │   └── incident_service.py
│   └── tests/
│       ├── test_emergency.py
│       └── test_incident.py
├── dashboard/                    # Responder web dashboard
│   ├── index.html
│   ├── css/
│   │   └── dashboard.css
│   ├── js/
│   │   ├── dashboard.js
│   │   └── incident.js
│   └── assets/
└── docs/
    ├── api.md
    └── architecture.md
```

---

## 8. Development Phases

### Phase 1: Environment & Project Setup
- [~] Create Flutter project structure (lib/ exists but NO android/ dir — `flutter run` impossible)
- [x] Create backend project directory
- [x] Create dashboard directory
- [~] Set up `pubspec.yaml` with dependencies (uses `withValues(alpha:)` which requires Flutter 3.27+, but SDK range allows 3.0+)
- [x] Set up `requirements.txt` with Python dependencies
- [~] Create folder structure (missing: `backend/services/`, `backend/models/user.py`, `backend/models/sensor_event.py`, `backend/routes/location.py`, `docs/`, `mobile_app/android/`, `dashboard/assets/`)
- [ ] Verify builds — CANNOT BUILD: Flutter missing android/ platform dirs

### Phase 2: Flutter Mobile App — Home Dashboard
- [~] Create Home Dashboard screen (code exists, untested — cannot compile without android/ dir)
- [~] Add Protection Status display (code exists, untested)
- [~] Add Sensor Status cards (code exists, untested)
- [~] Add Current Status display (code exists, untested)
- [~] Add Emergency Status display (code exists, untested)
- [~] Add Test Emergency button (code exists, uses AnimatedBuilder — verified correct)
- [~] Basic navigation and theming (code exists, untested)
- [!] Missing: `settings_screen.dart` planned but never created

### Phase 3: Sensor System
- [~] Implement Accelerometer Service (code exists, untested on device)
- [~] Calculate acceleration magnitude (custom _sqrt — correct but unverified)
- [~] Implement Gyroscope Service (code exists, untested on device)
- [~] Implement GPS Service (code exists, untested on device)
- [~] Create Sensor Manager to coordinate all sensors (code exists, untested)
- [~] Display sensor status on home screen (code exists, untested)

### Phase 4: Sensor Fusion + Emergency Score
- [~] Create Sensor Fusion Engine (code exists, no unit tests)
- [~] Combine accelerometer, gyroscope, and GPS data (code exists, untested)
- [x] Create configurable thresholds system (thresholds.dart — clean, all values match plan)
- [~] Implement Emergency Scorer (code exists, no unit tests)
  - [~] Impact detection (threshold-based, code correct)
  - [~] Sudden speed change detection (code correct)
  - [~] Rotation detection (code correct)
  - [~] Post-impact inactivity detection (code correct)
  - [~] Movement pattern analysis (code correct)
- [~] Calculate combined emergency score (0–100) (weighted formula, code correct)

### Phase 5: Context Engine
- [~] Create Context Engine (code exists, no unit tests for classification logic)
- [~] Define activity classifications:
  - [~] Normal (walking, running) — code correct
  - [~] Suspicious (phone drop, sudden stop) — code correct
  - [~] Emergency (high impact + speed change + rotation + inactivity) — code correct
- [~] Map sensor patterns to activity classes (code correct)
- [~] Integrate with Emergency Score (code correct)

### Phase 6: Emergency Verification
- [~] Create verification overlay/screen (code exists, untested)
- [~] Show "POSSIBLE EMERGENCY DETECTED — Are you okay?" (emergency_screen.dart — correct)
- [~] Add "I'M OK" button (cancel emergency) (code correct)
- [~] Add "SEND ALERT" button (confirm emergency) (code correct)
- [~] Implement configurable timeout (30s, configurable in thresholds.dart)
- [~] Auto-confirm if no response within timeout (code correct)

### Phase 7: Life Replay
- [~] Create rolling buffer (last ~60 seconds of events) (code exists, no tests)
- [~] Store timestamped sensor summaries (code correct)
- [~] On emergency confirmation, preserve timeline (takeSnapshot exists but never called on confirm)
- [~] Create Life Replay data structure (ReplayEvent model correct)
- [~] Display timeline on home screen (life_replay_preview exists in home_screen)

### Phase 8: FastAPI Backend
- [~] Set up FastAPI application (main.py — code looks correct, untested)
- [~] Create `POST /emergency` endpoint (code exists, tests written)
- [~] Create `POST /location` endpoint (inline in emergency.py — uses raw dict, no Pydantic model)
- [~] Create `POST /incident` endpoint (code exists, tests written)
- [~] Create `GET /incident/{id}` endpoint (code exists, tests written)
- [~] Create `GET /incidents` endpoint (code exists, tests written)
- [~] Add validation and error handling (Pydantic models exist, error handling present)
- [~] Add logging and environment variables (config.py + .env exist)
- [~] Add API documentation (Swagger auto-generated by FastAPI)
- [!] Missing: `backend/services/notification_service.py`, `backend/services/incident_service.py`
- [!] Missing: `backend/__init__.py`, `backend/models/__init__.py`, `backend/routes/__init__.py` (needed for clean imports)

### Phase 9: MongoDB Database
- [~] Set up MongoDB connection (motor async — code correct, untested with real MongoDB)
- [ ] Create `users` collection (BLOCKED — requires auth system)
- [~] Create `incidents` collection (index defined in database.py, untested)
- [ ] Create `sensor_events` collection (BLOCKED — requires mobile integration)
- [ ] Create `emergency_contacts` collection (BLOCKED — requires contact management UI)
- [~] Define schemas/models (Pydantic models exist, untested)

### Phase 10: Emergency Notifications
- [~] Create notification service (mock — notification_service.dart + _send_notification in emergency.py)
- [~] Send notification on emergency confirmation (only prints to console, never actually called from mobile app)
- [~] Include location, time, severity, score, incident ID (mock output correct)
- [~] Mock responder endpoints (backend notification mock exists)

### Phase 11: Responder Dashboard
- [~] Create HTML/CSS/JS dashboard (index.html + dashboard.css + dashboard.js — code clean, untested)
- [~] Show active emergencies (renderIncidents + demo data fallback)
- [~] Display incident details (severity, speed, impact, score) (renderDetail exists)
- [~] Show location on Leaflet map (markers + popups implemented)
- [~] Show incident timeline/replay (timeline rendering exists)
- [~] Auto-refresh incident list (10s interval polling)
- [!] Missing: `dashboard/js/incident.js` (planned but never created)
- [!] Missing: `dashboard/assets/` directory (planned but never created)

### Phase 12: AI/ML (Post-MVP)
- [ ] Create dataset strategy
- [ ] Define features: acceleration, gyroscope, speed, speed change, rotation, duration
- [ ] Label activity classes: walking, running, cycling, driving, phone drop, sudden stop, accident
- [ ] Train classification model
- [ ] Evaluate model performance
- [ ] Investigate TensorFlow Lite for on-device inference

### Phase 13: Advanced Features (Post-MVP)
- [ ] Smart battery optimization
- [ ] Offline incident storage
- [ ] Store-and-forward sync
- [ ] SMS fallback
- [ ] Nearby emergency services
- [ ] Trusted contacts management
- [ ] Emergency severity levels
- [ ] AI incident summary
- [ ] Anonymous accident heatmap

---

## 9. Dependencies

### Flutter (pubspec.yaml)
- `sensors_plus` — Accelerometer & Gyroscope
- `geolocator` — GPS/Location
- `permission_handler` — Runtime permissions
- `http` — API communication
- `provider` or `riverpod` — State management

### Backend (requirements.txt)
- `fastapi` — Web framework
- `uvicorn` — ASGI server
- `motor` — Async MongoDB driver
- `pydantic` — Data validation
- `python-dotenv` — Environment variables
- `pymongo` — MongoDB driver

### Dashboard
- Leaflet.js — Maps
- Vanilla JS — No framework required for MVP

---

## 10. APIs

| Method | Endpoint            | Description                    |
|--------|---------------------|--------------------------------|
| POST   | `/emergency`        | Report an emergency event      |
| POST   | `/location`         | Update user location           |
| POST   | `/incident`         | Create a new incident          |
| GET    | `/incident/{id}`    | Get incident by ID             |
| GET    | `/incidents`        | List all incidents             |

---

## 11. Database Structure

### users
```json
{
  "_id": "ObjectId",
  "name": "string",
  "email": "string",
  "phone": "string",
  "emergency_contacts": ["ObjectId"],
  "created_at": "datetime",
  "updated_at": "datetime"
}
```

### incidents
```json
{
  "_id": "ObjectId",
  "incident_id": "string (UUID)",
  "user_id": "ObjectId",
  "location": {
    "latitude": "double",
    "longitude": "double"
  },
  "time": "datetime",
  "speed": "double",
  "impact": "double",
  "emergency_score": "integer",
  "severity": "string (LOW | MEDIUM | HIGH | CRITICAL)",
  "status": "string (DETECTED | CONFIRMED | RESPONDING | RESOLVED | FALSE_ALARM)",
  "timeline": "array of LifeReplayEvents",
  "created_at": "datetime"
}
```

### sensor_events
```json
{
  "_id": "ObjectId",
  "user_id": "ObjectId",
  "incident_id": "ObjectId (nullable)",
  "type": "string (ACCELEROMETER | GYROSCOPE | GPS)",
  "data": "object",
  "timestamp": "datetime"
}
```

### emergency_contacts
```json
{
  "_id": "ObjectId",
  "user_id": "ObjectId",
  "name": "string",
  "phone": "string",
  "email": "string",
  "relationship": "string",
  "is_primary": "boolean"
}
```

---

## 12. Sensor Processing Logic

### Accelerometer
- Collect X, Y, Z values + timestamp
- Calculate magnitude: `sqrt(x² + y² + z²)`
- Subtract gravity (~9.81) for net acceleration
- Track peak acceleration over sliding window

### Gyroscope
- Collect rotation X, Y, Z + timestamp
- Calculate angular velocity magnitude
- Detect rapid orientation changes

### GPS
- Collect latitude, longitude, speed, timestamp
- Calculate speed changes (delta speed)
- Track distance traveled

---

## 13. Emergency Detection Logic

### Thresholds (Configurable)
```dart
const EmergencyThresholds = {
  impactThreshold: 30.0,        // m/s² net acceleration
  speedChangeThreshold: 20.0,   // km/h sudden change
  rotationThreshold: 100.0,     // degrees/s
  inactivityDuration: 30,       // seconds of no movement
  emergencyScoreThreshold: 70,  // score out of 100
};
```

### Scoring Weights
```
Impact Score:          30% weight
Speed Change Score:    25% weight
Rotation Score:        20% weight
Post-Impact Inactivity: 15% weight
Movement Anomaly:      10% weight
```

### Classification
- **Score 0–30**: Normal
- **Score 31–60**: Suspicious
- **Score 61–100**: Emergency

---

## 14. Verification Logic

1. When emergency score exceeds threshold → trigger verification
2. Display verification overlay with countdown (configurable, default 30s)
3. User actions:
   - Press "I'M OK" → Cancel emergency
   - Press "SEND ALERT" → Confirm and trigger notification
4. Timeout with no response → Auto-confirm emergency
5. After confirmation → Create incident → Notify responders

---

## 15. Life Replay Design

### Rolling Buffer
- Maintain last ~60 seconds of sensor summaries
- Each entry: `{ timestamp, description, severity }`
- On emergency, snapshot the buffer

### Example Timeline
```
10:42:00  Normal movement
10:43:00  Movement detected
10:44:00  Speed increased
10:44:08  HIGH IMPACT detected (score: 85)
10:44:12  Sudden stop
10:44:40  No movement (possible unconsciousness)
```

---

## 16. Backend Architecture

### FastAPI Structure
```
backend/
├── main.py              # App entry point
├── config.py            # Settings & env vars
├── database.py          # MongoDB connection
├── models/              # Pydantic models
├── routes/              # API endpoints
├── services/            # Business logic
└── tests/               # Unit tests
```

### Key Patterns
- All requests validated with Pydantic
- Proper HTTP status codes (201, 400, 404, 500)
- Structured logging
- CORS configured for dashboard
- Environment variables for secrets

---

## 17. Responder Dashboard

### Features
- Real-time active emergency list
- Incident detail view with:
  - Severity level (color-coded)
  - Location on interactive map (Leaflet)
  - Speed, impact, emergency score
  - Incident timeline/replay
  - Status management

### Tech
- Single-page HTML/CSS/JS
- Leaflet.js for maps
- Fetch API for polling backend
- Responsive design

---

## 18. AI/ML Plan

### Phase: Post-MVP Only

1. **Dataset Strategy**
   - Simulated sensor data for training
   - Activity classes: Walking, Running, Cycling, Driving, Phone Drop, Sudden Stop, Accident

2. **Feature Extraction**
   - Acceleration magnitude & variance
   - Gyroscope magnitude & variance
   - Speed & speed change
   - Rotation rate
   - Movement duration

3. **Model**
   - Classification: Normal / Suspicious / Emergency
   - Start with simple model (Random Forest / SVM)
   - Graduate to neural network

4. **Deployment**
   - Export to TensorFlow Lite
   - On-device inference (after validation)

> **Note**: Do NOT claim ML model is accurate unless trained and evaluated.

---

## 19. Testing Plan

### Sensor Tests
- [ ] Normal movement produces normal readings
- [ ] High movement triggers high acceleration values
- [ ] Sudden stop produces deceleration spike
- [ ] Rotation changes detected by gyroscope
- [ ] GPS location updates correctly

### Detection Tests
- [ ] Normal activity classified as Normal
- [ ] Phone drop classified as Suspicious
- [ ] Running classified as Normal
- [ ] Possible accident classified as Emergency

### Verification Tests
- [ ] "I'm OK" cancels emergency
- [ ] "Send Alert" confirms emergency
- [ ] Timeout auto-confirms emergency

### Backend Tests
- [ ] Valid emergency creates incident
- [ ] Invalid request returns 400
- [ ] Missing location handled gracefully
- [ ] Database failure returns 500

### UI Tests
- [ ] Home screen displays correctly
- [ ] Emergency screen triggers on detection
- [ ] Dashboard loads and shows incidents
- [ ] Incident replay timeline displays

---

## 20. Security & Privacy

- [ ] No continuous audio/video recording
- [ ] No unnecessary personal data exposure
- [ ] Secrets in environment variables
- [ ] Secure communication (HTTPS in production)
- [ ] Backend request validation
- [ ] Minimize stored sensor data
- [ ] Clear separation of demo/mock vs. real services

---

## 21. Future / Advanced Features

- [ ] Smart battery optimization
- [ ] Offline incident storage
- [ ] Store-and-forward synchronization
- [ ] SMS fallback notifications
- [ ] Nearby emergency services lookup
- [ ] Trusted contacts management
- [ ] Emergency severity levels
- [ ] AI-powered incident summary
- [ ] Anonymous accident heatmap

---

## 22. Final Demo Flow

```
PHONE SENSORS
    ↓ (Accelerometer + Gyroscope + GPS)
SENSOR FUSION ENGINE
    ↓ (Combine all sensor data)
EMERGENCY SCORE CALCULATOR
    ↓ (Impact + Speed Change + Rotation + Inactivity)
CONTEXT ENGINE
    ↓ (Normal / Suspicious / Emergency)
EMERGENCY VERIFICATION
    ↓ (User confirmation or timeout)
EMERGENCY CONFIRMED
    ↓
LIFE REPLAY CAPTURE
    ↓ (Timeline of events)
BACKEND API
    ↓ (Create incident, store data)
RESPONDER DASHBOARD
    ↓ (Map, severity, timeline)
NOTIFICATION SERVICE
    ↓ (Alert responders/trusted contacts)
```

---

## How to Run

### Backend
```bash
cd backend
pip install -r requirements.txt
python main.py
```
Backend runs at `http://localhost:8000`
API docs at `http://localhost:8000/docs`

### Dashboard
Open `dashboard/index.html` in a browser.
Dashboard auto-connects to backend. Falls back to demo data if backend is offline.

### Mobile App
```bash
cd mobile_app
flutter pub get
flutter run
```
Requires Flutter SDK and Android/iOS device or emulator.

### Backend Tests
```bash
cd backend
pip install pytest
pytest tests/ -v
```

## Current Progress

> **AUDITED STATUS** — All 11 phases have code written, but NOTHING has been tested or verified.
> Flutter app CANNOT compile (missing `android/` platform directory).
> Backend tests exist but have NEVER been run.
> Dashboard exists but has never been opened in a browser.
> **Actual progress: ~40% (code exists, 0% tested)**
> 
> Next: Fix broken build → Run backend tests → Run Flutter → Then Phase 12.
