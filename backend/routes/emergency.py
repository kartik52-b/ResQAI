from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse
from models.incident import (
    IncidentCreate,
    IncidentResponse,
    Location,
    LocationUpdate,
    Severity,
    IncidentStatus,
)
from database import incidents_collection
from pymongo.errors import DuplicateKeyError
from datetime import datetime
import uuid
import secrets

router = APIRouter()


def _generate_access_token() -> str:
    """Generate a secure, unpredictable access token for emergency links."""
    return secrets.token_urlsafe(16)  # 22-char URL-safe token


def _generate_incident_id() -> str:
    """Generate an 8-char incident ID, retrying on the (rare) collision."""
    return str(uuid.uuid4())[:8].upper()


@router.post("/emergency", response_model=dict)
async def report_emergency(event: IncidentCreate):
    """Report a new emergency event from the mobile app."""
    incident_id = _generate_incident_id()
    access_token = _generate_access_token()
    now = datetime.utcnow().isoformat()

    # Determine severity from score
    if event.emergency_score >= 85:
        severity = Severity.critical.value
    elif event.emergency_score >= 70:
        severity = Severity.high.value
    elif event.emergency_score >= 50:
        severity = Severity.medium.value
    else:
        severity = Severity.low.value

    doc = {
        "incident_id": incident_id,
        "access_token": access_token,
        "location": event.location.model_dump(),
        "time": now,
        "last_updated": now,
        "speed_kmh": event.speed_kmh,
        "impact_magnitude": event.impact_magnitude,
        "emergency_score": event.emergency_score,
        "severity": severity,
        "status": IncidentStatus.confirmed.value,
        "emergency_type": event.emergency_type,
        "timeline": [entry.model_dump() for entry in event.timeline],
        "created_at": now,
    }

    try:
        result = await incidents_collection.insert_one(doc)
    except DuplicateKeyError:
        # Rare: 8-char UUID prefix collision on incident_id/access_token.
        # Regenerate both and insert once more.
        incident_id = _generate_incident_id()
        doc["incident_id"] = incident_id
        access_token = _generate_access_token()
        doc["access_token"] = access_token
        result = await incidents_collection.insert_one(doc)

    # Send notification
    await _send_notification(doc)

    return {
        "status": "success",
        "incident_id": incident_id,
        "access_token": access_token,
        "message": f"Emergency reported. Incident {incident_id} created.",
        "severity": severity,
    }


@router.post("/location")
async def update_location(data: LocationUpdate):
    """Update the user's latest location (standalone endpoint).

    Called by the mobile app to push periodic location updates.
    """
    now = datetime.utcnow().isoformat()
    return {
        "status": "ok",
        "latitude": data.latitude,
        "longitude": data.longitude,
        "updated_at": now,
    }


@router.post("/incident/{incident_id}/location")
async def update_incident_location(incident_id: str, data: LocationUpdate):
    """Update the live location for an active emergency incident.

    Called periodically by the phone while the emergency is active.
    """
    now = datetime.utcnow().isoformat()

    update_fields = {
        "location.latitude": data.latitude,
        "location.longitude": data.longitude,
        "last_updated": now,
    }
    if data.accuracy is not None:
        update_fields["location.accuracy"] = data.accuracy
    if data.speed_kmh is not None:
        update_fields["speed_kmh"] = data.speed_kmh

    result = await incidents_collection.update_one(
        {"incident_id": incident_id},
        {"$set": update_fields},
    )

    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Incident not found")

    return {"status": "ok", "incident_id": incident_id, "updated_at": now}


@router.post("/incident/{incident_id}/resolve")
async def resolve_incident(incident_id: str):
    """Mark an incident as resolved (emergency cancelled)."""
    now = datetime.utcnow().isoformat()

    result = await incidents_collection.update_one(
        {"incident_id": incident_id},
        {"$set": {"status": IncidentStatus.resolved.value, "last_updated": now}},
    )

    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Incident not found")

    return {"status": "ok", "incident_id": incident_id, "incident_status": "RESOLVED"}


@router.get("/incident/{incident_id}")
async def get_incident(incident_id: str):
    """Get an incident by its ID (for dashboard)."""
    doc = await incidents_collection.find_one({"incident_id": incident_id})

    if not doc:
        raise HTTPException(status_code=404, detail="Incident not found")

    return {
        "id": str(doc["_id"]),
        "incident_id": doc["incident_id"],
        "access_token": doc.get("access_token", ""),
        "location": doc["location"],
        "time": doc["time"],
        "last_updated": doc.get("last_updated", doc["time"]),
        "speed_kmh": doc["speed_kmh"],
        "impact_magnitude": doc["impact_magnitude"],
        "emergency_score": doc["emergency_score"],
        "severity": doc["severity"],
        "status": doc["status"],
        "emergency_type": doc.get("emergency_type", "unknown"),
        "timeline": doc.get("timeline", []),
    }


