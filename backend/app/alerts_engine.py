# app/alerts_engine.py
from __future__ import annotations
from typing import Dict, Any, List, Tuple
from datetime import datetime, timezone
import hashlib
import math


# =========================
# Config (Product behavior)
# =========================

# ✅ حد أقصى للتوصيات (تقدرين تغيّرينه إلى 4 بسهولة)
MAX_RECOS = 6

# ✅ أقل درجة “قوة دليل” عشان نطلع توصية (0..1)
MIN_DRIVER_SCORE_TO_RECOMMEND = 0.45

# ✅ أقل درجة للسبب عشان نذكره ضمن "لماذا؟"
MIN_DRIVER_SCORE_TO_MENTION_AS_REASON = 0.40


# =========================
# Helpers
# =========================

def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _stable_id(*parts: str) -> str:
    raw = "|".join([p or "" for p in parts])
    h = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:14]
    return f"al_{h}"


def _pct(x: Any) -> float:
    try:
        v = float(x)
    except Exception:
        return 0.0
    if v < 0:
        return 0.0
    if v > 100:
        return 100.0
    return v


def _safe_int(x: Any) -> int:
    try:
        return int(x)
    except Exception:
        return 0


def _safe_float(x: Any) -> float:
    try:
        v = float(x)
        if math.isfinite(v):
            return v
        return 0.0
    except Exception:
        return 0.0


def _ratio(count: int, total: int) -> float:
    if total <= 0:
        return 0.0
    return float(count) / float(total)


def _trend_slope(values: List[float]) -> float:
    """
    Simple slope over index for last N points.
    Positive = increasing, Negative = decreasing.
    """
    xs, ys = [], []
    for i, v in enumerate(values):
        if v is None:
            continue
        try:
            fv = float(v)
        except Exception:
            continue
        if not math.isfinite(fv):
            continue
        xs.append(float(i))
        ys.append(fv)
    if len(xs) < 3:
        return 0.0

    x_mean = sum(xs) / len(xs)
    y_mean = sum(ys) / len(ys)
    num = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys))
    den = sum((x - x_mean) ** 2 for x in xs) + 1e-9
    return num / den


# =========================
# Priority & Recommendation Dedup
# =========================

_PRIORITY_RANK = {
    "عاجلة": 0,
    "مرتفعة": 1,
    "متوسطة": 2,
    "منخفضة": 3,
}

_PRIORITY_BY_ACTION = {
    "field_visit_now": "عاجلة",
    "field_visit_48h": "مرتفعة",
    "irrigation_audit": "مرتفعة",
    "field_inspection": "متوسطة",
    "nutrition_check": "متوسطة",
    "pest_disease_check": "متوسطة",
    "heat_mitigation": "متوسطة",
    "prepare_week": "متوسطة",
    "field_notes": "منخفضة",
    "auto_follow": "منخفضة",
}

# ✅ تجميع “المعنى” لتقليل التكرار
# أي توصيتين يخدمون نفس الهدف: نفس الـ group_key
_GROUP_BY_ACTION_KEY = {
    "visit_now": "field_visit",
    "visit_48h": "field_visit",

    "water_check": "irrigation",
    "irrigation_points": "irrigation",

    "visual_check": "field_inspection",

    "nutrient_check": "nutrition",

    "pest_disease_check": "pest",

    "heat_mitigation": "heat",

    "prepare_week": "prepare",

    "field_notes": "notes",
    "auto_follow": "autofollow",
}

# ✅ أيقونات بسيطة للـ UI (اختاري أسماء تناسب مكتبتكم)
_ICON_BY_GROUP = {
    "field_visit": {"whyIcon": "help_circle", "actionIcon": "map_pin"},
    "irrigation": {"whyIcon": "help_circle", "actionIcon": "droplet"},
    "field_inspection": {"whyIcon": "help_circle", "actionIcon": "search"},
    "nutrition": {"whyIcon": "help_circle", "actionIcon": "leaf"},
    "pest": {"whyIcon": "help_circle", "actionIcon": "bug"},
    "heat": {"whyIcon": "help_circle", "actionIcon": "sun"},
    "prepare": {"whyIcon": "help_circle", "actionIcon": "calendar"},
    "notes": {"whyIcon": "help_circle", "actionIcon": "clipboard"},
    "autofollow": {"whyIcon": "help_circle", "actionIcon": "refresh_cw"},
}

