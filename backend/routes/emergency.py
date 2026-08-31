from fastapi import APIRouter, HTTPException
from models.incident import (
    IncidentCreate,
    IncidentResponse,
    Location,
    Severity,
    IncidentStatus,
)
from database import incidents_collection
from datetime import datetime
import uuid

router = APIRouter()


@router.post("/emergency", response_model=dict)
async def report_emergency(event: IncidentCreate):
    """Report a new emergency event from the mobile app."""
    incident_id = str(uuid.uuid4())[:8].upper()
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
        "location": event.location.model_dump(),
        "time": now,
        "speed_kmh": event.speed_kmh,
        "impact_magnitude": event.impact_magnitude,
        "emergency_score": event.emergency_score,
        "severity": severity,
        "status": IncidentStatus.confirmed.value,
        "timeline": [entry.model_dump() for entry in event.timeline],
        "created_at": now,
    }

    result = await incidents_collection.insert_one(doc)

    # Send notification (mock)
    await _send_notification(doc)

    return {
        "status": "success",
        "incident_id": incident_id,
        "message": f"Emergency reported. Incident {incident_id} created.",
        "severity": severity,
    }


@router.post("/location")
async def update_location(data: dict):
    """Update user location (called periodically from mobile app)."""
    lat = data.get("latitude")
    lng = data.get("longitude")
    speed = data.get("speed", 0)

    if lat is None or lng is None:
        raise HTTPException(status_code=400, detail="latitude and longitude required")

    return {
        "status": "ok",
        "received": {"latitude": lat, "longitude": lng, "speed": speed},
    }


async def _send_notification(incident_doc: dict):
    """Mock notification service."""
    print(f"\n{'='*50}")
    print(f"EMERGENCY NOTIFICATION")
    print(f"Incident: {incident_doc['incident_id']}")
    print(f"Location: {incident_doc['location']}")
    print(f"Score: {incident_doc['emergency_score']}")
    print(f"Severity: {incident_doc['severity']}")
    print(f"Time: {incident_doc['time']}")
    print(f"{'='*50}\n")
