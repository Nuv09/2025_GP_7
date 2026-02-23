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



PROJECT_ID = os.environ.get("GEE_PROJECT_ID", "saaf-97251")
OUT_ROOT = os.environ.get("HEALTH_OUT_ROOT", "/tmp/saaf_health")
os.makedirs(OUT_ROOT, exist_ok=True)

TODAY = pd.Timestamp.utcnow().normalize()
DATE_TO = TODAY
DATE_FROM = TODAY - pd.Timedelta(weeks=52)

S2_COLLECTION = "COPERNICUS/S2_SR_HARMONIZED"
MAX_CLOUD = 40          
RESOLUTION = 10         

IF_MODEL_GS_URI = os.environ.get("IF_MODEL_GS_URI", "")

IF_MEANS_GS_URI = os.environ.get("IF_MEANS_GS_URI", "")

FORECAST_MODEL_GS_URI = os.environ.get("FORECAST_MODEL_GS_URI", "")


INDEX_COLS_ALL = [
    "NDVI", "GNDVI", "NDRE", "NDRE740", "MTCI",
    "NDMI", "NDWI_Gao", "SIWSI1", "SIWSI2", "SRWI", "NMDI",
]



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

    fd, tmp_path = tempfile.mkstemp(suffix=suffix, dir=OUT_ROOT)
    os.close(fd)
    blob.download_to_filename(tmp_path)
    return tmp_path


_IF_MODEL = None
_IF_FEATURE_MEANS = None  
_FORECAST_MODEL = None


def get_if_model():
    
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
  
    global _IF_FEATURE_MEANS
    if _IF_FEATURE_MEANS is not None:
        return _IF_FEATURE_MEANS

    if not IF_MEANS_GS_URI:
        raise RuntimeError("IF_MEANS_GS_URI غير مضبوط في متغيرات البيئة")

    local_path = _download_gcs_file(IF_MEANS_GS_URI, suffix=".joblib")
    obj = joblib.load(local_path)

    if isinstance(obj, dict):
        _IF_FEATURE_MEANS = {str(k): float(v) for k, v in obj.items()}
    else:
        raise TypeError(
            f"if_feature_means.joblib المتوقع يكون dict، لكن النوع الفعلي: {type(obj)}"
        )

    return _IF_FEATURE_MEANS


def get_forecast_model():
    global _FORECAST_MODEL
    if _FORECAST_MODEL is not None:
        return _FORECAST_MODEL

    if not FORECAST_MODEL_GS_URI:
        raise RuntimeError("FORECAST_MODEL_GS_URI غير مضبوط في متغيرات البيئة")

    try:
        print(f"[FCST] Downloading forecast model from GCS: {FORECAST_MODEL_GS_URI}")
        local_path = _download_gcs_file(FORECAST_MODEL_GS_URI, suffix=".joblib")
        print(f"[FCST] Forecast model file downloaded to: {local_path}")
        _FORECAST_MODEL = joblib.load(local_path)
        print(f"[FCST] Loaded forecast model OK, type={type(_FORECAST_MODEL)}")
    except Exception as e:
        print(f"[FCST] ERROR loading forecast model: {e}")
        raise

    return _FORECAST_MODEL

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



def _es_kPa(Tc):
    return 0.6108 * np.exp((17.27 * Tc) / (Tc + 237.3))

@memory.cache
def _weather_open_meteo(lat: float, lon: float, start_date, end_date):
  
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
 
    coords = site["polygon"]
    poly_for_centroid = [{"lat": lat, "lng": lon} for (lon, lat) in coords]
    lat, lon = polygon_centroid(poly_for_centroid)
    weeks = week_bins(DATE_FROM, DATE_TO)

    om = _weather_open_meteo(lat, lon, DATE_FROM, DATE_TO)
    if om is not None and not om.empty:
        return om

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



def load_week_LST_Landsat_GEE(site: Dict[str, Any], d_from, d_to) -> float:
   
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




