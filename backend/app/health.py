import tempfile
import os
import math
import warnings
from typing import Dict, Any, List, Tuple

import numpy as np
import pandas as pd
import requests
import joblib

import ee
import geemap

from requests.adapters import HTTPAdapter, Retry
from google.cloud import storage

from app.common import polygon_centroid

# =========================
# إعدادات عامة
# =========================

PROJECT_ID = os.environ.get("GEE_PROJECT_ID", "saaf-97251")
OUT_ROOT = os.environ.get("HEALTH_OUT_ROOT", "/tmp/saaf_health")
os.makedirs(OUT_ROOT, exist_ok=True)

# نطاق التاريخ (آخر 12 شهر تقريبًا)
TODAY = pd.Timestamp.utcnow().normalize()
DATE_TO = TODAY
DATE_FROM = TODAY - pd.Timedelta(weeks=52)

# Sentinel-2 / GEE إعدادات
S2_COLLECTION = "COPERNICUS/S2_SR_HARMONIZED"
MAX_CLOUD = 40          # أقصى نسبة غيوم
RESOLUTION = 10         # دقة S2 بالبكسل (متر)

# Isolation Forest model (مخزن في GCS كـ joblib)
IF_MODEL_GS_URI = os.environ.get("IF_MODEL_GS_URI", "")

# ملف المتوسطات المستخدمة لتعبئة NaN في الـ IF (مدرب على ~10M صف)
IF_MEANS_GS_URI = os.environ.get("IF_MEANS_GS_URI", "")

# قائمة المؤشرات الطيفية الأساسية
INDEX_COLS_ALL = [
    "NDVI", "GNDVI", "NDRE", "NDRE740", "MTCI",
    "NDMI", "NDWI_Gao", "SIWSI1", "SIWSI2", "SRWI", "NMDI",
]

# =========================
# أدوات GCS لتحميل نموذج IF / الـ means
# =========================

def _gcs() -> storage.Client:
    return storage.Client()

def _parse_gs_uri(uri: str) -> Tuple[str, str]:
    uri = uri.replace("gs://", "")
    bucket, *parts = uri.split("/")
    blob = "/".join(parts)
    return bucket, blob

def _download_gcs_file(gs_uri: str, suffix: str = ".joblib") -> str:
    if not gs_uri.startswith("gs://"):
        raise ValueError(f"GS URI يجب أن يكون بصيغة gs://bucket/path, الحالي: {gs_uri!r}")
    bucket_name, blob_name = _parse_gs_uri(gs_uri)
    client = _gcs()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    if not blob.exists():
        raise FileNotFoundError(f"Blob not found: {gs_uri}")

    # ✅ بدل os.mkstemp نستخدم tempfile.mkstemp
    fd, tmp_path = tempfile.mkstemp(suffix=suffix, dir=OUT_ROOT)
    os.close(fd)
    blob.download_to_filename(tmp_path)
    return tmp_path


_IF_MODEL = None
_IF_FEATURE_MEANS = None  # ⇐ cache لملف المتوسطات

def get_if_model():
    """
    تحميل نموذج Isolation Forest المدرب مرة واحدة من GCS (inference فقط)،
    مع طباعة سبب الفشل لو صار شيء.
    """
    global _IF_MODEL
    if _IF_MODEL is not None:
        return _IF_MODEL

    if not IF_MODEL_GS_URI:
        msg = "IF_MODEL_GS_URI غير مضبوط في متغيرات البيئة"
        print("[IF] ERROR:", msg)
        raise RuntimeError(msg)

    try:
        print(f"[IF] Downloading model from GCS: {IF_MODEL_GS_URI}")
        local_path = _download_gcs_file(IF_MODEL_GS_URI, suffix=".joblib")
        print(f"[IF] Model file downloaded to: {local_path}")
    except Exception as e:
        print(f"[IF] ERROR while downloading IF model from GCS: {e}")
        raise

    try:
        _IF_MODEL = joblib.load(local_path)
        print(f"[IF] Loaded IF model OK, type={type(_IF_MODEL)}")
    except Exception as e:
        print(f"[IF] ERROR while loading IF joblib from {local_path}: {e}")
        raise

    return _IF_MODEL


def get_if_feature_means() -> Dict[str, float]:
    """
    تحميل متوسطات الفيتشرز التي تم حسابها من داتا التدريب (≈10M صف)
    من ملف joblib في GCS (if_feature_means.joblib).
    ترجع dict: feature_name -> mean_value
    """
    global _IF_FEATURE_MEANS
    if _IF_FEATURE_MEANS is not None:
        return _IF_FEATURE_MEANS

    if not IF_MEANS_GS_URI:
        raise RuntimeError("IF_MEANS_GS_URI غير مضبوط في متغيرات البيئة")

    local_path = _download_gcs_file(IF_MEANS_GS_URI, suffix=".joblib")
    obj = joblib.load(local_path)

    # نتأكد أنه dict بسيط {col: float}
    if isinstance(obj, dict):
        _IF_FEATURE_MEANS = {str(k): float(v) for k, v in obj.items()}
    else:
        raise TypeError(
            f"if_feature_means.joblib المتوقع يكون dict، لكن النوع الفعلي: {type(obj)}"
        )

    return _IF_FEATURE_MEANS

# =========================
# تهيئة Earth Engine + جلسة HTTP
# =========================

def _init_ee():
    """
    تهيئة Earth Engine باستخدام GEE_PROJECT_ID.
    نخلي الخطأ الحقيقي يطلع عشان نعرف المشكلة (صلاحيات؟ مشروع؟).
    """
    try:
        ee.Initialize(project=PROJECT_ID)
    except Exception as e:
        raise RuntimeError(
            f"فشل تهيئة Earth Engine داخل health.py باستخدام المشروع '{PROJECT_ID}': {e}"
        )

