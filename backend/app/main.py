import os
import base64
import json
import logging
import sys
from datetime import datetime, timedelta

from flask import Flask, request, jsonify
from flask_cors import CORS

from google.cloud import firestore
import firebase_admin
from firebase_admin import messaging

from app.firestore_utils import set_status, get_farm_doc

app = Flask(__name__)
CORS(app)

# ✅ Firebase Admin init (يستخدم Service Account حق Cloud Run تلقائياً)
if not firebase_admin._apps:
    firebase_admin.initialize_app()

gunicorn_logger = logging.getLogger("gunicorn.error")
if gunicorn_logger.handlers:
    app.logger.handlers = gunicorn_logger.handlers
    app.logger.setLevel(gunicorn_logger.level)

logging.basicConfig(level=logging.INFO, stream=sys.stdout, force=True)

# ✅ Reuse Firestore client
DB = firestore.Client()

MODELS = None
MODEL_URIS = {}


def get_models_once():
    global MODELS, MODEL_URIS
    if MODELS is None:
        try:
            from app import inference as inf
            MODELS, MODEL_URIS = inf.load_models_auto()
        except Exception as e:
            app.logger.critical(f"❌ CRITICAL: Failed to load YOLO models on startup: {e}")
            MODELS = {}
            MODEL_URIS = {"error": str(e)}
    return MODELS, MODEL_URIS


def _try_decode_base64_json(b64_str: str):
    try:
        txt = base64.b64decode(b64_str).decode("utf-8")
        return json.loads(txt)
    except Exception:
        return None


def extract_farm_id(envelope: dict) -> tuple[str | None, str]:
    if not isinstance(envelope, dict):
        return None, "not_json"

    if "farmId" in envelope and isinstance(envelope["farmId"], str):
        return envelope["farmId"], "raw"

    data_obj = envelope.get("data")
    if isinstance(data_obj, dict) and isinstance(data_obj.get("farmId"), str):
        return data_obj["farmId"], "json_data"

    msg = envelope.get("message")
    if isinstance(msg, dict) and isinstance(msg.get("data"), str):
        inner = _try_decode_base64_json(msg["data"])
        if isinstance(inner, dict):
            if isinstance(inner.get("farmId"), str):
                return inner["farmId"], "eventarc_inner_farmId"
            value = inner.get("value")
            if isinstance(value, dict) and isinstance(value.get("name"), str):
                try:
                    f_id = value["name"].split("/")[-1]
                    if f_id:
                        return f_id, "eventarc_inner_value_name"
                except Exception:
                    pass
        return None, "bad_eventarc_payload"

    if isinstance(envelope.get("data"), dict):
        value = envelope["data"].get("value")
        if isinstance(value, dict) and isinstance(value.get("name"), str):
            try:
                f_id = value["name"].split("/")[-1]
                if f_id:
                    return f_id, "cloudevent_data_value_name"
            except Exception:
                pass

    if isinstance(envelope.get("resource"), str):
        try:
            f_id = envelope["resource"].split("/")[-1]
            if f_id:
                return f_id, "cloudevent_direct_resource"
        except Exception:
            pass

    return None, "no_supported_keys"


def send_push_to_token(token: str, title: str, body: str, data: dict | None = None):
    if not token:
        return
    safe_data = {str(k): str(v) for k, v in (data or {}).items()}  # ✅


    msg = messaging.Message(
        token=token,
        notification=messaging.Notification(title=title, body=body),
        android=messaging.AndroidConfig(priority="high"),
        data=safe_data,
    )
    messaging.send(msg)


def send_push_to_user(uid: str, title: str, body: str, data: dict | None = None):
    user_doc = DB.collection("users").document(uid).get()
    user_data = user_doc.to_dict() or {}
    token = user_data.get("fcmToken")

    if not token:
        app.logger.info(f"📭 No fcmToken for uid={uid}")
        return

    send_push_to_token(token, title, body, data=data)
    app.logger.info(f"✅ Push sent to uid={uid}")


