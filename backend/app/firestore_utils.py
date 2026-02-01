from typing import Optional, Dict, Any
from google.cloud import firestore

#test
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
    if "errorMessage" not in data:
        data["errorMessage"] = None
    data["updatedAt"] = firestore.SERVER_TIMESTAMP
    _get_db().collection("farms").document(farm_id).set(data, merge=True)