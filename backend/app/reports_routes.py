# app/reports_routes.py
import base64
import os
import logging
import traceback
from datetime import datetime

import pandas as pd
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


def _color_for_pct(pct: float) -> str:
    """لون حسب النسبة: أخضر / برتقالي / أحمر"""
    if pct >= 70:
        return "#22c55e"
    if pct >= 40:
        return "#f59e0b"
    return "#ef4444"


def _gauge_svg(pct: float, color: str, size: int = 120) -> str:
    """
    SVG نصف دائرة (Gauge) يعرض نسبة مئوية.
    pct: 0–100
    """
    pct = max(0.0, min(100.0, float(pct)))
    r = 46
    cx = cy = size / 2
    circumference = 3.14159 * r          # نصف الدائرة فقط
    stroke_dash = (pct / 100) * circumference
    stroke_gap = circumference - stroke_dash

    return f"""
<svg width="{size}" height="{size // 2 + 20}" viewBox="0 0 {size} {size // 2 + 20}">
  <!-- خلفية رمادية -->
  <path d="M {cx - r} {cy} A {r} {r} 0 0 1 {cx + r} {cy}"
        fill="none" stroke="#e5e7eb" stroke-width="10" stroke-linecap="round"/>
  <!-- القوس الملون -->
  <path d="M {cx - r} {cy} A {r} {r} 0 0 1 {cx + r} {cy}"
        fill="none" stroke="{color}" stroke-width="10" stroke-linecap="round"
        stroke-dasharray="{stroke_dash:.1f} {stroke_gap:.1f}"
        transform="rotate(0, {cx}, {cy})"/>
  <!-- النص -->
  <text x="{cx}" y="{cy + 8}" text-anchor="middle"
        font-family="Cairo, sans-serif" font-size="18" font-weight="700" fill="{color}">
    {pct:.0f}%
  </text>
</svg>""".strip()


def _trend_sparkline(values: list, color: str = "#22c55e", width: int = 160, height: int = 40) -> str:
    """رسم خط بياني بسيط SVG من قائمة أرقام"""
    if not values or len(values) < 2:
        return ""
    vals = [float(v) for v in values if v is not None]
    if len(vals) < 2:
        return ""
    mn, mx = min(vals), max(vals)
    rng = mx - mn if mx != mn else 1
    step = width / (len(vals) - 1)
    pts = []
    for i, v in enumerate(vals):
        x = i * step
        y = height - ((v - mn) / rng) * (height - 6) - 3
        pts.append(f"{x:.1f},{y:.1f}")
    polyline = " ".join(pts)
    return f"""
<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <polyline points="{polyline}" fill="none" stroke="{color}" stroke-width="2.5"
            stroke-linejoin="round" stroke-linecap="round"/>
</svg>""".strip()