def maybe_send_push_for_alerts(owner_uid: str, alerts_pkg: dict):
    """
    يرسل Push إذا عند المستخدم تنبيهات غير مقروءة.
    ويبني نص مختلف لو كانت تنبيهات تخص مزرعة واحدة فقط.
    """
    alerts_list = alerts_pkg.get("alerts", []) or []
    if not owner_uid or len(alerts_list) == 0:
        return

    notifs = (
        DB.collection("notifications")
        .where("ownerUid", "==", owner_uid)
        .where("isRead", "==", False)
        .stream()
    )
    notifs_list = list(notifs)      # ✅
    if len(notifs_list) == 0:       # ✅
       return

    farm_ids = set()
    for n in notifs_list:
        data = n.to_dict() or {}
        fid = data.get("farmId")
        if fid:
            farm_ids.add(fid)

    if len(farm_ids) == 1:
        single_farm_id = list(farm_ids)[0]
        farm_doc_single = DB.collection("farms").document(single_farm_id).get()
        farm_data = farm_doc_single.to_dict() or {}
        farm_name = (
           farm_data.get("name")
           or farm_data.get("farmName")
           or farm_data.get("title")
           or "مزرعتك"
            )
        body_text = f"يوجد تنبيهات جديدة في {farm_name} 🌴"
    else:
        body_text = "يوجد تنبيهات جديدة في مزارعك 🌴"

    send_push_to_user(
        uid=owner_uid,
        title="تنبيه جديد من سعف",
        body=body_text,
        data={"route": "notifications"},
    )


@app.get("/")
def index():
    models, uris = get_models_once()
    info = {k: v.rsplit("/", 1)[-1] for k, v in (uris or {}).items()}
    if "error" in info:
        info["status"] = "Failed to initialize models"
    return jsonify({"status": "alive", "models": info}), 200


@app.get("/debug/farms")
def debug_farms():
    docs = DB.collection("farms").limit(50).stream()
    items = []
    for d in docs:
        doc = d.to_dict() or {}
        poly = doc.get("polygon") or []
        items.append({"id": d.id, "polygon_len": len(poly), "keys": list(doc.keys())[:8]})
    return jsonify({"count": len(items), "items": items})


@app.get("/debug/farm/<farm_id>")
def debug_farm(farm_id):
    doc = get_farm_doc(farm_id)
    if not doc:
        return jsonify({"ok": False, "reason": "not_found", "farmId": farm_id}), 404
    poly = doc.get("polygon") or []
    return jsonify(
        {
            "ok": True,
            "farmId": farm_id,
            "keys": sorted(doc.keys()),
            "polygon_len": len(poly),
            "polygon_sample": poly[:3],
        }
    )


@app.post("/analyze")
def analyze():
    app.logger.info("🎯 /analyze called")

    try:
        import psutil
        memory = psutil.virtual_memory()
        app.logger.info(
            f"🧠 Memory: {memory.percent}% used, {memory.available/1024/1024:.0f}MB available"
        )
    except Exception as e:
        app.logger.info(f"⚠️ Could not check memory: {e}")

    envelope = request.get_json(silent=True) or {}
    farm_id, origin = extract_farm_id(envelope)

    if not farm_id:
        return (
            jsonify(
                {
                    "status": "error",
                    "message": f"Invalid event format. Could not extract farmId. Origin: {origin}",
                    "received_keys": list(envelope.keys()),
                }
            ),
            400,
        )

    try:
        app.logger.info(f"[ANALYZE] origin={origin} farmId={farm_id}")

        set_status(farm_id, status="running", errorMessage=None)

        from app import inference as inf
        from app import health as health_mod

        models, uris = get_models_once()
        if not models:
            raise RuntimeError(
                f"YOLO model initialization failed: {uris.get('error', 'Unknown failure')}"
            )

        farm_doc = get_farm_doc(farm_id)
        if not farm_doc:
            raise ValueError(f"Farm '{farm_id}' not found in Firestore")

        poly = farm_doc.get("polygon") or []
        if len(poly) < 3:
            raise ValueError("Farm polygon is missing or < 3 points")
        app.logger.info(f"[DEBUG] farmId={farm_id} polygon_len={len(poly)}")

        img_path = inf.get_sat_image_for_farm(farm_doc)
        app.logger.info(f"[IMG] {img_path}")

        picked = inf.run_both_and_pick_best(models, img_path)
        app.logger.info(f"[COUNT] done count={picked['count']} score={picked['score']}")

        count_summary = {
            "count": int(picked["count"]),
            "quality": float(picked["score"]),
            "model": picked.get("picked"),
        }

        # ✅ Health + Alerts + Push
        export_payload = {}
        try:
            health_result = health_mod.analyze_farm_health(farm_id, farm_doc) 

            # ✅ (جديد) تجهيز بيانات التصدير المختصرة
            
            try:
                export_payload = health_mod.prepare_export_data(farm_doc, health_result)
            except Exception as ee:
                app.logger.error(f"⚠️ Failed to prepare export data: {ee}")


            from app.alerts_engine import build_alerts_and_recommendations
            from app.firestore_utils import set_alerts_and_recommendations

            alerts_pkg = build_alerts_and_recommendations(farm_id, health_result)