def s2_week_pixels_gee(site: Dict[str, Any], wstart: pd.Timestamp, wend: pd.Timestamp) -> pd.DataFrame | None:
  
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

    ndvi     = _ratio(B8,  B4,  "NDVI")
    gndvi    = _ratio(B8,  B3,  "GNDVI")
    ndre     = _ratio(B8,  B5,  "NDRE")
    ndre740  = _ratio(B8,  B6,  "NDRE740")
    mtci     = B8A.subtract(B5).divide(B5.subtract(B4).add(1e-6)).rename("MTCI")

    ndmi     = _ratio(B8,  B11, "NDMI")
    ndwi_gg  = _ratio(B8,  B11, "NDWI_Gao")
    siwsi1   = _ratio(B8,  B11, "SIWSI1")
    siwsi2   = _ratio(B8A, B11, "SIWSI2")
    srwi     = B8.divide(B11.add(1e-6)).rename("SRWI")

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

    # جلب الإحداثيات الجغرافية
    lonlat = ee.Image.pixelLonLat()
    
    # السر هنا: نعيد تسمية longitude إلى x و latitude إلى y
    # لكي لا يشعر باقي الكود بأي تغيير ويستمر في الحسابات بشكل سليم
    coords_img = lonlat.select(['longitude', 'latitude'], ['x', 'y'])
    
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



def add_features(df: pd.DataFrame) -> pd.DataFrame:
  
    if df.empty:
        return df

    df = df.sort_values(["site", "x", "y", "date"]).copy()
    df["weekofyear"] = df["date"].dt.isocalendar().week.astype(int)
    df["month"] = df["date"].dt.month

    core_indices = ["NDVI", "NDRE", "NDMI", "SIWSI1"]

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

    def _q80(s):
        arr = s.values.astype(float)
        valid = np.isfinite(arr)
        if valid.sum() < 4:
            return np.nan
        return np.nanquantile(arr[valid], 0.8)

    for col in core_indices:
        if col in df.columns:
            df[f"{col}_base"] = g_pixel[col].transform(_q80)

    for col in ["NDVI", "NDMI", "SIWSI1"]:
        base_col = f"{col}_base"
        if col in df.columns and base_col in df.columns:
            b = df[base_col]
            df[f"{col}_drop_frac"] = (b - df[col]) / (b + 1e-9)

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

    cnt_weeks = (
        df[INDEX_COLS_ALL].notna().any(axis=1)
    ).groupby([df["site"], df["x"], df["y"]]).sum()
    history_df = cnt_weeks.rename("history_weeks").reset_index()
    df = df.merge(history_df, on=["site", "x", "y"], how="left")

    return df


def compute_if_risk_inference(all_df: pd.DataFrame) -> pd.DataFrame:
   
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

    try:
        training_means = get_if_feature_means()  
    except Exception:
        training_means = {}

    col_means_data = X.mean(skipna=True)
    valid_cols = col_means_data[col_means_data.notna()].index.tolist()
    if not valid_cols:
        
        fallback_cols = [c for c in X.columns if c in training_means]
        if not fallback_cols:
            return all_df
        valid_cols = fallback_cols

    
    means_dict: Dict[str, float] = {}
    for col in valid_cols:
        if col in training_means:
            means_dict[col] = float(training_means[col])
        else:
            means_dict[col] = float(col_means_data.get(col, np.nan))

    col_means = pd.Series(means_dict)
    X = X[valid_cols]
    X_filled = X.fillna(col_means)

    print("\n====== DEBUG IF INPUT ======")
    print("Valid feature columns:", valid_cols)
    print("Shape before fill:", X.shape)
    print("Sample before fill:\n", X.head(5))
    print("\nMeans used for fill:\n", col_means)
    print("\nSample AFTER fill:\n", X_filled.head(5))
    print("Describe AFTER fill:\n", X_filled.describe())
    print("====== END DEBUG ======\n")

    try:
        IF_model = get_if_model()
    except Exception as e:
        raise RuntimeError(
            f"فشل تحميل نموذج Isolation Forest من GCS.\n"
            f"IF_MODEL_GS_URI = {IF_MODEL_GS_URI!r}\n"
            f"السبب الأصلي: {type(e).__name__}: {e}"
        ) from e


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



