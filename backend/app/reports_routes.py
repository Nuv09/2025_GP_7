# app/reports_routes.py
import base64
import io
from datetime import datetime
from flask import Blueprint, request, jsonify

from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import cm

reports_bp = Blueprint("reports_bp", __name__)

def _safe_float(x, default=0.0):
    try:
        return float(x)
    except Exception:
        return default

def _safe_str(x, default="—"):
    return default if x is None else str(x)

def build_farm_pdf_bytes(payload: dict) -> bytes:
    """
    payload expected keys:
      - farmName, farmId, lastAnalysisAt
      - totalPalms
      - healthyPct, monitorPct, criticalPct
      - recommendations: list of {title_ar, priority_ar, why_ar, text_ar}
    """
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    width, height = A4

    # Header
    c.setTitle("SAAF Farm Report")
    c.setFont("Helvetica-Bold", 16)
    c.drawString(2 * cm, height - 2.2 * cm, "SAAF - Farm Report (Simple v1)")

    c.setFont("Helvetica", 10)
    c.drawString(2 * cm, height - 3.0 * cm, f"Generated at: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}")

    farm_name = _safe_str(payload.get("farmName"), "Farm")
    farm_id = _safe_str(payload.get("farmId"), "—")
    last_analysis = _safe_str(payload.get("lastAnalysisAt"), "—")

    c.setFont("Helvetica-Bold", 12)
    c.drawString(2 * cm, height - 4.2 * cm, f"Farm: {farm_name}")
    c.setFont("Helvetica", 10)
    c.drawString(2 * cm, height - 4.8 * cm, f"Farm ID: {farm_id}")
    c.drawString(2 * cm, height - 5.4 * cm, f"Last analysis: {last_analysis}")

    # Summary box
    total = int(_safe_float(payload.get("totalPalms"), 0))
    h = _safe_float(payload.get("healthyPct"), 0.0)
    m = _safe_float(payload.get("monitorPct"), 0.0)
    cr = _safe_float(payload.get("criticalPct"), 0.0)

    y = height - 6.7 * cm
    c.setFont("Helvetica-Bold", 12)
    c.drawString(2 * cm, y, "Summary")
    y -= 0.6 * cm

    c.setFont("Helvetica", 10)
    c.drawString(2 * cm, y, f"Total palms: {total}")
    y -= 0.5 * cm
    c.drawString(2 * cm, y, f"Healthy: {h:.1f}%")
    y -= 0.5 * cm
    c.drawString(2 * cm, y, f"Monitor: {m:.1f}%")
    y -= 0.5 * cm
    c.drawString(2 * cm, y, f"Critical: {cr:.1f}%")
    y -= 0.8 * cm

    # Recommendations (top 6)
    recos = payload.get("recommendations") or []
    if not isinstance(recos, list):
        recos = []

    c.setFont("Helvetica-Bold", 12)
    c.drawString(2 * cm, y, "Top Recommendations (max 6)")
    y -= 0.7 * cm

    c.setFont("Helvetica", 9)
    max_items = min(6, len(recos))
    if max_items == 0:
        c.drawString(2 * cm, y, "- No recommendations -")
        y -= 0.5 * cm
    else:
        for i in range(max_items):
            r = recos[i] if isinstance(recos[i], dict) else {}
            title = _safe_str(r.get("title_ar") or r.get("title") or "Recommendation", "Recommendation")
            pr = _safe_str(r.get("priority_ar") or r.get("priority") or "—", "—")
            why = _safe_str(r.get("why_ar") or "", "")
            action = _safe_str(r.get("text_ar") or r.get("text") or "", "")

            line = f"{i+1}) [{pr}] {title}"
            c.drawString(2 * cm, y, line)
            y -= 0.45 * cm

            if why:
                c.drawString(2.6 * cm, y, f"Why: {why[:120]}")
                y -= 0.45 * cm
            if action:
                c.drawString(2.6 * cm, y, f"Action: {action[:120]}")
                y -= 0.55 * cm

            # new page if needed
            if y < 2.5 * cm:
                c.showPage()
                y = height - 2.5 * cm
                c.setFont("Helvetica", 9)

    c.showPage()
    c.save()
    buf.seek(0)
    return buf.read()

@reports_bp.post("/reports/<farm_id>/pdf")
def export_pdf(farm_id):
    """
    Returns: { ok, fileName, base64 }
    """
    try:
        body = request.get_json(silent=True) or {}

        # هنا مبدئيًا نقرأ "farmData" من نفس الطلب (لأننا نبغى خطوة 1 تشتغل بسرعة)
        farm = body.get("farmData") or {}
        if not isinstance(farm, dict):
            farm = {}

        # جهّز Payload للتقرير
        payload = {
            "farmName": farm.get("farmName", "Farm"),
            "farmId": farm_id,
            "lastAnalysisAt": farm.get("lastAnalysisAt", "—"),
            "totalPalms": farm.get("finalCount", 0),
        }

        # health current
        health = farm.get("health") or {}
        current = (health.get("current_health") or {}) if isinstance(health, dict) else {}
        payload["healthyPct"] = current.get("Healthy_Pct", 0)
        payload["monitorPct"] = current.get("Monitor_Pct", 0)
        payload["criticalPct"] = current.get("Critical_Pct", 0)

        # recommendations
        payload["recommendations"] = farm.get("recommendations", [])

        pdf_bytes = build_farm_pdf_bytes(payload)
        b64 = base64.b64encode(pdf_bytes).decode("utf-8")

        fname = f"SAAF_Report_{farm_id}_{datetime.utcnow().strftime('%Y-%m-%d')}.pdf"
        return jsonify({"ok": True, "fileName": fname, "base64": b64}), 200

    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500