_init_ee()

session = requests.Session()
retries = Retry(
    total=6,
    backoff_factor=0.8,
    status_forcelist=[429, 500, 502, 503, 504],
)
adapter = HTTPAdapter(max_retries=retries)
session.mount("http://", adapter)
session.mount("https://", adapter)

memory = joblib.Memory(location=OUT_ROOT, verbose=0)

def week_bins(start: pd.Timestamp, end: pd.Timestamp) -> List[Tuple[pd.Timestamp, pd.Timestamp]]:
    """
    يرجّع قائمة بأسابيع [start, end) بين تاريخين.
    """
    start = pd.to_datetime(start).normalize()
    end = pd.to_datetime(end).normalize()
    weeks: List[Tuple[pd.Timestamp, pd.Timestamp]] = []
    cur = start
    while cur < end:
        wend = cur + pd.Timedelta(days=7)
        weeks.append((cur, min(wend, end)))
        cur = wend
    return weeks

# =========================
# طقس أسبوعي (Open-Meteo ERA5)
# =========================

def _es_kPa(Tc):
    return 0.6108 * np.exp((17.27 * Tc) / (Tc + 237.3))

@memory.cache
def _weather_open_meteo(lat: float, lon: float, start_date, end_date):
    """
    نفس منطق النوتبوك:
      - استخدام ERA5
      - حساب RH/VPD مع fallback من dew point لو RH مش متوفرة
      - تجميع أسبوعي 7 أيام
    """
    try:
        url = "https://archive-api.open-meteo.com/v1/era5"
        daily_vars = ",".join([
            "precipitation_sum",
            "temperature_2m_mean",
            "temperature_2m_max",
            "temperature_2m_min",
            "shortwave_radiation_sum",
            "wind_speed_10m_mean",
            "relative_humidity_2m_mean",
            "dew_point_2m_mean",
        ])
        params = {
            "latitude": float(lat),
            "longitude": float(lon),
            "start_date": str(pd.to_datetime(start_date).date()),
            "end_date":   str(pd.to_datetime(end_date).date()),
            "daily": daily_vars,
            "timezone": "UTC",
        }
        r = session.get(url, params=params, timeout=60)
        r.raise_for_status()
        js = r.json()
        if "daily" not in js or not js["daily"].get("time"):
            return None

        daily = pd.DataFrame(js["daily"])
        daily["date"] = pd.to_datetime(daily["time"]).dt.normalize()

        # RH من العمود لو موجود، وإلا نحسبها من dew point
        if "relative_humidity_2m_mean" in daily.columns:
            daily["rh2m_mean"] = daily["relative_humidity_2m_mean"]
        elif "dew_point_2m_mean" in daily.columns:
            t = daily["temperature_2m_mean"].astype(float)
            d = daily["dew_point_2m_mean"].astype(float)
            es = 6.112 * np.exp((17.67 * t) / (t + 243.5))
            e = 6.112 * np.exp((17.67 * d) / (d + 243.5))
            daily["rh2m_mean"] = 100.0 * (e / (es + 1e-6))
        else:
            daily["rh2m_mean"] = np.nan

        # VPD من T و dew point لو متوفر
        if "dew_point_2m_mean" in daily.columns:
            t_C = daily["temperature_2m_mean"].astype(float)
            d_C = daily["dew_point_2m_mean"].astype(float)
            daily["vpd_kPa"] = _es_kPa(t_C) - _es_kPa(d_C)
        else:
            daily["vpd_kPa"] = np.nan

        daily = daily.rename(columns={
            "precipitation_sum": "precip_mm",
            "temperature_2m_mean": "t2m_mean",
            "temperature_2m_max": "t2m_max",
            "temperature_2m_min": "t2m_min",
            "shortwave_radiation_sum": "ssrd_MJ",
            "wind_speed_10m_mean": "wind10_ms",
        }).set_index("date")

        # تجميع أسبوعي 7 أيام
        w = daily.resample(
            "7D",
            origin=pd.to_datetime(start_date),
            label="left",
            closed="left",
        )
        weekly = pd.DataFrame({
            "precip_mm": w["precip_mm"].sum(),
            "t2m_mean":  w["t2m_mean"].mean(),
            "t2m_max":   w["t2m_max"].max(),
            "t2m_min":   w["t2m_min"].min(),
            "ssrd_MJ":   w["ssrd_MJ"].sum(),
            "wind10_ms": w["wind10_ms"].mean(),
            "vpd_kPa":   w["vpd_kPa"].mean(),
            "rh2m_mean": w["rh2m_mean"].mean(),
        }).reset_index().rename(columns={"date": "date"})
        weekly["date"] = pd.to_datetime(weekly["date"]).dt.normalize()
        weekly["wx_source"] = "OpenMeteo_ERA5"
        return weekly

    except Exception:
        return None

def weekly_weather(site: Dict[str, Any]) -> pd.DataFrame:
    """
    طقس أسبوعي لمزرعة واحدة، باستخدام مركز المضلع.
    farm_doc["polygon"] = [{'lat':..,'lng':..}, ...]
    هنا site["polygon"] = [(lon, lat), ...]
    """
    coords = site["polygon"]
    poly_for_centroid = [{"lat": lat, "lng": lon} for (lon, lat) in coords]
    lat, lon = polygon_centroid(poly_for_centroid)
    weeks = week_bins(DATE_FROM, DATE_TO)

    om = _weather_open_meteo(lat, lon, DATE_FROM, DATE_TO)
    if om is not None and not om.empty:
        return om

    # فشل الاتصال أو لا توجد بيانات → إطار فارغ بنفس هيكل الأعمدة
    df = pd.DataFrame({
        "date": [w[0].normalize() for w in weeks],
        "precip_mm": np.nan,
        "t2m_mean": np.nan,
        "t2m_max": np.nan,
        "t2m_min": np.nan,
        "ssrd_MJ": np.nan,
        "wind10_ms": np.nan,
        "vpd_kPa": np.nan,
        "rh2m_mean": np.nan,
        "wx_source": "NONE",
    })
    return df