@router.get("/incident/token/{access_token}")
async def get_incident_by_token(access_token: str):
    """Get an incident by its access token (for family emergency page).

    This is the public-facing endpoint used by the emergency link.
    Only returns location/status info — no personal data.
    """
    doc = await incidents_collection.find_one({"access_token": access_token})

    if not doc:
        raise HTTPException(status_code=404, detail="Incident not found or link expired")

    return {
        "incident_id": doc["incident_id"],
        "location": doc["location"],
        "time": doc["time"],
        "last_updated": doc.get("last_updated", doc["time"]),
        "speed_kmh": doc["speed_kmh"],
        "emergency_score": doc["emergency_score"],
        "severity": doc["severity"],
        "status": doc["status"],
        "emergency_type": doc.get("emergency_type", "unknown"),
    }


@router.get("/incidents")
async def list_incidents():
    """List all incidents, newest first."""
    cursor = incidents_collection.find().sort("created_at", -1).limit(50)
    incidents = []

    async for doc in cursor:
        incidents.append({
            "id": str(doc["_id"]),
            "incident_id": doc["incident_id"],
            "access_token": doc.get("access_token", ""),
            "location": doc["location"],
            "time": doc["time"],
            "last_updated": doc.get("last_updated", doc["time"]),
            "speed_kmh": doc["speed_kmh"],
            "impact_magnitude": doc["impact_magnitude"],
            "emergency_score": doc["emergency_score"],
            "severity": doc["severity"],
            "status": doc["status"],
            "emergency_type": doc.get("emergency_type", "unknown"),
            "timeline": doc.get("timeline", []),
        })

    return {
        "incidents": incidents,
        "total": len(incidents),
    }


# ======================================================================
# EMERGENCY FAMILY PAGE — Leaflet + OpenStreetMap
# ======================================================================

