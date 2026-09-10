"""
ResQ AI Backend Tests
Run with: pytest tests/ -v
"""
import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, patch


# Mock the database before importing app
@pytest.fixture(autouse=True)
def mock_db():
    """Mock MongoDB for testing.

    ``find()`` must return a cursor-like chain (find → sort → limit) whose
    result supports ``async for`` — an AsyncMock here returns a coroutine,
    which breaks ``list_incidents``.
    """

    class FakeAsyncCursor:
        """Minimal motor-style cursor supporting sort/limit and async iteration."""

        def __init__(self, docs=None):
            self._docs = docs or []

        def sort(self, *args, **kwargs):
            return self

        def limit(self, *args, **kwargs):
            return self

        def __aiter__(self):
            return self

        async def __anext__(self):
            if not self._docs:
                raise StopAsyncIteration
            return self._docs.pop(0)

    with patch("database.incidents_collection") as mock_collection:
        mock_collection.find.return_value = FakeAsyncCursor()
        mock_collection.insert_one = AsyncMock(
            return_value=AsyncMock(inserted_id="test_id")
        )
        mock_collection.find_one = AsyncMock(return_value=None)
        mock_collection.update_one = AsyncMock(
            return_value=AsyncMock(matched_count=0)
        )
        mock_collection.create_index = AsyncMock()
        yield mock_collection


@pytest.fixture
def client():
    """Create test client."""
    from main import app
    return TestClient(app)


def test_root(client):
    """Test root endpoint."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "ResQ AI Backend"
    assert data["status"] == "running"


def test_health(client):
    """Test health endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_report_emergency(client):
    """Test emergency report endpoint."""
    payload = {
        "location": {"latitude": 28.6139, "longitude": 77.2090},
        "speed_kmh": 45.0,
        "impact_magnitude": 52.3,
        "emergency_score": 85,
        "timeline": [
            {"timestamp": "2024-01-01T10:00:00", "description": "Impact detected"}
        ],
    }
    response = client.post("/emergency", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert "incident_id" in data
    assert data["severity"] == "CRITICAL"


def test_report_emergency_low_score(client):
    """Test emergency with low score."""
    payload = {
        "location": {"latitude": 28.6139, "longitude": 77.2090},
        "speed_kmh": 10.0,
        "impact_magnitude": 15.0,
        "emergency_score": 25,
    }
    response = client.post("/emergency", json=payload)
    assert response.status_code == 200
    assert response.json()["severity"] == "LOW"


def test_update_location(client):
    """Test location update endpoint."""
    payload = {
        "latitude": 28.6139,
        "longitude": 77.2090,
        "speed": 5.0,
    }
    response = client.post("/location", json=payload)
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_update_location_missing_fields(client):
    """Test location update with missing fields."""
    payload = {"speed": 5.0}
    response = client.post("/location", json=payload)
    assert response.status_code == 400


def test_create_incident(client):
    """Test incident creation."""
    payload = {
        "location": {"latitude": 28.6139, "longitude": 77.2090},
        "speed_kmh": 60.0,
        "impact_magnitude": 45.0,
        "emergency_score": 75,
    }
    response = client.post("/incident", json=payload)
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "created"
    assert "incident_id" in data


def test_get_incident_not_found(client):
    """Test getting non-existent incident."""
    response = client.get("/incident/NONEXISTENT")
    assert response.status_code == 404


def test_list_incidents(client):
    """Test listing incidents."""
    response = client.get("/incidents")
    assert response.status_code == 200
    assert "incidents" in response.json()