# =========================
# LST من Landsat عبر GEE
# =========================

def load_week_LST_Landsat_GEE(site: Dict[str, Any], d_from, d_to) -> float:
    """
    متوسط حرارة المظلة °C للأسبوع باستخدام Landsat 8/9 ST_B10 من GEE.
    نفس منطق النوتبوك (scale/offset + فلترة القيم الغريبة)،
    مع طباعة أسباب رجوع NaN للتشخيص.
    """
    site_name = site.get("name", "UNKNOWN")
    geom = ee.Geometry.Polygon(site["polygon"])

    d_from_ts = pd.to_datetime(d_from)
    d_to_ts = pd.to_datetime(d_to)
    d_from_iso = d_from_ts.date().isoformat()
    d_to_iso = d_to_ts.date().isoformat()

    print(f"[LST] Request for site={site_name}, window={d_from_iso} → {d_to_iso}")

    col8 = (ee.ImageCollection("LANDSAT/LC08/C02/T1_L2")
            .filterBounds(geom)
            .filterDate(d_from_iso, d_to_iso)
            .filter(ee.Filter.lt("CLOUD_COVER", 80)))
    col9 = (ee.ImageCollection("LANDSAT/LC09/C02/T1_L2")
            .filterBounds(geom)
            .filterDate(d_from_iso, d_to_iso)
            .filter(ee.Filter.lt("CLOUD_COVER", 80)))

    col = col8.merge(col9)

    try:
        size = col.size().getInfo()
    except Exception as e:
        print(f"[LST] ERROR size().getInfo() for site={site_name}: {type(e).__name__}: {e}")
        return np.nan

    if size == 0:
        print(f"[LST] No Landsat 8/9 images for site={site_name} in {d_from_iso} → {d_to_iso}")
        return np.nan

    img = ee.Image(col.sort("CLOUD_COVER").first())

    # حاول نطبع ID للصورة للتشخيص (لو متاح)
    img_id = None
    try:
        img_id = img.get("LANDSAT_PRODUCT_ID").getInfo()
    except Exception:
        try:
            img_id = img.get("SYSTEM_INDEX").getInfo()
        except Exception:
            img_id = "UNKNOWN_ID"

    try:
        band_names = img.bandNames().getInfo()
    except Exception as e:
        print(f"[LST] ERROR bandNames().getInfo() site={site_name}, img={img_id}: {type(e).__name__}: {e}")
        return np.nan

    if "ST_B10" not in band_names:
        print(f"[LST] Image {img_id} for site={site_name} has no ST_B10 band → returning NaN")
        return np.nan

    st = img.select("ST_B10")

    scale = 0.00341802
    offset = 149.0
    lst_k = st.multiply(scale).add(offset)
    lst_c = lst_k.subtract(273.15).rename("LST_C")

    try:
        mean_dict = lst_c.reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=geom,
            scale=30,
            maxPixels=1e8,
            bestEffort=True,
        ).getInfo()
    except Exception as e:
        print(f"[LST] ERROR reduceRegion() site={site_name}, img={img_id}, "
              f"window={d_from_iso}→{d_to_iso}: {type(e).__name__}: {e}")
        return np.nan

    if not mean_dict:
        print(f"[LST] reduceRegion returned empty dict for site={site_name}, img={img_id}")
        return np.nan

    val = mean_dict.get("LST_C", None)
    if val is None:
        print(f"[LST] reduceRegion has no 'LST_C' key for site={site_name}, img={img_id} → {mean_dict}")
        return np.nan

    try:
        temp_c = float(val)
    except Exception as e:
        print(f"[LST] ERROR casting LST_C to float for site={site_name}, img={img_id}: {type(e).__name__}: {e}")
        return np.nan

    if (temp_c < 15.0) or (temp_c > 65.0):
        print(f"[LST] Discarding out-of-range canopy_temp={temp_c:.2f}°C "
              f"(site={site_name}, img={img_id}) → set NaN")
        return np.nan

    print(f"[LST] OK site={site_name}, img={img_id}, canopy_temp={temp_c:.2f}°C")
    return temp_c


# =========================
# Sentinel-2 GEE → بكسلات أسبوعية
# =========================

