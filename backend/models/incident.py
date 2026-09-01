from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from enum import Enum


class Severity(str, Enum):
    low = "LOW"
    medium = "MEDIUM"
    high = "HIGH"
    critical = "CRITICAL"


class IncidentStatus(str, Enum):
    detected = "DETECTED"
    confirmed = "CONFIRMED"
    responding = "RESPONDING"
    resolved = "RESOLVED"
    false_alarm = "FALSE_ALARM"


class Location(BaseModel):
    latitude: float
    longitude: float
    accuracy: Optional[float] = None  # GPS accuracy in meters


class TimelineEntry(BaseModel):
    timestamp: str
    description: str
    activity_type: str = "unknown"
    score: int = 0


class IncidentCreate(BaseModel):
    location: Location
    speed_kmh: float = 0.0
    impact_magnitude: float = 0.0
    emergency_score: int = 0
    severity: str = "LOW"
    emergency_type: str = "unknown"  # speed_drop, voice, impact, etc.
    timeline: List[TimelineEntry] = []


class LocationUpdate(BaseModel):
    latitude: float
    longitude: float
    accuracy: Optional[float] = None
    speed_kmh: Optional[float] = None


class IncidentResponse(BaseModel):
    id: str
    incident_id: str
    access_token: str
    user_id: Optional[str] = None
    location: Location
    time: str
    speed_kmh: float
    impact_magnitude: float
    emergency_score: int
    severity: str
    status: str
    emergency_type: str
    last_updated: Optional[str] = None
    timeline: List[TimelineEntry]


class IncidentListResponse(BaseModel):
    incidents: List[IncidentResponse]
    total: int
