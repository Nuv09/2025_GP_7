import base64
import math
import os
import logging
import traceback
from datetime import datetime
import requests
import io
from PIL import Image

from flask import Blueprint, jsonify, render_template
from google.cloud import firestore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DB = firestore.Client()
reports_bp = Blueprint("reports_bp", __name__)
TILE_SIZE_MAP = 512
REPORT_TILE_URL = "https://api.maptiler.com/maps/satellite/{zoom}/{x}/{y}.jpg?key={key}"


# ─────────────────────────────────────────────
# helpers
# ─────────────────────────────────────────────

def get_farm_safely(identifier):
    """البحث عن المزرعة عبر الـ ID أو رقم العقد"""
    try:
        doc_ref = DB.collection("farms").document(identifier).get()
        if doc_ref.exists:
            return doc_ref, "ID"
    except Exception as e:
        logger.error(f"Error fetching document: {e}")

    try:
        query = DB.collection("farms").where("contractNumber", "==", identifier).limit(1).get()
        docs = list(query)
        if docs:
            return docs[0], "contractNumber"
    except Exception as e:
        logger.error(f"Error querying contractNumber: {e}")

    return None, None


def _safe_float(v, default=0.0):
    try:
        if v is None:
            return default
        result = float(v)
        if math.isnan(result) or math.isinf(result):
            return default
        return result
    except Exception:
        return default


def _safe_int(v, default=0):
    try:
        if v is None:
            return default
        return int(v)
    except Exception:
        return default

def _load_local_image_as_data_uri(*relative_parts) -> str | None:
    try:
        path = os.path.join(os.path.dirname(__file__), *relative_parts)
        if not os.path.exists(path):
            return None
        with open(path, "rb") as img_file:
            img_b64 = base64.b64encode(img_file.read()).decode("utf-8")
        ext = os.path.splitext(path)[1].lower()
        mime = "image/png" if ext == ".png" else "image/jpeg" if ext in {".jpg", ".jpeg"} else "image/svg+xml" if ext == ".svg" else "application/octet-stream"
        return f"data:{mime};base64,{img_b64}"
    except Exception as e:
        logger.warning(f"Failed to load local image {'/'.join(relative_parts)}: {e}")
        return None

def _inline_svg_data_uri(svg_text: str) -> str:
    svg_b64 = base64.b64encode(svg_text.encode("utf-8")).decode("utf-8")
    return f"data:image/svg+xml;base64,{svg_b64}"


def _default_watermark_data_uri() -> str:
    svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 220">
      <g fill="none" fill-rule="evenodd">
        <circle cx="110" cy="110" r="92" fill="#0f766e" opacity="0.10"/>
        <path d="M110 36 L152 78 L110 120 L68 78 Z" fill="#065f46" opacity="0.22"/>
        <path d="M110 58 C118 78, 118 102, 110 124 C102 102, 102 78, 110 58 Z" fill="#10b981" opacity="0.34"/>
      </g>
    </svg>
    """
    return _inline_svg_data_uri(svg)


def _color_for_pct(pct: float) -> str:
    if pct >= 75:
        return "#16a34a"
    if pct >= 45:
        return "#f59e0b"
    return "#dc2626"


def _gauge_svg(pct: float, color: str, size: int = 116) -> str:
    pct = max(0.0, min(100.0, float(pct)))
    r = 44
    cx = cy = size / 2
    circumference = 3.14159 * r
    stroke_dash = (pct / 100) * circumference
    stroke_gap = circumference - stroke_dash

    return f"""
<svg width="{size}" height="{size // 2 + 22}" viewBox="0 0 {size} {size // 2 + 22}">
  <path d="M {cx - r} {cy} A {r} {r} 0 0 1 {cx + r} {cy}"
        fill="none" stroke="#e5e7eb" stroke-width="10" stroke-linecap="round"/>
  <path d="M {cx - r} {cy} A {r} {r} 0 0 1 {cx + r} {cy}"
        fill="none" stroke="{color}" stroke-width="10" stroke-linecap="round"
        stroke-dasharray="{stroke_dash:.1f} {stroke_gap:.1f}"/>
  <text x="{cx}" y="{cy + 8}" text-anchor="middle"
        font-family="Cairo, sans-serif" font-size="20" font-weight="800" fill="{color}">
    {pct:.0f}%
  </text>
</svg>
""".strip()


def _trend_sparkline(values: list, color: str = "#2563eb", width: int = 235, height: int = 68) -> str:
    if not values:
        return ""

    vals = []
    for v in values:
        try:
            vals.append(float(v))
        except Exception:
            pass

    if len(vals) < 2:
        return ""

    mn, mx = min(vals), max(vals)
    rng = mx - mn if mx != mn else 1.0
    step = width / (len(vals) - 1)

    pts = []
    circles = []

    for i, v in enumerate(vals):
        x = i * step
        y = height - ((v - mn) / rng) * (height - 18) - 9
        pts.append(f"{x:.1f},{y:.1f}")
        circles.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="3" fill="{color}" />')

    polyline = " ".join(pts)

    return f"""
<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <line x1="0" y1="{height - 9}" x2="{width}" y2="{height - 9}" stroke="#dbeafe" stroke-width="1"/>
  <polyline points="{polyline}" fill="none" stroke="{color}" stroke-width="3"
            stroke-linejoin="round" stroke-linecap="round"/>
  {''.join(circles)}
