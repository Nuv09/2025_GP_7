# app/alerts_engine.py
from __future__ import annotations
from typing import Dict, Any, List
from datetime import datetime, timezone
import hashlib


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


def _actions(severity: str, kind: str) -> List[Dict[str, str]]:
    """
    kind: 'current' | 'water' | 'stress' | 'growth' | 'unusual' | 'forecast'
    """
    severity = (severity or "").lower().strip()

    base = [
        {
            "key": "visit_now" if severity == "critical" else "visit_48h",
            "title_ar": "إجراء عاجل" if severity == "critical" else "إجراء خلال 48 ساعة",
            "text_ar": "البدء فورًا بفحص ميداني موجّه للمناطق الحمراء كما تظهر على الخريطة."
            if severity == "critical"
            else "إجراء فحص ميداني موجّه للمناطق التي تظهر على الخريطة على أنها متأثرة.",
        },
        {
            "key": "water_check",
            "title_ar": "الري",
            "text_ar": "التأكد ميدانيًا من انتظام الري ووصول الماء للمناطق المتأثرة (عدم وجود انسداد/تسرب/ضعف ضخ)."
            if severity == "critical"
            else "مراجعة انتظام الري وتوزيعه حول المناطق المتأثرة.",
        },
        {
            "key": "visual_check",
            "title_ar": "فحص بصري",
            "text_ar": "فحص بصري للنخيل في المناطق المتأثرة لرصد علامات إجهاد أو إصابة.",
        },
        {
            "key": "auto_follow",
            "title_ar": "متابعة تلقائية",
            "text_ar": "سيعيد النظام التحقق تلقائيًا في التحديث القادم، وإذا استمرت الإشارة أو اتسعت المناطق المتأثرة فسيتم رفع مستوى التنبيه."
            if severity == "critical"
            else "سيعيد النظام التحقق تلقائيًا في التحديث القادم لتأكيد اتجاه الحالة.",
        },
    ]

    extra: List[Dict[str, str]] = []
    if kind == "stress":
        extra.append(
            {
                "key": "irrigation_points",
                "title_ar": "نقاط الري",
                "text_ar": "فحص نقاط الري الأقرب للمناطق المتأثرة والتأكد من أن التغطية متساوية.",
            }
        )
    if kind == "growth":
        extra.append(
            {
                "key": "field_notes",
                "title_ar": "توثيق",
                "text_ar": "توثيق ملاحظات الفحص الميداني للمناطق المتأثرة لتسهيل متابعة التحسن في التحديثات القادمة.",
            }
        )
    if kind == "unusual":
        extra.append(
            {
                "key": "focus_spots",
                "title_ar": "تركيز",
                "text_ar": "التركيز على النقاط غير المعتادة التي يحددها النظام على الخريطة لأنها تختلف عن نمط المزرعة.",
            }
        )
    if kind == "forecast":
        extra.append(
            {
                "key": "prepare_week",
                "title_ar": "استعداد",
                "text_ar": "رفع وتيرة المتابعة للمناطق المتأثرة قبل بداية الأسبوع القادم لتقليل احتمالية التدهور.",
            }
        )

    return base + extra


# -------------------------
# ✅ توصيات بدون تكرار
# -------------------------
_PRIORITY_RANK = {
    "عاجلة": 0,
    "مرتفعة": 1,
    "متوسطة": 2,
    "منخفضة": 3,
}


def _priority_min(a: str, b: str) -> str:
    ra = _PRIORITY_RANK.get((a or "").strip(), 99)
    rb = _PRIORITY_RANK.get((b or "").strip(), 99)
    return a if ra <= rb else b


