# app/alerts_engine.py
from __future__ import annotations

from typing import Dict, Any, List, Tuple
from datetime import datetime, timezone
import hashlib
import math


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
    "visit_now": "عاجلة",
    "visit_48h": "مرتفعة",
    "water_check": "مرتفعة",
    "irrigation_points": "متوسطة",
    "visual_check": "متوسطة",
    "nutrient_check": "متوسطة",
    "pest_disease_check": "متوسطة",
    "heat_mitigation": "متوسطة",
    "prepare_week": "متوسطة",
    "field_notes": "منخفضة",
    "auto_follow": "منخفضة",
}


def _priority_for_action(action_key: str) -> str:
    return _PRIORITY_BY_ACTION.get((action_key or "").strip(), "متوسطة")


def _priority_min(a: str, b: str) -> str:
    ra = _PRIORITY_RANK.get((a or "").strip(), 99)
    rb = _PRIORITY_RANK.get((b or "").strip(), 99)
    return a if ra <= rb else b


def _add_reco(
    recos_map: Dict[str, Dict[str, Any]],
    farm_id: str,
    source: str,
    action: Dict[str, Any],
    *,
    priority_override: str | None = None,
    why: str | None = None,
) -> None:
    key = (action.get("key") or "").strip()
    if not key:
        return

    priority_ar = (priority_override or _priority_for_action(key)).strip()

    existing = recos_map.get(key)
    if existing is None:
        recos_map[key] = {
            "id": _stable_id(farm_id, "reco", key),
            "key": key,
            "sources": [source],
            "priority_ar": priority_ar,
            "title_ar": action.get("title_ar", ""),
            "text_ar": action.get("text_ar", ""),
            "why_ar": why or action.get("why_ar", ""),
            "createdAtISO": _now_iso(),
        }
        return

    existing["priority_ar"] = _priority_min(existing.get("priority_ar", ""), priority_ar)

    srcs = set(existing.get("sources", []) or [])
    srcs.add(source)
    existing["sources"] = sorted(srcs)

    # Keep the strongest / earliest explanation; only fill if empty
    if (not existing.get("why_ar")) and why:
        existing["why_ar"] = why


# =========================
# Actions Library (Product-grade Arabic)
# =========================