def add_rpw_flags_and_score(
    df: pd.DataFrame,
    ndre_low_q: float = 0.25,
    ndwi_low_q: float = 0.25,
    rpw_monitor_q: float = 0.80,
    rpw_critical_q: float = 0.95,
    if_risk_q: float = 0.90,
) -> pd.DataFrame:
  
    if df.empty:
        df = df.copy()
        df["RPW_score"] = np.nan
        df["pixel_risk_class"] = "Healthy"
        df["RPW_label_rule"] = "Healthy"
        return df

    df = df.sort_values(["site", "x", "y", "date"]).copy()

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

    def minmax(s):
        s = s.astype(float)
        valid = np.isfinite(s)
        if not valid.any():
            return pd.Series(np.nan, index=s.index)
        lo, hi = np.nanpercentile(s[valid], 5), np.nanpercentile(s[valid], 95)
        return (s - lo) / (hi - lo + 1e-9)

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

    if "canopy_temp" in df.columns:
        thermal = minmax(df["canopy_temp"])
    elif "lst_canopy_C" in df.columns:
        thermal = minmax(df["lst_canopy_C"])
    else:
        thermal = pd.Series(0.0, index=df.index)

    df["RPW_score"] = (0.5 * water + 0.4 * vigour + 0.1 * thermal).clip(0, 1)

    if "IF_score" not in df.columns:
        df["IF_score"] = 0.0
    df["IF_score"] = df["IF_score"].fillna(0.0)

    rpw_valid = df["RPW_score"].replace([np.inf, -np.inf], np.nan).dropna()
    if rpw_valid.empty:
        df["pixel_risk_class"] = "Healthy"
        df["RPW_label_rule"] = "Healthy"
        return df

    
    rpw_min, rpw_max = rpw_valid.min(), rpw_valid.max()
    spread = rpw_max - rpw_min if np.isfinite(rpw_min) and np.isfinite(rpw_max) else np.nan
    use_rpw_quantiles = bool(np.isfinite(spread) and (spread >= 5e-4))


    if use_rpw_quantiles:
        rpw_mon_thr = rpw_valid.quantile(rpw_monitor_q)
        rpw_crit_thr = rpw_valid.quantile(rpw_critical_q)
    else:
        rpw_mon_thr = np.inf
        rpw_crit_thr = np.inf

    if_valid = df["IF_score"].replace([np.inf, -np.inf], np.nan).dropna()
    if if_valid.empty:
        if_thr = np.inf
    else:
        if_min, if_max = if_valid.min(), if_valid.max()
        spread_if = if_max - if_min if np.isfinite(if_min) and np.isfinite(if_max) else np.nan

        if not (np.isfinite(spread_if) and (spread_if >= 5e-4)):
            if_thr = np.inf
        else:
            if_thr = if_valid.quantile(if_risk_q)


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

    df["pixel_risk_class"] = "Healthy"
    df["RPW_label_rule"] = "Healthy"

    df.loc[m_mon_baseline, "pixel_risk_class"] = "Monitor"
    df.loc[m_mon_baseline, "RPW_label_rule"] = "Monitor_baseline_drop"

    df.loc[m_mon_rpw, "pixel_risk_class"] = "Monitor"
    df.loc[m_mon_rpw, "RPW_label_rule"] = "Monitor_RPW_tail"

    df.loc[m_mon_if, "pixel_risk_class"] = "Monitor"
    df.loc[m_mon_if, "RPW_label_rule"] = "Monitor_IF_outlier"

    df.loc[m_crit_baseline, "pixel_risk_class"] = "Critical"
    df.loc[m_crit_baseline, "RPW_label_rule"] = "Critical_baseline_drop"

    df.loc[m_crit_rpw, "pixel_risk_class"] = "Critical"
    df.loc[m_crit_rpw, "RPW_label_rule"] = "Critical_RPW_tail"

    df.loc[m_crit_if, "pixel_risk_class"] = "Critical"
    df.loc[m_crit_if, "RPW_label_rule"] = "Critical_IF_outlier"

    return df