def s2_week_pixels_gee(site: Dict[str, Any], wstart: pd.Timestamp, wend: pd.Timestamp) -> pd.DataFrame | None:
    """
    تحميل مشهد Sentinel-2 من GEE للأسبوع المحدد، حساب 11 مؤشر طيفي،
    وأخذ عينة بكسلات (x, y + المؤشرات).
    """
    site_name = site["name"]
    geom = ee.Geometry.Polygon(site["polygon"])

    d_from = (wstart - pd.Timedelta(days=6)).date().isoformat()
    d_to   = (wend   + pd.Timedelta(days=6)).date().isoformat()

    col = (ee.ImageCollection(S2_COLLECTION)
           .filterBounds(geom)
           .filterDate(d_from, d_to)
           .filter(ee.Filter.lte("CLOUDY_PIXEL_PERCENTAGE", MAX_CLOUD)))

    size = col.size().getInfo()
    if size == 0:
        return None

    image = ee.Image(col.sort("CLOUDY_PIXEL_PERCENTAGE").first())
    scl = image.select("SCL")

    # نباتات فقط (4,5) واستبعاد سحب 7–11
    valid = scl.eq(4).Or(scl.eq(5))
    clouds = (scl.eq(7)
              .Or(scl.eq(8))
              .Or(scl.eq(9))
              .Or(scl.eq(10))
              .Or(scl.eq(11)))
    mask = valid.And(clouds.Not())
    image = image.updateMask(mask)

    B2  = image.select("B2")
    B3  = image.select("B3")
    B4  = image.select("B4")
    B5  = image.select("B5")
    B6  = image.select("B6")
    B7  = image.select("B7")
    B8  = image.select("B8")
    B8A = image.select("B8A")
    B11 = image.select("B11")
    B12 = image.select("B12")

    def _ratio(b_hi, b_lo, name):
        return b_hi.subtract(b_lo).divide(b_hi.add(b_lo).add(1e-6)).rename(name)

    # Vegetation / chlorophyll indices
    ndvi     = _ratio(B8,  B4,  "NDVI")
    gndvi    = _ratio(B8,  B3,  "GNDVI")
    ndre     = _ratio(B8,  B5,  "NDRE")
    ndre740  = _ratio(B8,  B6,  "NDRE740")
    mtci     = B8A.subtract(B5).divide(B5.subtract(B4).add(1e-6)).rename("MTCI")

    # Water / moisture indices
    ndmi     = _ratio(B8,  B11, "NDMI")
    ndwi_gg  = _ratio(B8,  B11, "NDWI_Gao")
    siwsi1   = _ratio(B8,  B11, "SIWSI1")
    siwsi2   = _ratio(B8A, B11, "SIWSI2")
    srwi     = B8.divide(B11.add(1e-6)).rename("SRWI")

    # NMDI – نفس معادلة النوتبوك (B8 - (B11 - B12)) / (B8 + (B11 - B12))
    nmdi = (
        B8.subtract(B11.subtract(B12))
          .divide(B8.add(B11.subtract(B12)).add(1e-6))
          .rename("NMDI")
    )

    indices_img = (ndvi
                   .addBands(gndvi)
                   .addBands(ndre)
                   .addBands(ndre740)
                   .addBands(mtci)
                   .addBands(ndmi)
                   .addBands(ndwi_gg)
                   .addBands(siwsi1)
                   .addBands(siwsi2)
                   .addBands(srwi)
                   .addBands(nmdi))

    coords_img = ee.Image.pixelCoordinates(B8.projection()).select(["x", "y"])
    full_img = indices_img.addBands(coords_img)

    fc = full_img.sample(
        region=geom,
        scale=RESOLUTION,
        geometries=False,
        seed=42,
    )

    try:
        df = geemap.ee_to_df(fc)
    except Exception:
        return None

    if df.empty:
        return None

    df["site"] = site_name
    df["date"] = pd.to_datetime(wstart).normalize()
    return df

# =========================
# ميّزات زمنية (K-scores, slopes, drops, history)
# =========================