def _actions_library(severity: str) -> Dict[str, Dict[str, str]]:
    """
    NOTE:
    - Wording is user-facing and intentionally avoids technical indicator names.
    - We avoid hard claims ("السبب كذا") and use evidence-based, non-committal language.
    """
    sev = (severity or "").lower().strip()
    urgent = (sev == "critical")

    return {
        "visit_now": {
            "key": "visit_now",
            "title_ar": "إجراء عاجل",
            "text_ar": "توجّه فورًا إلى المناطق الأكثر تأثرًا كما تظهر على الخريطة، وابدأ التحقق الميداني قبل تنفيذ أي تعديل واسع.",
        },
        "visit_48h": {
            "key": "visit_48h",
            "title_ar": "زيارة خلال 48 ساعة",
            "text_ar": "قم بزيارة المناطق المتأثرة كما تظهر على الخريطة للتحقق من الحالة ميدانيًا وتحديد الإجراء الأنسب.",
        },
        "water_check": {
            "key": "water_check",
            "title_ar": "مراجعة الري",
            "text_ar": (
                "تحقق من انتظام وصول الماء للمناطق المتأثرة: توزيع التغطية، الفروقات بين الخطوط، وأي مؤشرات على ضعف ضخ أو عدم توازن."
                if urgent
                else "راجع انتظام توزيع الماء حول المناطق المتأثرة وتأكد من عدم وجود تباين واضح في التغطية."
            ),
        },
        "irrigation_points": {
            "key": "irrigation_points",
            "title_ar": "فحص نقاط الري القريبة",
            "text_ar": "افحص أقرب نقاط ري للمناطق المتأثرة للتأكد من كفاءة الضخ وتوازن التغطية مقارنة بالمناطق السليمة.",
        },
        "visual_check": {
            "key": "visual_check",
            "title_ar": "فحص بصري موجه للنخيل",
            "text_ar": "نفّذ فحصًا بصريًا داخل المناطق المتأثرة لرصد أي تغيرات ظاهرية (مثل تغير اللون أو ضعف النمو أو أعراض غير معتادة).",
        },
        "nutrient_check": {
            "key": "nutrient_check",
            "title_ar": "تقييم التسميد عند الحاجة",
            "text_ar": "إذا استمرت الإشارة بعد الفحص الميداني وضبط الري، راجع برنامج التسميد أو نفّذ اختبار تربة/ورق لتحديد الاحتياج بدقة.",
        },
        "pest_disease_check": {
            "key": "pest_disease_check",
            "title_ar": "تحقق من عوامل موضعية محتملة",
            "text_ar": "ركّز الفحص على احتمال وجود عامل موضعي في المناطق المتأثرة (مثل آفة/مرض/مشكلة محلية) لأنها تختلف عن النمط العام للمزرعة.",
        },
        "heat_mitigation": {
            "key": "heat_mitigation",
            "title_ar": "تقليل أثر الحرارة",
            "text_ar": "في موجات الحر، قدّم الري لأوقات أبرد (الفجر/المساء) وزد متابعة المناطق المتأثرة لتقليل الإجهاد الحراري.",
        },
        "prepare_week": {
            "key": "prepare_week",
            "title_ar": "تعزيز المتابعة للأسبوع القادم",
            "text_ar": "ارفع وتيرة المتابعة خلال الأسبوع القادم وراقب المناطق المتأثرة مبكرًا لتقليل احتمال التدهور.",
        },
        "field_notes": {
            "key": "field_notes",
            "title_ar": "توثيق الملاحظات",
            "text_ar": "وثّق نتائج الزيارة (صور/ملاحظات/مواقع) لمقارنة التحسن في التحديثات القادمة واتخاذ قرار أدق.",
        },
        "auto_follow": {
            "key": "auto_follow",
            "title_ar": "متابعة تلقائية",
            "text_ar": "سيعيد النظام التحقق تلقائيًا في التحديث القادم للتأكد من الاتجاه العام وتقليل الإنذارات غير الضرورية.",
        },
    }


# =========================
# Driver detection (Internal only - no indicator names shown to user)
# =========================

def _extract_history_series(health_result: Dict[str, Any]) -> Dict[str, List[float]]:
    """
    We only use numeric series internally to detect trend.
    We DO NOT display any indicator names to the user.
    """
    hist = health_result.get("indices_history_last_month", []) or []
    a, b, c = [], [], []
    for row in hist:
        # keep as-is from pipeline; never show names outside
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

    # Water-related signals (counts)
    water_flags = (
        _safe_int(flag_counts.get("flag_drop_SIWSI10pct", 0))
        + _safe_int(flag_counts.get("flag_drop_NDWI10pct", 0))
        + _safe_int(flag_counts.get("flag_NDWI_low", 0))
        + _safe_int(flag_counts.get("flag_NDWI_below_025", 0))
    )

    # Plant-activity-related signals (counts)
    growth_flags = (
        _safe_int(flag_counts.get("flag_drop_NDVI005", 0))
        + _safe_int(flag_counts.get("flag_NDVI_below_030", 0))
        + _safe_int(flag_counts.get("flag_NDRE_low", 0))
        + _safe_int(flag_counts.get("flag_NDRE_below_035", 0))
    )

    # Rule evidence
    baseline_drop = _safe_int(rule_counts.get("Critical_baseline_drop", 0)) + _safe_int(rule_counts.get("Monitor_baseline_drop", 0))
    stress_pockets = _safe_int(rule_counts.get("Critical_RPW_tail", 0)) + _safe_int(rule_counts.get("Monitor_RPW_tail", 0))
    unusual_points = _safe_int(rule_counts.get("Critical_IF_outlier", 0)) + _safe_int(rule_counts.get("Monitor_IF_outlier", 0))

    # History trend (internal)
    series = _extract_history_series(health_result)
    slope_a = _trend_slope([_safe_float(v) for v in series.get("A", [])])  # general activity proxy
    slope_b = _trend_slope([_safe_float(v) for v in series.get("B", [])])  # general moisture proxy
    slope_c = _trend_slope([_safe_float(v) for v in series.get("C", [])])  # general color/chl proxy

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

    # Scoring (pixel-level tuned)
    water_score = clamp01(water_rate / 0.08)
    growth_score = clamp01(growth_rate / 0.10)
    unusual_score = clamp01(unusual_rate / 0.04)
    trend_score = clamp01(max(0.0, (-slope_a)) / 0.03)  # decreasing general activity is bad
    pockets_score = clamp01(pockets_rate / 0.06)
    forecast_score = clamp01(max(mon_next / 100.0, crit_next / 5.0))

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
    strong = [(k, s) for k, s in items if s >= 0.35]
    return strong[:topk]