def _heatmap_svg(map_points: list, width: int = 320, height: int = 185) -> str:
    """
    يرسم خريطة حرارية SVG حقيقية من نقاط health_map.
    كل نقطة: {"lat": float, "lng": float, "s": 0|1|2}
    s=0 سليم (أخضر)، s=1 متابعة (برتقالي)، s=2 حرج (أحمر+توهج)
    """
    if not map_points:
        return ""

    lats = [p.get("lat", 0) for p in map_points]
    lngs = [p.get("lng", 0) for p in map_points]
    min_lat, max_lat = min(lats), max(lats)
    min_lng, max_lng = min(lngs), max(lngs)
    lat_rng = max_lat - min_lat or 1e-6
    lng_rng = max_lng - min_lng or 1e-6
    pad = 18

    def to_xy(lat, lng):
        x = pad + ((lng - min_lng) / lng_rng) * (width  - pad * 2)
        y = pad + ((max_lat - lat)  / lat_rng) * (height - pad * 2)
        return round(x, 1), round(y, 1)

    color_map   = {0: "#22c55e", 1: "#f59e0b", 2: "#ef4444"}
    opacity_map = {0: "0.70",    1: "0.85",    2: "0.95"}
    radius_map  = {0: 4,         1: 5.5,        2: 7}

    layers: dict = {0: [], 1: [], 2: []}
    for pt in map_points:
        try:
            s = int(pt.get("s", 0))
        except (TypeError, ValueError):
            s = 0

        if s not in layers:
            s = 0

        try:
            lat = float(pt.get("lat", 0))
            lng = float(pt.get("lng", 0))
        except (TypeError, ValueError):
            continue

        layers[s].append(to_xy(lat, lng))

    circles = ""
    for s in [0, 1, 2]:
        glow = 'filter="url(#glow)"' if s == 2 else ""
        for x, y in layers[s]:
            circles += (
                f'<circle cx="{x}" cy="{y}" r="{radius_map[s]}" '
                f'fill="{color_map[s]}" opacity="{opacity_map[s]}" {glow}/>\n'
            )

    corners = [
        to_xy(min_lat, min_lng), to_xy(min_lat, max_lng),
        to_xy(max_lat, max_lng), to_xy(max_lat, min_lng),
    ]
    pts_str = " ".join(f"{x},{y}" for x, y in corners)

    crit_label = ""
    if layers[2]:
        avg_x = sum(x for x, _ in layers[2]) / len(layers[2])
        avg_y = sum(y for _, y in layers[2]) / len(layers[2])
        lbl_y = min(avg_y + 18, height - 6)
        crit_label = (
            f'<rect x="{avg_x-52}" y="{lbl_y-12}" width="104" height="16" '
            f'rx="4" fill="#7f1d1d" opacity="0.85"/>'
            f'<text x="{avg_x}" y="{lbl_y}" text-anchor="middle" '
            f'font-family="Cairo,sans-serif" font-size="9" fill="#fca5a5">'
            f'⚠ منطقة تحتاج تدخل</text>'
        )

    return (
        f'<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}" '
        f'xmlns="http://www.w3.org/2000/svg">'
        f'<defs>'
        f'<radialGradient id="mapbg" cx="50%" cy="50%" r="70%">'
        f'<stop offset="0%" stop-color="#1a3a2a"/>'
        f'<stop offset="100%" stop-color="#0a1f14"/></radialGradient>'
        f'<filter id="glow"><feGaussianBlur stdDeviation="3" result="coloredBlur"/>'
        f'<feMerge><feMergeNode in="coloredBlur"/>'
        f'<feMergeNode in="SourceGraphic"/></feMerge></filter>'
        f'</defs>'
        f'<rect width="{width}" height="{height}" fill="url(#mapbg)"/>'
        f'<line x1="{width//4}" y1="0" x2="{width//4}" y2="{height}" stroke="#1e4d30" stroke-width="0.4"/>'
        f'<line x1="{width//2}" y1="0" x2="{width//2}" y2="{height}" stroke="#1e4d30" stroke-width="0.4"/>'
        f'<line x1="{3*width//4}" y1="0" x2="{3*width//4}" y2="{height}" stroke="#1e4d30" stroke-width="0.4"/>'
        f'<line x1="0" y1="{height//3}" x2="{width}" y2="{height//3}" stroke="#1e4d30" stroke-width="0.4"/>'
        f'<line x1="0" y1="{2*height//3}" x2="{width}" y2="{2*height//3}" stroke="#1e4d30" stroke-width="0.4"/>'
        f'<polygon points="{pts_str}" fill="none" stroke="#6ee7b7" '
        f'stroke-width="1.5" stroke-dasharray="5,3" opacity="0.6"/>'
        f'{circles}{crit_label}'
        f'<text x="{width//2}" y="10" text-anchor="middle" '
        f'font-family="Cairo,sans-serif" font-size="9" fill="#6ee7b7" opacity="0.7">شمال</text>'
        f'</svg>'
    )