def site_summary(dfx: pd.DataFrame) -> Dict[str, Any]:
   
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

def indices_history_last_weeks(
    df_all: pd.DataFrame,
    weeks: int = 5,
    agg: str = "mean",  # "mean" أو "median"
) -> List[Dict[str, Any]]:
    """
    يرجّع سلسلة زمنية أسبوعية لآخر N أسابيع: NDVI/NDMI/NDRE على مستوى المزرعة.
    """
    if df_all.empty or "date" not in df_all.columns:
        return []

    df = df_all.copy()
    df["date"] = pd.to_datetime(df["date"]).dt.normalize()

    # نجمع على مستوى (site, date) بدل البكسلات
    cols = [c for c in ["NDVI", "NDMI", "NDRE"] if c in df.columns]
    if not cols:
        return []

    if agg == "median":
        g = df.groupby(["site", "date"], as_index=False)[cols].median()
    else:
        g = df.groupby(["site", "date"], as_index=False)[cols].mean()

    g = g.sort_values("date").tail(weeks)

    out: List[Dict[str, Any]] = []
    for _, row in g.iterrows():
        out.append({
            "date": row["date"].date().isoformat(),
            "NDVI": float(row.get("NDVI", np.nan)) if np.isfinite(row.get("NDVI", np.nan)) else None,
            "NDMI": float(row.get("NDMI", np.nan)) if np.isfinite(row.get("NDMI", np.nan)) else None,
            "NDRE": float(row.get("NDRE", np.nan)) if np.isfinite(row.get("NDRE", np.nan)) else None,
        })
    return out


def decode_class_code(code: float) -> str:
    if code < 0.5:
        return "Healthy"
    elif code < 1.5:
        return "Monitor"
    else:
        return "Critical"
FORECAST_FEATURES = [
    "NDVI","GNDVI","NDRE","NDRE740","MTCI","NDMI","NDWI_Gao","SIWSI1","SIWSI2","SRWI","NMDI",
    "k_NDVI","k_NDRE","k_NDMI","k_SIWSI1",
    "slope8_NDVI","slope8_NDMI",
    "NDVI_drop_frac","NDMI_drop_frac","SIWSI1_drop_frac",
    "NDVI_drop_3w","NDMI_drop_3w",
    "weekofyear","month",
    "canopy_temp",
    "precip_mm","t2m_mean","t2m_max","t2m_min","ssrd_MJ","wind10_ms","vpd_kPa","rh2m_mean",
    "RPW_score","IF_score",
]


#healthmap predection points (توقعات حالة البكسلات للأسبوع القادم) - نفس تنسيق نقاط الخريطة العادية لكن مع حالة التوقع وليس الحالة الحالية
def get_forecast_lookup(latest_last: pd.DataFrame) -> Dict[str, int]:
    if latest_last is None or latest_last.empty:
        return {}

    lookup = {}
    for _, row in latest_last.iterrows():
        code = row.get('pred_class_code_next', 0)
        status_code = 0
        if code >= 1.5: status_code = 2
        elif code >= 0.5: status_code = 1
            
        # المفتاح lat_lng
        key = f"{round(float(row['y']), 6)}_{round(float(row['x']), 6)}"
        lookup[key] = status_code
    return lookup


    