</svg>
""".strip()


def _distribution_compare_svg(
    current_dist: dict,
    next_dist: dict,
    width: int = 300,
    height: int = 150
) -> str:
    """رسم أعمدة واضح بدون نصوص عربية داخل SVG لتجنب انعكاسها في PDF."""

    current_vals = [
        _safe_float(current_dist.get("Healthy_Pct", 0)),
        _safe_float(current_dist.get("Monitor_Pct", 0)),
        _safe_float(current_dist.get("Critical_Pct", 0)),
    ]
    next_vals = [
        _safe_float(next_dist.get("Healthy_Pct_next", 0)),
        _safe_float(next_dist.get("Monitor_Pct_next", 0)),
        _safe_float(next_dist.get("Critical_Pct_next", 0)),
    ]

    strong_colors = ["#22c55e", "#f59e0b", "#ef4444"]
    light_colors  = ["#bbf7d0", "#fde68a", "#fecaca"]

    pad_l, pad_r, pad_t, pad_b = 18, 18, 20, 26
    chart_h = height - pad_t - pad_b
    base_y = pad_t + chart_h
    bar_w = 22
    inner_gap = 7
    group_gap = 24
    x = pad_l
    parts = []

    for frac in [0.25, 0.5, 0.75, 1.0]:
        gy = pad_t + chart_h * (1 - frac)
        label = int(frac * 100)
        parts.append(f'<line x1="{pad_l}" y1="{gy:.1f}" x2="{width-pad_r}" y2="{gy:.1f}" stroke="#eef2f7" stroke-width="1"/>')
        parts.append(f'<text x="{pad_l-4}" y="{gy+3:.1f}" text-anchor="end" font-family="Arial, sans-serif" font-size="8" fill="#94a3b8">{label}</text>')

    parts.append(f'<line x1="{pad_l}" y1="{base_y}" x2="{width-pad_r}" y2="{base_y}" stroke="#cbd5e1" stroke-width="1.2"/>')

    for i in range(3):
        cur_v = max(0.0, min(100.0, current_vals[i]))
        nxt_v = max(0.0, min(100.0, next_vals[i]))
        cur_h = (cur_v / 100.0) * chart_h
        nxt_h = (nxt_v / 100.0) * chart_h
        cur_x = x
        nxt_x = x + bar_w + inner_gap
        cur_y = base_y - cur_h
        nxt_y = base_y - nxt_h

        parts.append(f'<rect x="{cur_x}" y="{cur_y:.1f}" width="{bar_w}" height="{cur_h:.1f}" rx="7" fill="{strong_colors[i]}"/>')
        parts.append(f'<rect x="{nxt_x}" y="{nxt_y:.1f}" width="{bar_w}" height="{nxt_h:.1f}" rx="7" fill="{light_colors[i]}" stroke="{strong_colors[i]}" stroke-width="0.9"/>')

        parts.append(f'<text x="{cur_x + bar_w/2:.1f}" y="{cur_y - 4:.1f}" text-anchor="middle" font-family="Arial, sans-serif" font-size="8" font-weight="700" fill="{strong_colors[i]}">{cur_v:.0f}%</text>')
        parts.append(f'<text x="{nxt_x + bar_w/2:.1f}" y="{nxt_y - 4:.1f}" text-anchor="middle" font-family="Arial, sans-serif" font-size="8" font-weight="700" fill="#64748b">{nxt_v:.0f}%</text>')

        x += (bar_w * 2 + inner_gap + group_gap)

    return f"""
<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg">
  {''.join(parts)}
</svg>
""".strip()

def _mini_bar_svg(values: list[float], colors: list[str], width: int = 215, height: int = 84) -> str:
    """
    قراف أفقي صغير لعرض 3 قيم بسرعة بدون نصوص عربية داخل SVG.
    """
    if not values:
        return ""

    vals = [max(0.0, _safe_float(v, 0.0)) for v in values]
    mx = max(max(vals), 1.0)

    bar_h = 14
    gap = 10
    left = 8
    top = 8

    parts = []
    for i, v in enumerate(vals):
        y = top + i * (bar_h + gap)
        w = (v / mx) * (width - 40)
        parts.append(
            f'<rect x="{left}" y="{y}" width="{width-30}" height="{bar_h}" rx="7" fill="#edf2f7"/>'
        )
        parts.append(
            f'<rect x="{left}" y="{y}" width="{w:.1f}" height="{bar_h}" rx="7" fill="{colors[i]}"/>'
        )

    return f"""
<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  {''.join(parts)}
</svg>
""".strip()


def _multi_index_sparkline(
    multi_trend: dict,
    width: int = 430,
    height: int = 126,
) -> str:
    """رسم أوضح للمؤشرات الطيفية مع مساحة أكبر حتى لا يُقص داخل الكرت."""
    ndvi = [_safe_float(v) for v in (multi_trend.get("ndvi") or []) if v is not None]
    ndmi = [_safe_float(v) for v in (multi_trend.get("ndmi") or []) if v is not None]
    ndre = [_safe_float(v) for v in (multi_trend.get("ndre") or []) if v is not None]

    series = [
        (ndvi, "#16a34a", "NDVI"),
        (ndmi, "#2563eb", "NDMI"),
        (ndre, "#0f766e", "NDRE"),
    ]
    valid = [(vals, color, label) for vals, color, label in series if len(vals) >= 2]
    if not valid:
        return ""

    all_vals = [v for vals, _, _ in valid for v in vals]
    mn, mx = min(all_vals), max(all_vals)
    if mn == mx:
        mn -= 0.1
        mx += 0.1
    rng = mx - mn

    pad_l, pad_r, pad_t, pad_b = 34, 12, 10, 28
    chart_w = width - pad_l - pad_r
    chart_h = height - pad_t - pad_b

    parts = []

    for frac in [0.0, 0.25, 0.5, 0.75, 1.0]:
        y = pad_t + chart_h - (frac * chart_h)
        val = mn + frac * rng
        parts.append(f'<line x1="{pad_l}" y1="{y:.1f}" x2="{pad_l+chart_w}" y2="{y:.1f}" stroke="#e5e7eb" stroke-width="1"/>')
        parts.append(f'<text x="{pad_l-6}" y="{y+3:.1f}" text-anchor="end" font-family="Arial, sans-serif" font-size="8" fill="#94a3b8">{val:.2f}</text>')

    longest = max(len(vals) for vals, _, _ in valid)
    step = chart_w / max(longest - 1, 1)
    for i in range(longest):
        x = pad_l + i * step
        parts.append(f'<line x1="{x:.1f}" y1="{pad_t}" x2="{x:.1f}" y2="{pad_t+chart_h}" stroke="#f1f5f9" stroke-width="1"/>')

    for vals, color, label in valid:
        n = len(vals)
        local_step = chart_w / max(n - 1, 1)
        pts = []
        for i, v in enumerate(vals):
            x = pad_l + i * local_step
            y = pad_t + chart_h - ((v - mn) / rng) * chart_h
            pts.append((x, y))

        polyline = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        parts.append(f'<polyline points="{polyline}" fill="none" stroke="{color}" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"/>')
        for x, y in pts:
            parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="2.7" fill="{color}"/>')

    lx = pad_l
    for _, color, lbl in valid:
        parts.append(f'<rect x="{lx}" y="{height-14}" width="11" height="7" rx="3" fill="{color}"/>')
        parts.append(f'<text x="{lx+15}" y="{height-8}" font-family="Arial, sans-serif" font-size="8" fill="#475569">{lbl}</text>')
        lx += 62

    return f"""
<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg">
  {''.join(parts)}
