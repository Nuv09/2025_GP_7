from typing import Optional, Dict, Any
from google.cloud import firestore


_db = None

def _get_db():
    global _db
    if _db is None:
        _db = firestore.Client()
    return _db

def get_farm_doc(farm_id: str) -> Optional[Dict[str, Any]]:
    doc = _get_db().collection("farms").document(farm_id).get()
    if not doc.exists:
        return None
    return doc.to_dict()

def set_status(farm_id: str, **data):
    data.setdefault("status", "pending")
    

    fields_to_clean = ["errorMessage", "imagePath", "imageURL"]
    
    for field in fields_to_clean:

        if data.get(field) is None:
            data[field] = firestore.DELETE_FIELD
    
    data["updatedAt"] = firestore.SERVER_TIMESTAMP
    _get_db().collection("farms").document(farm_id).set(data, merge=True)


def set_alerts_and_recommendations(farm_id: str, alerts: list, recommendations: list):
    db = firestore.Client()
    db.collection("farms").document(farm_id).set({
        "alerts": alerts,
        "recommendations": recommendations,
        "alertsUpdatedAt": firestore.SERVER_TIMESTAMP,
        "hasUnreadAlerts": True if alerts else False,
    }, merge=True)
