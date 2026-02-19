from typing import Optional, Dict, Any, List
from google.cloud import firestore
from google.api_core.exceptions import AlreadyExists


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


def set_alerts_and_recommendations(
    farm_id: str,
    alerts: List[Dict[str, Any]],
    recommendations: List[Dict[str, Any]],
):
    db = _get_db()

    # 1) حفظ نفس الشي داخل farms (زي قبل)
    db.collection("farms").document(farm_id).set(
        {
            "alerts": alerts,
            "recommendations": recommendations,
            "alertsUpdatedAt": firestore.SERVER_TIMESTAMP,
            "hasUnreadAlerts": True if alerts else False,
        },
        merge=True,
    )

    # 2) NEW: اكتب alerts داخل collection('notifications')
    # عشان notifications_page.dart يقدر يقرأها
    if not alerts:
        return

    farm_doc = get_farm_doc(farm_id) or {}
    owner_uid = farm_doc.get("createdBy") or farm_doc.get("ownerUid")
    farm_name = farm_doc.get("farmName") or ""

    if not owner_uid:
        return

    for a in alerts:
        alert_id = (a.get("id") or "").strip()
        if not alert_id:
            continue

        notif_payload = {
            "ownerUid": owner_uid,          # مهم للـ where('ownerUid'...)
            "farmId": farm_id,
            "farmName": farm_name,

            "type": a.get("type", ""),
            "severity": a.get("severity", ""),
            "title_ar": a.get("title_ar", ""),
            "message_ar": a.get("message_ar", ""),
            "actions": a.get("actions", []),
            "hotspots": a.get("hotspots", []),

            # مهم للترتيب في الصفحة
            "createdAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,

            # مهم لأن الصفحة غالبًا تعرض غير المقروء
            "isRead": False,
        }

        ref = db.collection("notifications").document(alert_id)

        # create لو أول مرة، وإذا موجود سو merge update
        try:
            ref.create(notif_payload)
        except AlreadyExists:
            ref.set(notif_payload, merge=True)