def forecast_next_week_summary(df_all: pd.DataFrame) -> Dict[str, Any]:
    if df_all.empty:
        return {
            "Healthy_Pct_next": 0.0,
            "Monitor_Pct_next": 0.0,
            "Critical_Pct_next": 0.0,
            "ndvi_delta_next_mean": 0.0,
            "ndmi_delta_next_mean": 0.0,
        }

    model = get_forecast_model()

    latest_last = (
        df_all.sort_values(["site", "x", "y", "date"])
             .groupby(["site", "x", "y"], as_index=False)
             .tail(1)
             .copy()
    )

    for c in FORECAST_FEATURES:
        if c not in latest_last.columns:
            latest_last[c] = np.nan

    X = latest_last[FORECAST_FEATURES].replace([np.inf, -np.inf], np.nan)


    preds = model.predict(X)
    if preds is None or len(preds) != len(latest_last) or preds.shape[1] != 3:
        raise RuntimeError(f"شكل مخرجات مودل التوقعات غير متوقع: {getattr(preds, 'shape', None)}")

    latest_last["pred_class_code_next"] = preds[:, 0]
    latest_last["pred_ndvi_delta_next"] = preds[:, 1]
    latest_last["pred_ndmi_delta_next"] = preds[:, 2]
    latest_last["pred_class_next"] = latest_last["pred_class_code_next"].apply(decode_class_code)

    # ✅ FIX: avoid "cannot insert site, already exists"
    counts = latest_last.groupby(["site", "pred_class_next"]).size()
    pct = (counts / counts.groupby(level=0).transform("sum")) * 100.0

    farm_pivot = (
        pct.rename("pct")
           .reset_index()
           .pivot_table(index="site", columns="pred_class_next", values="pct", fill_value=0.0)
           .reset_index()
           .rename(columns={
               "Healthy": "Healthy_Pct_next",
               "Monitor": "Monitor_Pct_next",
               "Critical": "Critical_Pct_next",
           })
    )



    delta_agg = latest_last.groupby("site").agg(
        ndvi_delta_next_mean=("pred_ndvi_delta_next", "mean"),
        ndmi_delta_next_mean=("pred_ndmi_delta_next", "mean"),
    ).reset_index()

    out = farm_pivot.merge(delta_agg, on="site", how="left")

    if out.empty:
        return {
            "Healthy_Pct_next": 0.0,
            "Monitor_Pct_next": 0.0,
            "Critical_Pct_next": 0.0,
            "ndvi_delta_next_mean": 0.0,
            "ndmi_delta_next_mean": 0.0,
        }
    history_last_month = indices_history_last_weeks(df_all, weeks=5, agg="mean")
    forecast_lookup = get_forecast_lookup(latest_last)
    row = out.iloc[0].to_dict()
    return {
    "summary": {
        "Healthy_Pct_next": float(row.get("Healthy_Pct_next", 0.0)),
        "Monitor_Pct_next": float(row.get("Monitor_Pct_next", 0.0)),
        "Critical_Pct_next": float(row.get("Critical_Pct_next", 0.0)),
        "ndvi_delta_next_mean": float(row.get("ndvi_delta_next_mean", 0.0) or 0.0),
        "ndmi_delta_next_mean": float(row.get("ndmi_delta_next_mean", 0.0) or 0.0),
    },
    "lookup": forecast_lookup # نرجع القاموس هنا
}