def _priority_for_action(action_key: str) -> str:
    return _PRIORITY_BY_ACTION.get((action_key or "").strip(), "متوسطة")


def _priority_min(a: str, b: str) -> str:
    ra = _PRIORITY_RANK.get((a or "").strip(), 99)
    rb = _PRIORITY_RANK.get((b or "").strip(), 99)
    return a if ra <= rb else b


def _action_group(action_key: str) -> str:
    return _GROUP_BY_ACTION_KEY.get((action_key or "").strip(), (action_key or "").strip() or "misc")


def _add_reco(
    recos_map: Dict[str, Dict[str, Any]],
    farm_id: str,
    source: str,
    action: Dict[str, Any],
    *,
    priority_override: str | None = None,
    why: str | None = None,
    group_override: str | None = None,
    score: float | None = None,
) -> None:
    """
    ✅ DEDUP by semantic group:
    - لا نكرر توصيتين بنفس المعنى (مثال: "زيارة" + "فحص بصري" إذا كانت تتحول لنفس فئة الزيارة)
    - ندمج المصادر، ونحافظ على أعلى أولوية، ونختار أفضل نص "لماذا؟" إذا توفر
    """
    key = (action.get("key") or "").strip()
    if not key:
        return

    group_key = (group_override or _action_group(key)).strip() or key
    priority_ar = (priority_override or _priority_for_action(action.get("priority_key", key))).strip()

    existing = recos_map.get(group_key)
    if existing is None:
        icons = _ICON_BY_GROUP.get(group_key, {"whyIcon": "help_circle", "actionIcon": "sparkles"})
        recos_map[group_key] = {
            "id": _stable_id(farm_id, "reco", group_key),
            "group": group_key,
            "key": key,  # keep last contributing action key
            "sources": [source],
            "priority_ar": priority_ar,

            # ✅ UI-friendly
            "whyTitle_ar": "لماذا؟",
            "actionTitle_ar": "ماذا أفعل؟",
            "whyIcon": icons["whyIcon"],
            "actionIcon": icons["actionIcon"],

            # ✅ content
            "title_ar": action.get("title_ar", ""),
            "text_ar": action.get("text_ar", ""),   # ماذا أفعل؟
            "why_ar": (why or action.get("why_ar", "")).strip(),

            # scoring (internal ordering)
            "score": float(score) if score is not None else 0.0,

            "createdAtISO": _now_iso(),
        }
        return

    # merge
    existing["priority_ar"] = _priority_min(existing.get("priority_ar", ""), priority_ar)

    srcs = set(existing.get("sources", []) or [])
    srcs.add(source)
    existing["sources"] = sorted(srcs)

    # prefer why if empty or new why is more specific
    new_why = (why or "").strip()
    if new_why and (not existing.get("why_ar")):
        existing["why_ar"] = new_why

    # keep highest score to rank
    try:
        existing["score"] = max(float(existing.get("score", 0.0) or 0.0), float(score or 0.0))
    except Exception:
        pass

    # keep a stable title/text if existing empty
    if (not existing.get("title_ar")) and action.get("title_ar"):
        existing["title_ar"] = action.get("title_ar", "")
    if (not existing.get("text_ar")) and action.get("text_ar"):
        existing["text_ar"] = action.get("text_ar", "")

    existing["key"] = key


# =========================
# Actions Library (Professional Arabic)
# =========================

