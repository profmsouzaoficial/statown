#!/usr/bin/env python3
"""
StaTown - Bake da arte definitiva do mapa a partir da ilustracao de referencia.

Pega `assets/Gemini_Generated_FULL-MAP.jpeg` (mapa ilustrado do Vale do Rio
Doce), converte para o padrao do projeto com cara de pixel art:

  1. reduz para 1920x1440 com LANCZOS (media de cor, sem serrilhado)
  2. quantiza para 96 cores (MEDIANCUT, sem dithering -> blocos chapados)
  3. amplia x2 com NEAREST -> 3840x2880 (cada "pixel de arte" = 2x2 px)

Depois desenha as rotas do jogo (extraidas do proprio asfalto da arte) como
linhas finas, calcula a rota dos barcos no rio e grava tudo:

    assets/art/world_map.png            3840x2880 RGB
    assets/art/world/chunk_<C>_<L>.png  16 chunkes 960x720
    assets/art/world_mini.png           960x720
    assets/art/zone_map.png             240x180 (ids das vilas)
    data/map_data.json                  zonas, rotas, barcos, RLEs

As rotas saem do esqueleto (Zhang-Suen) dos tiles de asfalto da arte, entao
os carros andam exatamente sobre as ruas desenhadas.

Uso:
    python3 tools/extract_terrain.py      # 1) classifica o terreno
    python3 tools/bake_map.py             # 2) gera arte + dados
    python3 tools/split_world.py --verificar
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_world as rw  # noqa: E402  (reuso das rotinas de mundo)

ROOT = rw.ROOT
ORIGEM = os.path.join(ROOT, "assets", "Gemini_Generated_FULL-MAP.jpeg")
ARTE = os.path.join(ROOT, "assets", "art", "world_map.png")
TERRAIN = os.path.join(ROOT, "tools", "terrain_ids.png")
CORES = 96
MEIO_W, MEIO_H = rw.W // 2, rw.H // 2  # 1920x1440


# ------------------------------------------------------------------ arte
def assar() -> Image.Image:
    """Ilustracao -> PNG 3840x2880 com blocos de 2x2 px."""
    if not os.path.exists(ORIGEM):
        raise SystemExit(f"[bake] arte nao encontrada: {ORIGEM}")
    src = Image.open(ORIGEM).convert("RGB").resize((MEIO_W, MEIO_H), Image.LANCZOS)
    # quantizacao sem dithering: menos cores = leitura "pixel art"
    pequena = src.quantize(colors=CORES, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    grande = pequena.resize((rw.W, rw.H), Image.NEAREST)
    print(f"[bake] arte {src.size[0]}x{src.size[1]} -> {rw.W}x{rw.H} ({CORES} cores, blocos 2x2)")
    return grande.convert("RGBA")


# ------------------------------------------------------- estradas da arte
def _transicoes(p2, p3, p4, p5, p6, p7, p8, p9):
    seq = (p2, p3, p4, p5, p6, p7, p8, p9, p2)
    a = np.zeros_like(p2, dtype=np.uint8)
    for u, v in zip(seq, seq[1:]):
        a += ((u == 0) & (v == 1)).astype(np.uint8)
    return a


def esqueletizar(mask: np.ndarray) -> np.ndarray:
    """Afinamento de Zhang-Suen vetorizado (scipy nao traz skeletonize)."""
    img = mask.astype(np.uint8).copy()
    while True:
        mudou = False
        for passo in (0, 1):
            p = np.pad(img, 1, constant_values=0)
            p2, p3, p4 = p[:-2, 1:-1], p[:-2, 2:], p[1:-1, 2:]
            p5, p6, p7 = p[2:, 2:], p[2:, 1:-1], p[2:, :-2]
            p8, p9 = p[1:-1, :-2], p[:-2, :-2]
            b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
            a = _transicoes(p2, p3, p4, p5, p6, p7, p8, p9)
            if passo == 0:
                r = (p2 * p4 * p6 == 0) & (p4 * p6 * p8 == 0)
            else:
                r = (p2 * p4 * p8 == 0) & (p2 * p6 * p8 == 0)
            remover = (img == 1) & (b >= 2) & (b <= 6) & (a == 1) & r
            if remover.any():
                img[remover] = 0
                mudou = True
        if not mudou:
            return img.astype(bool)


def _vizinhos(p, pts):
    y, x = p
    out = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy == 0 and dx == 0:
                continue
            q = (y + dy, x + dx)
            if q in pts:
                out.append(q)
    return out


def caminhar(skel: np.ndarray) -> list[list[tuple[int, int]]]:
    """Esqueleto -> lista de polilinhas (coordenadas (x, y) em tiles)."""
    pts = {(int(y), int(x)) for y, x in zip(*np.where(skel))}
    if not pts:
        return []
    grau = {p: len(_vizinhos(p, pts)) for p in pts}
    visitadas: set[tuple] = set()

    def chave(a, b):
        return (a, b) if a < b else (b, a)

    def andar(inicio, primeiro):
        caminho = [inicio, primeiro]
        visitadas.add(chave(inicio, primeiro))
        anterior, atual = inicio, primeiro
        while grau.get(atual, 0) == 2:
            nxt = [q for q in _vizinhos(atual, pts) if q != anterior]
            if not nxt:
                break
            seguinte = nxt[0]
            if chave(atual, seguinte) in visitadas:
                break
            visitadas.add(chave(atual, seguinte))
            caminho.append(seguinte)
            anterior, atual = atual, seguinte
        return [(x, y) for (y, x) in caminho]

    rotas = []
    for origem in [p for p in pts if grau[p] != 2]:
        for prox in _vizinhos(origem, pts):
            if chave(origem, prox) not in visitadas:
                rotas.append(andar(origem, prox))
    # aneis fechados (todos os pontos com grau 2)
    for p in pts:
        if grau.get(p) != 2:
            continue
        for prox in _vizinhos(p, pts):
            if chave(p, prox) not in visitadas:
                rotas.append(andar(p, prox))
    return rotas


def estradas_da_arte(terrain: np.ndarray) -> list[list[list[float]]]:
    """Rotas (unidades de tile) seguindo o asfalto desenhado na arte."""
    mask = (terrain == 7)
    mask = ndimage.binary_closing(mask, np.ones((2, 2)))
    mask = ndimage.binary_opening(mask, np.ones((2, 2)))
    skel = esqueletizar(mask)
    brutas = caminhar(skel)
    rotas = []
    for pts in brutas:
        if len(pts) < 4:
            continue
        comp = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:]))
        if comp < 5.0:  # menos de 5 tiles: ruido de texto/sombra
            continue
        pts = rw.WorldBuilder._simplify([(float(x), float(y)) for x, y in pts], 0.55)
        pts = rw.WorldBuilder._chaikin(pts, 2)
        rotas.append([[round(x, 2), round(y, 2)] for x, y in pts])
    print(f"[bake] esqueleto: {len(brutas)} trechos -> {len(rotas)} rotas de carro")
    return rotas


def desenhar_rotas(img: Image.Image, rotas: list) -> None:
    """Reforca as ruas da arte com um traco fino, para o trafego ser legivel."""
    camada = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(camada)
    for rota in rotas:
        if len(rota) < 2:
            continue
        pts = [(p[0] * rw.T, p[1] * rw.T) for p in rota]
        d.line(pts, fill=(46, 42, 52, 70), width=5, joint="curve")
        d.line(pts, fill=(226, 210, 180, 26), width=2, joint="curve")
    img.alpha_composite(camada)


def main() -> int:
    if not os.path.exists(TERRAIN):
        raise SystemExit("[bake] rode antes: python3 tools/extract_terrain.py")
    arte = assar()
    wb = rw.WorldBuilder(terreno=True)
    wb.img = arte
    wb.roads = estradas_da_arte(wb.terrain)
    desenhar_rotas(wb.img, wb.roads)
    # fecha a paleta: ate 256 cores no mestre -> chunkes PNG indexados sem perda
    wb.img = wb.img.convert("RGB").quantize(colors=256, method=Image.MEDIANCUT,
                                            dither=Image.NONE).convert("RGBA")
    wb.compute_boat_route()
    wb.save()
    # minimapa em PNG indexado (128 cores): 1,5 MB -> ~0,47 MB sem diferenca visivel
    final = Image.open(ARTE).convert("RGB")
    mini = final.resize((rw.W // 4, rw.H // 4), Image.LANCZOS)
    mini.quantize(colors=128, method=Image.MEDIANCUT, dither=Image.NONE).save(
        os.path.join(rw.ROOT, "assets", "art", "world_mini.png"), optimize=True)
    print(f"[bake] map_data.json: {len(wb.roads)} rotas, {len(wb.boats)} trecho(s) de barco")
    if "--preview" in sys.argv:
        wb.img.convert("RGB").resize((rw.W // 4, rw.H // 4), Image.LANCZOS).save(
            os.path.join(ROOT, "tools", "world_preview.png"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
