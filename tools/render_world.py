#!/usr/bin/env python3
"""
StaTown - Gerador do mundo (Rio Doce + 20 Vilas) em pixel art.

Le as mascaras geradas por extract_map_geometry.py e compoe a textura do mundo
(240x180 tiles de 16 px) com os assets Kenney. Tambem emite data/map_data.json
com grafo viario, ancoras das vilas e rota dos barcos.

Uso:
  python3 tools/render_world.py [--preview]                 # mapa procedural Kenney
  python3 tools/render_world.py --terreno [--preview]       # terreno da arte Gemini
"""
from __future__ import annotations

import heapq
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "extracted")
OUT_ART = os.path.join(ROOT, "assets", "art")
OUT_DATA = os.path.join(ROOT, "data")

GX, GY, T = 240, 180, 16
W, H = GX * T, GY * T

C = {
    "grass": (132, 198, 105), "grass_l": (170, 227, 147), "grass_d": (101, 165, 86),
    "grass_dd": (67, 149, 69),
    "water": (117, 227, 255), "water_l": (159, 235, 255), "water_d": (70, 196, 228),
    "water_dd": (0, 154, 220), "water_deep": (0, 122, 190),
    "sand": (234, 165, 108), "sand_d": (197, 110, 51),
    "stone": (192, 203, 220), "stone_d": (139, 155, 180), "stone_dd": (82, 96, 124),
    "dark": (63, 38, 49), "asph": (103, 119, 148), "asph_l": (139, 155, 180),
    "white": (255, 255, 255), "dirt": (170, 120, 78), "dirt_l": (196, 148, 104),
    "dirt_d": (140, 96, 60), "rock": (139, 155, 180), "rock_l": (192, 203, 220),
    "rock_d": (82, 96, 124), "wood": (150, 106, 68), "wood_d": (112, 78, 52),
}

VILA_NAMES = {
    1: "Vila Central do Rio", 2: "Vila Ribeira Leste", 3: "Vila da Encosta Norte",
    4: "Vila das Nascentes", 5: "Vila do Mirante", 6: "Vila Esplanada Real",
    7: "Vila da Ilha", 8: "Vila Beira-Rio Oeste", 9: "Vila do Claustro",
    10: "Vila das Acácias", 11: "Vila do Vale Distante", 12: "Vila da Ponte Sul",
    13: "Vila Entre-Pontes", 14: "Vila dos Ipês", 15: "Vila do Pico",
    16: "Vila Fabril Sudoeste", 17: "Vila Horizonte Oeste", 18: "Vila da Várzea Sul",
    19: "Vila das Chácaras", 20: "Vila da Cachoeira Leste",
}
PROFILES = {
    1: "core", 2: "industrial", 3: "residential", 4: "residential", 5: "urban",
    6: "urban", 7: "coastal", 8: "urban", 9: "urban", 10: "residential",
    11: "rural", 12: "industrial", 13: "industrial", 14: "residential",
    15: "residential", 16: "industrial", 17: "rural", 18: "rural",
    19: "rural", 20: "rural",
}
PALETTES = {1: "gray", 2: "blue", 3: "red", 4: "green", 5: "orange", 6: "gray",
            7: "blue", 8: "gray", 9: "red", 10: "green", 11: "green", 12: "orange",
            13: "gray", 14: "green", 15: "orange", 16: "gray", 17: "green",
            18: "orange", 19: "green", 20: "orange"}


class Sheet:
    def __init__(self, rel: str, tile: int = 16):
        self.img = Image.open(os.path.join(ASSETS, rel)).convert("RGBA")
        self.tile = tile
        self.cols = self.img.width // tile

    def t(self, idx: int) -> Image.Image:
        cx, cy = idx % self.cols, idx // self.cols
        return self.img.crop((cx * self.tile, cy * self.tile,
                              (cx + 1) * self.tile, (cy + 1) * self.tile))


def _px(img, x, y, col):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), col)


def grass_tile(rng: random.Random, variant: int = 0) -> Image.Image:
    im = Image.new("RGBA", (T, T), C["grass"] + (255,))
    for _ in range(4):
        x, y = rng.randrange(T), rng.randrange(T)
        _px(im, x, y, (C["grass_l"] if rng.random() < 0.6 else C["grass_d"]) + (255,))
    if variant == 1:
        for _ in range(2):
            x, y = rng.randrange(2, T - 2), rng.randrange(3, T - 1)
            _px(im, x, y, C["grass_dd"] + (255,))
            _px(im, x + 1, y - 1, C["grass_d"] + (255,))
    elif variant == 2:
        x, y = rng.randrange(3, T - 4), rng.randrange(3, T - 4)
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            _px(im, x + dx, y + dy, (255, 226, 150, 255))
        _px(im, x + 2, y, (255, 210, 110, 255))
    return im


def sand_tile(rng: random.Random) -> Image.Image:
    im = Image.new("RGBA", (T, T), C["sand"] + (255,))
    for _ in range(4):
        _px(im, rng.randrange(T), rng.randrange(T), (212, 146, 92, 255))
    return im


def dirt_tile(rng: random.Random, furrow: bool = False) -> Image.Image:
    im = Image.new("RGBA", (T, T), C["dirt"] + (255,))
    if furrow:
        for y in (4, 9, 14):
            im.paste(C["dirt_d"] + (255,), (0, y, T, y + 1))
            im.paste(C["dirt_l"] + (255,), (0, y - 1, T, y))
    for _ in range(3):
        _px(im, rng.randrange(T), rng.randrange(T), C["dirt_l"] + (255,))
    return im


PAVE_L = (206, 195, 173)
PAVE = (181, 168, 145)
PAVE_D = (146, 133, 112)