# ─────────────────────────────────────────────
# PDF Generation — weasyprint
# ─────────────────────────────────────────────
def generate_pdf_report(export_data: dict, farm_id: str) -> str:
    try:
        from weasyprint import HTML, CSS
    except ImportError:
        raise RuntimeError(
            "weasyprint غير مثبتة. أضف 'weasyprint' لـ requirements.txt"
        )

    header        = export_data.get("header", {})
    dist          = export_data.get("distribution", {})
    biometrics    = export_data.get("biometrics", {})
    forecast      = export_data.get("forecast", {})
    top_action    = export_data.get("top_action") or {}
    map_points    = export_data.get("health_map_points", [])
    wellness      = float(export_data.get("wellness_score", dist.get("Healthy_Pct", 0)))

    healthy_pct   = float(dist.get("Healthy_Pct", 0))
    monitor_pct   = float(dist.get("Monitor_Pct", 0))
    critical_pct  = float(dist.get("Critical_Pct", 0))

    gauge_color = _color_for_pct(wellness)
    gauge_svg   = _gauge_svg(wellness, gauge_color, size=120)
    sparkline   = _trend_sparkline(forecast.get("trend_data", []), color="#3b82f6")
    heatmap_svg = _heatmap_svg(map_points)

    ndvi = biometrics.get("ndvi", {})
    ndmi = biometrics.get("ndmi", {})
    ndre = biometrics.get("ndre", {})

    def delta_badge(d):
        d = float(d or 0)
        clr   = "#22c55e" if d >= 0 else "#ef4444"
        arrow = "▲" if d >= 0 else "▼"
        return f'<span style="color:{clr};font-size:11px;">{arrow} {abs(d):.1f}%</span>'

    def ndvi_verdict(v):
        v = float(v or 0)
        if v >= 0.65:
            return ("ممتاز 🌟", "#dcfce7", "#15803d")
        if v >= 0.45:
            return ("جيد ✅", "#d1fae5", "#065f46")
        if v >= 0.30:
            return ("مقبول ⚠️", "#fef9c3", "#a16207")
        return ("منخفض 🚨", "#fee2e2", "#b91c1c")

    def ndmi_verdict(v):
        v = float(v or 0)
        if v >= 0.40:
            return ("رطوبة جيدة ✅", "#d1fae5", "#065f46")
        if v >= 0.25:
            return ("رطوبة مقبولة ⚠️", "#fef9c3", "#a16207")
        return ("جفاف 🚨", "#fee2e2", "#b91c1c")

    def ndre_verdict(v):
        v = float(v or 0)
        if v >= 0.50:
            return ("أوراق صحية ✅", "#d1fae5", "#065f46")
        if v >= 0.35:
            return ("تغذية مقبولة ⚠️", "#fef9c3", "#a16207")
        return ("نقص غذائي 🚨", "#fee2e2", "#b91c1c")

    nv, nb, nc = ndvi_verdict(ndvi.get("val", 0))
    nmv, nmb, nmc = ndmi_verdict(ndmi.get("val", 0))
    nrv, nrb, nrc = ndre_verdict(ndre.get("val", 0))

    wellness_text = (
        "مزرعتك بصحة ممتازة 🌟" if wellness >= 75 else
        "مزرعتك بصحة جيدة ✅" if wellness >= 55 else
        "تحتاج متابعة ⚠️" if wellness >= 35 else
        "تحتاج تدخل عاجل 🚨"
    )

    wellness_desc = (
        f"تُظهر النتائج أن نسبة الحالة السليمة تبلغ {healthy_pct:.0f}%. "
        f"{'لا توجد مؤشرات حرجة تستوجب تدخلًا فوريًا.' if critical_pct < 10 else f'توجد نسبة حرجة تبلغ {critical_pct:.0f}% تحتاج تدخلًا أسرع.'}"
    )

  

    action_title = top_action.get("title_ar", "استمر في الروتين الحالي")
    action_text  = top_action.get("text_ar", "جميع المؤشرات ضمن النطاقات الطبيعية.")

    report_date   = header.get("date") or datetime.now().strftime("%Y-%m-%d")
    farm_name     = header.get("name", "مزرعة سعف")
    farm_area     = header.get("area", "—")
    total_palms   = header.get("total_palms", "—")
    forecast_text = forecast.get("text", "—")

    if heatmap_svg:
        map_block = f"""
        <div style="background:#0f2027;border-radius:12px;overflow:hidden;">
          {heatmap_svg}
        </div>
        """
    else:
        map_block = '<div style="color:#9ca3af;font-size:11px;padding:20px;text-align:center;">لا توجد بيانات خريطة بعد</div>'
    map_note = (
        "النقاط الحمراء في الخريطة تحدد مواقع النخيل التي تحتاج تدخلًا أسرع."
        if critical_pct > 0 else
        "جميع مناطق المزرعة ضمن الحالة الطبيعية."
    )

    raw_hotspots = export_data.get("hotspots_table", [])
    hotspots = []
    for pt in raw_hotspots[:5]:
        hotspots.append({
            "lat": pt.get("lat", "—"),
            "lng": pt.get("lng", pt.get("lon", "—")),
            "status": pt.get("status", "—"),
            "note": pt.get("note", "—"),
        })

    # ========= إضافات القالب الجديد =========

    logo_url = export_data.get("logo_url")

    executive_status = export_data.get("executive_status", wellness_text)

    executive_summary = export_data.get(
        "executive_summary",
        f"تُظهر نتائج التحليل أن المزرعة في وضع {'جيد' if wellness >= 55 else 'يحتاج متابعة'} حاليًا، "
        f"حيث تبلغ نسبة النخيل السليم {healthy_pct:.0f}%، ونسبة المتابعة {monitor_pct:.0f}%، "
        f"بينما تم رصد {critical_pct:.0f}% من النخيل بحاجة إلى تدخل أسرع."
    )

    executive_next_step = export_data.get(
        "executive_next_step",
        f"الخطوة التالية المقترحة: {action_title}."
    )

    key_findings = export_data.get("key_findings", [
        f"تبلغ نسبة الحالة السليمة حاليًا {healthy_pct:.0f}%.",
        f"توجد نسبة متابعة تبلغ {monitor_pct:.0f}% وتحتاج مراقبة دورية.",
        f"تم رصد نسبة حرجة تبلغ {critical_pct:.0f}% تحتاج مراجعة أسرع.",
    ])[:3]

    extra_indices = export_data.get("extra_indices", [])[:4]

    forecast_next = export_data.get("forecast_next_week", {})
    forecast_summary = {
        "healthy": f"{float(forecast_next.get('Healthy_Pct_next', healthy_pct)):.1f}%",
        "monitor": f"{float(forecast_next.get('Monitor_Pct_next', monitor_pct)):.1f}%",
        "critical": f"{float(forecast_next.get('Critical_Pct_next', critical_pct)):.1f}%",
    }

    risk_drivers = export_data.get("risk_drivers", [])[:4]



    logo_data_uri = None
    logo_path = os.path.join(
        os.path.dirname(__file__),
        "static",
        "images",
        "saaf_logo.png"
    )

    if os.path.exists(logo_path):
        with open(logo_path, "rb") as img_file:
            logo_b64 = base64.b64encode(img_file.read()).decode("utf-8")
            logo_data_uri = f"data:image/png;base64,{logo_b64}"

    html_content = render_template(
        "reports/farm_report.html",
        farm_id=farm_id,
        farm_name=farm_name,
        farm_area=farm_area,
        total_palms=total_palms,
        report_date=report_date,

        logo_data_uri=logo_data_uri,
        logo_url=logo_url,

        gauge_svg=gauge_svg,
        gauge_color=gauge_color,
        wellness_text=wellness_text,
        wellness_desc=wellness_desc,

        healthy_pct=healthy_pct,
        monitor_pct=monitor_pct,
        critical_pct=critical_pct,
       

        map_block=map_block,
        map_note=map_note,

        ndvi_val=ndvi.get("val", "—"),
        ndmi_val=ndmi.get("val", "—"),
        ndre_val=ndre.get("val", "—"),

        nv=nv, nb=nb, nc=nc,
        nmv=nmv, nmb=nmb, nmc=nmc,
        nrv=nrv, nrb=nrb, nrc=nrc,

        ndvi_delta_badge=delta_badge(ndvi.get("delta", 0)),
        ndmi_delta_badge=delta_badge(ndmi.get("delta", 0)),
        ndre_delta_badge=delta_badge(ndre.get("delta", 0)),

        forecast_text=forecast_text,
        sparkline=sparkline,
        forecast_summary=forecast_summary,

        action_title=action_title,
        action_text=action_text,

        executive_status=executive_status,
        executive_summary=executive_summary,
        executive_next_step=executive_next_step,

        key_findings=key_findings,
        extra_indices=extra_indices,
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
    from openpyxl.styles import (
        Font, PatternFill, Alignment, Border, Side, GradientFill
    )
    from openpyxl.utils import get_column_letter

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "تقرير المزرعة"
    ws.sheet_view.rightToLeft = True

    header     = export_data.get("header", {})
    dist       = export_data.get("distribution", {})
    biometrics = export_data.get("biometrics", {})
    forecast   = export_data.get("forecast", {})
    hotspots   = export_data.get("critical_hotspots", [])
    wellness   = float(export_data.get("wellness_score", dist.get("Healthy_Pct", 0)))

    # ── Styles ──
    GREEN_DARK  = "064E3B"
    GREEN_MID   = "10B981"
    GREEN_LIGHT = "D1FAE5"
    ORANGE      = "F59E0B"
    RED         = "EF4444"
    GRAY_BG     = "F8FAFC"
    BORDER_CLR  = "E2E8F0"

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
        return Alignment(horizontal="center", vertical="center",
                         wrap_text=wrap, readingOrder=2)

    def right_align():
        return Alignment(horizontal="right", vertical="center",
                         readingOrder=2)

    # ── Header Block ──
    ws.merge_cells("A1:F1")
    c = ws["A1"]
    c.value = "🌴 سعف — تقرير تحليل صحة المزرعة"
    c.font  = Font(name="Cairo", size=16, bold=True, color="FFFFFF")
    c.fill  = fill(GREEN_DARK)
    c.alignment = center()
    ws.row_dimensions[1].height = 36

    # Farm info row
    info_labels = ["اسم المزرعة", "رقم المزرعة", "المساحة", "عدد النخيل",
                   "تاريخ التقرير", "مؤشر العافية"]
    info_vals   = [
        header.get("name", "—"), farm_id,
        f"{header.get('area', '—')} م²",
        str(header.get("total_palms", "—")),
        header.get("date", datetime.now().strftime("%Y-%m-%d")),
        f"{wellness:.1f}%",
    ]
    for col, (lbl, val) in enumerate(zip(info_labels, info_vals), start=1):
        ws.row_dimensions[2].height = 20
        ws.row_dimensions[3].height = 26
        cl = ws.cell(row=2, column=col, value=lbl)
        cl.font = Font(name="Cairo", size=10, bold=True, color="064E3B")
        cl.fill = fill(GREEN_LIGHT)
        cl.alignment = center()
        cl.border = full_border(BORDER_CLR)

        cv = ws.cell(row=3, column=col, value=val)
        cv.font = body_font(11, bold=True, color="1E293B")
        cv.alignment = center()
        cv.border = full_border(BORDER_CLR)

    ws.row_dimensions[4].height = 10  # فراغ

    # ── Section: التوزيع الصحي ──
    ws.merge_cells("A5:F5")
    c = ws["A5"]
    c.value = "📊 توزيع الحالة الصحية"
    c.font  = header_font(12)
    c.fill  = fill(GREEN_MID)
    c.alignment = center()
    ws.row_dimensions[5].height = 28

    dist_data = [
        ("✅ سليم",          dist.get("Healthy_Pct",  0), GREEN_MID),
        ("⚠️ يحتاج متابعة", dist.get("Monitor_Pct",  0), ORANGE),
        ("🚨 حرج",           dist.get("Critical_Pct", 0), RED),
    ]
    for i, (lbl, pct, clr) in enumerate(dist_data):
        row = 6 + i
        ws.row_dimensions[row].height = 24
        ws.merge_cells(f"A{row}:C{row}")
        cl = ws.cell(row=row, column=1, value=lbl)
        cl.font = body_font(11, bold=True)
        cl.alignment = right_align()
        cl.border = full_border()

        ws.merge_cells(f"D{row}:F{row}")
        cv = ws.cell(row=row, column=4, value=f"{float(pct):.1f}%")
        cv.font = Font(name="Cairo", size=12, bold=True, color=clr)
        cv.alignment = center()
        cv.border = full_border()

    ws.row_dimensions[9].height = 10

    # ── Section: المؤشرات الطيفية ──
    ws.merge_cells("A10:F10")
    c = ws["A10"]
    c.value = "🔬 المؤشرات الطيفية"
    c.font  = header_font(12)
    c.fill  = fill(GREEN_MID)
    c.alignment = center()
    ws.row_dimensions[10].height = 28

    bio_headers = ["المؤشر", "الاسم العلمي", "القيمة الحالية", "التغير %", "", ""]
    for col, h in enumerate(bio_headers, 1):
        c = ws.cell(row=11, column=col, value=h)
        c.font = Font(name="Cairo", size=10, bold=True, color="374151")
        c.fill = fill(GRAY_BG)
        c.alignment = center()
        c.border = full_border()
    ws.row_dimensions[11].height = 22

    bio_rows = [
        ("مؤشر الخضرة",        "NDVI",
         biometrics.get("ndvi", {}).get("val", "—"),
         biometrics.get("ndvi", {}).get("delta", 0)),
        ("مؤشر الرطوبة",       "NDMI",
         biometrics.get("ndmi", {}).get("val", "—"),
         biometrics.get("ndmi", {}).get("delta", 0)),
        ("مؤشر الأحمر الحافة", "NDRE",
         biometrics.get("ndre", {}).get("val", "—"),
         biometrics.get("ndre", {}).get("delta", 0)),
    ]
    for i, (name_ar, name_sci, val, delta) in enumerate(bio_rows):
        row = 12 + i
        ws.row_dimensions[row].height = 24
        row_fill = fill("FFFFFF") if i % 2 == 0 else fill(GRAY_BG)

        ws.merge_cells(f"A{row}:B{row}")
        c = ws.cell(row=row, column=1, value=name_ar)
        c.font = body_font(11); c.fill = row_fill
        c.alignment = right_align(); c.border = full_border()

        c = ws.cell(row=row, column=3, value=name_sci)
        c.font = Font(name="Consolas", size=10, color="6B7280")
        c.fill = row_fill; c.alignment = center(); c.border = full_border()

        c = ws.cell(row=row, column=4, value=val)
        c.font = body_font(12, bold=True); c.fill = row_fill
        c.alignment = center(); c.border = full_border()

        delta_val = float(delta or 0)
        delta_clr = "22C55E" if delta_val >= 0 else "EF4444"
        delta_str = f"{'▲' if delta_val >= 0 else '▼'} {abs(delta_val):.1f}%"
        ws.merge_cells(f"E{row}:F{row}")
        c = ws.cell(row=row, column=5, value=delta_str)
        c.font = Font(name="Cairo", size=11, bold=True, color=delta_clr)
        c.fill = row_fill; c.alignment = center(); c.border = full_border()

    ws.row_dimensions[15].height = 10

    # ── Section: التوقعات ──
    ws.merge_cells("A16:F16")
    c = ws["A16"]
    c.value = "📈 توقع الأسبوع القادم"
    c.font  = header_font(12)
    c.fill  = fill(GREEN_MID)
    c.alignment = center()
    ws.row_dimensions[16].height = 28

    ws.merge_cells("A17:F17")
    c = ws["A17"]
    c.value = forecast.get("text", "—")
    c.font  = body_font(11); c.alignment = right_align()
    c.border = full_border()
    ws.row_dimensions[17].height = 24

    trend = forecast.get("trend_data", [])
    if trend:
        ws.row_dimensions[18].height = 18
        ws.merge_cells("A18:F18")
        c = ws["A18"]
        c.value = "مسار NDVI: " + " → ".join([f"{v:.2f}" if isinstance(v, float) else str(v) for v in trend[-5:]])
        c.font = Font(name="Cairo", size=10, color="6B7280")
        c.alignment = right_align()

    ws.row_dimensions[19].height = 10

    # ── Section: النقاط الحرجة ──
    if hotspots:
        ws.merge_cells("A20:F20")
        c = ws["A20"]
        c.value = "🚨 النقاط الحرجة"
        c.font  = header_font(12)
        c.fill  = fill("7F1D1D")
        c.alignment = center()
        ws.row_dimensions[20].height = 28

        hs_hdrs = ["#", "خط العرض", "خط الطول", "الحالة", "القاعدة", ""]
        for col, h in enumerate(hs_hdrs, 1):
            c = ws.cell(row=21, column=col, value=h)
            c.font = Font(name="Cairo", size=10, bold=True, color="374151")
            c.fill = fill("FEE2E2"); c.alignment = center(); c.border = full_border()
        ws.row_dimensions[21].height = 22

        for j, pt in enumerate(hotspots[:8]):
            row = 22 + j
            ws.row_dimensions[row].height = 22
            rf = fill("FFFFFF") if j % 2 == 0 else fill("FFF7F7")
            vals = [j+1, pt.get("lat","—"), pt.get("lng","—"),
                    pt.get("status","—"), pt.get("note","—"), ""]
            for col, v in enumerate(vals, 1):
                c = ws.cell(row=row, column=col, value=v)
                c.font = body_font(10); c.fill = rf
                c.alignment = center(); c.border = full_border()

    # ── Column widths ──
    col_widths = [22, 18, 18, 18, 18, 14]
    for i, w in enumerate(col_widths, 1):
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

        export_data = doc.to_dict().get('export_data')
        if not export_data:
            return jsonify({"ok": False, "error": "بيانات التحليل ناقصة. شغّل التحليل أولاً."}), 400

        pdf_path = generate_pdf_report(export_data, farm_id)
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

        export_data = doc.to_dict().get('export_data', {})
        if not export_data:
            return jsonify({"ok": False, "error": "بيانات التحليل ناقصة. شغّل التحليل أولاً."}), 400

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