def _severity_from_health(crit_now: float, mon_now: float) -> str:
    # Product behavior: critical if >=2% critical pixels; warning if monitor >=35%
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

    # Conservative rules to avoid noisy forecast alerts
    if crit_next >= 1.0:
        return True, "critical"
    if mon_next >= 80.0 and severity_now != "critical":
        return True, "warning"
    if (delta_activity <= -0.03 or delta_moisture <= -0.03) and severity_now == "info":
        return True, "warning"
    return False, "info"


# =========================
# Product-grade wording helpers
# =========================

def _why_templates() -> Dict[str, str]:
    """
    Short, evidence-based explanations (NO hard causal claims).
    """
    return {
        "visit": "تم رصد تباين مكاني داخل المزرعة؛ التحقق الميداني هو أسرع خطوة لتأكيد الحالة وتحديد السبب بدقة.",
        "water": "ظهرت إشارات قد تتوافق مع تغير في مستوى الرطوبة أو انتظام التغطية المائية في بعض المناطق مقارنة بالمحيط.",
        "growth": "البيانات تشير إلى انخفاض في نشاط النبات أو اتجاه هبوط خلال الأسابيع الأخيرة في مناطق محددة.",
        "unusual": "تم رصد مناطق تختلف عن النمط العام للمزرعة؛ وغالبًا ما تكون مرتبطة بعامل محلي يحتاج فحصًا مباشرًا.",
        "forecast": "النموذج التنبؤي يتوقع ارتفاع الحاجة للمتابعة الأسبوع القادم؛ تعزيز المتابعة يقلل احتمالية التدهور.",
        "follow": "إعادة التحقق في التحديث القادم تساعد على تأكيد الاتجاه وتقليل الإنذارات غير الضرورية.",
        "notes": "التوثيق يسهّل المقارنة بين الزيارات والتحديثات ويجعل القرار التالي أكثر دقة.",
    }


def _driver_titles() -> Dict[str, str]:
    return {
        "water": "إشارات مرتبطة بالري والرطوبة",
        "growth": "إشارات انخفاض في نشاط النبات",
        "unusual": "مناطق غير معتادة داخل المزرعة",
        "trend": "اتجاه هبوط خلال الأسابيع الأخيرة",
        "stress_pockets": "جيوب إجهاد متفرقة",
        "forecast": "مخاطر متوقعة للأسبوع القادم",
    }


# =========================
# Main builder
# =========================