def _actions_library(severity: str) -> Dict[str, Dict[str, str]]:
    sev = (severity or "").lower().strip()
    urgent = (sev == "critical")

    return {
        "visit_now": {
            "key": "visit_now",
            "priority_key": "field_visit_now",
            "title_ar": "زيارة ميدانية عاجلة",
            "text_ar": "ابدأ بزيارة المناطق الأكثر تأثرًا كما تظهر في الخريطة، وركّز على التحقق من السبب في الموقع.",
        },
        "visit_48h": {
            "key": "visit_48h",
            "priority_key": "field_visit_48h",
            "title_ar": "زيارة ميدانية خلال 48 ساعة",
            "text_ar": "قم بزيارة المناطق المتأثرة كما تظهر في الخريطة للتأكد من السبب وتحديد الإجراء المناسب.",
        },
        "water_check": {
            "key": "water_check",
            "priority_key": "irrigation_audit",
            "title_ar": "مراجعة نظام الري",
            "text_ar": (
                "تحقق من وصول الماء للمناطق المتأثرة: ضغط الضخ، انسداد النقاط، التسرب، وعدم توازن التوزيع."
                if urgent else
                "راجع توزيع الري حول المناطق المتأثرة وتأكد من توازن التغطية وعدم وجود ضعف موضعي."
            ),
        },
        "irrigation_points": {
            "key": "irrigation_points",
            "priority_key": "irrigation_audit",
            "title_ar": "فحص نقاط الري الأقرب للمناطق المتأثرة",
            "text_ar": "افحص النقاط الأقرب للمناطق المتأثرة للتأكد من قوة الضخ وتوازن التغطية وعدم وجود انسداد.",
        },
        "visual_check": {
            "key": "visual_check",
            "priority_key": "field_inspection",
            "title_ar": "فحص ميداني للنخيل",
            "text_ar": "افحص النخيل بصريًا في المناطق المتأثرة لرصد ذبول/اصفرار/جفاف/حشرات/تعفن أو اختلاف واضح عن بقية المزرعة.",
        },
        "nutrient_check": {
            "key": "nutrient_check",
            "priority_key": "nutrition_check",
            "title_ar": "مراجعة التسميد والتغذية",
            "text_ar": "راجع برنامج التسميد. إذا استمرت الإشارة، يُفضّل اختبار تربة/ورق لتحديد أي نقص بدقة قبل تعديل الجرعات.",
        },
        "pest_disease_check": {
            "key": "pest_disease_check",
            "priority_key": "pest_disease_check",
            "title_ar": "تحقق من آفة/مرض (سبب موضعي محتمل)",
            "text_ar": "ركّز الفحص على احتمال وجود آفة/مرض في المناطق المتأثرة، خصوصًا إذا كانت بقعًا متفرقة تختلف عن نمط المزرعة.",
        },
        "heat_mitigation": {
            "key": "heat_mitigation",
            "priority_key": "heat_mitigation",
            "title_ar": "تقليل أثر الإجهاد الحراري",
            "text_ar": "في فترات الحر: قدّم مواعيد الري لأوقات أبرد (الفجر/المساء) وراقب المناطق المتأثرة بشكل أقرب.",
        },
        "prepare_week": {
            "key": "prepare_week",
            "priority_key": "prepare_week",
            "title_ar": "استعداد للأسبوع القادم",
            "text_ar": "ارفع وتيرة المتابعة قبل بداية الأسبوع القادم وركّز على المناطق المتأثرة لتقليل احتمال التدهور.",
        },
        "field_notes": {
            "key": "field_notes",
            "priority_key": "field_notes",
            "title_ar": "توثيق ملاحظات وصور",
            "text_ar": "وثّق نتائج الفحص (صور/ملاحظات) لمقارنة التحسن في التحديثات القادمة وتجنب تكرار نفس المشكلة.",
        },
        "auto_follow": {
            "key": "auto_follow",
            "priority_key": "auto_follow",
            "title_ar": "متابعة تلقائية في التحديث القادم",
            "text_ar": "سيعيد النظام التحليل تلقائيًا في التحديث القادم لتأكيد اتجاه الحالة وتقليل الإنذارات غير الدقيقة.",
        },
    }


# =========================
# Driver detection (internal use; do NOT show index names to user)
# =========================

def _extract_history_series(health_result: Dict[str, Any]) -> Dict[str, List[float]]:
    """
    We only use the numeric series internally to detect trend.
    We DO NOT display any indicator names to the user.
    """
    hist = health_result.get("indices_history_last_month", []) or []
    a, b, c = [], [], []
    for row in hist:
        a.append(row.get("NDVI"))
        b.append(row.get("NDMI"))
        c.append(row.get("NDRE"))
    return {"A": a[-5:], "B": b[-5:], "C": c[-5:]}