def stone_tile(rng: random.Random) -> Image.Image:
    """Calcada / praca em pedra clara (tom quente, nao confundir com agua)."""
    im = Image.new("RGBA", (T, T), PAVE_D + (255,))
    for gy in range(0, T, 4):
        off = 2 if (gy // 4) % 2 else 0
        for gx in range(-off, T, 8):
            im.paste(PAVE + (255,), (gx, gy, min(gx + 7, T), min(gy + 3, T)))
            im.paste(PAVE_L + (255,), (gx, gy, min(gx + 7, T), gy + 1))
    return im


MATA = (78, 124, 80)
MATA_D = (56, 98, 62)
MATA_L = (104, 150, 96)


def mata_tile(rng: random.Random) -> Image.Image:
    """Chao de mata: verde escuro com folhico, para a copa das arvores contrastar."""
    im = Image.new("RGBA", (T, T), MATA + (255,))
    for _ in range(6):
        x, y = rng.randrange(T), rng.randrange(T)
        _px(im, x, y, (MATA_L if rng.random() < 0.45 else MATA_D) + (255,))
    return im


ROCHA = (124, 116, 118)
ROCHA_D = (92, 84, 92)
ROCHA_L = (158, 150, 148)


def rocha_tile(rng: random.Random) -> Image.Image:
    """Chao de serra: cinza-marrom com pedras soltas."""
    im = Image.new("RGBA", (T, T), ROCHA + (255,))
    for _ in range(7):
        x, y = rng.randrange(T), rng.randrange(T)
        _px(im, x, y, (ROCHA_L if rng.random() < 0.45 else ROCHA_D) + (255,))
    return im


CROP_G = (139, 178, 84)
CROP_G2 = (108, 152, 68)
CROP_Y = (214, 190, 96)
CROP_Y2 = (178, 154, 72)


def crop_tile(rng: random.Random, kind: int) -> Image.Image:
    """Talhao: 0 = solo arado, 1 = lavoura verde, 2 = lavoura dourada."""
    if kind == 0:
        return dirt_tile(rng, furrow=True)
    base, dark = (CROP_G, CROP_G2) if kind == 1 else (CROP_Y, CROP_Y2)
    im = Image.new("RGBA", (T, T), base + (255,))
    for y in (3, 8, 13):
        im.paste(dark + (255,), (0, y, T, y + 2))
    for _ in range(6):
        _px(im, rng.randrange(T), rng.randrange(T), dark + (255,))
    return im


def asphalt_tile(rng: random.Random) -> Image.Image:
    im = Image.new("RGBA", (T, T), C["asph"] + (255,))
    for _ in range(4):
        _px(im, rng.randrange(T), rng.randrange(T), C["asph_l"] + (255,))
    return im


def water_tile(rng: random.Random, depth: int) -> Image.Image:
    if depth <= 1:
        base = C["water"]
    elif depth == 2:
        base = C["water_d"]
    elif depth == 3:
        base = C["water_dd"]
    else:
        base = C["water_deep"]
    im = Image.new("RGBA", (T, T), base + (255,))
    n = 2 if depth >= 2 else 2
    for _ in range(n):
        x, y = rng.randrange(0, T - 4), rng.randrange(1, T - 2)
        for k in range(3):
            _px(im, x + k, y, C["water_l"] + (255,))
    return im


class WorldBuilder:
    def __init__(self, terreno: bool = False) -> None:
        self.terreno = terreno
        self.terrain = None
        self.zone = np.asarray(Image.open(os.path.join(ROOT, "tools", "zone_ids.png")).convert("L")).astype(np.uint8)
        if terreno:
            # terreno classificado a partir da arte de referencia (extract_terrain.py)
            self.terrain = np.asarray(Image.open(os.path.join(ROOT, "tools", "terrain_ids.png")).convert("L")).astype(np.uint8)
            self.water = (self.terrain == 6).astype(np.float32)
        else:
            self.water = np.asarray(Image.open(os.path.join(ROOT, "tools", "water_mask.png")).convert("L")).astype(np.float32) / 255.0
        self.meta = json.load(open(os.path.join(ROOT, "tools", "generated_map_data.json"), encoding="utf-8"))
        self.sheets = {
            "town": Sheet("kenney_tiny-town/Tilemap/tilemap_packed.png"),
            "city": Sheet("kenney_tiny-city/Tilemap/tilemap_packed.png"),
            "farm": Sheet("kenney_tiny-farm/Tilemap/tilemap_packed.png"),
            "battle": Sheet("kenney_tiny-battle/Tilemap/tilemap_packed.png"),
            "factory": Sheet("kenney_tiny-factory/Tilemap/tilemap_packed.png"),
        }
        self.img = Image.new("RGBA", (W, H), C["grass"] + (255,))
        self.blocked = np.zeros((GY, GX), dtype=bool)
        self.water_b = self.water > 0.5
        self.road = np.zeros((GY, GX), dtype=bool)
        self.street = np.zeros((GY, GX), dtype=bool)
        self.plots = np.zeros((GY, GX), dtype=bool)
        self.roads: list = []
        self.boats: list = []

    # ------------------------------------------------------------------ utils
    def rng_for(self, *parts) -> random.Random:
        seed = 20261104
        for p in parts:
            seed = (seed * 1000003 + int(p)) & 0xFFFFFFFF
        return random.Random(seed)

    def paste(self, im: Image.Image, gx: int, gy: int) -> None:
        if 0 <= gx < GX and 0 <= gy < GY:
            self.img.paste(im, (gx * T, gy * T))

    def stamp(self, spr: Image.Image, gx: int, gy: int) -> None:
        if 0 <= gx < GX and 0 <= gy < GY:
            self.img.alpha_composite(spr, (gx * T, gy * T))

    def fbm(self, size: int, seed: int, octaves: int = 4) -> np.ndarray:
        rng = np.random.default_rng(seed)
        out = np.zeros((size, size), dtype=np.float32)
        amp, total = 1.0, 0.0
        for k in range(octaves):
            n = 2 ** (k + 2)
            base = rng.random((n, n)).astype(np.float32)
            up = np.kron(base, np.ones((size // n + 1, size // n + 1)))[:size, :size]
            out += up * amp
            total += amp
            amp *= 0.5
        out /= total
        return (out - out.min()) / (out.max() - out.min() + 1e-9)

    # ------------------------------------------------------------- 1. terreno
    def paint_ground(self) -> None:
        print("[world] terreno", flush=True)
        rng = self.rng_for(1)
        variants = [grass_tile(self.rng_for(i), i % 3) for i in range(14)]
        if self.terreno:
            self._chao_terreno(variants, rng)
            return
        for gy in range(GY):
            for gx in range(GX):
                self.paste(variants[rng.randrange(len(variants))], gx, gy)
        field = np.kron(self.fbm(64, 7), np.ones((GY // 64 + 1, GX // 64 + 1)))[:GY, :GX]
        for gy in range(GY):
            for gx in range(GX):
                if field[gy, gx] > 0.70 and self.zone[gy, gx] == 0 and not self.water_b[gy, gx]:
                    self.paste(grass_tile(self.rng_for(gx, gy), 1), gx, gy)

    def _chao_terreno(self, variants, rng) -> None:
        """Chao do mundo pintado a partir da classificacao da arte de referencia."""
        # talhoes: cada mancha de lavoura recebe um tipo (verde ou dourado)
        rot_campo, n_campo = ndimage.label(self.terrain == 1, structure=np.ones((3, 3)))
        tipo_campo = {}
        for rid in range(1, n_campo + 1):
            tipo_campo[rid] = 2 if self.rng_for(rid, 61).random() < 0.40 else 1
        for gy in range(GY):
            for gx in range(GX):
                tipo = int(self.terrain[gy, gx])
                if tipo == 6:
                    continue  # agua pintada em paint_water
                if tipo == 1:  # lavoura: talhoes, com carreador de terra a cada 4 tiles
                    rid = int(rot_campo[gy, gx])
                    kind = tipo_campo.get(rid, 1)
                    self.paste(crop_tile(self.rng_for(gx // 2, gy // 2, 61), kind), gx, gy)
                elif tipo == 2:  # areia da margem
                    self.paste(sand_tile(self.rng_for(gx, gy, 63)), gx, gy)
                elif tipo == 3:  # mancha urbana: terra batida, grama e calcada
                    r = self.rng_for(gx // 2, gy // 2, 64).random()
                    if r < 0.38:
                        self.paste(dirt_tile(self.rng_for(gx // 2, gy // 2, 65)), gx, gy)
                    elif r < 0.84:
                        self.paste(variants[self.rng_for(gx // 2, gy // 2, 66).randrange(len(variants))], gx, gy)
                    else:
                        self.paste(stone_tile(self.rng_for(gx // 3, gy // 3, 67)), gx, gy)
                elif tipo == 5:  # serra: chao de rocha
                    self.paste(rocha_tile(self.rng_for(gx // 2, gy // 2, 68)), gx, gy)
                elif tipo == 7:  # eixo viario ja existente na arte
                    self.paste(asphalt_tile(self.rng_for(gx, gy, 69)), gx, gy)
                elif tipo == 4:  # mata: chao escuro de folhagem
                    self.paste(mata_tile(self.rng_for(gx // 2, gy // 2, 70)), gx, gy)
                    if self.rng_for(gx, gy, 71).random() < 0.10:
                        self.paste(grass_tile(self.rng_for(gx, gy, 1), 1), gx, gy)
                else:
                    self.paste(variants[rng.randrange(len(variants))], gx, gy)

    # ----------------------------------------------------------------- 2. agua
    def paint_water(self) -> None:
        print("[world] rio", flush=True)
        wb = self.water_b
        depth = ndimage.distance_transform_edt(wb)
        near = ndimage.distance_transform_edt(~wb)
        beach = (~wb) & (near <= 1.6) & (self.zone == 0)
        for gy in range(GY):
            for gx in range(GX):
                if beach[gy, gx]:
                    self.paste(sand_tile(self.rng_for(gx, gy, 5)), gx, gy)
        for gy in range(GY):
            for gx in range(GX):
                if not wb[gy, gx]:
                    continue
                d = depth[gy, gx]
                lvl = 1 if d < 1.8 else (2 if d < 3.6 else (3 if d < 6.0 else 4))
                self.paste(water_tile(self.rng_for(gx, gy, 9), lvl), gx, gy)
        edge = wb & (~ndimage.binary_erosion(wb, np.ones((2, 2))))
        for gy in range(GY):
            for gx in range(GX):
                if not edge[gy, gx]:
                    continue
                im = water_tile(self.rng_for(gx, gy, 11), 1).copy()
                rng = self.rng_for(gx, gy, 12)
                for x in range(rng.randrange(0, 3), T, 4):
                    _px(im, x, T - 1, C["water_l"] + (255,))
                    _px(im, x + 1, T - 2, C["water_l"] + (255,))
                self.paste(im, gx, gy)
        rng = self.rng_for(3)
        for _ in range(34):
            gy, gx = rng.randrange(24, GY - 10), rng.randrange(8, GX - 8)
            if not wb[gy, gx] or depth[gy, gx] < 2.2:
                continue
            r = rng.choice([1, 1, 1, 2])
            win = depth[max(0, gy - r - 1):gy + r + 2, max(0, gx - r - 1):gx + r + 2]
            if win.size == 0 or win.min() < 1.9:
                continue
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if abs(dx) + abs(dy) <= r:
                        self.paste(sand_tile(self.rng_for(gx + dx, gy + dy)), gx + dx, gy + dy)

    def paint_river_extensions(self) -> None:
        if self.terreno:
            return  # a arte de referencia ja traz o rio de ponta a ponta
        wb = self.water_b
        ys, xs = np.where(wb)
        if not len(xs):
            return
        tail = int(np.argmin(xs * 1.0 + (GY - ys) * 0.55))
        sx, sy = int(xs[tail]), int(ys[tail])
        self._carve(self._curve([(0, min(GY - 2, sy + 16)), (sx * 0.35, sy + 6),
                                 (sx * 0.7, sy + 1), (sx, sy)], 6), 3.2, 0)
        head = int(np.argmax(xs - ys * 0.25))
        ex, ey = int(xs[head]), int(ys[head])
        self._carve(self._curve([(ex, ey), (ex + (GX - ex) * 0.4, ey - 2),
                                 (ex + (GX - ex) * 0.75, ey - 9), (GX - 2, max(5, ey - 15))], 8), 2.6, 1)

    def _carve(self, pts, width: float, seed_off: int) -> None:
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
            for i in range(n + 1):
                t = i / n
                cx, cy = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                for dy in range(-4, 5):
                    for dx in range(-4, 5):
                        if dx * dx + dy * dy > width * width:
                            continue
                        gx, gy = int(round(cx)) + dx, int(round(cy)) + dy
                        if not (0 <= gx < GX and 0 <= gy < GY):
                            continue
                        self.water_b[gy, gx] = True
                        self.water[gy, gx] = 1.0
                        lvl = 4 if (dx * dx + dy * dy) < (width - 1.6) ** 2 else 2
                        self.paste(water_tile(self.rng_for(gx, gy, 21 + seed_off), lvl), gx, gy)
                        for ddy, ddx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                            nx, ny = gx + ddx, gy + ddy
                            if 0 <= nx < GX and 0 <= ny < GY and not self.water_b[ny, nx]:
                                self.paste(sand_tile(self.rng_for(nx, ny, 22)), nx, ny)

    # ------------------------------------------------------------- 3. estradas
    def paint_roads(self) -> None:
        print("[world] estradas", flush=True)
        links = [(1, 2), (1, 5), (1, 6), (1, 7), (1, 8), (2, 5), (3, 5), (3, 4),
                 (4, 5), (4, 6), (4, 10), (5, 6), (6, 9), (6, 10), (7, 8),
                 (8, 14), (8, 19), (9, 10), (10, 14), (10, 17), (14, 13),
                 (13, 16), (13, 12), (12, 15), (15, 18), (15, 19), (16, 17),
                 (16, 18), (18, 12), (11, 4), (20, 2), (1, 19), (4, 17), (3, 11)]
        anchors = {int(k): (int(v["anchor"][0]), int(v["anchor"][1]))
                   for k, v in self.meta["zones"].items()}
        cost = np.ones((GY, GX), dtype=np.float32) + self.water * 30.0
        if self.terreno:
            # as estradas do jogo procuram as avenidas/rodovias que ja existem na arte
            cost = np.where(self.terrain == 7, 0.45, cost)
            cost = np.where(self.terrain == 3, 0.62, cost)
            cost = np.where(self.terrain == 5, 2.20, cost)
            cost = np.where(self.terrain == 4, 1.35, cost)
        for a, b in links:
            if a not in anchors or b not in anchors:
                continue
            path = self._astar(anchors[a], anchors[b], cost)
            if not path:
                continue
            path = self._simplify(path, 1.0)
            path = self._chaikin(path, 2)
            self.roads.append([[round(x, 2), round(y, 2)] for x, y in path])

        mask = np.zeros((GY, GX), dtype=bool)
        for path in self.roads:
            for (x0, y0), (x1, y1) in zip(path, path[1:]):
                n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
                for i in range(n + 1):
                    t = i / n
                    gx, gy = int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t))
                    if 0 <= gx < GX and 0 <= gy < GY:
                        mask[gy, gx] = True
        self.road = mask

        for gy in range(GY):
            for gx in range(GX):
                if not mask[gy, gx]:
                    continue
                if self.water_b[gy, gx]:
                    self.paste(self._bridge_tile(gx, gy), gx, gy)
                    continue
                im = asphalt_tile(self.rng_for(gx, gy, 33))
                h = (gx > 0 and mask[gy, gx - 1]) or (gx < GX - 1 and mask[gy, gx + 1])
                v = (gy > 0 and mask[gy - 1, gx]) or (gy < GY - 1 and mask[gy + 1, gx])
                if h and not v:
                    for x in range(0, T, 8):
                        im.paste((255, 205, 101, 255), (x + 2, 7, x + 6, 9))
                    im.paste((60, 40, 48, 255), (0, 0, T, 1))
                    im.paste((60, 40, 48, 255), (0, T - 1, T, T))
                elif v and not h:
                    for y in range(0, T, 8):
                        im.paste((255, 205, 101, 255), (7, y + 2, 9, y + 6))
                    im.paste((60, 40, 48, 255), (0, 0, 1, T))
                    im.paste((60, 40, 48, 255), (T - 1, 0, T, T))
                else:
                    im.paste((70, 44, 52, 255), (0, 0, T, 1))
                    im.paste((70, 44, 52, 255), (0, T - 1, T, T))
                    im.paste((70, 44, 52, 255), (0, 0, 1, T))
                    im.paste((70, 44, 52, 255), (T - 1, 0, T, T))
                self.paste(im, gx, gy)

    def _bridge_tile(self, gx: int, gy: int) -> Image.Image:
        im = Image.new("RGBA", (T, T), (160, 116, 74, 255))
        for y in range(0, T, 4):
            im.paste((120, 84, 56, 255), (0, y, T, y + 1))
        h = (gx > 0 and self.road[gy, gx - 1]) or (gx < GX - 1 and self.road[gy, gx + 1])
        if h:
            im.paste((92, 64, 44, 255), (0, 0, T, 2))
            im.paste((92, 64, 44, 255), (0, T - 2, T, T))
        else:
            im.paste((92, 64, 44, 255), (0, 0, 2, T))
            im.paste((92, 64, 44, 255), (T - 2, 0, T, T))
        return im

    def _astar(self, start, goal, cost):
        sx, sy = int(start[0]), int(start[1])
        tx, ty = int(goal[0]), int(goal[1])
        openq = [(0.0, (sx, sy))]
        came = {}
        g = {(sx, sy): 0.0}
        dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        while openq:
            _, (x, y) = heapq.heappop(openq)
            if (x, y) == (tx, ty):
                break
            for dx, dy in dirs:
                nx, ny = x + dx, y + dy
                if not (0 <= nx < GX and 0 <= ny < GY):
                    continue
                step = 1.4142 if dx and dy else 1.0
                ng = g[(x, y)] + step * (1.0 + cost[ny, nx])
                if ng < g.get((nx, ny), 1e18):
                    g[(nx, ny)] = ng
                    came[(nx, ny)] = (x, y)
                    heapq.heappush(openq, (ng + math.hypot(nx - tx, ny - ty), (nx, ny)))
        if (tx, ty) not in came and (tx, ty) != (sx, sy):
            return []
        path = [(tx, ty)]
        cur = (tx, ty)
        while cur in came:
            cur = came[cur]
            path.append(cur)
        path.reverse()
        return [(float(x), float(y)) for x, y in path]

    @staticmethod
    def _simplify(pts, eps):
        if len(pts) < 3:
            return pts
        keep = {0, len(pts) - 1}
        stack = [(0, len(pts) - 1)]
        while stack:
            lo, hi = stack.pop()
            if hi <= lo + 1:
                continue
            (x0, y0), (x1, y1) = pts[lo], pts[hi]
            dx, dy = x1 - x0, y1 - y0
            L = math.hypot(dx, dy) or 1e-9
            best, bi = -1, lo
            for i in range(lo + 1, hi):
                d = abs(dy * (pts[i][0] - x0) - dx * (pts[i][1] - y0)) / L
                if d > best:
                    best, bi = d, i
            if best > eps:
                keep.add(bi)
                stack.append((lo, bi))
                stack.append((bi, hi))
        return [pts[i] for i in sorted(keep)]

    @staticmethod
    def _chaikin(pts, iters=1):
        for _ in range(iters):
            if len(pts) < 3:
                return pts
            out = [pts[0]]
            for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
                out.append((x0 * 0.75 + x1 * 0.25, y0 * 0.75 + y1 * 0.25))
                out.append((x0 * 0.25 + x1 * 0.75, y0 * 0.25 + y1 * 0.75))
            out.append(pts[-1])
            pts = out
        return pts

    def _curve(self, pts, steps=6):
        out = []
        for i in range(len(pts) - 1):
            p0 = pts[max(0, i - 1)]
            p1, p2 = pts[i], pts[i + 1]
            p3 = pts[min(len(pts) - 1, i + 2)]
            for s in range(steps):
                t = s / steps
                t2, t3 = t * t, t * t * t
                x = 0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
                y = 0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
                out.append((x, y))
        out.append(tuple(pts[-1]))
        return out

    # -------------------------------------------------------------- 4. vilas
    def build_vilas(self) -> None:
        print("[world] vilas", flush=True)
        anchors = {int(k): v for k, v in self.meta["zones"].items()}
        for zid in sorted(anchors):
            prof = PROFILES.get(zid, "residential")
            if prof in ("core", "urban", "coastal"):
                self._city_blocks(zid, anchors[zid], prof)
            elif prof == "industrial":
                self._industry_blocks(zid, anchors[zid])
            else:
                self._rural_blocks(zid, anchors[zid])
        self._paint_boundaries()

    def _zone_mask(self, zid: int) -> np.ndarray:
        return (self.zone == zid) & (~self.water_b)

    def _city_blocks(self, zid: int, info: dict, prof: str) -> None:
        m = self._zone_mask(zid)
        ys, xs = np.where(m)
        if not len(xs):
            return
        x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
        cx, cy = info["centroid"]
        base = {"gray": 8, "green": 20, "blue": 32, "red": 44, "orange": 56}[PALETTES.get(zid, "green")]
        rng = self.rng_for(zid, 501)
        block = 5 if prof == "core" else 6
        sw = 1

        street = np.zeros_like(m)
        for yy in range(y0, y1 + 1):
            if (yy - y0) % (block + sw) < sw:
                street[yy, x0:x1 + 1] |= m[yy, x0:x1 + 1]
        for xx in range(x0, x1 + 1):
            if (xx - x0) % (block + sw) < sw:
                street[y0:y1 + 1, xx] |= m[y0:y1 + 1, xx]
        street &= m

        for gy in range(y0, y1 + 1):
            for gx in range(x0, x1 + 1):
                if not street[gy, gx]:
                    continue
                self.paste(asphalt_tile(self.rng_for(gx, gy, 55)), gx, gy)
                self.street[gy, gx] = True
                self.blocked[gy, gx] = True

        by0 = y0
        while by0 <= y1:
            bx0 = x0
            while bx0 <= x1:
                self._fill_block(m, bx0, min(bx0 + block - 1, x1), by0, min(by0 + block - 1, y1),
                                 base, rng, prof)
                bx0 += block + sw
            by0 += block + sw

        self._plaza(int(cx), int(cy), rng)
        self._waterfront_trees(m, rng)

    def _fill_block(self, m, bx0, bx1, by0, by1, base, rng, prof) -> None:
        sub = m[by0:by1 + 1, bx0:bx1 + 1]
        if sub.size == 0 or sub.sum() < max(4, sub.size * 0.45):
            return
        if sub.size >= 16 and rng.random() < 0.14:
            for gy in range(by0, by1 + 1):
                for gx in range(bx0, bx1 + 1):
                    if m[gy, gx] and not self.blocked[gy, gx]:
                        self.paste(grass_tile(self.rng_for(gx, gy, 61), 2), gx, gy)
                        if rng.random() < 0.3:
                            self.stamp(self.sheets["town"].t(rng.choice([3, 4, 5, 15, 16, 17])), gx, gy)
                            self.blocked[gy, gx] = True
            return
        for gy in range(by0, by1 + 1):
            for gx in range(bx0, bx1 + 1):
                if not m[gy, gx] or self.blocked[gy, gx]:
                    continue
                edge = (gx in (bx0, bx1)) or (gy in (by0, by1))
                if not edge:
                    if rng.random() < 0.25:
                        self.paste(grass_tile(self.rng_for(gx, gy, 63), 1), gx, gy)
                    continue
                if rng.random() > (0.86 if prof == "core" else 0.7):
                    continue
                roll = rng.random()
                if rng.random() < 0.22:
                    base = base - 12 if base > 12 else base
                if prof == "core":
                    tile = base + 2 if roll < 0.55 else (base + 1 if roll < 0.85 else base)
                elif prof == "urban":
                    tile = base + 2 if roll < 0.28 else (base + 1 if roll < 0.6 else base)
                else:
                    tile = base + 1 if roll < 0.25 else base
                self._place_building(gx, gy, tile)

    def _place_building(self, gx: int, gy: int, tile: int) -> None:
        sh = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((1, 11, T - 1, T - 1), fill=(40, 26, 36, 60))
        self.img.alpha_composite(sh, (gx * T, gy * T + 2))
        self.img.alpha_composite(self.sheets["battle"].t(tile), (gx * T, gy * T))
        self.blocked[gy, gx] = True

    def _plaza(self, cx: int, cy: int, rng) -> None:
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                gx, gy = cx + dx, cy + dy
                if not (0 <= gx < GX and 0 <= gy < GY):
                    continue
                if self.water_b[gy, gx] or self.road[gy, gx]:
                    continue
                self.paste(stone_tile(self.rng_for(gx, gy, 51)), gx, gy)
                self.blocked[gy, gx] = True
        if 0 <= cx < GX and 0 <= cy < GY:
            self.stamp(self.sheets["town"].t(92), cx, cy)
            self.blocked[cy, cx] = True

    def _waterfront_trees(self, m, rng) -> None:
        near_w = ndimage.binary_dilation(self.water_b, np.ones((3, 3))) & m
        ys, xs = np.where(near_w)
        for gy, gx in zip(ys, xs):
            gy, gx = int(gy), int(gx)
            if self.blocked[gy, gx] or self.road[gy, gx]:
                continue
            if rng.random() < 0.30:
                self.stamp(self.sheets["town"].t(rng.choice([4, 5, 16, 17, 20, 21])), gx, gy)
                self.blocked[gy, gx] = True

    def _industry_blocks(self, zid: int, info: dict) -> None:
        m = self._zone_mask(zid)
        ys, xs = np.where(m)
        if not len(xs):
            return
        base = {"gray": 8, "green": 20, "blue": 32, "red": 44, "orange": 56}[PALETTES.get(zid, "gray")]
        rng = self.rng_for(zid, 601)
        x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
        for gy in range(y0, y1 + 1):
            for gx in range(x0, x1 + 1):
                if m[gy, gx] and rng.random() < 0.55:
                    self.paste(dirt_tile(self.rng_for(gx, gy, 71)), gx, gy)
        for gy in range(y0, y1 + 1, 4):
            for gx in range(x0, x1 + 1, 5):
                blk = m[gy:gy + 3, gx:gx + 3]
                if blk.size == 0 or blk.sum() < 6:
                    continue
                if rng.random() < 0.72:
                    self._place_building(gx, gy, base + 3)
                    for dx in (1, 2):
                        if gx + dx < GX and m[gy, gx + dx]:
                            self._place_building(gx + dx, gy, base + 3)
                    if rng.random() < 0.4 and gy + 1 < GY and m[gy + 1, gx]:
                        self._place_building(gx + 1, gy + 1, base)
                elif rng.random() < 0.4:
                    self._place_building(gx, gy, base + 4)
        for _ in range(10):
            gx, gy = rng.randrange(x0, x1 + 1), rng.randrange(y0, y1 + 1)
            if m[gy, gx] and not self.blocked[gy, gx]:
                self.stamp(self.sheets["factory"].t(rng.choice([96, 97, 108, 109])), gx, gy)
                self.blocked[gy, gx] = True

    def _rural_blocks(self, zid: int, info: dict) -> None:
        m = self._zone_mask(zid)
        ys, xs = np.where(m)
        if not len(xs):
            return
        rng = self.rng_for(zid, 701)
        x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
        pw, ph = 4, 3
        for gy in range(y0, y1 + 1, ph + 1):
            for gx in range(x0, x1 + 1, pw + 1):
                sub = m[gy:gy + ph, gx:gx + pw]
                if sub.size == 0 or sub.sum() < sub.size * 0.6 or rng.random() > 0.55:
                    continue
                kind = rng.choices([0, 1, 2], weights=[0.42, 0.36, 0.22])[0]
                for dy in range(ph):
                    for dx in range(pw):
                        y2, x2 = gy + dy, gx + dx
                        if y2 < GY and x2 < GX and m[y2, x2] and not self.blocked[y2, x2]:
                            self.plots[y2, x2] = True
                            self.paste(crop_tile(self.rng_for(x2, y2, 81), kind), x2, y2)
                # cerca nos quatro lados, com abertura virada para a estrada
                for dx in range(-1, pw + 1):
                    for yy in (gy - 1, gy + ph):
                        if 0 <= yy < GY and 0 <= gx + dx < GX and m[yy, gx + dx] and not self.blocked[yy, gx + dx] and not self.road[yy, gx + dx]:
                            self.stamp(self._fence(False), gx + dx, yy)
                            self.blocked[yy, gx + dx] = True
                for dy in range(ph):
                    for xx in (gx - 1, gx + pw):
                        if 0 <= xx < GX and 0 <= gy + dy < GY and m[gy + dy, xx] and not self.blocked[gy + dy, xx] and not self.road[gy + dy, xx]:
                            self.stamp(self._fence(True), xx, gy + dy)
                            self.blocked[gy + dy, xx] = True
        for _ in range(max(4, int(m.sum()) // 140)):
            gx, gy = rng.randrange(x0, x1 + 1), rng.randrange(y0, y1 + 1)
            if not m[gy, gx] or self.blocked[gy, gx] or self.road[gy, gx]:
                continue
            self._farmhouse(gx, gy, rng)
        for _ in range(max(3, int(m.sum()) // 200)):
            gx, gy = rng.randrange(x0, x1 + 1), rng.randrange(y0, y1 + 1)
            if not m[gy, gx] or self.blocked[gy, gx]:
                continue
            self.stamp(self.sheets["farm"].t(rng.choice([120, 121, 122, 108, 109])), gx, gy)
            self.blocked[gy, gx] = True

    def _farmhouse(self, gx: int, gy: int, rng) -> None:
        roof = rng.choice([52, 53, 54, 76, 77, 78])
        wall = rng.choice([72, 73, 75, 80, 81])
        for dy in range(3):
            for dx in range(2):
                if 0 <= gy + dy < GY and 0 <= gx + dx < GX:
                    self.blocked[gy + dy, gx + dx] = True
        sh = Image.new("RGBA", (32, 48), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((2, 36, 29, 47), fill=(40, 26, 36, 55))
        self.img.alpha_composite(sh, (gx * T, gy * T + 2))
        self.stamp(self.sheets["town"].t(roof), gx, gy)
        self.stamp(self.sheets["town"].t(wall), gx, gy + 1)
        self.stamp(self.sheets["town"].t(roof), gx + 1, gy)
        self.stamp(self.sheets["town"].t(wall), gx + 1, gy + 1)
        self.stamp(self.sheets["town"].t(wall), gx, gy + 2)
        self.stamp(self.sheets["town"].t(wall), gx + 1, gy + 2)

    def _fence(self, vertical: bool) -> Image.Image:
        im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        if vertical:
            im.paste(C["wood"] + (255,), (6, 0, 9, T))
            im.paste(C["wood_d"] + (255,), (8, 0, 9, T))
            im.paste(C["wood_d"] + (255,), (5, 3, 10, 4))
        else:
            im.paste(C["wood"] + (255,), (0, 7, T, 10))
            im.paste(C["wood_d"] + (255,), (0, 9, T, 10))
            im.paste(C["wood_d"] + (255,), (3, 6, 4, 11))
        return im

    def _paint_boundaries(self) -> None:
        z = self.zone
        for gy in range(1, GY - 1):
            for gx in range(1, GX - 1):
                a = z[gy, gx]
                if a == 0 or self.blocked[gy, gx] or self.water_b[gy, gx] or self.road[gy, gx]:
                    continue
                for dy, dx in ((1, 0), (0, 1)):
                    b = z[gy + dy, gx + dx]
                    if b != a and b != 0:
                        prof = PROFILES.get(int(a), "residential")
                        if prof in ("core", "urban", "coastal"):
                            self.paste(stone_tile(self.rng_for(gx, gy, 91)), gx, gy)
                        else:
                            self.stamp(self._fence(dx == 0), gx, gy)
                        self.blocked[gy, gx] = True
                        break

    # -------------------------------------------------------- 5. natureza
    def paint_nature(self) -> None:
        print("[world] vegetacao", flush=True)
        if self.terreno:
            self._natureza_terreno()
            return
        forest = np.kron(self.fbm(120, 11, 5), np.ones((GY // 120 + 1, GX // 120 + 1)))[:GY, :GX]
        rng = self.rng_for(97)
        for gy in range(1, GY - 1):
            for gx in range(1, GX - 1):
                if self.blocked[gy, gx] or self.water_b[gy, gx] or self.road[gy, gx]:
                    continue
                z = self.zone[gy, gx]
                border = z > 0 and (self.zone[gy - 1, gx] != z or self.zone[gy + 1, gx] != z
                                    or self.zone[gy, gx - 1] != z or self.zone[gy, gx + 1] != z)
                f = forest[gy, gx]
                if z == 0:
                    p = 0.02 + 0.62 * max(0.0, f - 0.50)
                elif border:
                    p = 0.13
                else:
                    p = 0.006 + 0.05 * max(0.0, f - 0.7)
                if rng.random() > p:
                    continue
                nb = self.blocked[max(0, gy - 1):gy + 2, max(0, gx - 1):gx + 2].sum()
                if z == 0 and nb == 0 and f < 0.6:
                    continue
                self._tree(gx, gy, rng)

        for _ in range(1400):
            gx, gy = rng.randrange(1, GX - 1), rng.randrange(1, GY - 1)
            if self.blocked[gy, gx] or self.water_b[gy, gx] or self.road[gy, gx]:
                continue
            if self.zone[gy, gx] != 0 and rng.random() < 0.6:
                continue
            self.stamp(self.sheets["town"].t(rng.choice([29, 30, 31, 41, 42, 43, 44, 45, 46])), gx, gy)
            self.blocked[gy, gx] = True

    def _natureza_terreno(self) -> None:
        """Vegetacao e mobiliario seguindo as classes de terreno da arte."""
        rng = self.rng_for(97)
        densidade = {4: 0.62, 5: 0.14, 0: 0.05, 3: 0.05, 1: 0.008, 2: 0.0, 7: 0.015}
        # clareiras: a propria classe ja separa mata de campo, mas um ruido
        # quebra a monotonia e cria bosques dentro do campo aberto
        ruido = np.kron(self.fbm(60, 11, 4), np.ones((GY // 60 + 1, GX // 60 + 1)))[:GY, :GX]
        for gy in range(1, GY - 1):
            for gx in range(1, GX - 1):
                if self.blocked[gy, gx] or self.water_b[gy, gx] or self.road[gy, gx]:
                    continue
                tipo = int(self.terrain[gy, gx])
                p = densidade.get(tipo, 0.05)
                if tipo == 0:
                    p = 0.03 + 0.30 * max(0.0, ruido[gy, gx] - 0.55)
                z = self.zone[gy, gx]
                if z > 0:
                    p *= 0.30
                    borda = (self.zone[gy - 1, gx] != z or self.zone[gy + 1, gx] != z
                             or self.zone[gy, gx - 1] != z or self.zone[gy, gx + 1] != z)
                    if borda:
                        p = 0.12
                if rng.random() > p:
                    continue
                if tipo == 4 and self.blocked[max(0, gy - 1):gy + 2, max(0, gx - 1):gx + 2].sum() >= 4:
                    continue
                self._tree(gx, gy, rng)

        # construcoes soltas no chao urbano/rural (fora dos quarteiroes das vilas)
        for _ in range(900):
            gx, gy = rng.randrange(1, GX - 1), rng.randrange(1, GY - 1)
            if self.blocked[gy, gx] or self.water_b[gy, gx] or self.road[gy, gx]:
                continue
            tipo = int(self.terrain[gy, gx])
            if tipo not in (3, 7, 0):
                continue
            if self.zone[gy, gx] != 0 and rng.random() < 0.45:
                continue
            if tipo == 3 and rng.random() < 0.55:
                self.stamp(self.sheets["city"].t(rng.choice([0, 1, 2, 3, 16, 17, 18, 19])), gx, gy)
            else:
                self.stamp(self.sheets["town"].t(rng.choice([29, 30, 31, 41, 42, 43, 44, 45, 46])), gx, gy)
            self.blocked[gy, gx] = True

    def _tree(self, gx: int, gy: int, rng) -> None:
        sh = Image.new("RGBA", (24, 20), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((3, 11, 21, 19), fill=(39, 66, 47, 55))
        self.img.alpha_composite(sh, (gx * T - 4, gy * T + 2))
        self.stamp(self.sheets["town"].t(rng.choice([3, 4, 5, 6, 7, 15, 16, 17, 19, 20, 21, 22, 23])), gx, gy)
        self.blocked[gy, gx] = True
        if rng.random() < 0.28 and gx + 1 < GX and not self.blocked[gy, gx + 1]:
            self.stamp(self.sheets["town"].t(rng.choice([6, 7, 19, 20])), gx + 1, gy)
            self.blocked[gy, gx + 1] = True

    def paint_mountains(self) -> None:
        print("[world] serras", flush=True)
        if self.terreno:
            self._serras_terreno()
            return
        rng = self.rng_for(131)
        for (mx, my, rx, ry, dense) in [(118, 176, 40, 12, 0.86), (58, 5, 34, 9, 0.8),
                                        (176, 14, 30, 11, 0.7), (206, 92, 22, 18, 0.5),
                                        (24, 177, 22, 7, 0.6), (152, 58, 14, 8, 0.45)]:
            for gy in range(max(1, my - ry), min(GY - 1, my + ry)):
                for gx in range(max(1, mx - rx), min(GX - 1, mx + rx)):
                    d = ((gx - mx) / rx) ** 2 + ((gy - my) / ry) ** 2
                    if d > 1.0 or rng.random() > dense * (1.0 - d * 0.7):
                        continue
                    if self.zone[gy, gx] != 0 or self.water_b[gy, gx] or self.road[gy, gx] or self.blocked[gy, gx]:
                        continue
                    self._pico(gx, gy, d, rng)

    def _serras_terreno(self) -> None:
        """Serras onde a arte de referencia mostra relevo (classe 5)."""
        rng = self.rng_for(131)
        dens = ndimage.uniform_filter((self.terrain == 5).astype(np.float32), size=9)
        for gy in range(1, GY - 1):
            for gx in range(1, GX - 1):
                if self.terrain[gy, gx] != 5:
                    continue
                if self.zone[gy, gx] != 0 or self.water_b[gy, gx] or self.road[gy, gx] or self.blocked[gy, gx]:
                    continue
                if rng.random() > 0.12 + 0.85 * dens[gy, gx]:
                    continue
                self._pico(gx, gy, max(0.15, 1.0 - dens[gy, gx]), rng)

    def _pico(self, gx: int, gy: int, d: float, rng) -> None:
        h = int(T * (0.55 + 0.45 * (1 - d)))
        im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        dd = ImageDraw.Draw(im)
        dd.polygon([(0, T), (T // 2, T - h), (T, T)], fill=C["rock_d"] + (255,))
        dd.polygon([(T // 2, T - h), (T, T), (T // 2 + 4, T)], fill=C["rock"] + (255,))
        dd.line([(T // 2, T - h + 2), (T // 2 - 3, T - 3)], fill=C["rock_l"] + (255,))
        dd.line([(T // 2, T - h + 6), (T // 2 + 3, T - 3)], fill=C["stone_dd"] + (255,))
        self.stamp(im, gx, gy)
        self.blocked[gy, gx] = True
        if rng.random() < 0.5 and gy > 1:
            self.stamp(self.sheets["town"].t(rng.choice([3, 4, 15, 16])), gx, gy - 1)


    def paint_landmarks(self) -> None:
        rng = self.rng_for(151)
        depth = ndimage.distance_transform_edt(self.water_b)
        for _ in range(40):
            gy, gx = rng.randrange(10, GY - 10), rng.randrange(6, GX - 6)
            if not self.water_b[gy, gx] or depth[gy, gx] < 2:
                continue
            self.stamp(self.sheets["battle"].t(rng.choice([64, 65, 66, 67, 76, 77, 88, 89, 100, 101, 112])), gx, gy)
        for zid in (1, 7, 8, 19, 2):
            if str(zid) not in self.meta["zones"]:
                continue
            ax, ay = self.meta["zones"][str(zid)]["anchor"]
            done = False
            for r in range(1, 14):
                for dy in range(-r, r + 1):
                    for dx in range(-r, r + 1):
                        gx, gy = ax + dx, ay + dy
                        if 0 <= gx < GX and 0 <= gy < GY and self.water_b[gy, gx]:
                            self.stamp(self.sheets["battle"].t(72), gx, gy)
                            done = True
                            break
                    if done:
                        break
                if done:
                    break

    def compute_boat_route(self) -> None:
        print("[world] rota de barcos", flush=True)
        wb = self.water_b
        if wb.sum() < 50:
            return
        dist = ndimage.distance_transform_edt(wb)
        ys, xs = np.where(wb)
        si = int(np.argmin(xs + (GY - ys) * 0.4))
        ei = int(np.argmax(xs - ys * 0.15))
        start = (int(xs[si]), int(ys[si]))
        goal = (int(xs[ei]), int(ys[ei]))
        openq = [(0.0, start)]
        came = {}
        g = {start: 0.0}
        dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        while openq:
            _, cur = heapq.heappop(openq)
            if cur == goal:
                break
            x, y = cur
            for dx, dy in dirs:
                nx, ny = x + dx, y + dy
                if not (0 <= nx < GX and 0 <= ny < GY) or not wb[ny, nx]:
                    continue
                step = 1.4142 if dx and dy else 1.0
                ng = g[cur] + step * (1.0 + 6.0 / (dist[ny, nx] + 0.4))
                if ng < g.get((nx, ny), 1e18):
                    g[(nx, ny)] = ng
                    came[(nx, ny)] = cur
                    heapq.heappush(openq, (ng + math.hypot(nx - goal[0], ny - goal[1]), (nx, ny)))
        if goal not in came and goal != start:
            return
        path = [goal]
        cur = goal
        while cur in came:
            cur = came[cur]
            path.append(cur)
        path.reverse()
        path = self._simplify([(float(x), float(y)) for x, y in path], 0.7)
        path = self._chaikin(path, 1)
        self.boats.append([[round(x, 2), round(y, 2)] for x, y in path])

    @staticmethod
    def _rle(mask: np.ndarray) -> list:
        """Run-length encoding no formato que VilaRegistry._rle_decode espera."""
        plano = np.asarray(mask, dtype=np.uint8).reshape(-1)
        saida: list = []
        if plano.size == 0:
            return saida
        atual = int(plano[0])
        n = 1
        for valor in plano[1:]:
            v = int(valor)
            if v == atual:
                n += 1
            else:
                saida.append([atual, n])
                atual, n = v, 1
        saida.append([atual, n])
        return saida

    def save(self) -> None:
        os.makedirs(OUT_ART, exist_ok=True)
        os.makedirs(OUT_DATA, exist_ok=True)
        rgb = self.img.convert("RGB")
        rgb.save(os.path.join(OUT_ART, "world_map.png"), optimize=True)
        # chunkes 4x4 para carregamento sob demanda no celular
        cdir = os.path.join(OUT_ART, "world")
        os.makedirs(cdir, exist_ok=True)
        for cy in range(4):
            for cx in range(4):
                box = (cx * W // 4, cy * H // 4, (cx + 1) * W // 4, (cy + 1) * H // 4)
                rgb.crop(box).save(os.path.join(cdir, f"chunk_{cx}_{cy}.png"), optimize=True)
        rgb.resize((W // 4, H // 4), Image.LANCZOS).save(os.path.join(OUT_ART, "world_mini.png"), optimize=True)
        Image.fromarray(self.zone, mode="L").convert("RGB").save(os.path.join(OUT_ART, "zone_map.png"))
        out = {"grid": {"w": GX, "h": GY, "tile": T}, "pixel": {"w": W, "h": H},
               "zones": [], "roads": self.roads, "boats": self.boats,
               "zone_rle": self._rle(self.zone),
               "water_rle": self._rle(self.water_b.astype(np.uint8))}
        for zid in range(1, 21):
            info = self.meta["zones"].get(str(zid))
            if not info:
                continue
            out["zones"].append({
                "id": zid, "name": VILA_NAMES[zid], "profile": PROFILES.get(zid, "residential"),
                "centroid": info["centroid"], "anchor": info["anchor"],
                "bbox": info["bbox"], "area_tiles": info["area_tiles"], "color": info["color"]})
        with open(os.path.join(OUT_DATA, "map_data.json"), "w", encoding="utf-8") as fh:
            json.dump(out, fh, indent=1, ensure_ascii=False)
        print(f"[world] salvo {self.img.width}x{self.img.height} | {len(self.roads)} estradas", flush=True)


def main() -> int:
    terreno = "--terreno" in sys.argv
    wb = WorldBuilder(terreno=terreno)
    wb.paint_ground()
    wb.paint_water()
    wb.paint_river_extensions()
    wb.paint_roads()
    wb.build_vilas()
    wb.paint_nature()
    wb.paint_mountains()
    wb.paint_landmarks()
    wb.compute_boat_route()
    wb.save()
    if "--preview" in sys.argv:
        wb.img.convert("RGB").resize((W // 4, H // 4), Image.LANCZOS).save(
            os.path.join(ROOT, "tools", "world_preview.png"))
        print("[world] preview")
    return 0


if __name__ == "__main__":
    sys.exit(main())
