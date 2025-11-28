import os
import io
import tempfile
import math
from typing import Dict, Any, Tuple, List

import requests
import time, hashlib, logging
from PIL import Image, ImageOps
from google.cloud import storage
from ultralytics import YOLO

import gc
import torch
from app.common import polygon_centroid


TILE_SIZE = 1024        
OVERLAP = 0.20          
CONF_THRESHOLD = 0.30   
NMS_IOU_THRESHOLD = 0.70  
MAX_DETECTION_LIMIT = 5000  

MAPTILER_KEY = os.environ.get("MAPTILER_KEY")
TILE_URL = "https://api.maptiler.com/maps/satellite/{zoom}/{x}/{y}.jpg?key={key}"
TILE_SIZE_MAP = 512     

DEFAULT_BUCKET = os.environ.get("STORAGE_BUCKET", "saaf-97251.firebasestorage.app")
MODELS_PREFIX = os.environ.get("REMOTE_MODELS_PREFIX", "models/")
MODELS_GCS_URI_A = os.environ.get("MODELS_GCS_URI_A")
MODELS_GCS_URI_B = os.environ.get("MODELS_GCS_URI_B")



def _gcs() -> storage.Client:
    return storage.Client()


def _download_blob(bucket_name: str, blob_name: str) -> str:
    client = _gcs()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    if not blob.exists():
        raise FileNotFoundError(f"Blob not found: gs://{bucket_name}/{blob_name}")
    fd, tmp = tempfile.mkstemp(suffix=".pt")
    os.close(fd)
    blob.download_to_filename(tmp)
    print(f"✅ Downloaded gs://{bucket_name}/{blob_name} -> {tmp}")
    return tmp


def _parse_gs_uri(uri: str) -> Tuple[str, str]:
    without = uri.replace("gs://", "")
    bucket = without.split("/")[0]
    blob = "/".join(without.split("/")[1:])
    return bucket, blob


def _auto_pick_two_pt(bucket: str, prefix: str) -> Tuple[str, str]:
    client = _gcs()
    blobs = list(client.list_blobs(bucket, prefix=prefix))
    pts = [b for b in blobs if b.name.lower().endswith(".pt")]
    if len(pts) < 2:
        raise FileNotFoundError(f"Need >=2 .pt under gs://{bucket}/{prefix}")

    finetuned = [b for b in pts if os.path.basename(b.name).startswith("best_finetuned")]
    best_named = [b for b in pts if os.path.basename(b.name) == "best.pt"]

    if finetuned and best_named:
        fa = sorted(finetuned, key=lambda b: b.updated or b.time_created, reverse=True)[0]
        bb = sorted(best_named, key=lambda b: b.updated or b.time_created, reverse=True)[0]
        return fa.name, bb.name

    pts_sorted = sorted(pts, key=lambda b: b.updated or b.time_created, reverse=True)
    return pts_sorted[0].name, pts_sorted[1].name


def load_models_auto():
    if MODELS_GCS_URI_A and MODELS_GCS_URI_B:
        a_bucket, a_blob = _parse_gs_uri(MODELS_GCS_URI_A)
        b_bucket, b_blob = _parse_gs_uri(MODELS_GCS_URI_B)

        a_local = _download_blob(a_bucket, a_blob)
        b_local = _download_blob(b_bucket, b_blob)

        model_a = YOLO(a_local)
        model_a.model.to("cpu").eval()
        model_b = YOLO(b_local)
        model_b.model.to("cpu").eval()

        return {"A": model_a, "B": model_b}, {
            "A": MODELS_GCS_URI_A,
            "B": MODELS_GCS_URI_B,
        }

    blob_a, blob_b = _auto_pick_two_pt(DEFAULT_BUCKET, MODELS_PREFIX)

    a_local = _download_blob(DEFAULT_BUCKET, blob_a)
    b_local = _download_blob(DEFAULT_BUCKET, blob_b)

    model_a = YOLO(a_local)
    model_a.model.to("cpu").eval()
    model_b = YOLO(b_local)
    model_b.model.to("cpu").eval()

    return (
        {"A": model_a, "B": model_b},
        {
            "A": f"gs://{DEFAULT_BUCKET}/{blob_a}",
            "B": f"gs://{DEFAULT_BUCKET}/{blob_b}",
        },
    )


def _http_get_with_retry(url: str, tries: int = 3, backoff: float = 0.75, timeout: int = 30):
    last = None
    for i in range(tries):
        r = requests.get(url, timeout=timeout)
        logging.info(
            f"[FETCH] url={url} status={r.status_code} bytes={len(r.content)} try={i + 1}/{tries}"
        )
        if r.status_code < 500:
            r.raise_for_status()
            return r
        last = r
        time.sleep(backoff * (2 ** i))
    last.raise_for_status()


def _open_fix_to_rgb(raw_bytes: bytes, tag: str):
    """تصحيح EXIF، إزالة alpha، والتحويل إلى RGB."""
    im = Image.open(io.BytesIO(raw_bytes))
    try:
        im = ImageOps.exif_transpose(im)
    except Exception as e:
        logging.info(f"[IMG] exif_transpose_fail tag={tag} err={e}")

    if im.mode in ("RGBA", "LA"):
        bg = Image.new("RGB", im.size, (0, 0, 0))
        im_alpha = im.split()[-1]
        bg.paste(im, mask=im_alpha)
        im = bg
    elif im.mode != "RGB":
        im = im.convert("RGB")

    logging.info(f"[IMG] opened tag={tag} mode={im.mode} size={im.size}")
    return im



