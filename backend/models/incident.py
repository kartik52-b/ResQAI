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
    timeline: List[TimelineEntry] = []


class IncidentResponse(BaseModel):
    id: str
    incident_id: str
    user_id: Optional[str] = None
    location: Location
    time: str
    speed_kmh: float
    impact_magnitude: float
    emergency_score: int
    severity: str
    status: str
    timeline: List[TimelineEntry]


class IncidentListResponse(BaseModel):
    incidents: List[IncidentResponse]
    total: int
