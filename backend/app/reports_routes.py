import base64
import os
import logging
import traceback
from datetime import datetime

from flask import Blueprint, jsonify, render_template
from google.cloud import firestore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DB = firestore.Client()
reports_bp = Blueprint("reports_bp", __name__)


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
        return float(v)
    except Exception:
        return default


def _safe_int(v, default=0):
    try:
        if v is None:
            return default
        return int(v)
    except Exception:
        return default


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


def _distribution_compare_svg(current_dist: dict, next_dist: dict, width: int = 245, height: int = 112) -> str:
    """
    قراف مقارنة بسيط بدون نص عربي داخل SVG لتجنب مشاكل الاتجاه.
    3 مجموعات: healthy / monitor / critical
    عمود غامق = current
    عمود فاتح = next
    """
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

    colors = ["#22c55e", "#f59e0b", "#ef4444"]

    base_y = 92
    bar_max_h = 58
    bar_w = 12
    gap = 7
    group_gap = 28
    x = 28

    parts = [
        f'<line x1="8" y1="{base_y}" x2="{width-8}" y2="{base_y}" stroke="#e5e7eb" stroke-width="1"/>'
    ]

    for i in range(3):
        cur_h = max(0, min(100, current_vals[i])) / 100.0 * bar_max_h
        nxt_h = max(0, min(100, next_vals[i])) / 100.0 * bar_max_h
        color = colors[i]

        parts.append(
            f'<rect x="{x}" y="{base_y-cur_h:.1f}" width="{bar_w}" height="{cur_h:.1f}" '
            f'rx="4" fill="{color}" opacity="0.95"/>'
        )
        parts.append(
            f'<rect x="{x+bar_w+gap}" y="{base_y-nxt_h:.1f}" width="{bar_w}" height="{nxt_h:.1f}" '
            f'rx="4" fill="{color}" opacity="0.28" stroke="{color}" stroke-width="1"/>'
        )

        x += (bar_w * 2 + gap + group_gap)

    return f"""
<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}">
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


def _heatmap_svg(map_points: list, width: int = 505, height: int = 280, farm_polygon: list | None = None) -> str:
    norm_poly = _normalize_polygon(farm_polygon)

    if not map_points and not norm_poly:
        return ""

    lats = []
    lngs = []

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
        return ""

    min_lat, max_lat = min(lats), max(lats)
    min_lng, max_lng = min(lngs), max(lngs)

    lat_rng = max(max_lat - min_lat, 1e-6)
    lng_rng = max(max_lng - min_lng, 1e-6)
    pad = 12

    def to_xy(lat, lng):
        x = pad + ((lng - min_lng) / lng_rng) * (width - pad * 2)
        y = pad + ((max_lat - lat) / lat_rng) * (height - pad * 2)
        return round(x, 1), round(y, 1)

    color_map = {
        0: "#22c55e",
        1: "#f59e0b",
        2: "#ef4444",
    }

    poly_svg = ""
    if norm_poly:
        pts = " ".join(f"{x},{y}" for x, y in [to_xy(lat, lng) for lat, lng in norm_poly])
        poly_svg = (
            f'<polygon points="{pts}" fill="#f0fdf4" stroke="#10b981" '
            f'stroke-width="2.2" opacity="0.98"/>'
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
                f'stroke="#2563eb" stroke-width="1.5" opacity="0.92"/>'
            )

        circles.append(
            ring +
            f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" opacity="0.96" />'
        )

    return f"""
<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}"
     xmlns="http://www.w3.org/2000/svg">
  <rect width="{width}" height="{height}" rx="14" fill="#ffffff"/>
  <rect x="0.5" y="0.5" width="{width-1}" height="{height-1}" rx="14"
        fill="none" stroke="#dde8e1"/>
  {poly_svg}
  {''.join(circles)}
</svg>
""".strip()


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
        return f'<img src="{logo_data_uri}" alt="Saaf" style="height:16px; width:auto; display:block;" />'
    return '<div style="font-size:12px;font-weight:900;color:#6ee7b7;">سعف</div>'


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
    map_points = export_data.get("health_map_points", [])
    farm_poly = export_data.get("farm_polygon", []) or farm_doc.get("polygon", [])
    risk_drivers = (export_data.get("risk_drivers", []) or [])[:3]
    hotspots = (export_data.get("hotspots_table", []) or [])[:3]
    indices_table = export_data.get("indices_table", []) or []
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
    map_svg = _heatmap_svg(map_points, farm_polygon=farm_poly)
    compare_svg = _distribution_compare_svg(dist, forecast_next)
    drivers_bar_svg = _mini_bar_svg(
        [r.get("count", 0) for r in risk_drivers[:3]],
        ["#0ea5e9", "#f59e0b", "#ef4444"]
    )

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

    critical_hotspots_count = len([h for h in hotspots if h.get("status") == "حرجة"])
    monitor_hotspots_count = len([h for h in hotspots if h.get("status") == "متابعة"])
    top_driver = risk_drivers[0]["title"] if risk_drivers else "—"
    top_action_title = top_action.get("title_ar", "—")
    top_action_text = top_action.get("text_ar", "—")

    map_note = (
        "اللون يوضح الحالة الحالية لكل نقطة داخل حدود المزرعة، "
        "والحلقة الزرقاء تشير إلى نقاط قد تتغير حالتها لاحقًا."
    )

    logo_data_uri = None
    logo_path = os.path.join(os.path.dirname(__file__), "static", "images", "saaf_logo.png")
    if os.path.exists(logo_path):
        with open(logo_path, "rb") as img_file:
            logo_b64 = base64.b64encode(img_file.read()).decode("utf-8")
            logo_data_uri = f"data:image/png;base64,{logo_b64}"

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
        map_note=map_note,
        critical_hotspots_count=critical_hotspots_count,
        monitor_hotspots_count=monitor_hotspots_count,
        top_driver=top_driver,
        top_action_title=top_action_title,
        top_action_text=top_action_text,

        compare_svg=compare_svg,
        drivers_bar_svg=drivers_bar_svg,

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


# ─────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────

@reports_bp.route('/reports/<farm_id>/pdf', methods=['GET'])
def export_pdf(farm_id):
    try:
        doc, _ = get_farm_safely(farm_id)
        if not doc:
            return jsonify({"ok": False, "error": "المزرعة غير موجودة"}), 404

        farm_data = doc.to_dict() or {}
        export_data = farm_data.get('export_data')
        if not export_data:
            return jsonify({"ok": False, "error": "بيانات التحليل ناقصة. شغّل التحليل أولاً."}), 400

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
        export_data = farm_data.get('export_data', {})
        if not export_data:
            return jsonify({"ok": False, "error": "بيانات التحليل ناقصة. شغّل التحليل أولاً."}), 400

        # fallback count if export_data stale
        if not export_data.get("finalCount"):
            export_data["finalCount"] = farm_data.get("finalCount", 0)

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