def _deg_to_tile(lat: float, lon: float, zoom: int) -> Tuple[int, int]:
    lat_rad = math.radians(lat)
    n = 2.0 ** zoom
    xtile = int((lon + 180.0) / 360.0 * n)
    ytile = int(
        (
            n
            * (1.0 - math.log(math.tan(lat_rad) + (1 / math.cos(lat_rad))) / math.pi)
            / 2.0
        )
    )
    return xtile, ytile


def _download_and_stitch_tiles(
    lat: float, lon: float, zoom: int, target_size: int = TILE_SIZE
) -> Image.Image:
    if not MAPTILER_KEY:
        raise RuntimeError("MAPTILER_KEY is required")

    cx, cy = _deg_to_tile(lat, lon, zoom)

    tiles_per_side = target_size // TILE_SIZE_MAP
    if tiles_per_side < 1:
        tiles_per_side = 1

    start_x = cx - (tiles_per_side // 2)
    start_y = cy - (tiles_per_side // 2)
    stitched_image = Image.new(
        "RGB", (tiles_per_side * TILE_SIZE_MAP, tiles_per_side * TILE_SIZE_MAP)
    )

    for i in range(tiles_per_side):
        for j in range(tiles_per_side):
            x = start_x + i
            y = start_y + j
            url = TILE_URL.format(zoom=zoom, x=x, y=y, key=MAPTILER_KEY)

            r = _http_get_with_retry(url, tries=3, backoff=0.75, timeout=60)
            tile_image = Image.open(io.BytesIO(r.content)).convert("RGB")

            stitched_image.paste(tile_image, (i * TILE_SIZE_MAP, j * TILE_SIZE_MAP))

    return stitched_image.crop((0, 0, target_size, target_size))


def get_sat_image_for_farm(farm: Dict[str, Any]) -> str:
    
    img_url = (farm.get("imageURL") or farm.get("imageUrl") or "").strip()

    if img_url:
        r = _http_get_with_retry(img_url, tries=2, backoff=0.75, timeout=120)
        sha1 = hashlib.sha1(r.content).hexdigest()
        logging.info(
            f"[SRC] user content_type={r.headers.get('Content-Type')} "
            f"bytes={len(r.content)} sha1={sha1}"
        )
        img = _open_fix_to_rgb(r.content, tag="user")
        img = img.resize((TILE_SIZE, TILE_SIZE))
        path = "/tmp/input.jpg"
        img.save(path, "JPEG", quality=90)
        logging.info(f"[IMG] saved path={path} source=user")
        return path

    poly = farm.get("polygon") or []
    if not poly or len(poly) < 3:
        raise ValueError("Farm polygon is missing or < 3 points")

    lat, lon = polygon_centroid(poly)

    img = _download_and_stitch_tiles(lat=lat, lon=lon, zoom=18, target_size=TILE_SIZE)

    logging.info(f"[SRC] maptiler size={img.size}")
    path = "/tmp/input.jpg"
    img.convert("RGB").save(path, "JPEG", quality=85)
    return path



def _yolo_predict(model: YOLO, image_path: str) -> Dict[str, Any]:
    try:
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()

        results = model.predict(
            image_path,
            device="cpu",
            verbose=False,
            conf=CONF_THRESHOLD,
            iou=NMS_IOU_THRESHOLD,
            max_det=MAX_DETECTION_LIMIT,
        )

        r = results[0]
        dets: List[Dict[str, Any]] = []

        if hasattr(r, "boxes") and r.boxes is not None:
            names = getattr(r, "names", {}) or {}
            limit = min(len(r.boxes), MAX_DETECTION_LIMIT)

            for i in range(limit):
                b = r.boxes[i]
                cls = int(b.cls[0])
                conf = float(b.conf[0])

                if conf >= CONF_THRESHOLD:
                    x1, y1, x2, y2 = [float(v) for v in b.xyxy[0].tolist()]
                    dets.append(
                        {
                            "cls": cls,
                            "label": names.get(cls, str(cls)),
                            "conf": conf,
                            "box_xyxy": [x1, y1, x2, y2],
                        }
                    )

        mean_conf = (sum(d["conf"] for d in dets) / len(dets)) if dets else 0.0
        score = float(mean_conf + 0.05 * math.log(1 + len(dets)))
        return {"detections": dets, "count": len(dets), "score": score}

    finally:
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()


def run_both_and_pick_best(models, image_path: str) -> Dict[str, Any]:
    
    a = _yolo_predict(models["A"], image_path)
    b = _yolo_predict(models["B"], image_path)
    best = a if a["score"] >= b["score"] else b
    return {
        "picked": "A" if best is a else "B",
        "count": best["count"],
        "score": best["score"],
        "best_detections": best["detections"],
        "A": {"count": a["count"], "score": a["score"]},
        "B": {"count": b["count"], "score": b["score"]},
    }




def count_palms(models, image_path: str) -> Dict[str, Any]:
  
    result = run_both_and_pick_best(models, image_path)

    return {
        "count": int(result["count"]),
        "quality": float(result["score"]),
        "model": result.get("picked"),
    }
