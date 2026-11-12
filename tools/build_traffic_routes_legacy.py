#!/usr/bin/env python3
"""Gera rotas de trafego seguindo o asfalto cinza do mapa.

O `map_data.json` atual guarda 20 fragmentos de esqueleto (5-15 tiles cada),
curtos demais para o trafego: os carros balancavam de um lado para o outro e
pareciam parados. Este utilitario traca rotas longas por A* sobre o custo da
arte (asfalto barato, predios caros, agua proibida) e grava
`data/traffic_routes.json`.

Uso:
    python3 tools/build_traffic_routes.py
"""
from __future__ import annotations

import heapq
import json
import math
import os
from pathlib import Path

import numpy as np
from PIL import Image

RAIZ = Path(__file__).resolve().parent.parent
MAPA = RAIZ / "assets" / "art" / "world_map.png"
DADOS = RAIZ / "data" / "map_data.json"
SAIDA = RAIZ / "data" / "traffic_routes.json"

W, H = 240, 180

# Cores centrais do asfalto na paleta do bake (amostradas nas rotas antigas).
ASFALTO = np.array([
    [115, 118, 112], [133, 137, 127], [111, 108, 101], [123, 123, 119],
    [126, 127, 119], [142, 144, 132], [109, 111, 106], [96, 97, 96],
    [123, 118, 109], [134, 132, 125],
], dtype=float)


def carregar_mapa():
    im = Image.open(MAPA).convert("RGB").resize((W, H), Image.NEAREST)
    return np.asarray(im, dtype=np.int16)


def custo_terreno(rgb: np.ndarray) -> np.ndarray:
    """Custo por tile: 1 asfalto, 4 chao, 25 mata, 70 predio."""
    d = np.min(np.abs(rgb[:, :, None, :] - ASFALTO[None, None, :, :]).sum(3), axis=2)
    custo = np.full((H, W), 4.0)
    custo[d < 18] = 1.0
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    # telhados laranja/avermelhados: nao cortar quarteiroes
    predio = (r > 145) & (r > g + 25) & (g > b + 10)
    custo[predio] = 70.0
    # mata fechada: desvio caro, mas possivel em ultimo caso
    mata = (g > r + 12) & (g > b + 12) & (g < 145)
    custo[mata] = 25.0
    # areia/grama clara: chao barato
    return custo


def decodificar_rle(rle):
    out = np.zeros(W * H, dtype=np.uint8)
    pos = 0
    for valor, n in rle:
        out[pos:pos + n] = int(valor)
        pos += int(n)
    return out.reshape(H, W)


def astar(custo: np.ndarray, inicio, fim):
    """A* 8-vizinhos; devolve lista de (x,y) em tiles."""
    sx, sy = inicio
    tx, ty = fim
    if not (0 <= sx < W and 0 <= sy < H and 0 <= tx < W and 0 <= ty < H):
        return []
    if custo[ty, tx] >= 1e5 or custo[sy, sx] >= 1e5:
        return []
    aberto = [(0.0, 0.0, sx, sy)]
    veio = {}
    g = {(sx, sy): 0.0}
    while aberto:
        _, gc, x, y = heapq.heappop(aberto)
        if (x, y) == (tx, ty):
            caminho = [(x, y)]
            while (x, y) in veio:
                x, y = veio[(x, y)]
                caminho.append((x, y))
            caminho.reverse()
            return caminho
        if gc > g.get((x, y), 1e18) + 1e-9:
            continue
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1),
                       (-1, -1), (-1, 1), (1, -1), (1, 1)):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < W and 0 <= ny < H):
                continue
            base = custo[ny, nx]
            if base >= 1e5:
                continue
            passo = math.hypot(dx, dy) * base
            ng = gc + passo
            if ng + 1e-9 < g.get((nx, ny), 1e18):
                g[(nx, ny)] = ng
                veio[(nx, ny)] = (x, y)
                h = math.hypot(tx - nx, ty - ny)
                heapq.heappush(aberto, (ng + h, ng, nx, ny))
    return []


def simplificar(pts, tol=0.35):
    """Douglas-Peucker simples."""
    if len(pts) < 3:
        return pts
    a, b = np.asarray(pts[0]), np.asarray(pts[-1])
    ab = b - a
    n = np.linalg.norm(ab)
    if n < 1e-6:
        d = [np.linalg.norm(np.asarray(p) - a) for p in pts]
    else:
        d = [abs(np.cross(ab, np.asarray(p) - a)) / n for p in pts]
    idx = int(np.argmax(d))
    if d[idx] > tol:
        esq = simplificar(pts[:idx + 1], tol)
        dir = simplificar(pts[idx:], tol)
        return esq[:-1] + dir
    return [pts[0], pts[-1]]


