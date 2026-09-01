import motor.motor_asyncio
from config import settings

# Async MongoDB client
client = motor.motor_asyncio.AsyncIOMotorClient(settings.MONGODB_URL)
db = client[settings.DATABASE_NAME]

# Collections
users_collection = db["users"]
incidents_collection = db["incidents"]
sensor_events_collection = db["sensor_events"]
emergency_contacts_collection = db["emergency_contacts"]


async def init_db():
    """Initialize database indexes."""
    await incidents_collection.create_index("incident_id", unique=True)
    await incidents_collection.create_index("access_token", unique=True)
    await incidents_collection.create_index("user_id")
    await incidents_collection.create_index("status")
    await sensor_events_collection.create_index("user_id")
    await sensor_events_collection.create_index("incident_id")
    await users_collection.create_index("email", unique=True, sparse=True)


async def close_db():
    """Close database connection."""
    client.close()