def build_alerts_and_recommendations(farm_id: str, health_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    Returns:
      - alerts: MAX 2 (overall + forecast if needed)
      - recommendations: deduped + prioritized
      - summary: useful for UI (drivers + evidence) without exposing indicator names
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

    driver_titles = _driver_titles()
    why_t = _why_templates()

    created_at = _now_iso()

    # -------------------------
    # 1) Overall alert (CONCISE)
    # -------------------------
    overall_needed = (severity_now != "info") or (len(top_drivers) > 0)
    if overall_needed:
        sev = severity_now if severity_now != "info" else "warning"
        actions_lib = _actions_library(sev)

        # Short alert message: no long reasons; reasons go into recommendations
        if crit_now >= 0.5:
            msg = f"تم رصد مناطق تحتاج تدخل سريع ({crit_now:.1f}%) ومناطق تحتاج متابعة ({mon_now:.1f}%). راجع الخريطة واتّبع التوصيات المقترحة."
        else:
            msg = f"تم رصد مناطق تحتاج متابعة ({mon_now:.1f}%). راجع الخريطة واتّبع التوصيات المقترحة."

        title = "تنبيه عاجل: مناطق متأثرة داخل المزرعة" if sev == "critical" else "تنبيه: مناطق تحتاج متابعة"

        a_id = _stable_id(
            farm_id,
            "overall",
            sev,
            str(round(crit_now, 2)),
            str(round(mon_now, 2)),
            ",".join([k for k, _ in top_drivers]) if top_drivers else "none",
        )

        # Choose hotspots for alert display
        hs = (
            hotspots.get("critical", []) if sev == "critical"
            else (hotspots.get("monitor", []) or hotspots.get("stress", []) or [])
        )

        # Actions inside alert: keep minimal (avoid repetition)
        acts: List[Dict[str, Any]] = []
        acts.append(actions_lib["visit_now"] if sev == "critical" else actions_lib["visit_48h"])
        acts.append(actions_lib["auto_follow"])

        alerts.append(
            {
                "id": a_id,
                "type": "overall",
                "severity": sev,
                "title_ar": title,
                "message_ar": msg,
                # drivers can exist for UI badges/insights, but alert text stays short
                "drivers": [
                    {"key": k, "title_ar": driver_titles.get(k, k), "score": float(s)}
                    for k, s in top_drivers
                ],
                "actions": acts,
                "hotspots": hs,
                "createdAtISO": created_at,
            }
        )

        # Recommendations from overall (visit + follow), with professional "why"
        _add_reco(
            recos_map, farm_id, "overall",
            acts[0],
            why=why_t["visit"]
        )
        _add_reco(
            recos_map, farm_id, "overall",
            acts[1],
            why=why_t["follow"]
        )

    # -------------------------
    # 2) Forecast alert (only if meaningful; also concise)
    # -------------------------
    forecast = health_result.get("forecast_next_week", {}) or {}
    forecast_needed, forecast_sev = _should_forecast_alert(severity_now, drivers)

    if forecast and forecast_needed:
        fc = drivers.get("forecast", {}) or {}
        mon_next = _safe_float(fc.get("Monitor_Pct_next"))
        crit_next = _safe_float(fc.get("Critical_Pct_next"))
        delta_activity = _safe_float(fc.get("delta_activity_next_mean"))
        delta_moisture = _safe_float(fc.get("delta_moisture_next_mean"))

        parts: List[str] = ["قد ترتفع الحاجة للمتابعة خلال الأسبوع القادم."]
        if crit_next >= 1.0:
            parts.append(f"قد تظهر مناطق تحتاج تدخل سريع بنسبة تقريبية {crit_next:.1f}%.")
        if mon_next >= 70.0:
            parts.append(f"مناطق المتابعة قد تصل إلى {mon_next:.1f}%.")

        # Explain deltas by meaning (no indicator names)
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
        ]

        alerts.append(
            {
                "id": a_id,
                "type": "forecast_next_week",
                "severity": forecast_sev,
                "title_ar": "توقعات الأسبوع القادم",
                "message_ar": " ".join(parts),
                "actions": acts,
                "hotspots": hotspots.get("monitor", []) or hotspots.get("stress", []) or hotspots.get("critical", []),
                "createdAtISO": created_at,
            }
        )

        # Recos from forecast (no duplication if already exists; _add_reco handles)
        _add_reco(
            recos_map, farm_id, "forecast_next_week",
            actions_lib["prepare_week"],
            why=why_t["forecast"]
        )

    # -------------------------
    # 3) Targeted recommendations by drivers (DETAILED + with reasons)
    #    Goal: avoid repetition.
    #    - Alert is short.
    #    - Recommendations carry the explanation.
    # -------------------------
    scores = drivers.get("scores", {}) or {}
    water_s = _safe_float(scores.get("water"))
    growth_s = _safe_float(scores.get("growth"))
    unusual_s = _safe_float(scores.get("unusual"))
    trend_s = _safe_float(scores.get("trend"))
    pockets_s = _safe_float(scores.get("stress_pockets"))

    lib = _actions_library("critical" if severity_now == "critical" else "warning")

    # Always useful: field notes (low priority), but only if we already triggered some recos
    def _has_any_reco() -> bool:
        return len(recos_map) > 0

    # Water-related: keep ONE core action, add "points" only if strong/urgent
    if water_s >= 0.45 or pockets_s >= 0.55:
        _add_reco(
            recos_map, farm_id, "drivers",
            lib["water_check"],
            priority_override="مرتفعة" if severity_now == "critical" else "متوسطة",
            why=why_t["water"]
        )
        if severity_now == "critical" or water_s >= 0.70:
            _add_reco(
                recos_map, farm_id, "drivers",
                lib["irrigation_points"],
                priority_override="متوسطة",
                why="وجود فرق واضح بين مناطق متجاورة يستدعي فحص أقرب نقاط ري لتحديد مصدر التباين بسرعة."
            )

    # Growth/trend: keep visual check as primary; nutrient as conditional follow-up
    if growth_s >= 0.45 or trend_s >= 0.45:
        _add_reco(
            recos_map, farm_id, "drivers",
            lib["visual_check"],
            priority_override="متوسطة",
            why=why_t["growth"]
        )
        # Only add nutrient_check if signal is strong (to avoid repeating too much)
        if growth_s >= 0.65 or (trend_s >= 0.65 and severity_now != "info"):
            _add_reco(
                recos_map, farm_id, "drivers",
                lib["nutrient_check"],
                priority_override="متوسطة",
                why="كخيار ثانوي: إذا لم يفسر الفحص الميداني الحالة أو استمرت الإشارة، فالتقييم التحليلي يساعد على استبعاد العوامل التغذوية."
            )

    # Unusual/local anomalies: include only when strong
    if unusual_s >= 0.55:
        _add_reco(
            recos_map, farm_id, "drivers",
            lib["pest_disease_check"],
            priority_override="متوسطة",
            why=why_t["unusual"]
        )

    # Forecast preparation already added when needed; keep it clean (no duplicates)
    if forecast and forecast_needed:
        _add_reco(
            recos_map, farm_id, "forecast_next_week",
            lib["prepare_week"],
            priority_override="متوسطة",
            why=why_t["forecast"]
        )

    # Add field notes only if there is at least one meaningful action
    if _has_any_reco():
        _add_reco(
            recos_map, farm_id, "system",
            lib["field_notes"],
            priority_override="منخفضة",
            why=why_t["notes"]
        )

    # -------------------------
    # 4) Sort outputs + cap alerts
    # -------------------------
    recos = list(recos_map.values())
    recos.sort(
        key=lambda r: (
            _PRIORITY_RANK.get((r.get("priority_ar") or "").strip(), 99),
            r.get("title_ar", ""),
        )
    )

    # Alerts: critical then warning then info; keep MAX 2
    order = {"critical": 0, "warning": 1, "info": 2}
    alerts.sort(key=lambda a: (order.get(a.get("severity", "info"), 9), a.get("type", "")))
    alerts = alerts[:2]

    summary = {
        "current_severity": severity_now,
        "health_now": {"Critical_Pct": crit_now, "Monitor_Pct": mon_now},
        "drivers_top": [
            {"key": k, "title_ar": driver_titles.get(k, k), "score": float(s)}
            for k, s in top_drivers
        ],
        "drivers_scores": drivers.get("scores", {}),
        "evidence_counts": drivers.get("evidence_counts", {}),
        "rates": drivers.get("rates", {}),
        "forecast": drivers.get("forecast", {}),
        "total_pixels_latest": total_pixels_latest,
        "has_forecast_alert": bool(forecast and forecast_needed),
    }

    return {"alerts": alerts, "recommendations": recos, "summary": summary}