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
        if v != v:
            return 0.0
        return max(0.0, min(100.0, v))
    except Exception:
        return 0.0


def _severity_from_current(cur_c: float, cur_m: float) -> str:
    # مبني على مخرجاتكم: وجود Critical => حرج، وجود Monitor => تحذير، غير ذلك => معلومات
    if cur_c > 0.0:
        return "critical"
    if cur_m > 0.0:
        return "warning"
    return "info"


def _actions(severity: str, focus: str) -> List[Dict[str, str]]:
    """
    focus:
      - "critical" / "monitor" / "water" / "growth" / "stress" / "forecast" / "unusual"
    """
    if severity == "critical":
        base = [
            {"key": "visit_now", "title_ar": "إجراء عاجل", "text_ar": "البدء فورًا بفحص ميداني موجّه للمناطق الحمراء كما تظهر على الخريطة."},
            {"key": "water_check", "title_ar": "الري", "text_ar": "التأكد ميدانيًا من انتظام الري ووصول الماء للمناطق المتأثرة (عدم وجود انسداد/تسرب/ضعف ضخ)."},
            {"key": "visual_check", "title_ar": "فحص بصري", "text_ar": "فحص بصري للنخيل في المناطق المتأثرة لرصد علامات إجهاد أو إصابة."},
            {"key": "auto_follow", "title_ar": "متابعة تلقائية", "text_ar": "سيعيد النظام التحقق تلقائيًا في التحديث القادم، وإذا استمرت الإشارة أو اتسعت المناطق المتأثرة فسيتم رفع مستوى التنبيه."},
        ]
    elif severity == "warning":
        base = [
            {"key": "visit_48h", "title_ar": "إجراء خلال 48 ساعة", "text_ar": "إجراء فحص ميداني موجّه للمناطق التي تظهر على الخريطة على أنها متأثرة."},
            {"key": "water_check", "title_ar": "الري", "text_ar": "مراجعة انتظام الري وتوزيعه حول المناطق المتأثرة."},
            {"key": "auto_follow", "title_ar": "متابعة تلقائية", "text_ar": "سيعيد النظام التحقق تلقائيًا في التحديث القادم لتأكيد اتجاه الحالة."},
        ]
    else:
        base = [
            {"key": "watch", "title_ar": "مراقبة", "text_ar": "لا توجد مؤشرات مقلقة حاليًا. يُنصح بمتابعة التحديث القادم للتأكد من استمرار الاستقرار."}
        ]

    extra: List[Dict[str, str]] = []
    if focus in {"water", "stress"}:
        extra.append({"key": "irrigation_points", "title_ar": "نقاط الري", "text_ar": "فحص نقاط الري الأقرب للمناطق المتأثرة والتأكد من أن التغطية متساوية."})
    if focus in {"growth"}:
        extra.append({"key": "field_notes", "title_ar": "توثيق", "text_ar": "توثيق ملاحظات الفحص الميداني للمناطق المتأثرة لتسهيل متابعة التحسن في التحديثات القادمة."})
    if focus == "forecast":
        extra.append({"key": "prepare_week", "title_ar": "استعداد", "text_ar": "رفع وتيرة المتابعة للمناطق المتأثرة قبل بداية الأسبوع القادم لتقليل احتمالية التدهور."})
    if focus == "unusual":
        extra.append({"key": "focus_spots", "title_ar": "تركيز", "text_ar": "التركيز على النقاط غير المعتادة التي يحددها النظام على الخريطة لأنها تختلف عن نمط المزرعة."})

    return base + extra