</svg>
""".strip()


def _flag_breakdown_rows(flag_counts: dict) -> list[dict]:
    """تفصيل الإشارات؛ هذا عدّ إشارات وليس عدّ بكسلات فريدة."""
    water = int(flag_counts.get("water_low", 0)) + int(flag_counts.get("water_below_025", 0))
    veg = int(flag_counts.get("ndvi_below_030", 0)) + int(flag_counts.get("ndvi_drop", 0))
    leaf = int(flag_counts.get("ndre_low", 0)) + int(flag_counts.get("ndre_below_035", 0))
    stress = int(flag_counts.get("siwsi_drop", 0)) + int(flag_counts.get("water_drop", 0))

    rows = [
        {"label": "إجهاد مائي", "value": water, "color": "#3b82f6"},
        {"label": "هبوط الخضرة", "value": veg, "color": "#22c55e"},
        {"label": "ضعف التغذية", "value": leaf, "color": "#0d9488"},
        {"label": "ضغط مائي مركب", "value": stress, "color": "#f59e0b"},
    ]

    max_value = max([r["value"] for r in rows] + [1])
    for row in rows:
        row["pct"] = round((row["value"] / max_value) * 100, 1)

    return rows

def _sector_distribution_rows(map_points: list) -> list[dict]:
    """تلخيص توزيع الحالات حسب القطاع المكاني داخل المزرعة."""
    points = []
    for p in map_points or []:
        try:
            lat = float(p.get("lat"))
            lng = float(p.get("lng"))
            s = int(p.get("s", 0))
            points.append((lat, lng, s))
        except Exception:
            continue

    if not points:
        return [
            {"label": "شمال", "healthy_pct": 0, "monitor_pct": 0, "critical_pct": 0, "total": 0},
            {"label": "جنوب", "healthy_pct": 0, "monitor_pct": 0, "critical_pct": 0, "total": 0},
            {"label": "شرق", "healthy_pct": 0, "monitor_pct": 0, "critical_pct": 0, "total": 0},
            {"label": "غرب", "healthy_pct": 0, "monitor_pct": 0, "critical_pct": 0, "total": 0},
        ]

    lats = [p[0] for p in points]
    lngs = [p[1] for p in points]
    lat_mid = (min(lats) + max(lats)) / 2
    lng_mid = (min(lngs) + max(lngs)) / 2

    buckets = {
        "شمال": {0: 0, 1: 0, 2: 0},
        "جنوب": {0: 0, 1: 0, 2: 0},
        "شرق": {0: 0, 1: 0, 2: 0},
        "غرب": {0: 0, 1: 0, 2: 0},
    }

    for lat, lng, s in points:
        if abs(lat - lat_mid) >= abs(lng - lng_mid):
            key = "شمال" if lat >= lat_mid else "جنوب"
        else:
            key = "شرق" if lng >= lng_mid else "غرب"
        buckets[key][2 if s == 2 else 1 if s == 1 else 0] += 1

    rows = []
    for label in ["شمال", "جنوب", "شرق", "غرب"]:
        counts = buckets[label]
        total = counts[0] + counts[1] + counts[2]
        if total == 0:
            rows.append({"label": label, "healthy_pct": 0, "monitor_pct": 0, "critical_pct": 0, "total": 0})
        else:
            rows.append({
                "label": label,
                "healthy_pct": round((counts[0] / total) * 100, 1),
                "monitor_pct": round((counts[1] / total) * 100, 1),
                "critical_pct": round((counts[2] / total) * 100, 1),
                "total": total,
            })
    return rows

def _normalize_polygon(poly: list | None) -> list[tuple[float, float]]:
    out = []
    if not poly:
        return out

    for item in poly:
        try:
            if isinstance(item, dict):
                lat = float(item.get("lat"))
                lng = float(item.get("lng"))
                out.append((lat, lng))
            elif isinstance(item, (list, tuple)) and len(item) >= 2:
                a = float(item[0])
                b = float(item[1])
                if abs(a) <= 90 and abs(b) <= 180:
                    out.append((a, b))
                else:
                    out.append((b, a))
        except Exception:
            continue

    return out

def _map_bounds(map_points: list, farm_polygon: list | None = None):
    norm_poly = _normalize_polygon(farm_polygon)

    lats, lngs = [], []

    for p in map_points or []:
        try:
            lats.append(float(p.get("lat")))
            lngs.append(float(p.get("lng")))
        except Exception:
            pass

    for lat, lng in norm_poly:
        lats.append(lat)
        lngs.append(lng)

    if not lats or not lngs:
        return None

    min_lat, max_lat = min(lats), max(lats)
    min_lng, max_lng = min(lngs), max(lngs)

    # padding بسيط حتى ما تكون الحدود ملاصقة للصورة
    lat_pad = max((max_lat - min_lat) * 0.08, 0.0008)
    lng_pad = max((max_lng - min_lng) * 0.08, 0.0008)

    return {
        "min_lat": min_lat - lat_pad,
        "max_lat": max_lat + lat_pad,
        "min_lng": min_lng - lng_pad,
        "max_lng": max_lng + lng_pad,
    }




def _heatmap_svg(map_points: list, width: int = 505, height: int = 280, farm_polygon: list | None = None) -> dict:
    norm_poly = _normalize_polygon(farm_polygon)

    if not map_points and not norm_poly:
        return {"bg_data_uri": None, "overlay_svg": ""}

    bounds = _map_bounds(map_points, farm_polygon)
    if not bounds:
        return {"bg_data_uri": None, "overlay_svg": ""}

    min_lat = bounds["min_lat"]
    max_lat = bounds["max_lat"]
    min_lng = bounds["min_lng"]
    max_lng = bounds["max_lng"]

    lat_rng = max(max_lat - min_lat, 1e-6)
    lng_rng = max(max_lng - min_lng, 1e-6)
    pad = 8

    def to_xy(lat, lng):
        x = pad + ((lng - min_lng) / lng_rng) * (width - pad * 2)
        y = pad + ((max_lat - lat) / lat_rng) * (height - pad * 2)
        return round(x, 1), round(y, 1)

    color_map = {
        0: "#22c55e",
        1: "#f59e0b",
        2: "#ef4444",
    }

    bg_data_uri = _stitch_maptiler_tiles(bounds, width, height, zoom=18)

    poly_svg = ""
    if norm_poly:
        pts = " ".join(f"{x},{y}" for x, y in [to_xy(lat, lng) for lat, lng in norm_poly])
        poly_svg = (
            f'<polygon points="{pts}" fill="white" fill-opacity="0.10" stroke="#10b981" '
            f'stroke-width="2.2" opacity="1"/>'
        )

    circles = []
    for pt in map_points or []:
        try:
            lat = float(pt.get("lat"))
            lng = float(pt.get("lng"))
            s = int(pt.get("s", 0))
            ps = int(pt.get("ps", s))
        except Exception:
            continue

        x, y = to_xy(lat, lng)
        r = 4.8 if s == 2 else 4.3 if s == 1 else 3.9
        fill = color_map.get(s, "#22c55e")

        ring = ""
        if ps != s:
            ring = (
                f'<circle cx="{x}" cy="{y}" r="{r + 2.8}" fill="none" '
                f'stroke="#2563eb" stroke-width="1.5" opacity="0.95"/>'
            )

        circles.append(
            ring +
            f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" opacity="0.95" />'
        )

    overlay_svg = f"""<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}"
     xmlns="http://www.w3.org/2000/svg" style="position:absolute;top:0;left:0;">
  {poly_svg}
  {''.join(circles)}