def analyze_farm_health(farm_id: str, farm_doc: Dict[str, Any]) -> Dict[str, Any]:
    # 1. التحقق من المضلع (Polygon)
    poly = farm_doc.get("polygon") or []
    if len(poly) < 3:
        raise ValueError("Farm polygon is missing or < 3 points")

    coords = [(p["lng"], p["lat"]) for p in poly]
    site = {"name": farm_id, "polygon": coords}

    # 2. جلب بيانات Sentinel-2 و Landsat LST من GEE
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

    # 3. تجميع البيانات في DataFrame واحد
    if weekly_series:
        df_s2 = pd.concat(weekly_series, ignore_index=True)
    else:
        df_s2 = pd.DataFrame(columns=["site", "date", "x", "y", "NDVI", "GNDVI", "NDRE", "NDRE740", "MTCI", "NDMI", "NDWI_Gao", "SIWSI1", "SIWSI2", "SRWI", "NMDI"])

    df_th = pd.DataFrame(thermal_rows)
    df_th["date"] = pd.to_datetime(df_th["date"]).dt.normalize()

    wx = weekly_weather(site)
    wx["site"] = farm_id

    df_all = (
        df_s2.merge(wx, on=["site", "date"], how="left")
             .merge(df_th, on=["site", "date"], how="left")
    )

    if df_all.empty:
        raise RuntimeError("لم يتمكن النظام من جلب أي بكسلات Sentinel-2 لهذه المزرعة")

    # 4. معالجة الميزات (Features) وحساب المخاطر
    df_all["date"] = pd.to_datetime(df_all["date"]).dt.normalize()
    df_all = add_features(df_all)
    df_all = df_all.dropna(subset=INDEX_COLS_ALL, how="all").copy()

    if "history_weeks" in df_all.columns:
        df_all = df_all[df_all["history_weeks"] >= 6].reset_index(drop=True)

    df_all = compute_if_risk_inference(df_all)
    df_all = add_rpw_flags_and_score(df_all)
    alert_signals = build_alert_signals(df_all)

    # 5. حساب الإحصائيات الحالية (Stats)
    stats = site_summary(df_all)
    processed_health = {
        "Healthy_Pct": float(stats.get("Healthy_Pct", 0.0)),
        "Monitor_Pct": float(stats.get("Monitor_Pct", 0.0)),
        "Critical_Pct": float(stats.get("Critical_Pct", 0.0)),
    }
    history_last_month = indices_history_last_weeks(df_all, weeks=5, agg="mean")

    # 6. جلب التوقعات والقاموس (Lookup) ودمجها في الخريطة
    forecast_res = forecast_next_week_summary(df_all)
    lookup = forecast_res.get("lookup", {}) # القاموس الذي يحتوي على الإحداثيات والحالة المتوقعة

    health_map_data = get_health_map_points(df_all)

    # دمج الحالة المتوقعة (ps) داخل نقاط الخريطة الحالية لتوفير حجم البيانات
    for pt in health_map_data:
        key = f"{pt['lat']}_{pt['lng']}"
        pt['ps'] = lookup.get(key, 0) # الحالة المتوقعة الافتراضية 0 (سليم)

    # 7. الإرجاع النهائي الموحد لـ Firestore
    return {
        "current_health": processed_health,
        "forecast_next_week": forecast_res.get("summary", {}), # ملخص النسب المئوية للمستقبل
        "health_map": health_map_data, # القائمة الموحدة التي تحتوي على s و ps
        "indices_history_last_month": history_last_month,
        "alert_signals": alert_signals,
    }