def chaikin(pts, iteracoes=2):
    for _ in range(iteracoes):
        novo = []
        for a, b in zip(pts, pts[1:]):
            novo.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            novo.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        pts = novo
    return pts


def rota(custo, waypoints, fechar=False):
    if fechar:
        waypoints = list(waypoints) + [waypoints[0]]
    partes = []
    for a, b in zip(waypoints, waypoints[1:]):
        trecho = astar(custo, a, b)
        if not trecho:
            raise SystemExit(f"sem caminho entre {a} e {b}")
        partes.extend(trecho if not partes else trecho[1:])
    # remove duplicados consecutivos
    limpo = []
    for p in partes:
        if not limpo or limpo[-1] != p:
            limpo.append(p)
    suave = chaikin([(float(x), float(y)) for x, y in limpo], 2)
    suave = simplificar(suave, 0.30)
    return [[round(x, 2), round(y, 2)] for x, y in suave]


def main():
    rgb = carregar_mapa()
    custo = custo_terreno(rgb)
    dados = json.load(open(DADOS, encoding="utf-8"))
    agua = decodificar_rle(dados["water_rle"])
    # Pontes: o asfalto sobre o rio continua sendo passagem. Sem isso o A*
    # considerava a ponte "agua" e nenhuma rota cruzava para a outra margem.
    d = np.min(np.abs(rgb[:, :, None, :] - ASFALTO[None, None, :, :]).sum(3), axis=2)
    ponte = (agua != 0) & (d < 18)
    # A ponte tem 1-2 tiles de largura e o esqueleto nao chega ate ela:
    # abre uma faixa curta de acesso em volta dos tiles de asfalto sobre o rio.
    acesso = np.zeros_like(ponte)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            acesso |= np.roll(np.roll(ponte, dy, axis=0), dx, axis=1)
    custo[agua != 0] = 1e6
    custo[acesso & (agua != 0)] = 2.5

    # Pontos de referencia: foram escolhidos sobre as avenidas visiveis na arte.
    centros = {
        "centro_norte": ([(83, 55), (94, 51), (104, 48), (114, 51), (122, 57),
                          (119, 64), (110, 68), (100, 72), (91, 68), (85, 61)], True),
        "centro_sul": ([(84, 66), (89, 75), (94, 82), (99, 78), (101, 72),
                        (108, 68), (106, 74), (101, 80), (96, 84), (90, 80)], True),
        "avenida_norte": ([(97, 49), (108, 46), (120, 43), (133, 40), (146, 37),
                           (160, 30), (172, 29), (180, 28), (193, 28), (208, 28),
                           (222, 33), (234, 42), (239, 50)], False),
        "br_oeste": ([(64, 0), (59, 14), (54, 29), (49, 46), (44, 65), (38, 84),
                      (31, 103), (24, 122), (16, 143), (11, 153), (8, 158)], False),
        "br_sul": ([(92, 77), (98, 89), (103, 102), (107, 117), (112, 133),
                    (119, 149), (126, 164), (132, 178)], False),
    }

    rotas = {}
    for nome, (waypoints, fechar) in centros.items():
        pts = rota(custo, waypoints, fechar)
        if len(pts) < 8:
            raise SystemExit(f"rota curta demais: {nome}")
        comp = sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))
        rotas[nome] = {"pontos": pts, "fechada": fechar,
                       "comprimento_tiles": round(comp, 1)}
        print(f"{nome:14s} {len(pts):3d} pts  {comp:6.1f} tiles  {pts[:3]}")

    saida = {
        "nota": "Rotas de trafego tracadas por A* sobre o asfalto da arte. "
                "As ruas curtas de map_data.json ficam como dados historicos.",
        "rotas": rotas,
        "carros": ["centro_norte", "centro_sul", "avenida_norte", "br_oeste", "br_sul"],
        "caminhoes": ["avenida_norte", "br_oeste", "br_sul"],
    }
    SAIDA.write_text(json.dumps(saida, ensure_ascii=False, indent=1) + "\n",
                     encoding="utf-8")
    print("ok:", SAIDA, f"({SAIDA.stat().st_size} bytes)")

    # mapa de conferencia: rotas sobre a arte
    base = Image.open(MAPA).convert("RGB").resize((W, H), Image.NEAREST).resize((960, 720), Image.NEAREST)
    from PIL import ImageDraw
    dr = ImageDraw.Draw(base)
    cores = [(255, 60, 60), (60, 255, 80), (255, 220, 50), (80, 180, 255), (255, 100, 255)]
    for i, (nome, r) in enumerate(rotas.items()):
        pts = [(x * 4, y * 4) for x, y in r["pontos"]]
        dr.line(pts, fill=cores[i % len(cores)], width=3)
    base.save("/tmp/traffic_routes.png")


if __name__ == "__main__":
    main()