EMERGENCY_PAGE_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>ResQ AI — Emergency Location</title>
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0f1117;
            color: #e8eaed;
            min-height: 100vh;
            overflow-x: hidden;
        }

        /* Header */
        .header {
            background: linear-gradient(135deg, #dc2626, #ef4444);
            padding: 16px 20px;
            text-align: center;
            box-shadow: 0 4px 20px rgba(220, 38, 38, 0.4);
        }
        .header h1 { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
        .header .subtitle { font-size: 13px; opacity: 0.9; margin-top: 4px; }

        /* Status Banner */
        .status-banner {
            padding: 12px 20px;
            text-align: center;
            font-weight: 700;
            font-size: 14px;
            letter-spacing: 0.5px;
        }
        .status-banner.active {
            background: rgba(239, 68, 68, 0.15);
            color: #ef4444;
            border-bottom: 2px solid rgba(239, 68, 68, 0.3);
        }
        .status-banner.resolved {
            background: rgba(34, 197, 94, 0.15);
            color: #22c55e;
            border-bottom: 2px solid rgba(34, 197, 94, 0.3);
        }
        .status-banner.updating {
            background: rgba(245, 158, 11, 0.15);
            color: #f59e0b;
            border-bottom: 2px solid rgba(245, 158, 11, 0.3);
        }
        .status-banner.error {
            background: rgba(107, 114, 128, 0.15);
            color: #9ca3af;
            border-bottom: 2px solid rgba(107, 114, 128, 0.3);
        }
        .pulse-dot {
            display: inline-block;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #ef4444;
            margin-right: 8px;
            animation: pulse 1.5s ease-in-out infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.5; transform: scale(1.3); }
        }

        /* Map */
        #map {
            width: 100%;
            height: 45vh;
            min-height: 280px;
        }

        /* Info Panel */
        .info-panel {
            padding: 20px;
        }
        .info-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
            margin-bottom: 16px;
        }
        .info-card {
            background: #1a1d27;
            border-radius: 12px;
            padding: 14px;
            border: 1px solid #333845;
        }
        .info-card label {
            display: block;
            font-size: 11px;
            color: #9aa0a6;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 6px;
        }
        .info-card .value {
            font-size: 18px;
            font-weight: 700;
        }
        .info-card .value.red { color: #ef4444; }
        .info-card .value.orange { color: #f59e0b; }
        .info-card .value.green { color: #22c55e; }
        .info-card .value.blue { color: #3b82f6; }
        .info-card .value.small { font-size: 14px; }

        /* Location details */
        .location-card {
            background: #1a1d27;
            border-radius: 12px;
            padding: 16px;
            border: 1px solid #333845;
            margin-bottom: 16px;
        }
        .location-card h3 {
            font-size: 13px;
            color: #9aa0a6;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 12px;
        }
        .location-row {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #333845;
        }
        .location-row:last-child { border-bottom: none; }
        .location-row .label { color: #9aa0a6; font-size: 13px; }
        .location-row .data { font-size: 14px; font-weight: 600; }

        /* Google Maps link */
        .maps-link {
            display: block;
            background: #3b82f6;
            color: white;
            text-align: center;
            padding: 14px;
            border-radius: 12px;
            text-decoration: none;
            font-weight: 700;
            font-size: 15px;
            margin-bottom: 16px;
            transition: background 0.2s;
        }
        .maps-link:hover { background: #2563eb; }

        /* Update indicator */
        .update-indicator {
            text-align: center;
            padding: 12px;
            font-size: 12px;
            color: #9aa0a6;
        }
        .update-indicator .dot {
            display: inline-block;
            width: 6px;
            height: 6px;
            border-radius: 50%;
            margin-right: 6px;
            vertical-align: middle;
        }
        .update-indicator .dot.live { background: #22c55e; }
        .update-indicator .dot.stale { background: #ef4444; }

        /* Footer */
        .footer {
            text-align: center;
            padding: 20px;
            color: #6b7280;
            font-size: 12px;
            border-top: 1px solid #333845;
        }

        /* Loading */
        .loading {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            gap: 16px;
        }
        .spinner {
            width: 40px;
            height: 40px;
            border: 3px solid #333845;
            border-top: 3px solid #ef4444;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        /* Error */
        .error-page {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            gap: 16px;
            padding: 40px;
            text-align: center;
        }
        .error-page h2 { font-size: 24px; color: #ef4444; }
        .error-page p { color: #9aa0a6; font-size: 14px; }

        /* Responsive */
        @media (max-width: 600px) {
            .info-grid { grid-template-columns: 1fr; }
            #map { height: 40vh; min-height: 240px; }
        }
    </style>
</head>
<body>
    <div id="app">
        <div class="loading" id="loading">
            <div class="spinner"></div>
            <p>Loading emergency location...</p>
        </div>
    </div>

    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <script>
        // Incident token is injected by the server
        const ACCESS_TOKEN = 'TOKEN_PLACEHOLDER';
        const API_BASE = 'API_BASE_PLACEHOLDER';

        let map = null;
        let marker = null;
        let accuracyCircle = null;
        let lastKnownTime = null;
        let pollInterval = null;

        function formatTime(isoString) {
            if (!isoString) return 'Unknown';
            const d = new Date(isoString);
            return d.toLocaleTimeString();
        }

        function timeAgo(isoString) {
            if (!isoString) return 'Unknown';
            const diff = Math.floor((Date.now() - new Date(isoString).getTime()) / 1000);
            if (diff < 5) return 'just now';
            if (diff < 60) return diff + 's ago';
            if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
            return Math.floor(diff / 3600) + 'h ago';
        }

        function getEmergencyTypeLabel(type) {
            const types = {
                'speed_drop': '🚗 Speed Drop / Sudden Stop',
                'voice': '🗣️ Voice Emergency',
                'impact': '💥 Impact / Collision',
                'unknown': '⚠️ Emergency Detected',
            };
            return types[type] || types['unknown'];
        }

        function getStatusBannerClass(status) {
            if (status === 'RESOLVED') return 'resolved';
            return 'active';
        }

        function renderPage(data) {
            const lat = data.location?.latitude || 0;
            const lng = data.location?.longitude || 0;
            const accuracy = data.location?.accuracy;
            const mapsUrl = 'https://www.google.com/maps/search/?api=1&query=' + lat + ',' + lng;

            const statusBannerClass = getStatusBannerClass(data.status);
            const statusText = data.status === 'RESOLVED'
                ? '✅ EMERGENCY RESOLVED'
                : '🚨 EMERGENCY ACTIVE — ' + timeAgo(data.last_updated);

            document.getElementById('app').innerHTML = `
                <div class="header">
                    <h1>🛡️ RESQ AI</h1>
                    <div class="subtitle">Emergency Location Tracking</div>
                </div>

                <div class="status-banner ${statusBannerClass}" id="status-banner">
                    <span class="pulse-dot"></span>
                    ${statusText}
                </div>

                <div id="map"></div>

                <div class="info-panel">
                    <a href="${mapsUrl}" target="_blank" class="maps-link">
                        📍 Open in Google Maps
                    </a>

                    <div class="info-grid">
                        <div class="info-card">
                            <label>Emergency Type</label>
                            <div class="value orange">${getEmergencyTypeLabel(data.emergency_type)}</div>
                        </div>
                        <div class="info-card">
                            <label>Severity</label>
                            <div class="value red">${data.severity}</div>
                        </div>
                        <div class="info-card">
                            <label>Speed at Incident</label>
                            <div class="value">${(data.speed_kmh || 0).toFixed(1)} km/h</div>
                        </div>
                        <div class="info-card">
                            <label>Emergency Score</label>
                            <div class="value orange">${data.emergency_score}/100</div>
                        </div>
                    </div>

                    <div class="location-card">
                        <h3>📍 Current Location</h3>
                        <div class="location-row">
                            <span class="label">Latitude</span>
                            <span class="data" id="lat">${lat.toFixed(6)}</span>
                        </div>
                        <div class="location-row">
                            <span class="label">Longitude</span>
                            <span class="data" id="lng">${lng.toFixed(6)}</span>
                        </div>
                        <div class="location-row">
                            <span class="label">Accuracy</span>
                            <span class="data" id="accuracy">${accuracy ? accuracy.toFixed(1) + ' m' : 'Unknown'}</span>
                        </div>
                        <div class="location-row">
                            <span class="label">Emergency Time</span>
                            <span class="data">${formatTime(data.time)}</span>
                        </div>
                        <div class="location-row">
                            <span class="label">Last Updated</span>
                            <span class="data" id="last-updated">${timeAgo(data.last_updated)}</span>
                        </div>
                    </div>

                    <div class="update-indicator" id="update-indicator">
                        <span class="dot live" id="update-dot"></span>
                        <span id="update-text">Live location tracking active</span>
                    </div>

                    <div class="footer">
                        ResQ AI — Emergency Location System<br>
                        Powered by Leaflet + OpenStreetMap
                    </div>
                </div>
            `;

            initMap(lat, lng, accuracy);
            startPolling();
        }

        function initMap(lat, lng, accuracy) {
            map = L.map('map', {
                zoomControl: true,
                attributionControl: true,
            }).setView([lat, lng], 16);

            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '&copy; <a href="https://openstreetmap.org/copyright">OpenStreetMap</a> contributors',
                maxZoom: 19,
            }).addTo(map);

            // Emergency marker
            const emergencyIcon = L.divIcon({
                className: 'emergency-marker',
                html: '<div style="background:#ef4444;width:20px;height:20px;border-radius:50%;border:3px solid white;box-shadow:0 2px 8px rgba(0,0,0,0.4);"></div>',
                iconSize: [20, 20],
                iconAnchor: [10, 10],
            });

            marker = L.marker([lat, lng], { icon: emergencyIcon }).addTo(map);
            marker.bindPopup('<b>🚨 Emergency Location</b><br>Lat: ' + lat.toFixed(6) + '<br>Lng: ' + lng.toFixed(6)).openPopup();

            // Accuracy circle
            if (accuracy && accuracy > 0) {
                accuracyCircle = L.circle([lat, lng], {
                    radius: accuracy,
                    color: '#ef4444',
                    fillColor: '#ef4444',
                    fillOpacity: 0.1,
                    weight: 1,
                    dashArray: '5, 5',
                }).addTo(map);
            }

            setTimeout(() => map.invalidateSize(), 200);
        }

        function updateMapPosition(lat, lng, accuracy) {
            if (!map || !marker) return;

            marker.setLatLng([lat, lng]);
            marker.setPopupContent('<b>🚨 Emergency Location</b><br>Lat: ' + lat.toFixed(6) + '<br>Lng: ' + lng.toFixed(6));

            if (accuracyCircle) {
                accuracyCircle.setLatLng([lat, lng]);
                if (accuracy) accuracyCircle.setRadius(accuracy);
            }

            // Don't re-center if user has panned away
            // Only center on first load or if they haven't interacted
        }

        function startPolling() {
            if (pollInterval) clearInterval(pollInterval);
            pollInterval = setInterval(fetchIncidentData, 5000);
        }

        async function fetchIncidentData() {
            try {
                const response = await fetch(API_BASE + '/incident/token/' + ACCESS_TOKEN);
                if (!response.ok) throw new Error('Not found');
                const data = await response.json();

                // Update location
                const lat = data.location?.latitude || 0;
                const lng = data.location?.longitude || 0;
                const accuracy = data.location?.accuracy;

                if (lat !== 0 && lng !== 0) {
                    updateMapPosition(lat, lng, accuracy);
                    document.getElementById('lat').textContent = lat.toFixed(6);
                    document.getElementById('lng').textContent = lng.toFixed(6);
                    document.getElementById('accuracy').textContent = accuracy ? accuracy.toFixed(1) + ' m' : 'Unknown';
                    document.getElementById('last-updated').textContent = timeAgo(data.last_updated);

                    // Update status
                    const banner = document.getElementById('status-banner');
                    if (data.status === 'RESOLVED') {
                        banner.className = 'status-banner resolved';
                        banner.innerHTML = '✅ EMERGENCY RESOLVED';
                    } else {
                        banner.className = 'status-banner active';
                        banner.innerHTML = '<span class="pulse-dot"></span>🚨 EMERGENCY ACTIVE — ' + timeAgo(data.last_updated);
                    }

                    // Update indicator
                    const dot = document.getElementById('update-dot');
                    const text = document.getElementById('update-text');
                    const diff = Math.floor((Date.now() - new Date(data.last_updated).getTime()) / 1000);
                    if (diff < 30) {
                        dot.className = 'dot live';
                        text.textContent = 'Live location tracking active';
                    } else {
                        dot.className = 'dot stale';
                        text.textContent = 'Location update stale — last ' + timeAgo(data.last_updated);
                    }
                }
            } catch (err) {
                console.error('Poll failed:', err);
                const dot = document.getElementById('update-dot');
                const text = document.getElementById('update-text');
                if (dot && text) {
                    dot.className = 'dot stale';
                    text.textContent = 'Unable to update emergency location';
                }
            }
        }

        // Initial load: fetch the incident, then render the full page.
        // BUGFIX: previously only fetchIncidentData() was called, but the page
        // shell (map + info cards) is created by renderPage(), so the page
        // stayed on the loading spinner forever. Now the first successful
        // fetch renders the page, then polling keeps it updated.
        (async function init() {
            try {
                const response = await fetch(API_BASE + '/incident/token/' + ACCESS_TOKEN);
                if (!response.ok) throw new Error('Not found');
                const data = await response.json();
                renderPage(data);
            } catch (err) {
                console.error('Initial load failed:', err);
                document.getElementById('app').innerHTML = `
                    <div class="error-page">
                        <h2>Unable to load emergency location</h2>
                        <p>The emergency data could not be fetched.<br>Please refresh the page and try again.</p>
                    </div>
                `;
            }
        })();
    </script>
</body>
</html>"""


@router.get("/emergency/{access_token}", response_class=HTMLResponse)
async def emergency_family_page(access_token: str):
    """Serve the Leaflet + OpenStreetMap emergency location page.

    Family members open this URL from the SMS link.
    The page polls the backend for live location updates.
    """
    # Verify the token exists
    doc = await incidents_collection.find_one({"access_token": access_token})
    if not doc:
        return HTMLResponse(
            content="""<!DOCTYPE html>
<html><head><title>ResQ AI</title>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>body{font-family:sans-serif;background:#0f1117;color:#e8eaed;display:flex;align-items:center;justify-content:center;height:100vh;text-align:center;padding:40px;}</style>
</head><body>
<div><h1 style="color:#ef4444">Incident Not Found</h1>
<p style="color:#9ca3af;margin-top:16px">This emergency link is invalid or has expired.</p></div>
</body></html>""",
            status_code=404,
        )

    html = EMERGENCY_PAGE_HTML.replace("TOKEN_PLACEHOLDER", access_token)
    html = html.replace("API_BASE_PLACEHOLDER", "")

    return HTMLResponse(content=html)


async def _send_notification(incident_doc: dict):
    """Notification service — logs the emergency."""
    print(f"\n{'='*50}")
    print(f"EMERGENCY NOTIFICATION")
    print(f"Incident: {incident_doc['incident_id']}")
    print(f"Access Token: {incident_doc.get('access_token', 'N/A')}")
    print(f"Emergency Page: /emergency/{incident_doc.get('access_token', '')}")
    print(f"Location: {incident_doc['location']}")
    print(f"Score: {incident_doc['emergency_score']}")
    print(f"Severity: {incident_doc['severity']}")
    print(f"Time: {incident_doc['time']}")
    print(f"{'='*50}\n")