def _add_reco(
    recos_map: Dict[str, Dict[str, Any]],
    farm_id: str,
    source: str,
    priority_ar: str,
    action: Dict[str, Any],
) -> None:
    """Deduplicate recommendations by action key and keep the highest priority."""
    key = (action.get("key") or "").strip()
    if not key:
        return

    existing = recos_map.get(key)
    if existing is None:
        recos_map[key] = {
            "id": _stable_id(farm_id, "reco", key),
            "key": key,
            "sources": [source],
            "priority_ar": priority_ar,
            "title_ar": action.get("title_ar", ""),
            "text_ar": action.get("text_ar", ""),
            "createdAtISO": _now_iso(),
        }
        return

    existing["priority_ar"] = _priority_min(existing.get("priority_ar", ""), priority_ar)
    srcs = set(existing.get("sources", []) or [])
    srcs.add(source)
    existing["sources"] = sorted(srcs)


def build_alerts_and_recommendations(farm_id: str, health_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    health_result: output of analyze_farm_health()

    returns:
      {
        "alerts": [...],
        "recommendations": [...],
        "summary": {...}
      }
    """
    alerts: List[Dict[str, Any]] = []
    recos_map: Dict[str, Dict[str, Any]] = {}

    health = health_result.get("current_health", {}) or {}
    forecast = health_result.get("forecast_next_week", {}) or {}

    crit_now = _pct(health.get("Critical_Pct"))
    mon_now = _pct(health.get("Monitor_Pct"))
    severity_now = "critical" if crit_now >= 2.0 else ("warning" if mon_now >= 35.0 else "info")

    hotspots = (
        (health_result.get("alert_signals", {}) or {}).get("hotspots", {})
        or health_result.get("hotspots", {})
        or {}
    )
    rule_counts = (health_result.get("alert_signals", {}) or {}).get("rule_counts_latest", {}) or {}
    flag_counts = (health_result.get("alert_signals", {}) or {}).get("flag_counts_latest", {}) or {}

    # -------------------------
    # 1) تنبيه الحالة الحالية
    # -------------------------
    if severity_now != "info":
        sev = severity_now
        a_id = _stable_id(farm_id, "current_health", sev, str(round(crit_now, 2)), str(round(mon_now, 2)))

        acts = _actions(sev, "current")

        title = (
            "تنبيه عاجل: مناطق متدهورة داخل المزرعة"
            if sev == "critical"
            else "تنبيه: تدهور محتمل يحتاج متابعة"
        )
        message = (
            "رصد النظام مناطق تحتاج تدخّلًا سريعًا. يُوصى بالبدء بالمناطق الحمراء كما تظهر على الخريطة."
            if sev == "critical"
            else "رصد النظام مناطق قد تحتاج متابعة. يُوصى بمراجعة المناطق المتأثرة ومتابعة التحديث القادم."
        )

        hs = hotspots.get("critical", []) if sev == "critical" else hotspots.get("monitor", [])

        alerts.append(
            {
                "id": a_id,
                "type": "current_health",
                "severity": sev,
                "title_ar": title,
                "message_ar": message,
                "actions": acts,
                "hotspots": hs,
                "createdAtISO": _now_iso(),
            }
        )

        for x in acts:
            _add_reco(
                recos_map,
                farm_id,
                "current_health",
                "عاجلة" if severity_now == "critical" else ("مرتفعة" if severity_now == "warning" else "متوسطة"),
                x,
            )

    # -------------------------
    # 2) baseline_drop
    # -------------------------
    base_crit = int(rule_counts.get("Critical_baseline_drop", 0))
    base_mon = int(rule_counts.get("Monitor_baseline_drop", 0))
    if base_crit > 0 or base_mon > 0:
        sev = "critical" if base_crit > 0 else "warning"
        a2_id = _stable_id(farm_id, "baseline_drop", sev, str(base_crit), str(base_mon))
        acts2 = _actions(sev, "growth")
        alerts.append(
            {
                "id": a2_id,
                "type": "baseline_drop",
                "severity": sev,
                "title_ar": "تنبيه: تغيّر ملحوظ مقارنة بالفترة السابقة",
                "message_ar": "رصد النظام تغيّرًا ملحوظًا مقارنة بالأسابيع السابقة. يُوصى بفحص ميداني موجّه للمناطق المتأثرة ومتابعة التحديث القادم.",
                "actions": acts2,
                "hotspots": hotspots.get("critical", []) if sev == "critical" else hotspots.get("monitor", []),
                "createdAtISO": _now_iso(),
            }
        )
        for x in acts2:
            _add_reco(recos_map, farm_id, "baseline_drop", "عاجلة" if sev == "critical" else "مرتفعة", x)

    # -------------------------
    # 3) stress_signals (RPW_tail)
    # -------------------------
    tail_crit = int(rule_counts.get("Critical_RPW_tail", 0))
    tail_mon = int(rule_counts.get("Monitor_RPW_tail", 0))
    if tail_crit > 0 or tail_mon > 0:
        sev = "critical" if tail_crit > 0 else "warning"
        a3_id = _stable_id(farm_id, "rpw_tail", sev, str(tail_crit), str(tail_mon))
        acts3 = _actions(sev, "stress")
        alerts.append(
            {
                "id": a3_id,
                "type": "stress_signals",
                "severity": sev,
                "title_ar": "تنبيه: مؤشرات إجهاد في بعض المناطق",
                "message_ar": "رصد النظام إشارات إجهاد في بعض المناطق. يُوصى بمراجعة الري وفحص المناطق المتأثرة كما تظهر على الخريطة.",
                "actions": acts3,
                "hotspots": hotspots.get("stress", []) or hotspots.get("monitor", []),
                "createdAtISO": _now_iso(),
            }
        )
        for x in acts3:
            _add_reco(recos_map, farm_id, "stress_signals", "عاجلة" if sev == "critical" else "مرتفعة", x)

    # -------------------------
    # 4) unusual_points (IF_outlier)
    # -------------------------
    if_crit = int(rule_counts.get("Critical_IF_outlier", 0))
    if_mon = int(rule_counts.get("Monitor_IF_outlier", 0))
    if if_crit > 0 or if_mon > 0:
        sev = "critical" if if_crit > 0 else "warning"
        a4_id = _stable_id(farm_id, "if_outlier", sev, str(if_crit), str(if_mon))
        acts4 = _actions(sev, "unusual")
        alerts.append(
            {
                "id": a4_id,
                "type": "unusual_points",
                "severity": sev,
                "title_ar": "تنبيه: نقاط غير معتادة داخل المزرعة",
                "message_ar": "رصد النظام نقاطًا تختلف عن النمط العام للمزرعة. يُوصى بفحص ميداني موجّه لهذه النقاط ثم متابعة التحديث القادم.",
                "actions": acts4,
                "hotspots": hotspots.get("monitor", []) or hotspots.get("stress", []),
                "createdAtISO": _now_iso(),
            }
        )
        for x in acts4:
            _add_reco(recos_map, farm_id, "unusual_points", "عاجلة" if sev == "critical" else "مرتفعة", x)

    # -------------------------
    # 5) water_signals (flags)
    # -------------------------
    water_flags = (
        int(flag_counts.get("flag_drop_SIWSI10pct", 0))
        + int(flag_counts.get("flag_drop_NDWI10pct", 0))
        + int(flag_counts.get("flag_NDWI_low", 0))
        + int(flag_counts.get("flag_NDWI_below_025", 0))
    )
    if water_flags > 0:
        sev = "critical" if severity_now == "critical" else "warning"
        a5_id = _stable_id(farm_id, "water_flags", sev, str(water_flags))
        acts5 = _actions(sev, "water")
        alerts.append(
            {
                "id": a5_id,
                "type": "water_signals",
                "severity": sev,
                "title_ar": "تنبيه: مؤشرات مرتبطة بالري والرطوبة",
                "message_ar": "ظهرت مؤشرات قد ترتبط باضطراب في الري أو الرطوبة في بعض المناطق. يُوصى بمراجعة الري ميدانيًا حول المناطق المتأثرة.",
                "actions": acts5,
                "hotspots": hotspots.get("stress", []) or hotspots.get("monitor", []),
                "createdAtISO": _now_iso(),
            }
        )
        for x in acts5:
            _add_reco(recos_map, farm_id, "water_signals", "مرتفعة" if sev == "warning" else "عاجلة", x)

    # -------------------------
    # 6) growth_signals (NDVI/NDRE drops)
    # -------------------------
    growth_flags = (
        int(flag_counts.get("flag_drop_NDVI005", 0))
        + int(flag_counts.get("flag_NDVI_below_030", 0))
        + int(flag_counts.get("flag_NDRE_low", 0))
        + int(flag_counts.get("flag_NDRE_below_035", 0))
    )
    if growth_flags > 0:
        sev = "critical" if severity_now == "critical" else "warning"
        a6_id = _stable_id(farm_id, "growth_flags", sev, str(growth_flags))
        acts6 = _actions(sev, "growth")
        alerts.append(
            {
                "id": a6_id,
                "type": "growth_signals",
                "severity": sev,
                "title_ar": "تنبيه: مؤشرات انخفاض في نشاط النبات",
                "message_ar": "ظهرت مؤشرات قد تشير إلى انخفاض في نشاط النبات داخل بعض المناطق. يُوصى بفحص ميداني موجّه ومتابعة التحديث القادم.",
                "actions": acts6,
                "hotspots": hotspots.get("stress", []) or hotspots.get("monitor", []),
                "createdAtISO": _now_iso(),
            }
        )
        for x in acts6:
            _add_reco(recos_map, farm_id, "growth_signals", "مرتفعة" if sev == "warning" else "عاجلة", x)

    # -------------------------
    # 7) forecast_next_week
    # -------------------------
    forecast_needed = False
    if forecast:
        crit_next = _pct(forecast.get("Critical_Pct_next"))
        mon_next = _pct(forecast.get("Monitor_Pct_next"))
        if mon_next >= 70.0 or crit_next >= 1.0:
            forecast_needed = True
            f_sev = "warning" if crit_next < 1.0 else "critical"
            a7_id = _stable_id(farm_id, "forecast_next_week", f_sev, str(round(mon_next, 2)), str(round(crit_next, 2)))
            acts7 = _actions(f_sev, "forecast")
            parts = ["يتوقع النظام زيادة الحاجة للمتابعة خلال الأسبوع القادم."]
            if mon_next >= 90:
                parts.append("معظم مناطق المزرعة قد تدخل نطاق المتابعة.")
            elif mon_next >= 70:
                parts.append("نسبة كبيرة قد تحتاج مراقبة.")

            alerts.append(
                {
                    "id": a7_id,
                    "type": "forecast_next_week",
                    "severity": f_sev,
                    "title_ar": "توقعات الأسبوع القادم",
                    "message_ar": " ".join(parts),
                    "actions": acts7,
                    "hotspots": hotspots.get("monitor", []) or hotspots.get("stress", []) or hotspots.get("critical", []),
                    "createdAtISO": _now_iso(),
                }
            )
            for x in acts7:
                _add_reco(
                    recos_map,
                    farm_id,
                    "forecast_next_week",
                    "مرتفعة" if f_sev in {"warning", "critical"} else "متوسطة",
                    x,
                )

    # ✅ تحويل توصيات (map) إلى قائمة مرتبة بدون تكرار
    recos = list(recos_map.values())
    recos.sort(key=lambda r: (_PRIORITY_RANK.get((r.get("priority_ar") or "").strip(), 99), r.get("title_ar", "")))

    # ترتيب التنبيهات: critical ثم warning ثم info
    order = {"critical": 0, "warning": 1, "info": 2}
    alerts.sort(key=lambda a: (order.get(a.get("severity", "info"), 9), a.get("type", "")))

    return {
        "alerts": alerts,
        "recommendations": recos,
        "summary": {
            "current_severity": severity_now,
            "has_forecast_alert": forecast_needed,
        },
    }
