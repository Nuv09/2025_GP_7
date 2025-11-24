from typing import List, Tuple, Dict, Any

def polygon_centroid(poly: List[Dict[str, float]]) -> Tuple[float, float]:
    """
    poly: [{'lat': .., 'lng': ..}, ...]
    يرجّع (lat, lon)
    """
    if not poly:
        raise ValueError("empty polygon")
    xs = [p["lng"] for p in poly]
    ys = [p["lat"] for p in poly]
    xs.append(xs[0]); ys.append(ys[0])
    a = 0.0; cx = 0.0; cy = 0.0
    for i in range(len(xs) - 1):
        cross = xs[i] * ys[i+1] - xs[i+1] * ys[i]
        a += cross
        cx += (xs[i] + xs[i+1]) * cross
        cy += (ys[i] + ys[i+1]) * cross
    a *= 0.5
    if a == 0:
        lat = sum(p["lat"] for p in poly) / len(poly)
        lon = sum(p["lng"] for p in poly) / len(poly)
        return (lat, lon)
    cx /= (6.0 * a)
    cy /= (6.0 * a)
    return (cy, cx)