</svg>""".strip()

    return {"bg_data_uri": bg_data_uri, "overlay_svg": overlay_svg}

def _delta_badge_html(delta_pct: float) -> str:
    delta_pct = _safe_float(delta_pct, 0.0)

    if abs(delta_pct) < 0.05:
        return '<span style="color:#64748b;">بدون تغير ملحوظ</span>'

    if delta_pct > 0:
        return f'<span style="color:#16a34a;">▲ {abs(delta_pct):.1f}%</span>'

    return f'<span style="color:#dc2626;">▼ {abs(delta_pct):.1f}%</span>'


def _metric_verdict(code: str, value: float):
    v = _safe_float(value, 0.0)

    if code == "NDVI":
        if v >= 0.60:
            return "جيدة", "#dcfce7", "#166534"
        if v >= 0.35:
            return "متوسطة", "#fef3c7", "#92400e"
        return "منخفضة", "#fee2e2", "#b91c1c"

    if code == "NDMI":
        if v >= 0.30:
            return "جيدة", "#dbeafe", "#1d4ed8"
        if v >= 0.10:
            return "متوسطة", "#fef3c7", "#92400e"
        return "منخفضة", "#fee2e2", "#b91c1c"

    if code == "NDRE":
        if v >= 0.45:
            return "جيدة", "#dcfce7", "#166534"
        if v >= 0.25:
            return "متوسطة", "#fef3c7", "#92400e"
        return "منخفضة", "#fee2e2", "#b91c1c"

    return "—", "#f1f5f9", "#475569"


def _footer_logo_html(logo_data_uri: str | None) -> str:
    if logo_data_uri:
        return (
            f'<img src="{logo_data_uri}" alt="Saaf" '
            f'style="height:42px; width:auto; max-width:150px; display:block; object-fit:contain;" />'
        )
    return '<div style="font-size:16px;font-weight:900;color:#6ee7b7;letter-spacing:1px;">سعف</div>'


# ─────────────────────────────────────────────
# PDF Generation — weasyprint
# ─────────────────────────────────────────────
def generate_pdf_report(export_data: dict, farm_id: str, farm_doc: dict | None = None) -> str:
    try:
        from weasyprint import HTML, CSS
    except ImportError:
        raise RuntimeError("weasyprint غير مثبتة. أضف 'weasyprint' لـ requirements.txt")

    farm_doc = farm_doc or {}

    header = export_data.get("header", {})
    dist = export_data.get("distribution", {})
    biometrics = export_data.get("biometrics", {})
    forecast = export_data.get("forecast", {})
    forecast_next = export_data.get("forecast_next_week", {})
    top_action = export_data.get("top_action") or {}
    map_points = (export_data.get("health_map_points") or export_data.get("health_map") or farm_doc.get("healthMap", []) or []  )
    farm_poly = export_data.get("farm_polygon", []) or farm_doc.get("polygon", [])
    risk_drivers = (export_data.get("risk_drivers", []) or [])[:3]
    hotspots = (export_data.get("hotspots_table", []) or [])[:3]
    indices_table = export_data.get("indices_table", []) or []
    climate = export_data.get("climate", {}) or {}
    alert_context = export_data.get("alert_context", {}) or {}
    multi_trend = export_data.get("multi_trend", {}) or {}
    owner_name = (
        export_data.get("owner_name")
        or header.get("owner_name")
        or farm_doc.get("ownerName")
        or "—"
    )

    # fallback قوي لعدد النخيل من الوثيقة نفسها وقت التصدير
    total_palms = (
        header.get("total_palms")
        or export_data.get("total_palms")
        or export_data.get("finalCount")
        or farm_doc.get("finalCount")
        or farm_doc.get("palmCount")
        or farm_doc.get("totalPalms")
        or 0
    )
    total_palms = _safe_int(total_palms, 0)

    wellness = float(export_data.get("wellness_score", dist.get("Healthy_Pct", 0)))

    healthy_pct = _safe_float(dist.get("Healthy_Pct", 0))
    monitor_pct = _safe_float(dist.get("Monitor_Pct", 0))
    critical_pct = _safe_float(dist.get("Critical_Pct", 0))

    gauge_color = _color_for_pct(wellness)
    gauge_svg = _gauge_svg(wellness, gauge_color, size=124)
    sparkline = _trend_sparkline(forecast.get("trend_data", []), color="#2563eb")
    map_result = _heatmap_svg(map_points, width=490, height=176, farm_polygon=farm_poly)
    map_bg_uri = map_result["bg_data_uri"]
    map_svg    = map_result["overlay_svg"]
    compare_svg = _distribution_compare_svg(dist, forecast_next)
    drivers_bar_svg = _mini_bar_svg(
        [r.get("count", 0) for r in risk_drivers[:3]],
        ["#0ea5e9", "#f59e0b", "#ef4444"]
    )
    # ── قرافات جديدة خاصة بالصفحة الأولى ──
    multi_sparkline_svg = _multi_index_sparkline(multi_trend)
    flag_rows = _flag_breakdown_rows(alert_context.get("flag_counts", {}))
    total_flag_signals = sum(int(r.get("value", 0) or 0) for r in flag_rows)
    sector_rows = _sector_distribution_rows(map_points)
    total_map_points = len([p for p in (map_points or []) if p.get("lat") is not None and p.get("lng") is not None])

    # ── بيانات المناخ والسياق ──
    rain_mm       = _safe_float(climate.get("rain_mm", 0))
    t_mean        = _safe_float(climate.get("t_mean", 0))
    rpw_score     = _safe_float(climate.get("rpw_score", 0))

    # ── نسبة RPW كنص وصفي ──
    total_pixels = int(alert_context.get("total_pixels", 0) or climate.get("total_pixels", 0) or 0)
    pixels_with_any_flag = int(alert_context.get("pixels_with_any_flag", 0) or 0)
    signal_note = alert_context.get("signal_note") or "قد تُسجَّل أكثر من إشارة للبكسل الواحد."

    if critical_pct >= 10:
        rpw_diagnosis = "تحتاج الحالة متابعة عاجلة"
        rpw_diagnosis_sub = "توجد نسبة حرجة ملحوظة في التوزيع العام للمزرعة."
    elif monitor_pct >= 35 or pixels_with_any_flag > 0:
        rpw_diagnosis = "تحتاج الحالة متابعة"
        rpw_diagnosis_sub = "هناك مناطق متأثرة أو إشارات تستلزم مراقبة أقرب."
    else:
        rpw_diagnosis = "الحالة مستقرة حاليًا"
        rpw_diagnosis_sub = "لا توجد إشارات تشغيلية مرتفعة في القراءة الحالية."

    if rpw_score >= 0.66:
        rpw_label = "مرتفع"
        rpw_color = "#dc2626"
    elif rpw_score >= 0.40:
        rpw_label = "متوسط"
        rpw_color = "#f59e0b"
    else:
        rpw_label = "منخفض"
        rpw_color = "#16a34a"
    
    ndvi = biometrics.get("ndvi", {})
    ndmi = biometrics.get("ndmi", {})
    ndre = biometrics.get("ndre", {})

    ndvi_state, ndvi_bg, ndvi_fg = _metric_verdict("NDVI", ndvi.get("val", 0))
    ndmi_state, ndmi_bg, ndmi_fg = _metric_verdict("NDMI", ndmi.get("val", 0))
    ndre_state, ndre_bg, ndre_fg = _metric_verdict("NDRE", ndre.get("val", 0))

    if healthy_pct >= 85 and critical_pct < 5:
        wellness_text = "الحالة العامة جيدة جدًا"
    elif healthy_pct >= 65 and critical_pct < 10:
        wellness_text = "الحالة العامة جيدة"
    elif critical_pct >= 10:
        wellness_text = "الحالة العامة تتطلب تدخلًا أسرع"
    else:
        wellness_text = "الحالة العامة تحتاج متابعة"

    wellness_desc = (
        "يعرض هذا التقرير الوضع الحالي للمزرعة استنادًا إلى المؤشرات الطيفية "
        "وتوزيع النقاط المتأثرة داخل حدود المزرعة."
    )

    report_date = header.get("date") or datetime.now().strftime("%Y-%m-%d")
    farm_name = header.get("name") or export_data.get("farmName") or farm_doc.get("farmName") or "—"
    farm_area = header.get("area") or export_data.get("farmSize") or farm_doc.get("farmSize") or "—"
    contract_number = header.get("contract_number") or farm_doc.get("contractNumber") or "—"
    region = header.get("city") or farm_doc.get("region") or "—"

    executive_status = export_data.get("executive_status", "ملخص الحالة")
    executive_summary = export_data.get("executive_summary", "—")
    executive_next_step = export_data.get("executive_next_step", top_action.get("title_ar", "—"))

    forecast_text = forecast.get("text", "—")
    forecast_summary = {
        "healthy": f"{_safe_float(forecast_next.get('Healthy_Pct_next', healthy_pct), 0):.1f}%",
        "monitor": f"{_safe_float(forecast_next.get('Monitor_Pct_next', monitor_pct), 0):.1f}%",
        "critical": f"{_safe_float(forecast_next.get('Critical_Pct_next', critical_pct), 0):.1f}%",
    }
    forecast_change_text = _delta_badge_html(_safe_float(forecast_next.get("ndvi_delta_next_mean"), 0) * 100.0)

    if not indices_table:
        indices_table = [
            {
                "label": "الخضرة",
                "code": "NDVI",
                "value": f"{_safe_float(ndvi.get('val', 0), 0):.2f}",
                "note": "يقيس كثافة الغطاء النباتي وحيوية النمو بشكل عام.",
            },
            {
                "label": "الرطوبة",
                "code": "NDMI",
                "value": f"{_safe_float(ndmi.get('val', 0), 0):.2f}",
                "note": "يعكس مستوى الرطوبة في المجموع الخضري واحتمال الإجهاد المائي.",
            },
            {
                "label": "حيوية الأوراق",
                "code": "NDRE",
                "value": f"{_safe_float(ndre.get('val', 0), 0):.2f}",
                "note": "يفيد في قراءة نشاط الأوراق والحالة التغذوية بشكل مبكر.",
            },
        ]


    logo_data_uri = _load_local_image_as_data_uri("static", "images", "saaf_logo.png")
    palm_icon_data_uri = _load_local_image_as_data_uri("static", "images", "PalmIcon.png")

    if not logo_data_uri:
        logger.warning("saaf_logo.png was not loaded, using inline fallback watermark.")
    if not palm_icon_data_uri:
        logger.warning("PalmIcon.png was not loaded, using fallback watermark.")

    watermark_data_uri = palm_icon_data_uri or logo_data_uri or _default_watermark_data_uri()
    footer_logo_html = _footer_logo_html(logo_data_uri)

    html_content = render_template(
        "reports/farm_report.html",
        farm_id=farm_id,
        farm_name=farm_name,
        farm_area=farm_area,
        total_palms=total_palms,
        report_date=report_date,
        contract_number=contract_number,
        region=region,
        owner_name=owner_name,

        logo_data_uri=logo_data_uri,
        palm_icon_data_uri=watermark_data_uri,
        footer_logo_html=footer_logo_html,

        executive_status=executive_status,
        executive_summary=executive_summary,
        executive_next_step=executive_next_step,

        gauge_svg=gauge_svg,
        gauge_color=gauge_color,
        wellness_text=wellness_text,
        wellness_desc=wellness_desc,
        healthy_pct=healthy_pct,
        monitor_pct=monitor_pct,
        critical_pct=critical_pct,

        map_svg=map_svg,
        map_bg_uri=map_bg_uri,
        compare_labels=["سليم", "متابعة", "حرج"],
        total_flag_signals=total_flag_signals,
        sector_rows=sector_rows,
        total_map_points=total_map_points,

        compare_svg=compare_svg,
        drivers_bar_svg=drivers_bar_svg,
        multi_sparkline_svg=multi_sparkline_svg,
        flag_rows=flag_rows,
        stress_pixels=f"{pixels_with_any_flag:,}".replace(",", "،"),
        stress_pixels_note=signal_note,
        trend_start_label=(multi_trend.get("dates") or ["الأقدم"])[0] if (multi_trend.get("dates") or []) else "الأقدم",
        trend_end_label=(multi_trend.get("dates") or ["الأحدث"])[-1] if (multi_trend.get("dates") or []) else "الأحدث",

        rain_mm=f"{rain_mm:.1f}",
        t_mean=f"{t_mean:.1f}",
        rpw_score=f"{rpw_score:.2f}",
        rpw_label=rpw_label,
        rpw_color=rpw_color,
        total_pixels=f"{total_pixels:,}".replace(",", "،"),

        ndvi_val=f"{_safe_float(ndvi.get('val', 0), 0):.2f}",
        ndmi_val=f"{_safe_float(ndmi.get('val', 0), 0):.2f}",
        ndre_val=f"{_safe_float(ndre.get('val', 0), 0):.2f}",

        ndvi_state=ndvi_state,
        ndvi_bg=ndvi_bg,
        ndvi_fg=ndvi_fg,
        ndmi_state=ndmi_state,
        ndmi_bg=ndmi_bg,
        ndmi_fg=ndmi_fg,
        ndre_state=ndre_state,
        ndre_bg=ndre_bg,
        ndre_fg=ndre_fg,

        ndvi_delta_badge=_delta_badge_html(_safe_float(ndvi.get("delta", 0), 0)),
        ndmi_delta_badge=_delta_badge_html(_safe_float(ndmi.get("delta", 0), 0)),
        ndre_delta_badge=_delta_badge_html(_safe_float(ndre.get("delta", 0), 0)),

        indices_table=indices_table,
        forecast_text=forecast_text,
        forecast_change_text=forecast_change_text,
        sparkline=sparkline,
        forecast_summary=forecast_summary,

        risk_drivers=risk_drivers,
        hotspots=hotspots,
        rpw_diagnosis=rpw_diagnosis,
        rpw_diagnosis_sub=rpw_diagnosis_sub,
    )

    output_path = f"/tmp/saaf_report_{farm_id}.pdf"

    HTML(string=html_content).write_pdf(
        output_path,
        stylesheets=[CSS(string="@page { size: A4; margin: 0; }")]
    )

    return output_path


# ─────────────────────────────────────────────
# Excel Generation — openpyxl
# ─────────────────────────────────────────────

def generate_excel_report(export_data: dict, farm_id: str) -> str:
    import openpyxl
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
    from openpyxl.utils import get_column_letter

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "تقرير المزرعة"
    ws.sheet_view.rightToLeft = True

    header = export_data.get("header", {})
    dist = export_data.get("distribution", {})
    forecast = export_data.get("forecast", {})
    hotspots = export_data.get("hotspots_table", [])[:3]
    owner_name = export_data.get("owner_name", "—")
    wellness = float(export_data.get("wellness_score", dist.get("Healthy_Pct", 0)))

    GREEN_DARK = "064E3B"
    GREEN_MID = "10B981"
    GREEN_LIGHT = "D1FAE5"
    ORANGE = "F59E0B"
    RED = "EF4444"
    BORDER_CLR = "E2E8F0"

    def side(color="E2E8F0"):
        return Side(style="thin", color=color)

    def full_border(color="E2E8F0"):
        s = side(color)
        return Border(left=s, right=s, top=s, bottom=s)

    def header_font(sz=12, bold=True, color="FFFFFF"):
        return Font(name="Cairo", size=sz, bold=bold, color=color)

    def body_font(sz=11, bold=False, color="1E293B"):
        return Font(name="Cairo", size=sz, bold=bold, color=color)

    def fill(hex_color):
        return PatternFill("solid", fgColor=hex_color)

    def center(wrap=False):
        return Alignment(horizontal="center", vertical="center", wrap_text=wrap, readingOrder=2)

    ws.merge_cells("A1:F1")
    c = ws["A1"]
    c.value = "سعف — تقرير تحليل صحة المزرعة"
    c.font = Font(name="Cairo", size=16, bold=True, color="FFFFFF")
    c.fill = fill(GREEN_DARK)
    c.alignment = center()

    info_labels = ["اسم المزرعة", "رقم العقد", "المنطقة", "اسم المالك", "المساحة", "عدد النخيل",
                   "تاريخ التقرير", "مؤشر الحالة"]
    info_vals = [
        header.get("name", export_data.get("farmName", "—")),
        header.get("contract_number", "—"),
        header.get("city", "—"),
        owner_name,
        f"{header.get('area', export_data.get('farmSize', '—'))}",
        str(header.get("total_palms") or export_data.get("finalCount") or 0),
        header.get("date", datetime.now().strftime("%Y-%m-%d")),
        f"{wellness:.1f}%"
    ]

    for col, (lbl, val) in enumerate(zip(info_labels, info_vals), start=1):
        cl = ws.cell(row=2, column=col, value=lbl)
        cl.font = Font(name="Cairo", size=10, bold=True, color="064E3B")
        cl.fill = fill(GREEN_LIGHT)
        cl.alignment = center()
        cl.border = full_border(BORDER_CLR)

        cv = ws.cell(row=3, column=col, value=val)
        cv.font = body_font(11, bold=True)
        cv.alignment = center()
        cv.border = full_border(BORDER_CLR)

    ws.merge_cells("A5:F5")
    c = ws["A5"]
    c.value = "توزيع الحالة الصحية"
    c.font = header_font(12)
    c.fill = fill(GREEN_MID)
    c.alignment = center()

    dist_data = [
        ("سليم", dist.get("Healthy_Pct", 0), GREEN_MID),
        ("متابعة", dist.get("Monitor_Pct", 0), ORANGE),
        ("حرج", dist.get("Critical_Pct", 0), RED),
    ]
    for i, (lbl, pct, clr) in enumerate(dist_data):
        row = 6 + i
        ws.merge_cells(f"A{row}:C{row}")
        ws.cell(row=row, column=1, value=lbl).font = body_font(11, bold=True)
        ws.cell(row=row, column=1).alignment = center()
        ws.cell(row=row, column=1).border = full_border()

        ws.merge_cells(f"D{row}:F{row}")
        ws.cell(row=row, column=4, value=f"{_safe_float(pct):.1f}%").font = Font(name="Cairo", size=12, bold=True, color=clr)
        ws.cell(row=row, column=4).alignment = center()
        ws.cell(row=row, column=4).border = full_border()

    ws.merge_cells("A10:F10")
    c = ws["A10"]
    c.value = "توقع الأسبوع القادم"
    c.font = header_font(12)
    c.fill = fill(GREEN_MID)
    c.alignment = center()

    ws.merge_cells("A11:F11")
    c = ws["A11"]
    c.value = forecast.get("text", "—")
    c.font = body_font(11)
    c.alignment = center(wrap=True)
    c.border = full_border()

    if hotspots:
        ws.merge_cells("A13:F13")
        c = ws["A13"]
        c.value = "أهم المناطق التي تحتاج متابعة"
        c.font = header_font(12)
        c.fill = fill("7F1D1D")
        c.alignment = center()

        headers = ["#", "خط العرض", "خط الطول", "الحالة", "الوصف", ""]
        for col, h in enumerate(headers, 1):
            cell = ws.cell(row=14, column=col, value=h)
            cell.font = Font(name="Cairo", size=10, bold=True, color="374151")
            cell.fill = fill("FEE2E2")
            cell.alignment = center()
            cell.border = full_border()

        for j, pt in enumerate(hotspots[:3]):
            row = 15 + j
            vals = [j + 1, pt.get("lat", "—"), pt.get("lon", "—"), pt.get("status", "—"), pt.get("note", "—"), ""]
            for col, v in enumerate(vals, 1):
                cell = ws.cell(row=row, column=col, value=v)
                cell.font = body_font(10)
                cell.alignment = center(wrap=True)
                cell.border = full_border()

    for i, w in enumerate([22, 18, 18, 18, 18, 14], 1):
        ws.column_dimensions[get_column_letter(i)].width = w

    output_path = f"/tmp/saaf_report_{farm_id}.xlsx"
    wb.save(output_path)
    return output_path
def _first_non_empty(*values):
    for v in values:
        if v is None:
            continue
        if isinstance(v, str) and not v.strip():
            continue
        if isinstance(v, (list, dict, tuple, set)) and len(v) == 0:
            continue
        if v == "":
            continue
        return v
    return None

def _prefer_live_number(old_value, live_value, default=0):
    """
    إذا القيمة القديمة None/فارغة نأخذ الحية.
    وإذا القديمة = 0 لكن الحية غير صفر، نأخذ الحية.
    وإلا نُبقي القديمة.
    """
    try:
        if old_value is None:
            return live_value if live_value is not None else default

        if isinstance(old_value, str) and not old_value.strip():
            return live_value if live_value is not None else default

        old_num = float(old_value)
        live_num = float(live_value) if live_value is not None else None

        if (math.isnan(old_num) or old_num == 0) and live_num not in (None, 0):

            return live_value

        return old_value
    except Exception:
        return live_value if live_value is not None else default
    

def _merge_export_with_live_farm_data(export_data: dict, farm_data: dict) -> dict:
    """
    يوحّد مصدر بيانات التقرير مع البيانات الحية الموجودة في وثيقة المزرعة.
    الهدف: إذا export_data ناقص أو قديم، نأخذ fallback من farm_data.
    """
    export_data = dict(export_data or {})
    farm_data = farm_data or {}

    health_root = farm_data.get("health") if isinstance(farm_data.get("health"), dict) else {}
    current_health = health_root.get("current_health") if isinstance(health_root.get("current_health"), dict) else {}
    forecast_next = health_root.get("forecast_next_week") if isinstance(health_root.get("forecast_next_week"), dict) else {}

    # ── Header fallback ─────────────────────────
    header = dict(export_data.get("header", {}) or {})
    header["name"] = _first_non_empty(header.get("name"), farm_data.get("farmName"), "—")
    header["area"] = _first_non_empty(header.get("area"), farm_data.get("farmSize"), "—")
    header["city"] = _first_non_empty(header.get("city"), farm_data.get("region"), farm_data.get("city"), "—")
    header["contract_number"] = _first_non_empty(header.get("contract_number"), farm_data.get("contractNumber"), "—")
    header["owner_name"] = _first_non_empty(header.get("owner_name"), farm_data.get("ownerName"), "—")
    header["total_palms"] = _first_non_empty(
        header.get("total_palms"),
        export_data.get("finalCount"),
        farm_data.get("finalCount"),
        farm_data.get("palmCount"),
        farm_data.get("totalPalms"),
        0,
    )
    export_data["header"] = header

    # ── حقول مباشرة ─────────────────────────────
    export_data["farmName"] = _first_non_empty(export_data.get("farmName"), farm_data.get("farmName"))
    export_data["farmSize"] = _first_non_empty(export_data.get("farmSize"), farm_data.get("farmSize"))
    export_data["finalCount"] = _first_non_empty(
        export_data.get("finalCount"),
        farm_data.get("finalCount"),
        farm_data.get("palmCount"),
        farm_data.get("totalPalms"),
        0,
    )
    export_data["owner_name"] = _first_non_empty(export_data.get("owner_name"), farm_data.get("ownerName"), "—")

    # ── polygon fallback ────────────────────────
    export_data["farm_polygon"] = _first_non_empty(
        export_data.get("farm_polygon"),
        farm_data.get("polygon"),
        [],
    )

    # ── الخريطة ─────────────────────────────────
    export_data["health_map_points"] = _first_non_empty(
        export_data.get("health_map_points"),
        farm_data.get("healthMap"),
        [],
    )

    # ── التوزيع الحالي ─────────────────────────
    dist = dict(export_data.get("distribution", {}) or {})
    export_data["distribution"] = {
        "Healthy_Pct": _prefer_live_number(dist.get("Healthy_Pct"), current_health.get("Healthy_Pct"), 0),
        "Monitor_Pct": _prefer_live_number(dist.get("Monitor_Pct"), current_health.get("Monitor_Pct"), 0),
        "Critical_Pct": _prefer_live_number(dist.get("Critical_Pct"), current_health.get("Critical_Pct"), 0),
    }

    # ── توقع الأسبوع القادم ────────────────────
    next_week = dict(export_data.get("forecast_next_week", {}) or {})
    export_data["forecast_next_week"] = {
        "Healthy_Pct_next": _prefer_live_number(next_week.get("Healthy_Pct_next"), forecast_next.get("Healthy_Pct_next"), 0),
        "Monitor_Pct_next": _prefer_live_number(next_week.get("Monitor_Pct_next"), forecast_next.get("Monitor_Pct_next"), 0),
        "Critical_Pct_next": _prefer_live_number(next_week.get("Critical_Pct_next"), forecast_next.get("Critical_Pct_next"), 0),
        "ndvi_delta_next_mean": _prefer_live_number(next_week.get("ndvi_delta_next_mean"), forecast_next.get("ndvi_delta_next_mean"), 0),
        "ndmi_delta_next_mean": _prefer_live_number(next_week.get("ndmi_delta_next_mean"), forecast_next.get("ndmi_delta_next_mean"), 0),
    }

    # ── المؤشرات الحيوية ────────────────────────
    biometrics = dict(export_data.get("biometrics", {}) or {})
    export_data["biometrics"] = {
        "ndvi": {
            "val": _prefer_live_number(
                (biometrics.get("ndvi") or {}).get("val") if isinstance(biometrics.get("ndvi"), dict) else None,
                _first_non_empty(current_health.get("NDVI"), current_health.get("ndvi_mean")),
                0,
            ),
            "delta": _prefer_live_number(
                (biometrics.get("ndvi") or {}).get("delta") if isinstance(biometrics.get("ndvi"), dict) else None,
                current_health.get("NDVI_delta"),
                0,
            ),
        },
        "ndmi": {
            "val": _prefer_live_number(
                (biometrics.get("ndmi") or {}).get("val") if isinstance(biometrics.get("ndmi"), dict) else None,
                _first_non_empty(current_health.get("NDMI"), current_health.get("ndmi_mean")),
                0,
            ),
            "delta": _prefer_live_number(
                (biometrics.get("ndmi") or {}).get("delta") if isinstance(biometrics.get("ndmi"), dict) else None,
                current_health.get("NDMI_delta"),
                0,
            ),
        },
        "ndre": {
            "val": _prefer_live_number(
                (biometrics.get("ndre") or {}).get("val") if isinstance(biometrics.get("ndre"), dict) else None,
                _first_non_empty(current_health.get("NDRE"), current_health.get("ndre_mean")),
                0,
            ),
            "delta": _prefer_live_number(
                (biometrics.get("ndre") or {}).get("delta") if isinstance(biometrics.get("ndre"), dict) else None,
                current_health.get("NDRE_delta"),
                0,
            ),
        },
    }

    # ── climate / alert_context ─────────────────
    climate = dict(export_data.get("climate", {}) or {})
    export_data["climate"] = {
        **climate,
        "rain_mm": _first_non_empty(climate.get("rain_mm"), 0),
        "t_mean": _first_non_empty(climate.get("t_mean"), 0),
        "total_pixels": _prefer_live_number(climate.get("total_pixels"), current_health.get("total_pixels"), 0),
        "rpw_score": _prefer_live_number(climate.get("rpw_score"), current_health.get("rpw_score"), 0),
    }

    alert_context = dict(export_data.get("alert_context", {}) or {})
    export_data["alert_context"] = {
        **alert_context,
        "total_pixels": _prefer_live_number(alert_context.get("total_pixels"), current_health.get("total_pixels"), 0),
        "pixels_with_any_flag": _prefer_live_number(
            alert_context.get("pixels_with_any_flag"),
            current_health.get("pixels_with_any_flag"),
            0,
        ),
        "flag_counts": _first_non_empty(alert_context.get("flag_counts"), {}),
    }

    # ── trend fallback ──────────────────────────
    if not export_data.get("multi_trend"):
        hist = health_root.get("indices_history_last_month", []) or []
        export_data["multi_trend"] = {
            "dates": [x.get("date") for x in hist if isinstance(x, dict)],
            "ndvi": [x.get("NDVI") for x in hist if isinstance(x, dict)],
            "ndmi": [x.get("NDMI") for x in hist if isinstance(x, dict)],
            "ndre": [x.get("NDRE") for x in hist if isinstance(x, dict)],
        }

    return export_data
# ─────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────
def _deg_to_tile(lat: float, lon: float, zoom: int):
    lat_rad = math.radians(lat)
    n = 2.0 ** zoom
    xtile = int((lon + 180.0) / 360.0 * n)
    ytile = int(
        n * (1.0 - math.log(math.tan(lat_rad) + (1 / math.cos(lat_rad))) / math.pi) / 2.0
    )
    return xtile, ytile


def _stitch_maptiler_tiles(bounds: dict, width: int, height: int, zoom: int = 18) -> str | None:
    try:
        api_key = os.environ.get("MAPTILER_KEY", "").strip()
        if not api_key or not bounds:
            return None

        center_lat = (bounds["min_lat"] + bounds["max_lat"]) / 2.0
        center_lng = (bounds["min_lng"] + bounds["max_lng"]) / 2.0

        cx, cy = _deg_to_tile(center_lat, center_lng, zoom)

        tiles_x = max(1, math.ceil(width / TILE_SIZE_MAP))
        tiles_y = max(1, math.ceil(height / TILE_SIZE_MAP))

        start_x = cx - (tiles_x // 2)
        start_y = cy - (tiles_y // 2)

        stitched = Image.new("RGB", (tiles_x * TILE_SIZE_MAP, tiles_y * TILE_SIZE_MAP))

        for ix in range(tiles_x):
            for iy in range(tiles_y):
                x = start_x + ix
                y = start_y + iy
                url = REPORT_TILE_URL.format(zoom=zoom, x=x, y=y, key=api_key)

                resp = requests.get(url, timeout=20)
                resp.raise_for_status()

                tile_img = Image.open(io.BytesIO(resp.content)).convert("RGB")
                stitched.paste(tile_img, (ix * TILE_SIZE_MAP, iy * TILE_SIZE_MAP))

        stitched = stitched.crop((0, 0, width, height))

        buffer = io.BytesIO()
        stitched.save(buffer, format="JPEG", quality=85)
        img_b64 = base64.b64encode(buffer.getvalue()).decode("utf-8")
        return f"data:image/jpeg;base64,{img_b64}"

    except Exception as e:
        logger.warning(f"Failed to stitch MapTiler tiles: {e}")
        return None
    
@reports_bp.route('/reports/<farm_id>/pdf', methods=['GET'])
def export_pdf(farm_id):
    try:
        doc, _ = get_farm_safely(farm_id)
        if not doc:
            return jsonify({"ok": False, "error": "المزرعة غير موجودة"}), 404

        farm_data = doc.to_dict() or {}
        export_data = farm_data.get('export_data') or {}

        if not export_data and not farm_data.get("health"):
            return jsonify({"ok": False, "error": "بيانات التحليل ناقصة. شغّل التحليل أولاً."}), 400

        export_data = _merge_export_with_live_farm_data(export_data, farm_data)

        logger.info(
            "PDF export debug | farm_id=%s | healthMap=%s | export health_map_points=%s | total_pixels=%s | rain_mm=%s | t_mean=%s",
            farm_id,
            len(farm_data.get("healthMap", []) or []),
            len(export_data.get("health_map_points", []) or []),
            ((export_data.get("alert_context", {}) or {}).get("total_pixels")),
            ((export_data.get("climate", {}) or {}).get("rain_mm")),
            ((export_data.get("climate", {}) or {}).get("t_mean")),
        )
        pdf_path = generate_pdf_report(export_data, farm_id, farm_doc=farm_data)
        with open(pdf_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')

        return jsonify({
            "ok": True,
            "pdfBase64": encoded,
            "fileName": f"Saaf_Report_{farm_id}.pdf"
        }), 200

    except Exception as e:
        logger.error(f"💥 PDF Route Crash: {traceback.format_exc()}")
        return jsonify({
            "ok": False,
            "error": str(e),
            "trace": traceback.format_exc()
        }), 500


@reports_bp.route('/reports/<farm_id>/excel', methods=['GET'])
def export_excel(farm_id):
    try:
        doc, _ = get_farm_safely(farm_id)
        if not doc:
            return jsonify({"ok": False, "error": "المزرعة غير موجودة"}), 404

        farm_data = doc.to_dict() or {}
        export_data = farm_data.get('export_data') or {}

        if not export_data and not farm_data.get("health"):
            return jsonify({"ok": False, "error": "بيانات التحليل ناقصة. شغّل التحليل أولاً."}), 400

        export_data = _merge_export_with_live_farm_data(export_data, farm_data)

        excel_path = generate_excel_report(export_data, farm_id)
        with open(excel_path, "rb") as f:
            encoded = base64.b64encode(f.read()).decode('utf-8')

        return jsonify({
            "ok": True,
            "excelBase64": encoded,
            "fileName": f"Saaf_Report_{farm_id}.xlsx"
        }), 200

    except Exception as e:
        logger.error(f"💥 Excel Route Crash: {traceback.format_exc()}")
        return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()}), 500