def _compute_drivers(
    health_result: Dict[str, Any],
    *,
    total_pixels_latest: int,
) -> Dict[str, Any]:
    alert_signals = health_result.get("alert_signals", {}) or {}
    rule_counts = alert_signals.get("rule_counts_latest", {}) or {}
    flag_counts = alert_signals.get("flag_counts_latest", {}) or {}

    # ✅ “رطوبة/ري” (counts)
    water_flags = (
        _safe_int(flag_counts.get("flag_drop_SIWSI10pct", 0))
        + _safe_int(flag_counts.get("flag_drop_NDWI10pct", 0))
        + _safe_int(flag_counts.get("flag_NDWI_low", 0))
        + _safe_int(flag_counts.get("flag_NDWI_below_025", 0))
    )

    # ✅ “نشاط/نمو/كلوروفيل” (counts)
    growth_flags = (
        _safe_int(flag_counts.get("flag_drop_NDVI005", 0))
        + _safe_int(flag_counts.get("flag_NDVI_below_030", 0))
        + _safe_int(flag_counts.get("flag_NDRE_low", 0))
        + _safe_int(flag_counts.get("flag_NDRE_below_035", 0))
    )

    # Rule evidence (pixel classification reasons)
    baseline_drop = _safe_int(rule_counts.get("Critical_baseline_drop", 0)) + _safe_int(rule_counts.get("Monitor_baseline_drop", 0))
    stress_pockets = _safe_int(rule_counts.get("Critical_RPW_tail", 0)) + _safe_int(rule_counts.get("Monitor_RPW_tail", 0))
    unusual_points = _safe_int(rule_counts.get("Critical_IF_outlier", 0)) + _safe_int(rule_counts.get("Monitor_IF_outlier", 0))

    # History trend (internal)
    series = _extract_history_series(health_result)
    slope_a = _trend_slope([_safe_float(v) for v in series.get("A", [])])  # general activity proxy
    slope_b = _trend_slope([_safe_float(v) for v in series.get("B", [])])  # general moisture proxy
    slope_c = _trend_slope([_safe_float(v) for v in series.get("C", [])])  # general color proxy

    # Forecast
    forecast = health_result.get("forecast_next_week", {}) or {}
    mon_next = _pct(forecast.get("Monitor_Pct_next"))
    crit_next = _pct(forecast.get("Critical_Pct_next"))
    delta_a = _safe_float(forecast.get("ndvi_delta_next_mean"))
    delta_b = _safe_float(forecast.get("ndmi_delta_next_mean"))

    # Convert counts->rates
    water_rate = _ratio(water_flags, total_pixels_latest)
    growth_rate = _ratio(growth_flags, total_pixels_latest)
    baseline_rate = _ratio(baseline_drop, total_pixels_latest)
    pockets_rate = _ratio(stress_pockets, total_pixels_latest)
    unusual_rate = _ratio(unusual_points, total_pixels_latest)

    def clamp01(x: float) -> float:
        return max(0.0, min(1.0, x))

    # Driver scoring (tuned)
    water_score = clamp01(water_rate / 0.08)
    growth_score = clamp01(growth_rate / 0.10)
    unusual_score = clamp01(unusual_rate / 0.04)
    trend_score = clamp01(max(0.0, (-slope_a)) / 0.03)  # decreasing activity = risk
    pockets_score = clamp01(pockets_rate / 0.06)

    # forecast score: stronger weight for critical-next
    forecast_score = clamp01(max(mon_next / 100.0, crit_next / 3.0))

    return {
        "rates": {
            "water_rate": water_rate,
            "growth_rate": growth_rate,
            "baseline_rate": baseline_rate,
            "pockets_rate": pockets_rate,
            "unusual_rate": unusual_rate,
        },
        "scores": {
            "water": water_score,
            "growth": growth_score,
            "unusual": unusual_score,
            "trend": trend_score,
            "stress_pockets": pockets_score,
            "forecast": forecast_score,
        },
        "history_slopes": {
            "general_activity_slope": slope_a,
            "general_moisture_slope": slope_b,
            "general_color_slope": slope_c,
        },
        "forecast": {
            "Monitor_Pct_next": mon_next,
            "Critical_Pct_next": crit_next,
            "delta_activity_next_mean": delta_a,
            "delta_moisture_next_mean": delta_b,
        },
        "evidence_counts": {
            "water_signals_count": water_flags,
            "growth_signals_count": growth_flags,
            "baseline_change_count": baseline_drop,
            "stress_pockets_count": stress_pockets,
            "unusual_points_count": unusual_points,
        },
        "raw": {
            "rule_counts": rule_counts,
            "flag_counts": flag_counts,
            "history_series_internal": series,
        },
    }