# ✅ (1) خزن alerts/recs وارجع لنا كم alert جديد انضاف
            new_alerts_count = set_alerts_and_recommendations(
               farm_id,
               alerts_pkg.get("alerts", []),
               alerts_pkg.get("recommendations", []),
              )

# ✅ (2) Push فقط لو فيه جديد
            owner_uid = farm_doc.get("createdBy") or farm_doc.get("ownerUid")
            if owner_uid and (new_alerts_count or 0) > 0:
               maybe_send_push_for_alerts(owner_uid, alerts_pkg)

            ch = health_result.get("current_health", {})
            app.logger.info(
                f"[HEALTH] site={farm_id} "
                f"H={ch.get('Healthy_Pct')} "
                f"M={ch.get('Monitor_Pct')} "
                f"C={ch.get('Critical_Pct')}"
            )
        except Exception as he:
            app.logger.exception(f"❌ ERROR during health analysis for farmId={farm_id}: {he}")
            health_result = {"error": str(he)}

        h_map = list(health_result.pop("health_map", []))
        set_status(
            farm_id,
            status="done",
            finalCount=count_summary["count"],
            finalQuality=count_summary["quality"],
            health=health_result,
            healthMap=h_map,
            export_data=export_payload,
            lastAnalysisAt=firestore.SERVER_TIMESTAMP,
        )

        return (
            jsonify(
                {
                    "status": "success",
                    "farmId": farm_id,
                    "origin": origin,
                    "countResult": count_summary,
                    "healthResult": health_result,
                    "debugCountRaw": picked,
                }
            ),
            200,
        )

    except Exception as e:
        set_status(farm_id, status="failed", errorMessage=str(e))
        app.logger.exception(f"❌ ERROR during /analyze: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


@app.post("/scheduled-update")
def scheduled_update():
    app.logger.info("⏰ /scheduled-update called")

    farms = DB.collection("farms").order_by("lastAnalysisAt").limit(8).stream()

    now = datetime.utcnow()
    updated = []
    skipped = []
    failed = []

    for doc in farms:
        farm = doc.to_dict() or {}
        farm_id = doc.id

        last = farm.get("lastAnalysisAt")
        if last is None:
            needs_update = True
        else:
            last_dt = last.replace(tzinfo=None)
            needs_update = (now - last_dt) >= timedelta(days=6)

        if not needs_update:
            skipped.append(farm_id)
            continue

        try:
            from app import inference as inf
            from app import health as health_mod
            from app.alerts_engine import build_alerts_and_recommendations
            from app.firestore_utils import set_alerts_and_recommendations

            models, uris = get_models_once()
            if not models:
                raise RuntimeError(
                    f"YOLO model initialization failed: {uris.get('error', 'Unknown failure')}"
                )

            # ✅ 1) Count
            img_path = inf.get_sat_image_for_farm(farm)
            picked = inf.run_both_and_pick_best(models, img_path)

            # ✅ 2) Health
            health_result = health_mod.analyze_farm_health(farm_id, farm)
            export_payload = health_mod.prepare_export_data(farm, health_result)
            h_map = list(health_result.pop("health_map", []))

            # ✅ 3) Alerts + Recommendations (هذا اللي كان ناقص!)
            alerts_pkg = build_alerts_and_recommendations(farm_id, health_result)

            new_alerts_count = set_alerts_and_recommendations(
                farm_id,
                alerts_pkg.get("alerts", []),
                alerts_pkg.get("recommendations", []),
            )

            # ✅ 4) Push فقط لو فعلاً فيه تنبيه جديد
            owner_uid = farm.get("createdBy") or farm.get("ownerUid")
            if owner_uid and (new_alerts_count or 0) > 0:
                maybe_send_push_for_alerts(owner_uid, alerts_pkg)

            # ✅ 5) Update farm doc / status
            set_status(
                farm_id,
                status="done",
                finalCount=int(picked["count"]),
                finalQuality=float(picked["score"]),
                health=health_result,
                healthMap=h_map,
                export_data=export_payload,
                lastAnalysisAt=firestore.SERVER_TIMESTAMP,
            )

            updated.append(
                {
                    "farmId": farm_id,
                    "newAlerts": int(new_alerts_count or 0),
                    "count": int(picked["count"]),
                    "score": float(picked["score"]),
                }
            )

        except Exception as e:
            app.logger.exception(f"❌ scheduled-update failed for farmId={farm_id}: {e}")
            set_status(farm_id, status="failed", errorMessage=str(e))
            failed.append({"farmId": farm_id, "error": str(e)})

    return jsonify({"updated": updated, "skipped": skipped, "failed": failed}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
    from app.reports_routes import reports_bp
    app.register_blueprint(reports_bp)