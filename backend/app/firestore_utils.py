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
) -> int:
    """
    ✅ نفس السكيمة الحالية (بدون أي تغيير على DB)
    ✅ يمنع "إعادة" createdAt و isRead للتنبيه إذا كان موجود
    ✅ يرجّع عدد التنبيهات الجديدة اللي تم إنشاؤها فعلياً (new_count)
    """
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

    # 2) اكتب alerts داخل collection('notifications') عشان notifications_page.dart يقدر يقرأها
    if not alerts:
        return 0

    farm_doc = get_farm_doc(farm_id) or {}
    owner_uid = farm_doc.get("createdBy") or farm_doc.get("ownerUid")
    farm_name = farm_doc.get("farmName") or farm_doc.get("name") or ""

    if not owner_uid:
        return 0

    new_count = 0

    for a in alerts:
        alert_id = (a.get("id") or "").strip()
        if not alert_id:
            continue

        ref = db.collection("notifications").document(alert_id)

        # ✅ Payload لأول مرة فقط (createdAt + isRead=False)
        create_payload = {
            "ownerUid": owner_uid,
            "farmId": farm_id,
            "farmName": farm_name,

            "type": a.get("type", ""),
            "severity": a.get("severity", ""),
            "title_ar": a.get("title_ar", ""),
            "message_ar": a.get("message_ar", ""),
            "actions": a.get("actions", []),
            "hotspots": a.get("hotspots", []),

            "createdAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,

            "isRead": False,
        }

        # ✅ Payload تحديث إذا كان موجود (بدون لمس createdAt ولا isRead)
        update_payload = {
            "ownerUid": owner_uid,  # لو تغيرت ملكية/بيانات - اختياري
            "farmId": farm_id,
            "farmName": farm_name,

            # إذا تبين تثبتي محتوى التنبيه بعد إنشائه، تقدرين تشيلين هذي السطور
            "type": a.get("type", ""),
            "severity": a.get("severity", ""),
            "title_ar": a.get("title_ar", ""),
            "message_ar": a.get("message_ar", ""),
            "actions": a.get("actions", []),
            "hotspots": a.get("hotspots", []),

            "updatedAt": firestore.SERVER_TIMESTAMP,
        }

        try:
            # create لو أول مرة
            ref.create(create_payload)
            new_count += 1
        except AlreadyExists:
            # موجود: سو merge update بدون createdAt/isRead
            ref.set(update_payload, merge=True)

    return new_count