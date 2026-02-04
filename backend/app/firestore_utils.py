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
    
    # 🛠️ التعديل هنا: 
    # إذا كان الحقل موجوداً وقيمته None، أو إذا أردنا التأكد من حذفه عند النجاح
    if data.get("errorMessage") is None:
        # استخدام DELETE_FIELD يخبر فايربيس بحذف المفتاح تماماً من الـ Object
        data["errorMessage"] = firestore.DELETE_FIELD
    
    data["updatedAt"] = firestore.SERVER_TIMESTAMP
    _get_db().collection("farms").document(farm_id).set(data, merge=True)