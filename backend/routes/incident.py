from fastapi import APIRouter, HTTPException
from models.incident import (
    IncidentCreate,
    IncidentResponse,
    IncidentListResponse,
    Location,
    IncidentStatus,
)
from database import incidents_collection
from datetime import datetime
import uuid

router = APIRouter()


@router.post("/incident", response_model=dict, status_code=201)
async def create_incident(incident: IncidentCreate):
    """Create a new incident record."""
    incident_id = str(uuid.uuid4())[:8].upper()
    now = datetime.utcnow().isoformat()

    if incident.emergency_score >= 85:
        severity = "CRITICAL"
    elif incident.emergency_score >= 70:
        severity = "HIGH"
    elif incident.emergency_score >= 50:
        severity = "MEDIUM"
    else:
        severity = "LOW"

    doc = {
        "incident_id": incident_id,
        "location": incident.location.model_dump(),
        "time": now,
        "speed_kmh": incident.speed_kmh,
        "impact_magnitude": incident.impact_magnitude,
        "emergency_score": incident.emergency_score,
        "severity": severity,
        "status": IncidentStatus.detected.value,
        "timeline": [entry.model_dump() for entry in incident.timeline],
        "created_at": now,
    }

    result = await incidents_collection.insert_one(doc)

    return {
        "status": "created",
        "incident_id": incident_id,
        "id": str(result.inserted_id),
    }


@router.get("/incident/{incident_id}", response_model=dict)
async def get_incident(incident_id: str):
    """Get an incident by its ID."""
    doc = await incidents_collection.find_one({"incident_id": incident_id})

    if not doc:
        raise HTTPException(status_code=404, detail="Incident not found")

    return {
        "id": str(doc["_id"]),
        "incident_id": doc["incident_id"],
        "location": doc["location"],
        "time": doc["time"],
        "speed_kmh": doc["speed_kmh"],
        "impact_magnitude": doc["impact_magnitude"],
        "emergency_score": doc["emergency_score"],
        "severity": doc["severity"],
        "status": doc["status"],
        "timeline": doc.get("timeline", []),
    }


@router.get("/incidents", response_model=dict)
async def list_incidents():
    """List all incidents, newest first."""
    cursor = incidents_collection.find().sort("created_at", -1).limit(50)
    incidents = []

    async for doc in cursor:
        incidents.append({
            "id": str(doc["_id"]),
            "incident_id": doc["incident_id"],
            "location": doc["location"],
            "time": doc["time"],
            "speed_kmh": doc["speed_kmh"],
            "impact_magnitude": doc["impact_magnitude"],
            "emergency_score": doc["emergency_score"],
            "severity": doc["severity"],
            "status": doc["status"],
            "timeline": doc.get("timeline", []),
        })

    return {
        "incidents": incidents,
        "total": len(incidents),
    }