def add_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    نفس دالة add_features في النوتبوك تقريبًا، مع:
      - seasonal mean per month
      - rolling std
      - K-scores
      - slopes
      - baseline q80
      - drop_frac + drop_3w
      - history_weeks لكل بكسل (يستخدم لاحقًا للفلترة)
    """
    if df.empty:
        return df

    df = df.sort_values(["site", "x", "y", "date"]).copy()
    df["weekofyear"] = df["date"].dt.isocalendar().week.astype(int)
    df["month"] = df["date"].dt.month

    core_indices = ["NDVI", "NDRE", "NDMI", "SIWSI1"]

    # متوسط موسمي لكل شهر وبكسل
    g_pixel_month = df.groupby(["site", "x", "y", "month"])
    for col in core_indices:
        if col in df.columns:
            df[f"{col}_season_mean"] = g_pixel_month[col].transform("mean")

    g_pixel = df.groupby(["site", "x", "y"])

    def _roll_std(s, w=8):
        return s.rolling(w, min_periods=4).std()

    for col in core_indices:
        if col in df.columns:
            df[f"{col}_std8"] = g_pixel[col].transform(_roll_std)

    # K-score مع fallback
    for col in core_indices:
        if col in df.columns:
            value = df[col].astype(float)
            base_col = f"{col}_season_mean"
            if base_col in df.columns:
                base = df[base_col].astype(float)
            else:
                base = value.copy()

            base_safe = base.where(np.isfinite(base), value)
            std_col = f"{col}_std8"
            if std_col in df.columns:
                std = df[std_col].astype(float)
            else:
                std = pd.Series(np.nan, index=df.index)
            std_safe = std.where(np.isfinite(std) & (std > 1e-6), np.nan)

            k_raw = (value - base_safe) / std_safe
            k = k_raw.copy()

            no_ref = ~np.isfinite(std_safe) | ~np.isfinite(base_safe)
            k[no_ref & np.isfinite(value)] = 0.0
            k[~np.isfinite(value)] = np.nan

            df[f"k_{col}"] = k

    # slopes لـ NDVI و NDMI
    def slope_s_np(x, w=8):
        res = np.full_like(x, np.nan, dtype=float)
        t = np.arange(w)
        for i in range(w - 1, len(x)):
            y_window = x[i - w + 1 : i + 1]
            ok = np.isfinite(y_window)
            if ok.sum() >= max(4, w // 2):
                y_temp = y_window.copy()
                m = np.nanmean(y_temp[ok])
                y_temp[~ok] = m
                cov = np.cov(t, y_temp, ddof=0)[0, 1]
                var_t = np.var(t)
                res[i] = cov / (var_t + 1e-6)
        return res

    for col in ["NDVI", "NDMI"]:
        if col in df.columns:
            df[f"slope8_{col}"] = g_pixel[col].transform(
                lambda s: pd.Series(slope_s_np(s.values, 8), index=s.index)
            )

    # baseline (q80) لكل بكسل
    def _q80(s):
        arr = s.values.astype(float)
        valid = np.isfinite(arr)
        if valid.sum() < 4:
            return np.nan
        return np.nanquantile(arr[valid], 0.8)

    for col in core_indices:
        if col in df.columns:
            df[f"{col}_base"] = g_pixel[col].transform(_q80)

    # نسب الانخفاض عن baseline
    for col in ["NDVI", "NDMI", "SIWSI1"]:
        base_col = f"{col}_base"
        if col in df.columns and base_col in df.columns:
            b = df[base_col]
            df[f"{col}_drop_frac"] = (b - df[col]) / (b + 1e-9)

    # متوسط الانخفاض آخر 3 أسابيع
    if "NDVI_drop_frac" in df.columns:
        df["NDVI_drop_3w"] = g_pixel["NDVI_drop_frac"].transform(
            lambda s: s.rolling(3, min_periods=2).mean()
        )
    else:
        df["NDVI_drop_3w"] = np.nan

    if "NDMI_drop_frac" in df.columns:
        df["NDMI_drop_3w"] = g_pixel["NDMI_drop_frac"].transform(
            lambda s: s.rolling(3, min_periods=2).mean()
        )
    else:
        df["NDMI_drop_3w"] = np.nan

    # history_weeks: كم أسبوع عند هذا البكسل فيه أي مؤشر مش NaN
    cnt_weeks = (
        df[INDEX_COLS_ALL].notna().any(axis=1)
    ).groupby([df["site"], df["x"], df["y"]]).sum()
    history_df = cnt_weeks.rename("history_weeks").reset_index()
    df = df.merge(history_df, on=["site", "x", "y"], how="left")

    return df

# =========================
# Isolation Forest risk (inference فقط)
# =========================
def compute_if_risk_inference(all_df: pd.DataFrame) -> pd.DataFrame:
    """
    نفس الميزات المستخدمة في التدريب:
      NDVI, NDRE, NDMI, NMDI, NDWI_Gao, SIWSI1,
      k_NDVI, k_NDMI, k_SIWSI1, slope8_NDVI, slope8_NDMI

    مع تعبئة NaN بمتوسطات *التدريب* المخزّنة في if_feature_means.joblib
    وليس من بيانات المزرعة الجديدة، للحفاظ على نفس الـ baseline.
    """
    feats = [
        "NDVI", "NDRE", "NDMI", "NMDI", "NDWI_Gao", "SIWSI1",
        "k_NDVI", "k_NDMI", "k_SIWSI1", "slope8_NDVI", "slope8_NDMI",
    ]
    feats = [f for f in feats if f in all_df.columns]

    all_df = all_df.copy()
    all_df["IF_score"] = np.nan

    if all_df.empty or not feats:
        return all_df

    X = all_df[feats].replace([np.inf, -np.inf], np.nan)

    # نحاول نقرأ متوسطات التدريب من الملف
    try:
        training_means = get_if_feature_means()  # dict: col -> mean
    except Exception:
        training_means = {}

    # نحدد الأعمدة اللي فيها أي قيمة
    col_means_data = X.mean(skipna=True)
    valid_cols = col_means_data[col_means_data.notna()].index.tolist()
    if not valid_cols:
        # حتى لو ما فيه mean من الداتا، ممكن يكون عندنا means من الملف
        # نستخدم الأعمدة الموجودة في X والمتاحة في training_means
        fallback_cols = [c for c in X.columns if c in training_means]
        if not fallback_cols:
            return all_df
        valid_cols = fallback_cols

    # نبني Series للـ means بالترتيب:
    # 1) من training_means لو موجود
    # 2) وإلا من mean داتا المزرعة
    means_dict: Dict[str, float] = {}
    for col in valid_cols:
        if col in training_means:
            means_dict[col] = float(training_means[col])
        else:
            means_dict[col] = float(col_means_data.get(col, np.nan))

    col_means = pd.Series(means_dict)
    X = X[valid_cols]
    X_filled = X.fillna(col_means)

    # ===== DEBUG لطباعة شكل الداتا الداخلة للمودل =====
    print("\n====== DEBUG IF INPUT ======")
    print("Valid feature columns:", valid_cols)
    print("Shape before fill:", X.shape)
    print("Sample before fill:\n", X.head(5))
    print("\nMeans used for fill:\n", col_means)
    print("\nSample AFTER fill:\n", X_filled.head(5))
    print("Describe AFTER fill:\n", X_filled.describe())
    print("====== END DEBUG ======\n")
    # ================================================

    try:
        IF_model = get_if_model()
    except Exception as e:
        raise RuntimeError(
            f"فشل تحميل نموذج Isolation Forest من GCS.\n"
            f"IF_MODEL_GS_URI = {IF_MODEL_GS_URI!r}\n"
            f"السبب الأصلي: {type(e).__name__}: {e}"
        ) from e


    # نحسب الـ risk لكل site
    for site, sdf in all_df.groupby("site"):
        X_site = sdf[valid_cols].replace([np.inf, -np.inf], np.nan).fillna(col_means)
        try:
            scores = IF_model.decision_function(X_site.values)
        except Exception:
            continue
        smin, smax = scores.min(), scores.max()
        risk = 1.0 - ((scores - smin) / (smax - 1e-6 - smin))
        all_df.loc[sdf.index, "IF_score"] = risk

    return all_df

# =========================
# RPW_score + تصنيف البكسلات (نفس النوتبوك)
# =========================

def add_rpw_flags_and_score(
    df: pd.DataFrame,
    ndre_low_q: float = 0.25,
    ndwi_low_q: float = 0.25,
    rpw_monitor_q: float = 0.80,
    rpw_critical_q: float = 0.95,
    if_risk_q: float = 0.90,
) -> pd.DataFrame:
    """
    نفس منطق add_rpw_flags_and_score في النوتبوك:
      - flags مبنية على NDVI/NDRE/NDWI drops + absolute thresholds
      - water/vigour/thermal components
      - RPW_score ∈ [0,1]
      - quantile thresholds للـ monitor/critical
      - دمج baseline rules + RPW + IF
    """
    if df.empty:
        df = df.copy()
        df["RPW_score"] = np.nan
        df["pixel_risk_class"] = "Healthy"
        df["RPW_label_rule"] = "Healthy"
        return df

    df = df.sort_values(["site", "x", "y", "date"]).copy()

    # 1) data-driven flags لـ NDRE/NDWI
    if "NDRE" in df.columns:
        ndre_thr = df["NDRE"].quantile(ndre_low_q)
        df["flag_NDRE_low"] = df["NDRE"] < ndre_thr
    else:
        df["flag_NDRE_low"] = False

    if "NDWI_Gao" in df.columns:
        ndwi_thr = df["NDWI_Gao"].quantile(ndwi_low_q)
        df["flag_NDWI_low"] = df["NDWI_Gao"] < ndwi_thr
    else:
        df["flag_NDWI_low"] = False

    # 1-b) قواعد ثابتة من المراجع (NDVI/NDRE/NDWI)
    if "NDVI" in df.columns:
        df["flag_NDVI_below_030"] = df["NDVI"] < 0.30
    else:
        df["flag_NDVI_below_030"] = False

    if "NDRE" in df.columns:
        df["flag_NDRE_below_035"] = df["NDRE"] < 0.35
    else:
        df["flag_NDRE_below_035"] = False

    if "NDWI_Gao" in df.columns:
        df["flag_NDWI_below_025"] = df["NDWI_Gao"] < 0.25
    else:
        df["flag_NDWI_below_025"] = False

    def rolling_median(s):
        return s.rolling(8, min_periods=4).median()

    g = df.groupby(["site", "x", "y"])

    base_SI = g["SIWSI1"].transform(rolling_median) if "SIWSI1" in df.columns else pd.Series(np.nan, index=df.index)
    base_WI = g["NDWI_Gao"].transform(rolling_median) if "NDWI_Gao" in df.columns else pd.Series(np.nan, index=df.index)
    base_NV = g["NDVI"].transform(rolling_median) if "NDVI" in df.columns else pd.Series(np.nan, index=df.index)

    if "SIWSI1" in df.columns:
        df["flag_drop_SIWSI10pct"] = ((base_SI - df["SIWSI1"]) / (base_SI + 1e-9)) >= 0.10
    else:
        df["flag_drop_SIWSI10pct"] = False

    if "NDWI_Gao" in df.columns:
        df["flag_drop_NDWI10pct"] = ((base_WI - df["NDWI_Gao"]) / (base_WI + 1e-9)) >= 0.10
    else:
        df["flag_drop_NDWI10pct"] = False

    if "NDVI" in df.columns:
        df["flag_drop_NDVI005"] = (base_NV - df["NDVI"]) >= 0.05
    else:
        df["flag_drop_NDVI005"] = False

    # 2) مكونات RPW (ماء + كلوروفيل + حرارة)
    def minmax(s):
        s = s.astype(float)
        valid = np.isfinite(s)
        if not valid.any():
            return pd.Series(np.nan, index=s.index)
        lo, hi = np.nanpercentile(s[valid], 5), np.nanpercentile(s[valid], 95)
        return (s - lo) / (hi - lo + 1e-9)

    # water component
    if "NDMI_drop_frac" in df.columns:
        ndmi_drop_norm = minmax(df["NDMI_drop_frac"].fillna(0.0))
    else:
        ndmi_drop_norm = pd.Series(0.0, index=df.index)

    water_components = pd.concat([
        df["flag_drop_SIWSI10pct"].astype(float),
        df["flag_drop_NDWI10pct"].astype(float),
        df["flag_NDWI_low"].astype(float),
        df["flag_NDWI_below_025"].astype(float),
        ndmi_drop_norm,
    ], axis=1)
    water = water_components.mean(axis=1)

    # vigour component
    if "NDVI_drop_frac" in df.columns:
        ndvi_drop_norm = minmax(df["NDVI_drop_frac"].fillna(0.0))
    else:
        ndvi_drop_norm = pd.Series(0.0, index=df.index)

    if "NDRE" in df.columns:
        ndre_low_norm = minmax(-df["NDRE"].fillna(df["NDRE"].median()))
    else:
        ndre_low_norm = pd.Series(0.0, index=df.index)

    if "MTCI" in df.columns:
        mtci_norm = minmax(-df["MTCI"].fillna(df["MTCI"].median()))
    else:
        mtci_norm = pd.Series(0.0, index=df.index)

    if "NDVI" in df.columns:
        flag_ndvi_abs_low = df["flag_NDVI_below_030"]
    else:
        flag_ndvi_abs_low = pd.Series(False, index=df.index)

    vigour_components = pd.concat([
        df["flag_drop_NDVI005"].astype(float),
        flag_ndvi_abs_low.astype(float),
        ndvi_drop_norm,
        ndre_low_norm,
        df["flag_NDRE_below_035"].astype(float),
        mtci_norm,
    ], axis=1)
    vigour = vigour_components.mean(axis=1)

    # thermal component
    if "canopy_temp" in df.columns:
        thermal = minmax(df["canopy_temp"])
    elif "lst_canopy_C" in df.columns:
        thermal = minmax(df["lst_canopy_C"])
    else:
        thermal = pd.Series(0.0, index=df.index)

    df["RPW_score"] = (0.5 * water + 0.4 * vigour + 0.1 * thermal).clip(0, 1)

    # Isolation Forest
    if "IF_score" not in df.columns:
        df["IF_score"] = 0.0
    df["IF_score"] = df["IF_score"].fillna(0.0)

    # thresholds
    rpw_valid = df["RPW_score"].replace([np.inf, -np.inf], np.nan).dropna()
    if rpw_valid.empty:
        df["pixel_risk_class"] = "Healthy"
        df["RPW_label_rule"] = "Healthy"
        return df

    # ✨ هنا التعديل الأساسي:
    # إذا توزيع RPW_score تقريباً ثابت (spread صغير) نتجاهل tails
    rpw_min, rpw_max = rpw_valid.min(), rpw_valid.max()
    spread = rpw_max - rpw_min if np.isfinite(rpw_min) and np.isfinite(rpw_max) else np.nan
    use_rpw_quantiles = bool(np.isfinite(spread) and (spread >= 5e-4))


    if use_rpw_quantiles:
        rpw_mon_thr = rpw_valid.quantile(rpw_monitor_q)
        rpw_crit_thr = rpw_valid.quantile(rpw_critical_q)
    else:
        # ما نستخدم RPW tail لو كله تقريباً نفس القيمة
        rpw_mon_thr = np.inf
        rpw_crit_thr = np.inf

        # IF thresholds
    if_valid = df["IF_score"].replace([np.inf, -np.inf], np.nan).dropna()
    if if_valid.empty:
        # ما فيه IF مفيد → تجاهله
        if_thr = np.inf
    else:
        if_min, if_max = if_valid.min(), if_valid.max()
        spread_if = if_max - if_min if np.isfinite(if_min) and np.isfinite(if_max) else np.nan

        # إذا توزيع IF_score تقريبًا ثابت (spread صغير جدًا) نعتبره غير مفيد
        if not (np.isfinite(spread_if) and (spread_if >= 5e-4)):
            # تعطيل IF في التصنيف (ما يدخل لا Monitor ولا Critical)
            if_thr = np.inf
        else:
            if_thr = if_valid.quantile(if_risk_q)


    # baseline / RPW / IF masks
    ndvi_drop_frac = df.get("NDVI_drop_frac", pd.Series(0.0, index=df.index)).fillna(0.0)
    ndvi_drop_3w   = df.get("NDVI_drop_3w",   pd.Series(0.0, index=df.index)).fillna(0.0)
    ndmi_drop_frac = df.get("NDMI_drop_frac", pd.Series(0.0, index=df.index)).fillna(0.0)

    m_crit_baseline = (
        (ndvi_drop_3w >= 0.40) |
        ((ndvi_drop_frac >= 0.50) & (ndmi_drop_frac >= 0.30))
    )

    m_crit_rpw = df["RPW_score"] >= rpw_crit_thr
    m_crit_if = np.isfinite(if_thr) & (df["IF_score"] >= if_thr) & (df["RPW_score"] >= rpw_mon_thr)

    m_mon_baseline = (
        (~m_crit_baseline) &
        (ndvi_drop_3w >= 0.20) &
        (ndvi_drop_frac >= 0.20)
    )

    m_mon_rpw = (
        ~(m_crit_baseline | m_crit_rpw | m_crit_if) &
        (df["RPW_score"] >= rpw_mon_thr)
    )

    m_mon_if = (
        np.isfinite(if_thr) &
        ~(m_crit_baseline | m_crit_rpw | m_crit_if | m_mon_rpw | m_mon_baseline) &
        (df["IF_score"] >= if_thr)
    )

    # default
    df["pixel_risk_class"] = "Healthy"
    df["RPW_label_rule"] = "Healthy"

    # Monitor rules
    df.loc[m_mon_baseline, "pixel_risk_class"] = "Monitor"
    df.loc[m_mon_baseline, "RPW_label_rule"] = "Monitor_baseline_drop"

    df.loc[m_mon_rpw, "pixel_risk_class"] = "Monitor"
    df.loc[m_mon_rpw, "RPW_label_rule"] = "Monitor_RPW_tail"

    df.loc[m_mon_if, "pixel_risk_class"] = "Monitor"
    df.loc[m_mon_if, "RPW_label_rule"] = "Monitor_IF_outlier"

    # Critical rules
    df.loc[m_crit_baseline, "pixel_risk_class"] = "Critical"
    df.loc[m_crit_baseline, "RPW_label_rule"] = "Critical_baseline_drop"

    df.loc[m_crit_rpw, "pixel_risk_class"] = "Critical"
    df.loc[m_crit_rpw, "RPW_label_rule"] = "Critical_RPW_tail"

    df.loc[m_crit_if, "pixel_risk_class"] = "Critical"
    df.loc[m_crit_if, "RPW_label_rule"] = "Critical_IF_outlier"

    return df

# =========================
# تجميع site-level summary (نفس منطق النوتبوك تقريبًا)
# =========================

def site_summary(dfx: pd.DataFrame) -> Dict[str, Any]:
    """
    ملخص للمزرعة:
      - يحسب النسب للأسبوع الأخير فقط (Healthy/Monitor/Critical)
      - RPW_score median لآخر 4 أسابيع
      - إجمالي المطر ومتوسط الحرارة في آخر 4 أسابيع
    نفس فكرة النوتبوك.
    """
    dfx = dfx.copy()
    if dfx.empty:
        return {
            "Total_Pixels_Count": 0,
            "Healthy_Pct": 0.0,
            "Monitor_Pct": 0.0,
            "Critical_Pct": 0.0,
            "RPW_score_med": 0.0,
            "rain_mm": 0.0,
            "t_mean": 0.0,
        }

    if "date" in dfx.columns:
        dfx["date"] = pd.to_datetime(dfx["date"]).dt.normalize()
        latest_date = dfx["date"].max()
        recent_data = dfx[dfx["date"] == latest_date]
        dfx_last4 = dfx[dfx["date"] >= latest_date - pd.Timedelta(weeks=4)]
    else:
        recent_data = dfx
        dfx_last4 = dfx

    total_pixels = recent_data.shape[0]
    if "pixel_risk_class" in recent_data.columns:
        class_counts = recent_data["pixel_risk_class"].value_counts(normalize=True) * 100.0
    else:
        class_counts = {}

    return {
        "Total_Pixels_Count": int(total_pixels),
        "Healthy_Pct": float(class_counts.get("Healthy", 0.0)),
        "Monitor_Pct": float(class_counts.get("Monitor", 0.0)),
        "Critical_Pct": float(class_counts.get("Critical", 0.0)),
        "RPW_score_med": float(dfx_last4.get("RPW_score", pd.Series([np.nan])).median()),
        "rain_mm": float(dfx_last4.get("precip_mm", pd.Series([0.0])).sum()),
        "t_mean": float(dfx_last4.get("t2m_mean", pd.Series([np.nan])).mean()),
    }

# =========================
# الدالة الرئيسية: تحليل صحة مزرعة واحدة
# =========================
def analyze_farm_health(farm_id: str, farm_doc: Dict[str, Any]) -> Dict[str, Any]:
    """
    يأخذ مستند مزرعة من Firestore:
      farm_doc["polygon"] = [{'lat':..,'lng':..}, ...]
    ويرجع ملخصًا لنسب الصحة (Healthy/Monitor/Critical) بناءً على:
      - Sentinel-2 مؤشرات أسبوعية
      - Landsat LST (حرارة المظلة)
      - طقس أسبوعي من Open-Meteo
      - ميزات زمنية (K-score, slopes, baseline, drops)
      - Isolation Forest (نموذج مدرب مسبقًا)
      - RPW_score (water + vigour + thermal)
    """
    poly = farm_doc.get("polygon") or []
    if len(poly) < 3:
        raise ValueError("Farm polygon is missing or < 3 points")

    coords = [(p["lng"], p["lat"]) for p in poly]
    site = {"name": farm_id, "polygon": coords}

    # 1) Sentinel-2 + LST أسبوعية من GEE
    weekly_series: List[pd.DataFrame] = []
    thermal_rows: List[Dict[str, Any]] = []

    for wstart, wend in week_bins(DATE_FROM, DATE_TO):
        s2 = s2_week_pixels_gee(site, wstart, wend)
        if s2 is not None and not s2.empty:
            weekly_series.append(s2)

        d_from = (wstart - pd.Timedelta(days=6))
        d_to   = (wend   + pd.Timedelta(days=6))
        lst_c = load_week_LST_Landsat_GEE(site, d_from, d_to)
        thermal_rows.append(
            {"site": farm_id, "date": pd.to_datetime(wstart).normalize(), "canopy_temp": lst_c}
        )

    if weekly_series:
        df_s2 = pd.concat(weekly_series, ignore_index=True)
    else:
        df_s2 = pd.DataFrame(
            columns=[
                "site", "date", "x", "y",
                "NDVI", "GNDVI", "NDRE", "NDRE740", "MTCI", "NDMI",
                "NDWI_Gao", "SIWSI1", "SIWSI2", "SRWI", "NMDI",
            ]
        )

    df_th = pd.DataFrame(thermal_rows)
    df_th["date"] = pd.to_datetime(df_th["date"]).dt.normalize()

    wx = weekly_weather(site)
    wx["site"] = farm_id

    df_all = (
        df_s2.merge(wx, on=["site", "date"], how="left")
             .merge(df_th, on=["site", "date"], how="left")
    )

    if df_all.empty:
        raise RuntimeError(
            "لم يتمكن النظام من جلب أي بكسلات Sentinel-2 لهذه المزرعة في الفترة المحددة"
        )

    df_all["date"] = pd.to_datetime(df_all["date"]).dt.normalize()

    # 2) ميزات زمنية كاملة (K, slopes, baseline, drops, history_weeks)
    df_all = add_features(df_all)

    # فلترة الصفوف التي لا تحتوي أي مؤشر
    df_all = df_all.dropna(subset=INDEX_COLS_ALL, how="all").copy()

    # فلترة البكسلات ذات التاريخ الكافي (≥ 6 أسابيع) – نفس النوتبوك
    if "history_weeks" in df_all.columns:
        df_all = df_all[df_all["history_weeks"] >= 6].reset_index(drop=True)

    if df_all.empty:
        raise RuntimeError(
            "كل البكسلات المتاحة أقل من 6 أسابيع تاريخ أو لا تحتوي مؤشرات كافية بعد الفلترة"
        )

    # 3) Isolation Forest (inference فقط) مع تعبئة NaN بمتوسطات التدريب
    df_all = compute_if_risk_inference(df_all)

        # 4) RPW_score + تصنيف البكسلات (نفس منطق النوتبوك)
    df_all = add_rpw_flags_and_score(df_all)

    # 5) ملخص المزرعة (آخر أسبوع)
    stats = site_summary(df_all)

    # 👈 نخزن فقط النِسَب الثلاثة
    health_summary = {
        "Healthy_Pct": float(stats.get("Healthy_Pct", 0.0)),
        "Monitor_Pct": float(stats.get("Monitor_Pct", 0.0)),
        "Critical_Pct": float(stats.get("Critical_Pct", 0.0)),
    }

    return health_summary

