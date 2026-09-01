# ResQ AI — Real-Time Personal Emergency Safety System

> **A smart emergency detection app that uses phone sensors (GPS, accelerometer, gyroscope) to automatically detect accidents and alert trusted contacts with live GPS location.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-blue)](https://dart.dev)
[![Kotlin](https://img.shields.io/badge/Kotlin-Android-purple)](https://kotlinlang.org)
[![Python](https://img.shields.io/badge/Python-FastAPI-green)](https://fastapi.tiangolo.com)

---

## The Problem

Every year, millions of road accidents go undetected. The victim may be **unconscious, injured, or unable to call for help**. Delayed emergency response is a leading cause of preventable deaths after road accidents — especially for solo riders and drivers.

## The Solution

ResQ AI uses the sensors already present in every modern smartphone to **automatically detect sudden deceleration, impact, and post-event inactivity** that may indicate an accident. When detected, it:

1. Asks **"Are you alright?"** via voice and on-screen prompt
2. Waits for a response (configurable timeout)
3. If no response → sends **real SMS with GPS location** to all trusted contacts
4. **Automatically calls** the primary trusted contact
5. Creates an **emergency incident** with live tracking via Leaflet + OpenStreetMap

---

## Key Features

| Feature | Description |
|---------|-------------|
| **Multi-Sensor Detection** | GPS speed drop + accelerometer impact + gyroscope rotation |
| **Smart False-Positive Prevention** | Normal braking, traffic lights, parking do NOT trigger alerts |
| **Voice Verification** | Speaks "Are you alright?" and listens for voice response |
| **Manual Confirmation** | "I'M OK" / "I NEED HELP" buttons |
| **Auto Emergency** | Configurable timeout (120s default) — no response = auto-confirm |
| **SMS to All Contacts** | Real GPS coordinates + Google Maps link |
| **Phone Call to Primary** | Automatic call to the designated primary contact |
| **Live Location Tracking** | Leaflet + OpenStreetMap emergency page for family |
| **Background Monitoring** | Android foreground service for continuous sensor monitoring |
| **Voice Emergency Detection** | Detects "help", "bachao", "madad" etc. via microphone |
| **Backend + Dashboard** | FastAPI backend with MongoDB + web dashboard |
| **Developer Test Mode** | Safe simulation for demos and testing |

---

## Architecture

```
Phone Sensors (GPS + Accelerometer + Gyroscope)
        ↓
  Sensor Manager (10Hz fusion timer)
        ↓
  GPS Filtering (accuracy validation → ground speed → rolling median → EMA)
        ↓
  Sensor Fusion + Movement Classification
        ↓
  Accident Detector (multi-sensor state machine)
        ↓
  Emergency Orchestrator
        ↓
  ┌─────────────────────────────────────────┐
  │  TTS: "Are you alright?"               │
  │  Voice: Listen for response            │
  │  UI:  I'M OK / I NEED HELP             │
  │  Countdown: 120s timeout               │
  └─────────────────────────────────────────┘
        ↓
  Emergency Actions:
  ├── SMS to ALL trusted contacts (with GPS location + Leaflet map link)
  ├── Call PRIMARY trusted contact
  ├── Backend incident report
  ├── Live location tracking (8s updates)
  └── Emergency notification
```

### Accident Detection State Machine

```
IDLE → NORMAL_MOVING → SUDDEN_DECELERATION → POSSIBLE_IMPACT
          ↓                                         ↓
    (speed > 15 km/h)                    (accel > 15 m/s² or
                                          gyro > 80 deg/s)
                                                 ↓
                                    POST_EVENT_INACTIVITY (6s)
                                                 ↓
                                            VERIFYING
```

**PATH B (Fall Detection):** Severe impact (≥40 m/s² ≈ 4g) or extreme rotation (≥150 deg/s) at any speed triggers possible impact directly.

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Mobile App** | Flutter / Dart | Cross-platform UI, sensor access, state management |
| **Android Native** | Kotlin | Foreground service, SMS, phone calls, notifications |
| **GPS** | Geolocator 10.1 | Real-time location with accuracy filtering |
| **Sensors** | sensors_plus 6.0 | Accelerometer + gyroscope data |
| **State** | Provider 6.1 | Reactive state management |
| **Backend** | Python FastAPI | REST API, incident management, emergency pages |
| **Database** | MongoDB (motor 3.3) | Async incident storage |
| **Dashboard** | HTML5 + Leaflet.js | Responder dashboard with live maps |
| **Emergency Map** | Leaflet + OpenStreetMap | Family emergency location page (no API key needed) |
| **SMS** | Android SmsManager | Real SMS delivery to trusted contacts |
| **Calls** | Android Intent.ACTION_CALL | Primary contact calling |
| **Speech** | Android SpeechRecognizer + TTS | Voice verification + emergency phrase detection |

---

## Project Structure

```
SIH/
├── backend/                    # Python FastAPI backend
│   ├── main.py                 # FastAPI application entry
│   ├── config.py               # Environment-based configuration
│   ├── database.py             # MongoDB connection (motor)
│   ├── models/
│   │   └── incident.py         # Incident data models
│   ├── routes/
│   │   ├── emergency.py        # Emergency API + Leaflet map page
│   │   └── incident.py         # Incident CRUD endpoints
│   ├── tests/
│   │   └── test_emergency.py   # Backend API tests
│   ├── requirements.txt        # Python dependencies
│   └── .env.example            # Environment variables template
│
├── dashboard/                  # Responder web dashboard
│   ├── index.html              # Dashboard UI
│   ├── css/dashboard.css       # Styles
│   └── js/dashboard.js         # Dashboard logic + Leaflet maps
│
├── mobile_app/                 # Flutter mobile application
│   ├── lib/
│   │   ├── main.dart           # App entry point
│   │   ├── config/
│   │   │   └── thresholds.dart # Detection thresholds (configurable)
│   │   ├── engine/             # Core detection algorithms
│   │   │   ├── accident_detector.dart
│   │   │   ├── speed_drop_detector.dart
│   │   │   ├── sensor_fusion.dart
│   │   │   ├── movement_classifier.dart
│   │   │   ├── emergency_scorer.dart
│   │   │   ├── context_engine.dart
│   │   │   ├── verification_system.dart
│   │   │   └── life_replay.dart
│   │   ├── models/
│   │   │   ├── sensor_data.dart
│   │   │   ├── emergency_event.dart
│   │   │   └── trusted_contact.dart
│   │   ├── screens/            # UI screens
│   │   │   ├── home_screen.dart
│   │   │   ├── monitoring_screen.dart
│   │   │   ├── emergency_screen.dart
│   │   │   ├── contacts_screen.dart
│   │   │   └── app_shell.dart
│   │   ├── sensors/            # Hardware interfaces
│   │   │   ├── gps_service.dart
│   │   │   ├── sensor_manager.dart
│   │   │   ├── accelerometer_service.dart
│   │   │   └── gyroscope_service.dart
│   │   ├── services/           # Application services
│   │   │   ├── safety_monitor_service.dart
│   │   │   ├── emergency_orchestrator.dart
│   │   │   ├── native_service_bridge.dart
│   │   │   ├── sms_service.dart
│   │   │   ├── contact_service.dart
│   │   │   ├── api_service.dart
│   │   │   ├── voice_emergency_detector.dart
│   │   │   └── voice_alert_service.dart
│   │   └── widgets/            # Reusable UI components
│   │       ├── protection_toggle.dart
│   │       ├── sensor_status_card.dart
│   │       └── emergency_button.dart
│   ├── android/                # Android native code
│   │   └── app/src/main/
│   │       ├── AndroidManifest.xml
│   │       └── kotlin/com/example/resq_ai/
│   │           ├── MainActivity.kt
│   │           └── ResQMonitoringService.kt
│   ├── test/                   # 101 automated unit tests
│   ├── pubspec.yaml
│   └── analysis_options.yaml
│
├── .gitignore
├── README.md
├── plan.md
├── FINAL_AUDIT_REPORT.md
└── FINAL_HANDOVER_REPORT.md
```

---

## Getting Started

### Prerequisites

- **Flutter SDK** ≥ 3.0.0 (with Dart ≥ 3.0.0)
- **Android Studio** or VS Code with Flutter plugin
- **Android device** with USB debugging enabled
- **Python 3.9+** (for backend)
- **MongoDB** (for backend)

### Run the Mobile App

```bash
cd mobile_app

# Install dependencies
flutter pub get

# Run on connected Android device
flutter run -d <device-id>

# Build release APK
flutter build apk --release
```

The APK is output to `mobile_app/build/app/outputs/flutter-apk/app-release.apk`.

### Run the Backend (Optional)

```bash
cd backend

# Install Python dependencies
pip install -r requirements.txt

# Copy and configure environment variables
cp .env.example .env
# Edit .env with your MongoDB URL, etc.

# Start the server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Run the Dashboard

```bash
cd dashboard
# Open index.html in a browser, or serve with any static file server
python -m http.server 8080
```

---

## Environment Variables

Create a `backend/.env` file (never commit this file):

```env
# Backend Configuration
DEBUG=true
MONGODB_URL=mongodb://localhost:27017
DATABASE_NAME=resq_ai
HOST=0.0.0.0
PORT=8000
ALLOWED_ORIGINS=*

# Google Gemini API Key (optional — for future AI features)
GEMINI_API_KEY=your_key_here
```

---

## How to Test

### Safe Demo for Judges

1. Open ResQ AI → go to **Monitoring** tab
2. Enable **Demo Mode** (15-second timeout)
3. Enable **Test Mode**
4. Tap **Driving 60** preset → shows 60 km/h
5. Tap **Sudden Stop** → triggers accident detection
6. **"ARE YOU ALRIGHT?"** appears with countdown
7. Tap **I'M OK** → cancelled
8. Repeat → tap **I NEED HELP** → emergency workflow starts

### Available Test Presets

| Preset | Speed | Impact | Rotation | Triggers Emergency |
|--------|-------|--------|----------|-------------------|
| Walking | 4 km/h | 1.5 m/s² | 10 deg/s | ❌ No |
| Cycling | 20 km/h | 2 m/s² | 25 deg/s | ❌ No |
| Driving 60 | 60 km/h | 3 m/s² | 15 deg/s | ❌ No |
| Stationary | 0 km/h | 0.5 m/s² | 2 deg/s | ❌ No |
| **Sudden Stop** | 60 km/h | 40 m/s² | 90 deg/s | ✅ Yes |
| **Impact Only** | 0 km/h | 80 m/s² | 120 deg/s | ✅ Yes (PATH B) |
| **Fall (walk)** | 4 km/h | 25 m/s² | 85 deg/s | ✅ Yes (PATH B) |
| **Crash 80** | 80 km/h | 60 m/s² | 200 deg/s | ✅ Yes |

### Real Device Testing

1. Install APK on Android phone
2. Enable **Protection** → confirm GPS becomes ACTIVE
3. Go outdoors for accurate GPS
4. Walk/ride to verify speed display
5. Use Test Mode presets for emergency flow verification

---

## Permissions

The app requests these permissions at runtime:

| Permission | Purpose | Required |
|-----------|---------|----------|
| `ACCESS_FINE_LOCATION` | GPS speed + coordinates | Yes |
| `ACCESS_COARSE_LOCATION` | Fallback location | Yes |
| `ACCESS_BACKGROUND_LOCATION` | Monitoring when app is minimized | Yes |
| `FOREGROUND_SERVICE_LOCATION` | Background GPS service | Yes |
| `FOREGROUND_SERVICE_MICROPHONE` | Background voice detection | Yes (when voice enabled) |
| `RECORD_AUDIO` | Voice emergency detection | When voice enabled |
| `SEND_SMS` | Emergency SMS to contacts | Yes |
| `CALL_PHONE` | Call primary trusted contact | Yes |
| `POST_NOTIFICATIONS` | Emergency notifications (Android 13+) | Yes |
| `INTERNET` | Backend communication | Yes |

---

## Testing

Run the automated test suite:

```bash
cd mobile_app
flutter test
```

**101 unit tests** covering:
- Sensor data models
- GPS service and filtering
- Accident detection state machine
- Speed drop detection
- Movement classification
- Sensor fusion
- Emergency scoring
- Threshold configuration
- Emergency flow (SMS, contacts, orchestration)

---

## Known Limitations

| Limitation | Explanation |
|-----------|-------------|
| **Background sensor processing** | Flutter Dart timers may be suspended when fully backgrounded. The foreground service keeps the process alive; GPS continues through native Geolocator. |
| **GPS accuracy** | Indoor/urban environments have degraded GPS. App requires outdoor GPS fix for accurate speed. |
| **Speech recognition** | Android `SpeechRecognizer` only works while the Activity is visible. Background voice detection is limited by Android OS. |
| **Battery** | Continuous GPS + sensor monitoring consumes battery. Uses partial wake lock while active. |
| **Backend optional** | SMS and phone calls work independently of the backend server. |

---

## License

Developed for **Smart India Hackathon (SIH)**.

---

## Authors

Built with ❤️ by the ResQ AI team.