def _pick_top_drivers(drivers: Dict[str, Any], topk: int = 3) -> List[Tuple[str, float]]:
    scores = drivers.get("scores", {}) or {}
    items = [(k, _safe_float(v)) for k, v in scores.items()]
    items.sort(key=lambda x: x[1], reverse=True)
    strong = [(k, s) for k, s in items if s >= MIN_DRIVER_SCORE_TO_MENTION_AS_REASON]
    return strong[:topk]


def _severity_from_health(crit_now: float, mon_now: float) -> str:
    # ✅ severity based on current distribution
    if crit_now >= 2.0:
        return "critical"
    if mon_now >= 35.0:
        return "warning"
    return "info"


def _should_forecast_alert(severity_now: str, drivers: Dict[str, Any]) -> Tuple[bool, str]:
    fc = drivers.get("forecast", {}) or {}
    mon_next = _safe_float(fc.get("Monitor_Pct_next"))
    crit_next = _safe_float(fc.get("Critical_Pct_next"))
    delta_activity = _safe_float(fc.get("delta_activity_next_mean"))
    delta_moisture = _safe_float(fc.get("delta_moisture_next_mean"))

    # ✅ only meaningful forecast alert
    if crit_next >= 1.0:
        return True, "critical"
    if mon_next >= 80.0 and severity_now != "critical":
        return True, "warning"
    if (delta_activity <= -0.03 or delta_moisture <= -0.03) and severity_now == "info":
        return True, "warning"
    return False, "info"


# =========================
# User-facing “Why?” phrasing (No indicator names)
# =========================

def _why_for_driver(driver_key: str, severity_now: str) -> str:
    """
    ✅ نص 'لماذا؟' احترافي — بدون أسماء مؤشرات.
    """
    driver_key = (driver_key or "").strip()

    if driver_key == "water":
        return "ظهرت إشارات تُرجّح وجود نقص في الرطوبة أو ضعف وصول الماء في مناطق محددة مقارنة ببقية المزرعة."
    if driver_key == "growth":
        return "ظهرت إشارات لانخفاض في نشاط النبات/قوة النمو في بعض المناطق، وقد يرتبط ذلك بإجهاد أو نقص تغذية."
    if driver_key == "trend":
        return "هناك اتجاه هبوط خلال الأسابيع الأخيرة في أداء النبات بشكل عام، مما يستدعي متابعة أقرب."
    if driver_key == "stress_pockets":
        return "توجد جيوب متفرقة من الإجهاد داخل المزرعة (مناطق محدودة تختلف عن محيطها)، وغالبًا يكون السبب موضعيًا."
    if driver_key == "unusual":
        return "تم رصد مناطق غير معتادة تختلف عن النمط العام للمزرعة، وقد يشير ذلك لمشكلة محلية (ري/آفة/مرض)."
    if driver_key == "forecast":
        return "توقعات النظام تشير إلى احتمال زيادة المناطق التي تحتاج متابعة في الأسبوع القادم."
    return "ظهرت إشارات تستدعي إجراء احترازي للتأكد من السبب وتقليل احتمال التدهور."


def _format_reco_text(action_text: str) -> str:
    """
    نتركه نصًا واحدًا عشان ما نكسر UI الحالي.
    لو تبين تقسيمه UI-ready، عندك whyTitle/actionTitle + icons + why_ar/text_ar.
    """
    return (action_text or "").strip()


# =========================
# Main builder
# =========================