def build_alerts_and_recommendations(farm_id: str, health_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    ✅ مخرجات جاهزة للواجهة والحفظ:
      alerts: قائمة تنبيهات (كل تنبيه معه actions + hotspots)
      recommendations: قائمة توصيات مفصولة (مناسبة لصفحة توصيات)
    """
    health_result = health_result or {}
    cur = health_result.get("current_health", {}) or {}
    fc  = health_result.get("forecast_next_week", {}) or {}
    sig = health_result.get("alert_signals", {}) or {}

    # نسب حالية
    cur_m = _pct(cur.get("Monitor_Pct"))
    cur_c = _pct(cur.get("Critical_Pct"))

    # نسب متوقعة
    nxt_m = _pct(fc.get("Monitor_Pct_next"))
    nxt_c = _pct(fc.get("Critical_Pct_next"))

    # إشارات
    rule_counts = sig.get("rule_counts_latest", {}) or {}
    flag_counts = sig.get("flag_counts_latest", {}) or {}
    hotspots = sig.get("hotspots", {}) or {}

    severity_now = _severity_from_current(cur_c, cur_m)

    alerts: List[Dict[str, Any]] = []
    recos: List[Dict[str, Any]] = []

    # -------------------------
    # 1) تنبيه الحالة الحالية
    # -------------------------
    if severity_now == "critical":
        title = "تنبيه عاجل: مناطق متدهورة داخل المزرعة"
        message = "رصد النظام مناطق تحتاج تدخّلًا سريعًا. يُوصى بالبدء بالمناطق الحمراء كما تظهر على الخريطة."
        focus = "critical"
        hs = hotspots.get("critical", [])
    elif severity_now == "warning":
        title = "تنبيه: مناطق تحتاج متابعة"
        message = "رصد النظام مناطق تحتاج متابعة خلال الفترة القادمة. يُوصى بفحص ميداني موجّه للمناطق المتأثرة كما تظهر على الخريطة."
        focus = "monitor"
        hs = hotspots.get("monitor", [])
    else:
        title = "حالة مطمئنة"
        message = "تبدو حالة المزرعة مستقرة وفق آخر تحديث."
        focus = "monitor"
        hs = []

    a_id = _stable_id(farm_id, "current", severity_now, str(round(cur_c, 2)), str(round(cur_m, 2)))
    acts = _actions(severity_now, focus)

    alerts.append({
        "id": a_id,
        "type": "current_health",
        "severity": severity_now,   # critical/warning/info
        "title_ar": title,
        "message_ar": message,
        "actions": acts,
        "hotspots": hs,
        "createdAtISO": _now_iso(),
    })

    for x in acts:
        recos.append({
            "id": _stable_id(farm_id, "reco", "current", x["key"]),
            "source": "current_health",
            "priority_ar": "عاجلة" if severity_now == "critical" else ("مرتفعة" if severity_now == "warning" else "متوسطة"),
            "title_ar": x["title_ar"],
            "text_ar": x["text_ar"],
            "createdAtISO": _now_iso(),
        })

    # -------------------------
    # 2) تنبيه "تغير ملحوظ" (baseline_drop) — من RPW_label_rule
    # -------------------------
    base_crit = int(rule_counts.get("Critical_baseline_drop", 0))
    base_mon  = int(rule_counts.get("Monitor_baseline_drop", 0))
    if base_crit > 0 or base_mon > 0:
        sev = "critical" if base_crit > 0 else "warning"
        a2_id = _stable_id(farm_id, "baseline_drop", sev, str(base_crit), str(base_mon))
        acts2 = _actions(sev, "growth")
        alerts.append({
            "id": a2_id,
            "type": "baseline_drop",
            "severity": sev,
            "title_ar": "تنبيه: تغيّر ملحوظ مقارنة بالفترة السابقة",
            "message_ar": "رصد النظام تغيّرًا ملحوظًا مقارنة بالأسابيع السابقة. يُوصى بفحص ميداني موجّه للمناطق المتأثرة ومتابعة التحديث القادم.",
            "actions": acts2,
            "hotspots": hotspots.get("critical", []) if sev == "critical" else hotspots.get("monitor", []),
            "createdAtISO": _now_iso(),
        })
        for x in acts2:
            recos.append({
                "id": _stable_id(farm_id, "reco", "baseline_drop", x["key"]),
                "source": "baseline_drop",
                "priority_ar": "عاجلة" if sev == "critical" else "مرتفعة",
                "title_ar": x["title_ar"],
                "text_ar": x["text_ar"],
                "createdAtISO": _now_iso(),
            })

    # -------------------------
    # 3) تنبيه "إجهاد" (RPW_tail) — من RPW_label_rule
    # -------------------------
    tail_crit = int(rule_counts.get("Critical_RPW_tail", 0))
    tail_mon  = int(rule_counts.get("Monitor_RPW_tail", 0))
    if tail_crit > 0 or tail_mon > 0:
        sev = "critical" if tail_crit > 0 else "warning"
        a3_id = _stable_id(farm_id, "rpw_tail", sev, str(tail_crit), str(tail_mon))
        acts3 = _actions(sev, "stress")
        alerts.append({
            "id": a3_id,
            "type": "stress_signals",
            "severity": sev,
            "title_ar": "تنبيه: مؤشرات إجهاد في بعض المناطق",
            "message_ar": "رصد النظام إشارات إجهاد في بعض المناطق. يُوصى بمراجعة الري وفحص المناطق المتأثرة كما تظهر على الخريطة.",
            "actions": acts3,
            "hotspots": hotspots.get("stress", []) or hotspots.get("monitor", []),
            "createdAtISO": _now_iso(),
        })
        for x in acts3:
            recos.append({
                "id": _stable_id(farm_id, "reco", "stress_signals", x["key"]),
                "source": "stress_signals",
                "priority_ar": "عاجلة" if sev == "critical" else "مرتفعة",
                "title_ar": x["title_ar"],
                "text_ar": x["text_ar"],
                "createdAtISO": _now_iso(),
            })

    # -------------------------
    # 4) تنبيه "نقاط غير معتادة" (IF_outlier) — من RPW_label_rule
    # -------------------------
    if_crit = int(rule_counts.get("Critical_IF_outlier", 0))
    if_mon  = int(rule_counts.get("Monitor_IF_outlier", 0))
    if if_crit > 0 or if_mon > 0:
        sev = "critical" if if_crit > 0 else "warning"
        a4_id = _stable_id(farm_id, "if_outlier", sev, str(if_crit), str(if_mon))
        acts4 = _actions(sev, "unusual")
        alerts.append({
            "id": a4_id,
            "type": "unusual_points",
            "severity": sev,
            "title_ar": "تنبيه: نقاط غير معتادة داخل المزرعة",
            "message_ar": "رصد النظام نقاطًا تختلف عن النمط العام للمزرعة. يُوصى بفحص ميداني موجّه لهذه النقاط ثم متابعة التحديث القادم.",
            "actions": acts4,
            "hotspots": hotspots.get("monitor", []) or hotspots.get("stress", []),
            "createdAtISO": _now_iso(),
        })
        for x in acts4:
            recos.append({
                "id": _stable_id(farm_id, "reco", "unusual_points", x["key"]),
                "source": "unusual_points",
                "priority_ar": "عاجلة" if sev == "critical" else "مرتفعة",
                "title_ar": x["title_ar"],
                "text_ar": x["text_ar"],
                "createdAtISO": _now_iso(),
            })

    # -------------------------
    # 5) تنبيه "الري/الرطوبة" — من FLAGS الموجودة في كودكم
    # -------------------------
    water_flags = (
        int(flag_counts.get("flag_drop_SIWSI10pct", 0)) +
        int(flag_counts.get("flag_drop_NDWI10pct", 0)) +
        int(flag_counts.get("flag_NDWI_low", 0)) +
        int(flag_counts.get("flag_NDWI_below_025", 0))
    )
    if water_flags > 0:
        sev = "critical" if severity_now == "critical" else "warning"
        a5_id = _stable_id(farm_id, "water_flags", sev, str(water_flags))
        acts5 = _actions(sev, "water")
        alerts.append({
            "id": a5_id,
            "type": "water_signals",
            "severity": sev,
            "title_ar": "تنبيه: مؤشرات مرتبطة بالري والرطوبة",
            "message_ar": "ظهرت مؤشرات قد ترتبط باضطراب في الري أو الرطوبة في بعض المناطق. يُوصى بمراجعة الري ميدانيًا حول المناطق المتأثرة.",
            "actions": acts5,
            "hotspots": hotspots.get("stress", []) or hotspots.get("monitor", []),
            "createdAtISO": _now_iso(),
        })
        for x in acts5:
            recos.append({
                "id": _stable_id(farm_id, "reco", "water_signals", x["key"]),
                "source": "water_signals",
                "priority_ar": "مرتفعة" if sev == "warning" else "عاجلة",
                "title_ar": x["title_ar"],
                "text_ar": x["text_ar"],
                "createdAtISO": _now_iso(),
            })

    # -------------------------
    # 6) تنبيه "نشاط/نمو" — من FLAGS الموجودة في كودكم
    # -------------------------
    growth_flags = (
        int(flag_counts.get("flag_drop_NDVI005", 0)) +
        int(flag_counts.get("flag_NDVI_below_030", 0)) +
        int(flag_counts.get("flag_NDRE_below_035", 0)) +
        int(flag_counts.get("flag_NDRE_low", 0))
    )
    if growth_flags > 0:
        sev = "critical" if severity_now == "critical" else "warning"
        a6_id = _stable_id(farm_id, "growth_flags", sev, str(growth_flags))
        acts6 = _actions(sev, "growth")
        alerts.append({
            "id": a6_id,
            "type": "growth_signals",
            "severity": sev,
            "title_ar": "تنبيه: مؤشرات انخفاض في نشاط النبات",
            "message_ar": "ظهرت مؤشرات قد تشير إلى انخفاض في نشاط النبات داخل بعض المناطق. يُوصى بفحص ميداني موجّه ومتابعة التحديث القادم.",
            "actions": acts6,
            "hotspots": hotspots.get("monitor", []) or hotspots.get("critical", []),
            "createdAtISO": _now_iso(),
        })
        for x in acts6:
            recos.append({
                "id": _stable_id(farm_id, "reco", "growth_signals", x["key"]),
                "source": "growth_signals",
                "priority_ar": "مرتفعة" if sev == "warning" else "عاجلة",
                "title_ar": x["title_ar"],
                "text_ar": x["text_ar"],
                "createdAtISO": _now_iso(),
            })

    # -------------------------
    # 7) تنبيه التوقعات — من مودلكم فقط (بدون thresholds جديدة)
    # -------------------------
    forecast_needed = False
    parts: List[str] = []
    f_sev = "info"

    if nxt_c > 0.0:
        forecast_needed = True
        f_sev = "critical" if severity_now == "critical" else "warning"
        parts.append("يتوقع النظام ارتفاع مستوى الخطر في بعض المناطق خلال الأسبوع القادم.")

    if nxt_c > cur_c:
        forecast_needed = True
        f_sev = "critical" if severity_now == "critical" else "warning"
        parts.append("الاتجاه المتوقع يشير إلى تزايد المناطق المتأثرة إذا لم تُتخذ إجراءات مبكرة.")

    if (nxt_c == 0.0) and (nxt_m > cur_m):
        forecast_needed = True
        if f_sev != "critical":
            f_sev = "warning"
        parts.append("يتوقع النظام زيادة الحاجة للمتابعة خلال الأسبوع القادم.")

    if forecast_needed:
        a7_id = _stable_id(farm_id, "forecast", f_sev, str(round(nxt_c, 2)), str(round(nxt_m, 2)))
        acts7 = _actions(f_sev, "forecast")
        alerts.append({
            "id": a7_id,
            "type": "forecast_next_week",
            "severity": f_sev,
            "title_ar": "توقعات الأسبوع القادم",
            "message_ar": " ".join(parts),
            "actions": acts7,
            "hotspots": hotspots.get("monitor", []) or hotspots.get("stress", []) or hotspots.get("critical", []),
            "createdAtISO": _now_iso(),
        })
        for x in acts7:
            recos.append({
                "id": _stable_id(farm_id, "reco", "forecast_next_week", x["key"]),
                "source": "forecast_next_week",
                "priority_ar": "مرتفعة" if f_sev in {"warning", "critical"} else "متوسطة",
                "title_ar": x["title_ar"],
                "text_ar": x["text_ar"],
                "createdAtISO": _now_iso(),
            })

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
