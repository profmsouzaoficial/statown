#!/usr/bin/env python3
"""
StaTown - Fase Zero: extracao da geometria cartografica do mapa de setorizacao
de Governador Valadares (PDF) para uma grade de tiles que alimenta o gerador
de mundo da Godot 4.

O PDF e um mapa vetorial do AutoCAD (20 zonas fiscais + calha do Rio Doce).
Extraimos as mascaras por cor de preenchimento, mapeamos para uma grade de
240x180 tiles e emitimos os dados que o renderizador do mundo consome.

Saidas:
  tools/generated_map_data.json   -> metadados (zonas, centroides, agua, warp)
  tools/zone_ids.png              -> 240x180, R = id da vila (0 = fora)
  tools/water_mask.png            -> 240x180, R = cobertura de agua (0-255)
  tools/preview_grid.png          -> conferencia visual

Uso:
  python3 tools/extract_map_geometry.py
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PDF = os.path.join(ROOT, "Mapa_de_setorizacao_do_municipio_Zoneamento_Fiscal (1).pdf")
RASTER = os.path.join(ROOT, "tools", "reference_map_raster.png")
GRID_W, GRID_H = 240, 180
WORK_W = 2340  # largura de trabalho; reduz o custo sem perder fidelidade na grade final

# Cor de preenchimento de cada zona no PDF (amostrada sob os rotulos do AutoCAD).
ZONE_COLORS = {
    1: (197, 249, 195), 2: (34, 52, 110), 3: (153, 27, 30), 4: (19, 103, 52),
    5: (242, 113, 114), 6: (69, 84, 165), 7: (122, 175, 223), 8: (114, 116, 48),
    9: (39, 118, 187), 10: (175, 217, 170), 11: (99, 100, 102), 12: (114, 116, 48),
    13: (100, 33, 101), 14: (88, 186, 72), 15: (242, 103, 34), 16: (209, 156, 199),
    17: (173, 221, 247), 18: (254, 204, 102), 19: (254, 234, 185), 20: (248, 215, 49),
}

# Coordenadas dos rotulos no raster de referencia (100 dpi, 4681x3312).
REF_SIZE = (4681, 3312)
LABEL_HINTS_REF = {
    1: (2444, 974), 2: (2731, 830), 3: (2364, 670), 4: (2148, 814),
    5: (2354, 854), 6: (2300, 1050), 7: (2418, 1264), 8: (2290, 1230),
    9: (2226, 1116), 10: (2027, 1169), 11: (1560, 492), 12: (2416, 1738),
    13: (2191, 1500), 14: (2112, 1306), 15: (2288, 1982), 16: (1853, 1794),
    17: (1824, 1208), 18: (2068, 2012), 19: (2568, 1370), 20: (4245, 720),
}
LABEL_YELLOW = (200, 201, 45)
WATER_CYAN = ((0, 255, 255), (24, 255, 255), (46, 255, 255), (89, 255, 255),
              (158, 255, 255), (127, 255, 255), (68, 255, 255), (162, 255, 255))


def log(msg: str) -> None:
    print(f"[map] {msg}", flush=True)


def rasterize_pdf() -> str:
    if os.path.exists(RASTER):
        log(f"raster reaproveitado: {RASTER}")
        return RASTER
    if shutil.which("pdftoppm") is None:
        raise RuntimeError("pdftoppm nao encontrado; instale poppler-utils")
    subprocess.run(["pdftoppm", "-png", "-r", "150", "-singlefile", PDF, RASTER[:-4]], check=True)
    log(f"raster gerado: {RASTER}")
    return RASTER


def color_mask(arr: np.ndarray, rgb, tol: int = 12) -> np.ndarray:
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    return (np.abs(r - rgb[0]) <= tol) & (np.abs(g - rgb[1]) <= tol) & (np.abs(b - rgb[2]) <= tol)


def detect_label_boxes(arr: np.ndarray) -> list[tuple[int, int]]:
    m = ndimage.binary_closing(color_mask(arr, LABEL_YELLOW, tol=40), np.ones((5, 5)))
    m = ndimage.binary_fill_holes(m)
    lab, _ = ndimage.label(m)
    boxes = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None:
            continue
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        area = int((lab[sl] == i + 1).sum())
        if 20 <= w <= 100 and 20 <= h <= 100 and area > 600 and 0.5 < w / h < 2.0:
            boxes.append(((sl[1].start + sl[1].stop) // 2, (sl[0].start + sl[0].stop) // 2))
    return boxes


def pick_component(mask: np.ndarray, hint: tuple[int, int], win: int = 150) -> np.ndarray:
    """Componente conexo dominante na vizinhanca do rotulo (o rotulo cobre parte da zona)."""
    lab, n = ndimage.label(mask)
    if n == 0:
        return mask
    H, W = mask.shape
    hx, hy = hint
    sub = lab[max(0, hy - win):min(H, hy + win), max(0, hx - win):min(W, hx + win)]
    vals, counts = np.unique(sub[sub > 0], return_counts=True)
    if len(vals) == 0:
        best, best_d = None, 1e18
        for i, sl in enumerate(ndimage.find_objects(lab)):
            if sl is None:
                continue
            cy = (sl[0].start + sl[0].stop) / 2
            cx = (sl[1].start + sl[1].stop) / 2
            d = (cx - hx) ** 2 + (cy - hy) ** 2
            if d < best_d:
                best_d, best = d, i + 1
        return lab == best if best else mask
    return lab == int(vals[int(np.argmax(counts))])


def main() -> int:
    raster = rasterize_pdf()
    im = Image.open(raster).convert("RGB")
    s = WORK_W / im.size[0]
    im = im.resize((WORK_W, int(round(im.size[1] * s))), Image.NEAREST)
    arr = np.asarray(im)
    H, W = arr.shape[:2]
    log(f"raster de trabalho {W}x{H} (escala {s:.4f})")

    # dicas de rotulo: raster de referencia (100 dpi) -> raster de trabalho
    k = W / REF_SIZE[0]
    hints = {z: (int(x * k), int(y * k)) for z, (x, y) in LABEL_HINTS_REF.items()}
    boxes = detect_label_boxes(arr)
    log(f"etiquetas detectadas: {len(boxes)}")
    if boxes:
        for z, (hx, hy) in hints.items():
            bx, by = min(boxes, key=lambda b: (b[0] - hx) ** 2 + (b[1] - hy) ** 2)
            hints[z] = (bx, by)

    # ---- 1. Mascaras das zonas --------------------------------------------
    zone_masks: dict[int, np.ndarray] = {}
    for zid, rgb in ZONE_COLORS.items():
        m = color_mask(arr, rgb, tol=12)
        m = ndimage.binary_opening(m, np.ones((3, 3)))
        m = ndimage.binary_closing(m, np.ones((5, 5)))
        m = ndimage.binary_fill_holes(m)
        m = pick_component(m, hints[zid], win=int(110 * k))
        m = ndimage.binary_fill_holes(ndimage.binary_closing(m, np.ones((7, 7))))
        zone_masks[zid] = m
        log(f"zona {zid:02d}: {int(m.sum()):>7} px")

    zone_index = np.zeros((H, W), dtype=np.uint8)
    for zid in sorted(zone_masks, key=lambda z: -int(zone_masks[z].sum())):
        zone_index[zone_masks[zid] & (zone_index == 0)] = zid

    # ---- 2. Calha do Rio Doce (hachura ciano) -----------------------------
    water = np.zeros((H, W), dtype=bool)
    for c in WATER_CYAN:
        for tol in (18, 34):
            water |= color_mask(arr, c, tol=tol)
    water = ndimage.binary_closing(water, np.ones((9, 9)))
    water = ndimage.binary_fill_holes(water)
    water = ndimage.binary_opening(water, np.ones((3, 3)))
    lab, nlab = ndimage.label(water)
    sizes = ndimage.sum(water, lab, range(1, nlab + 1))
    keep = np.zeros_like(water)
    for i, sz in enumerate(sizes):
        if sz > 3000:
            keep |= lab == i + 1
    water = keep
    log(f"agua: {int(water.sum())} px em {int((sizes > 3000).sum())} corpos")

    # ---- 3. Caixa envolvente ----------------------------------------------
    union = zone_index > 0
    ys, xs = np.where(union)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    pad_x = int((x1 - x0) * 0.055)
    pad_y = int((y1 - y0) * 0.055)
    x0, x1 = max(0, x0 - pad_x), min(W, x1 + pad_x)
    y0, y1 = max(0, y0 - pad_y), min(H, y1 + pad_y)
    bw, bh = x1 - x0, y1 - y0
    log(f"bbox: x[{x0},{x1}] y[{y0},{y1}] = {bw}x{bh} (ar {bw/bh:.3f})")

    # ---- 4. Rasteriza para a grade com superamostragem --------------------
    ss = 4
    margin = 2
    scale = min((GRID_W - 2 * margin) / bw, (GRID_H - 2 * margin) / bh)
    off_x = (GRID_W - bw * scale) / 2.0
    off_y = (GRID_H - bh * scale) / 2.0
    log(f"escala {scale:.5f} tiles/px  offset ({off_x:.1f},{off_y:.1f})")

    gx = (np.arange(GRID_W)[:, None] + (np.arange(ss)[None, :] + 0.5) / ss).reshape(-1)
    gy = (np.arange(GRID_H)[:, None] + (np.arange(ss)[None, :] + 0.5) / ss).reshape(-1)
    px = ((gx - off_x) / scale + x0).astype(np.int32).clip(0, W - 1)
    py = ((gy - off_y) / scale + y0).astype(np.int32).clip(0, H - 1)

    sub_z = zone_index[np.ix_(py, px)].reshape(GRID_H, ss, GRID_W, ss)
    sub_w = water[np.ix_(py, px)].astype(np.float32).reshape(GRID_H, ss, GRID_W, ss)

    zone_cov = np.zeros((GRID_H, GRID_W), dtype=np.float32)
    zone_grid = np.zeros((GRID_H, GRID_W), dtype=np.uint8)
    for zid in range(1, 21):
        c = (sub_z == zid).mean(axis=(1, 3))
        upd = c > zone_cov
        zone_cov[upd] = c[upd]
        zone_grid[upd] = zid

    water_grid = sub_w.mean(axis=(1, 3))

    # ---- 5. Consistencia zona x agua --------------------------------------
    zone_grid[zone_cov < 0.28] = 0
    zone_grid[(water_grid > 0.62) & (zone_cov < 0.50)] = 0

    # fecha buracos deixados pelas etiquetas numericas (por zona)
    for zid in range(1, 21):
        m = zone_grid == zid
        if not m.any():
            continue
        filled = ndimage.binary_fill_holes(m)
        hole = filled & ~m
        zone_grid[hole] = zid

    # tiles vazios encostados em zonas e secos -> zona mais proxima
    dry = (zone_grid == 0) & (water_grid < 0.35)
    if dry.any():
        dist, (iy, ix) = ndimage.distance_transform_edt(zone_grid == 0, return_indices=True)
        near = zone_grid[iy, ix]
        take = dry & (dist <= 4.0) & (near > 0)
        zone_grid[take] = near[take]

    # ---- 6. Recompressao espacial (enclave leste) --------------------------
    W_, H_ = GRID_W, GRID_H
    # limite leste do nucleo urbano continuo (zonas 1..19)
    core = np.isin(zone_grid, list(range(1, 20)))
    xs_core = np.where(core.any(axis=0))[0]
    xA = int(xs_core.max()) + 3 if len(xs_core) else W_ - 1
    xs_all = np.where((zone_grid > 0).any(axis=0))[0]
    xEnd = int(xs_all.max()) + 3 if len(xs_all) else W_ - 1
    xs_start = int(xs_core.min()) - 2 if len(xs_core) else 0

    # Y: estica o nucleo para ocupar a altura util
    ys_all = np.where((zone_grid > 0).any(axis=1))[0]
    yA0, yB0 = int(ys_all.min()) - 2, int(ys_all.max()) + 2
    yA1, yB1 = 3, H_ - 4

    def remap_row(a, b, c, d):
        """tabela de remapeamento linear por partes para indices de coluna."""
        lut = np.zeros(W_, dtype=np.int32)
        for i in range(W_):
            if i <= a:
                lut[i] = 0
            elif i <= b:
                lut[i] = int(round(c + (i - a) * (d - c) / max(1, b - a)))
            else:
                lut[i] = d
        return lut

    target_core_end = int(W_ * 0.63)
    target_all_end = W_ - 4
    x_lut = np.zeros(W_, dtype=np.int32)
    for i in range(W_):
        if i <= xs_start:
            x_lut[i] = 0
        elif i <= xA:
            x_lut[i] = int(round(1 + (i - xs_start) * (target_core_end - 1) / max(1, xA - xs_start)))
        else:
            x_lut[i] = int(round(target_core_end + (i - xA) * (target_all_end - target_core_end) / max(1, xEnd - xA)))
    y_lut = np.arange(H_, dtype=np.int32)
    for i in range(H_):
        if i <= yA0:
            y_lut[i] = 0
        elif i <= yB0:
            y_lut[i] = int(round(yA1 + (i - yA0) * (yB1 - yA1) / max(1, yB0 - yA0)))
        else:
            y_lut[i] = yB1

    # aplica warp por inversao (remapeia cada celula destino para a origem)
    src_x = np.zeros(W_, dtype=np.int32)
    for i in range(W_):
        # primeira coluna origem cujo destino >= i
        j = int(np.searchsorted(x_lut, i, side="left"))
        src_x[i] = min(W_ - 1, max(0, j))
    src_y = np.zeros(H_, dtype=np.int32)
    for i in range(H_):
        j = int(np.searchsorted(y_lut, i, side="left"))
        src_y[i] = min(H_ - 1, max(0, j))

    zone_grid = zone_grid[np.ix_(src_y, src_x)]
    water_grid = water_grid[np.ix_(src_y, src_x)]

    # recalcula cobertura de agua apos warp (suaviza serrilhado)
    water_grid = ndimage.gaussian_filter(water_grid, sigma=0.6)

    zone_meta = {}
    for zid in range(1, 21):
        m = zone_grid == zid
        area = int(m.sum())
        if area < 6:
            log(f"AVISO: zona {zid:02d} com {area} tiles")
            continue
        core_m = ndimage.binary_erosion(m, np.ones((3, 3)))
        src = core_m if core_m.sum() > 8 else m
        ys2, xs2 = np.where(src)
        cx, cy = float(xs2.mean()), float(ys2.mean())
        d2 = (xs2 - cx) ** 2 + (ys2 - cy) ** 2
        ai = int(np.argmin(d2))
        zone_meta[zid] = {
            "id": zid,
            "area_tiles": area,
            "centroid": [round(cx, 2), round(cy, 2)],
            "anchor": [int(xs2[ai]), int(ys2[ai])],
            "bbox": [int(xs2.min()), int(ys2.min()), int(xs2.max()), int(ys2.max())],
            "color": "#%02x%02x%02x" % ZONE_COLORS[zid],
        }

    # ---- 7. Saidas --------------------------------------------------------
    Image.fromarray(zone_grid, mode="L").convert("RGB").save(os.path.join(ROOT, "tools", "zone_ids.png"))
    Image.fromarray(np.clip(water_grid * 255, 0, 255).astype(np.uint8), mode="L").save(
        os.path.join(ROOT, "tools", "water_mask.png"))

    meta = {
        "grid": {"w": GRID_W, "h": GRID_H, "tile": 16},
        "source": os.path.basename(PDF),
        "work_size": [W, H],
        "bbox": [x0, y0, x1, y1],
        "scale": scale,
        "offset": [off_x, off_y],
        "zones": {str(k): v for k, v in zone_meta.items()},
    }
    with open(os.path.join(ROOT, "tools", "generated_map_data.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, ensure_ascii=False)

    # ---- 8. Preview -------------------------------------------------------
    pa = np.full((GRID_H, GRID_W, 3), 236, dtype=np.uint8)
    for zid in zone_meta:
        pa[zone_grid == zid] = ZONE_COLORS[zid]
    pa[water_grid > 0.5] = (0, 190, 255)
    Image.fromarray(pa, mode="RGB").resize((GRID_W * 5, GRID_H * 5), Image.NEAREST).save(
        os.path.join(ROOT, "tools", "preview_grid.png"))

    # preview em resolução de raster para conferir aderência
    prev2 = arr.copy()
    for zid, info in zone_meta.items():
        prev2[zone_index == zid] = (230, 230, 230)
    Image.fromarray(prev2).resize((W // 2, H // 2), Image.LANCZOS).save(
        os.path.join(ROOT, "tools", "preview_contact.png"))
    log("preview: tools/preview_grid.png | tools/preview_contact.png")
    log("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
