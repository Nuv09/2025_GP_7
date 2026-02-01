import os
from flask_cors import CORS
import base64
import json
from flask import Flask, request, jsonify

from app.firestore_utils import set_status, get_farm_doc
from google.cloud import firestore

app = Flask(__name__)
CORS(app)

import logging
import sys

gunicorn_logger = logging.getLogger("gunicorn.error")
if gunicorn_logger.handlers:
    app.logger.handlers = gunicorn_logger.handlers
    app.logger.setLevel(gunicorn_logger.level)

logging.basicConfig(level=logging.INFO, stream=sys.stdout, force=True)



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



@app.get("/")
def index():
    models, uris = get_models_once()
    info = {k: v.rsplit("/", 1)[-1] for k, v in (uris or {}).items()}
    if "error" in info:
        info["status"] = "Failed to initialize models"
    return jsonify({"status": "alive", "models": info}), 200

@app.get("/debug/farms")
def debug_farms():
    db = firestore.Client()
    docs = db.collection("farms").limit(50).stream()
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
            raise RuntimeError(f"YOLO model initialization failed: {uris.get('error', 'Unknown failure')}")

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

        try:
            health_result = health_mod.analyze_farm_health(farm_id, farm_doc)
            app.logger.info(
                f"[HEALTH] site={farm_id} "
                f"H={health_result.get('Healthy_Pct')} "
                f"M={health_result.get('Monitor_Pct')} "
                f"C={health_result.get('Critical_Pct')}"
            )
        except Exception as he:
            app.logger.exception(f"❌ ERROR during health analysis for farmId={farm_id}: {he}")
            health_result = {"error": str(he)}

        set_status(
            farm_id,
            status="done",
            finalCount=count_summary["count"],
            finalQuality=count_summary["quality"],
            health=health_result,
             result=count_summary,
            # errorMessage=None,
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



if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