def build_alerts_and_recommendations(farm_id: str, health_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    Returns:
      - alerts: MAX 2 (overall + forecast if needed)
      - recommendations: deduped by semantic meaning + prioritized
      - summary: for UI debugging (still no index names to user)
    """
    alerts: List[Dict[str, Any]] = []
    recos_map: Dict[str, Dict[str, Any]] = {}

    health = health_result.get("current_health", {}) or {}
    crit_now = _pct(health.get("Critical_Pct"))
    mon_now = _pct(health.get("Monitor_Pct"))
    severity_now = _severity_from_health(crit_now, mon_now)

    alert_signals = health_result.get("alert_signals", {}) or {}
    total_pixels_latest = _safe_int(alert_signals.get("total_pixels_latest", 0))

    hotspots = (
        alert_signals.get("hotspots", {})
        or health_result.get("hotspots", {})
        or {}
    )

    drivers = _compute_drivers(health_result, total_pixels_latest=total_pixels_latest)
    top_drivers = _pick_top_drivers(drivers, topk=3)

    driver_titles = {
        "water": "إشارات مرتبطة بالرطوبة والري",
        "growth": "إشارات انخفاض في نشاط النبات",
        "unusual": "مناطق غير معتادة داخل المزرعة",
        "trend": "اتجاه هبوط خلال الأسابيع الأخيرة",
        "stress_pockets": "جيوب إجهاد متفرقة",
        "forecast": "مخاطر متوقعة للأسبوع القادم",
    }

    created_at = _now_iso()

    # -------------------------
    # 1) Overall alert (SHORT)
    # -------------------------
    overall_needed = (severity_now != "info") or (crit_now >= 0.5) or (mon_now >= 15.0)
    if overall_needed:
        sev = severity_now if severity_now != "info" else "warning"
        actions_lib = _actions_library(sev)

        # ✅ تنبيه مختصر (بدون أسباب طويلة)
        if crit_now >= 0.5:
            msg = f"الحالة الحالية: مناطق تتطلب تدخّلًا سريعًا ({crit_now:.1f}%) ومناطق تحتاج متابعة ({mon_now:.1f}%)."
            title = "تنبيه عاجل: حالة غير مستقرة داخل المزرعة" if sev == "critical" else "تنبيه: متابعة مطلوبة داخل المزرعة"
        else:
            msg = f"الحالة الحالية: توجد مناطق تحتاج متابعة ({mon_now:.1f}%)."
            title = "تنبيه: متابعة مطلوبة داخل المزرعة"

        msg += " ركّز على المناطق الأكثر تأثرًا كما تظهر في الخريطة."

        a_id = _stable_id(
            farm_id,
            "overall",
            sev,
            str(round(crit_now, 2)),
            str(round(mon_now, 2)),
        )

        hs = hotspots.get("critical", []) if sev == "critical" else (hotspots.get("monitor", []) or hotspots.get("stress", []) or [])

        acts: List[Dict[str, Any]] = []
        acts.append(actions_lib["visit_now"] if sev == "critical" else actions_lib["visit_48h"])
        acts.append(actions_lib["auto_follow"])

        # dedupe actions preserving order
        seen = set()
        acts2 = []
        for a in acts:
            k = a.get("key")
            if k and k not in seen:
                seen.add(k)
                acts2.append(a)

        alerts.append(
            {
                "id": a_id,
                "type": "overall",
                "severity": sev,
                "title_ar": title,
                "message_ar": msg,
                # ✅ لا نضع أسباب كثيرة هنا
                "actions": acts2,
                "hotspots": hs,
                "createdAtISO": created_at,
            }
        )

        # ✅ لا نضيف "زيارة" كتوصية إلا إذا فعلاً في دلائل قوية، وإلا تصير “كل مرة”
        # (الزيارة نحتفظ فيها في التنبيه كـ baseline، والتوصيات تكون مخصصة بالسبب)
        # لكن لو الحالة critical، نضيفها كتوصية واحدة ضمن مجموعة الزيارة
        if sev == "critical":
            _add_reco(
                recos_map,
                farm_id,
                "overall",
                actions_lib["visit_now"],
                group_override="field_visit",
                why="الحالة الحالية تتضمن مناطق تتطلب تدخّلًا سريعًا؛ التحقق الميداني هو الأسرع لتثبيت السبب.",
                score=1.0,
            )

    # -------------------------
    # 2) Forecast alert (only if meaningful)
    # -------------------------
    forecast = health_result.get("forecast_next_week", {}) or {}
    forecast_needed, forecast_sev = _should_forecast_alert(severity_now, drivers)
    if forecast and forecast_needed:
        fc = drivers.get("forecast", {}) or {}
        mon_next = _safe_float(fc.get("Monitor_Pct_next"))
        crit_next = _safe_float(fc.get("Critical_Pct_next"))
        delta_activity = _safe_float(fc.get("delta_activity_next_mean"))
        delta_moisture = _safe_float(fc.get("delta_moisture_next_mean"))

        parts = ["يتوقع النظام زيادة الحاجة للمتابعة خلال الأسبوع القادم."]
        if crit_next >= 1.0:
            parts.append(f"قد تظهر مناطق تتطلب تدخّلًا سريعًا بنسبة تقريبية {crit_next:.1f}%.")
        if mon_next >= 70.0:
            parts.append(f"مناطق المتابعة قد تصل إلى {mon_next:.1f}%.")

        # explain deltas in plain meaning (no indicator names)
        if delta_activity < 0:
            parts.append("قد يظهر تراجع بسيط في نشاط النبات مقارنة بالأسبوع الحالي.")
        if delta_moisture < 0:
            parts.append("وقد تظهر إشارات أقل للرطوبة في بعض المناطق.")

        a_id = _stable_id(
            farm_id,
            "forecast",
            forecast_sev,
            str(round(mon_next, 2)),
            str(round(crit_next, 2)),
        )

        actions_lib = _actions_library(forecast_sev)
        acts = [
            actions_lib["prepare_week"],
            actions_lib["visit_now"] if forecast_sev == "critical" else actions_lib["visit_48h"],
            actions_lib["auto_follow"],
        ]

        alerts.append(
            {
                "id": a_id,
                "type": "forecast_next_week",
                "severity": forecast_sev,
                "title_ar": "تنبيه: توقعات الأسبوع القادم",
                "message_ar": " ".join(parts),
                "actions": acts,
                "hotspots": hotspots.get("monitor", []) or hotspots.get("stress", []) or hotspots.get("critical", []),
                "createdAtISO": created_at,
            }
        )

        # ✅ توصية الاستعداد تظهر إذا forecast قوي (بدون تكرار)
        _add_reco(
            recos_map,
            farm_id,
            "forecast_next_week",
            actions_lib["prepare_week"],
            group_override="prepare",
            why=_why_for_driver("forecast", severity_now),
            score=_safe_float(drivers.get("scores", {}).get("forecast")),
        )

    # -------------------------
    # 3) Targeted recommendations by drivers (dedup + conditional)
    # -------------------------
    scores = drivers.get("scores", {}) or {}
    water_s = _safe_float(scores.get("water"))
    growth_s = _safe_float(scores.get("growth"))
    unusual_s = _safe_float(scores.get("unusual"))
    trend_s = _safe_float(scores.get("trend"))
    pockets_s = _safe_float(scores.get("stress_pockets"))

    sev_for_actions = "critical" if severity_now == "critical" else "warning"
    lib = _actions_library(sev_for_actions)

    # ✅ (A) ري/رطوبة — توصية واحدة فقط ضمن مجموعة irrigation
    if max(water_s, pockets_s) >= MIN_DRIVER_SCORE_TO_RECOMMEND:
        # نختار النص الأدق حسب الحالة
        action = lib["water_check"]
        why = _why_for_driver("water", severity_now)
        _add_reco(
            recos_map, farm_id, "driver_water", action,
            group_override="irrigation",
            priority_override="مرتفعة" if severity_now == "critical" else "متوسطة",
            why=why,
            score=max(water_s, pockets_s),
        )

    # ✅ (B) نشاط/نمو — فحص ميداني + تغذية (لكن بدون تكرار مع الزيارة)
    if max(growth_s, trend_s) >= MIN_DRIVER_SCORE_TO_RECOMMEND:
        _add_reco(
            recos_map, farm_id, "driver_growth", lib["visual_check"],
            group_override="field_inspection",
            priority_override="متوسطة",
            why=_why_for_driver("growth" if growth_s >= trend_s else "trend", severity_now),
            score=max(growth_s, trend_s),
        )

        # التسميد فقط إذا دليل “نمو/لون” قوي (حتى ما تصير توصية ثابتة)
        if growth_s >= 0.55:
            _add_reco(
                recos_map, farm_id, "driver_growth", lib["nutrient_check"],
                group_override="nutrition",
                priority_override="متوسطة",
                why="هناك إشارات قد ترتبط بتغذية النبات؛ مراجعة التسميد واختبار تربة/ورق يمنع قرارات عشوائية.",
                score=growth_s,
            )

    # ✅ (C) غير معتاد/موضعي — آفة/مرض
    if unusual_s >= MIN_DRIVER_SCORE_TO_RECOMMEND:
        _add_reco(
            recos_map, farm_id, "driver_unusual", lib["pest_disease_check"],
            group_override="pest",
            priority_override="متوسطة",
            why=_why_for_driver("unusual", severity_now),
            score=unusual_s,
        )

    # ✅ (D) تقليل أثر الحرارة — فقط إذا كانت الإشارة موجودة عندكم لاحقًا
    # (حالياً ما عندنا driver مباشر للحرارة في هذا الملف، فنبقيها اختيارية لتجنب "هبد")
    # إذا لاحقًا أضفتم driver للحرارة، فعلوا هذا الشرط.

    # ✅ (E) توثيق + متابعة تلقائية: لا نكررهم إلا إذا عندنا على الأقل توصية واحدة حقيقية
    # ولا نطلعهم دائمًا لكل مزرعة.
    has_actionable = any(g for g in recos_map.keys() if g not in ("autofollow", "notes"))
    if has_actionable:
        _add_reco(
            recos_map, farm_id, "system", lib["field_notes"],
            group_override="notes",
            priority_override="منخفضة",
            why="التوثيق يساعد على مقارنة التحسن في التحديثات القادمة وتحديد الإجراء الأكثر فاعلية.",
            score=0.20,
        )
        _add_reco(
            recos_map, farm_id, "system", lib["auto_follow"],
            group_override="autofollow",
            priority_override="منخفضة",
            why="للتأكد من اتجاه الحالة في التحديث القادم وتقليل الإنذارات غير الدقيقة.",
            score=0.10,
        )

    # -------------------------
    # 4) Sort & Limit outputs
    # -------------------------
    recos = list(recos_map.values())

    # ✅ ترتيب: (أولوية) ثم (درجة) ثم (عنوان)
    recos.sort(
        key=lambda r: (
            _PRIORITY_RANK.get((r.get("priority_ar") or "").strip(), 99),
            -_safe_float(r.get("score", 0.0)),
            (r.get("title_ar") or ""),
        )
    )

    # ✅ حد أقصى (قد تكون أقل طبيعيًا)
    recos = recos[:MAX_RECOS]

    # Alerts: critical then warning then info; keep MAX 2
    order = {"critical": 0, "warning": 1, "info": 2}
    alerts.sort(key=lambda a: (order.get(a.get("severity", "info"), 9), a.get("type", "")))
    alerts = alerts[:2]

    summary = {
        "current_severity": severity_now,
        "health_now": {"Critical_Pct": crit_now, "Monitor_Pct": mon_now},

        # driver titles here for internal UI only (still no index names)
        "drivers_top": [{"key": k, "title_ar": driver_titles.get(k, k), "score": float(s)} for k, s in top_drivers],
        "drivers_scores": drivers.get("scores", {}),
        "evidence_counts": drivers.get("evidence_counts", {}),
        "rates": drivers.get("rates", {}),
        "forecast": drivers.get("forecast", {}),
        "total_pixels_latest": total_pixels_latest,
        "has_forecast_alert": bool(forecast and forecast_needed),

        # helpful for debugging dedupe
        "reco_groups": [r.get("group") for r in recos],
    }

    # ✅ اجعل نصوص التوصيات نظيفة
    for r in recos:
        r["text_ar"] = _format_reco_text(r.get("text_ar", ""))
        r["why_ar"] = (r.get("why_ar") or "").strip()

    return {"alerts": alerts, "recommendations": recos, "summary": summary}