def build_alert_signals(df_all: pd.DataFrame) -> Dict[str, Any]:
    """
    ✅ ملخص إشارات للتنبيهات مبني 100% على أعمدة df_all الناتجة من كودكم:
    - pixel_risk_class
    - RPW_label_rule
    - flag_* (الموجودة فعلاً في add_rpw_flags_and_score)
    - RPW_score / IF_score لترتيب النقاط الأهم (Hotspots)
    """
    if df_all is None or df_all.empty:
        return {
            "latest_date": None,
            "total_pixels_latest": 0,
            "risk_counts_latest": {"Healthy": 0, "Monitor": 0, "Critical": 0},
            "rule_counts_latest": {},
            "flag_counts_latest": {},
            "hotspots": {"critical": [], "monitor": [], "stress": []},
        }

    df = df_all.copy()
    df["date"] = pd.to_datetime(df["date"]).dt.normalize()
    latest = df["date"].max()

    d = df[df["date"] == latest].copy()
    total = int(len(d))

    # --- Risk counts (from pixel_risk_class) ---
    risk_counts = {"Healthy": 0, "Monitor": 0, "Critical": 0}
    if "pixel_risk_class" in d.columns:
        vc = d["pixel_risk_class"].astype(str).value_counts().to_dict()
        for k in risk_counts.keys():
            risk_counts[k] = int(vc.get(k, 0))

    # --- Rule label counts (from RPW_label_rule) ---
    rule_counts = {}
    if "RPW_label_rule" in d.columns:
        rule_counts = d["RPW_label_rule"].astype(str).value_counts().to_dict()

    # --- Flag counts (only flags that exist in your code) ---
    flag_cols = [
        "flag_drop_SIWSI10pct",
        "flag_drop_NDWI10pct",
        "flag_drop_NDVI005",
        "flag_NDVI_below_030",
        "flag_NDRE_below_035",
        "flag_NDWI_below_025",
        "flag_NDRE_low",
        "flag_NDWI_low",
    ]
    flag_counts = {}
    for c in flag_cols:
        if c in d.columns:
            flag_counts[c] = int(pd.to_numeric(d[c], errors="coerce").fillna(0).astype(bool).sum())
        else:
            flag_counts[c] = 0

    # --- Hotspots (top points by RPW_score then IF_score) ---
    if "RPW_score" not in d.columns:
        d["RPW_score"] = 0.0
    if "IF_score" not in d.columns:
        d["IF_score"] = 0.0
    d["RPW_score"] = pd.to_numeric(d["RPW_score"], errors="coerce").fillna(0.0)
    d["IF_score"] = pd.to_numeric(d["IF_score"], errors="coerce").fillna(0.0)

    def _top_points(mask, topn=12):
        sub = d[mask].copy()
        if sub.empty:
            return []

        sub = sub.sort_values(["RPW_score", "IF_score"], ascending=False).head(topn)

        out = []
        for _, r in sub.iterrows():
            # IMPORTANT: df columns are x/y (lng/lat) in degrees for map usage
            out.append({
                "lng": float(r.get("x", 0.0)),
                "lat": float(r.get("y", 0.0)),
                "risk": str(r.get("pixel_risk_class", "Healthy")),
                "rule": str(r.get("RPW_label_rule", "Healthy")),
            })
        return out

    crit_mask = (d["pixel_risk_class"].astype(str) == "Critical") if "pixel_risk_class" in d.columns else pd.Series(False, index=d.index)
    mon_mask  = (d["pixel_risk_class"].astype(str) == "Monitor")  if "pixel_risk_class" in d.columns else pd.Series(False, index=d.index)

    stress_mask = pd.Series(False, index=d.index)
    if "RPW_label_rule" in d.columns:
        stress_mask = d["RPW_label_rule"].astype(str).isin(["Monitor_RPW_tail", "Critical_RPW_tail"])

    return {
        "latest_date": str(latest.date()) if pd.notna(latest) else None,
        "total_pixels_latest": total,
        "risk_counts_latest": risk_counts,
        "rule_counts_latest": rule_counts,
        "flag_counts_latest": flag_counts,
        "hotspots": {
            "critical": _top_points(crit_mask, topn=12),
            "monitor":  _top_points(mon_mask,  topn=12),
            "stress":   _top_points(stress_mask, topn=12),
        },
    }


# --- دالة استخراج النقاط (المصححة لمسميات GEE) ---
def get_health_map_points(df_all: pd.DataFrame) -> List[Dict[str, Any]]:
    if df_all is None or df_all.empty:
        return []

    df = df_all.copy()
    
    # نحول المسميات من x/y إلى lng/lat فقط عند إرسالها للجوال
    if 'x' in df.columns:
        df = df.rename(columns={'x': 'lng', 'y': 'lat'})

    try:
        # التجميع بناءً على الإحداثيات (التي أصبحت الآن درجات حقيقية)
        latest_pixels = df.sort_values('date').groupby(['lat', 'lng']).last().reset_index()
    except KeyError:
        return []
    
    map_points = []
    for _, row in latest_pixels.iterrows():
        status_code = 0 
        risk_val = row.get('pixel_risk_class', 'Healthy')
        
        if risk_val == 'Critical': status_code = 2
        elif risk_val == 'Monitor': status_code = 1
            
        map_points.append({
            'lat': round(float(row['lat']), 6),
            'lng': round(float(row['lng']), 6),
            's': status_code
        })
    return map_points 

