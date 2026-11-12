#!/usr/bin/env python3
"""Gera as rotas de trafego dentro da mascara de rodovias do StaTown.

A fonte de verdade e `assets/art/road_nav_mask.png`, derivada da malha
original (`road_mask.png`) com fechamento de 1 px para reconectar microfuros de
antialias. O fechamento nao cria atalhos entre bairros. O A* percorre somente os
pixels dessa malha; a simplificacao so aceita
um segmento reto quando ele inteiro esta na estrada. Se uma curva nao puder
ser cortada, o script mantem o caminho denso do A* naquele trecho.

Uso (nesta ordem, se a malha original mudar):
    python3 tools/build_road_nav_mask.py
    python3 tools/build_traffic_routes.py

Saidas:
    data/traffic_routes.json   rotas de carros e caminhoes
    /tmp/traffic_routes.png    conferencia visual opcional
"""
from __future__ import annotations

import heapq
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, label

RAIZ = Path(__file__).resolve().parent.parent
MASCARA = RAIZ / "assets" / "art" / "road_nav_mask.png"
SAIDA = RAIZ / "data" / "traffic_routes.json"
CONFERENCIA = Path("/tmp/traffic_routes.png")

WT, HT = 240, 180          # mundo em tiles
TILE = 16.0
MIN_COMPONENTE = 1         # a malha principal e o componente 1; ver validacao

# Pontos de referencia das vias. Foram mantidos do gerador antigo para que o
# centro, a avenida norte e as BRs continuem com o mesmo desenho urbano.
ROTAS = {
    "centro_norte": {
        "fechada": True,
        "pontos": [(83, 55), (94, 51), (104, 48), (114, 51), (122, 57),
                   (119, 64), (110, 68), (100, 72), (91, 68), (85, 61)],
    },
    "centro_sul": {
        "fechada": True,
        "pontos": [(84, 66), (89, 75), (94, 82), (99, 78), (101, 72),
                   (108, 68), (106, 74), (101, 80), (96, 84), (90, 80)],
    },
    "avenida_norte": {
        "fechada": False,
        "pontos": [(97, 49), (108, 46), (120, 43), (133, 40), (146, 37),
                   (160, 30), (172, 29), (180, 28), (193, 28), (208, 28),
                   (222, 33), (234, 42), (239, 50)],
    },
    # A BR oeste original tinha pontos numa alca desconectada da malha. Os
    # pontos isolados foram removidos; o caminho usa a componente principal.
    "br_oeste": {
        "fechada": False,
        "pontos": [(64, 0), (59, 14), (54, 29), (49, 46), (44, 65),
                   (24, 122), (16, 143), (11, 153), (8, 158)],
    },
    "br_sul": {
        "fechada": False,
        "pontos": [(92, 77), (98, 89), (103, 102), (107, 117), (112, 133),
                   (119, 149), (126, 164), (132, 178)],
    },
}

VIZINHOS = [
    (-1, -1, math.sqrt(2)), (0, -1, 1), (1, -1, math.sqrt(2)),
    (-1, 0, 1), (1, 0, 1),
    (-1, 1, math.sqrt(2)), (0, 1, 1), (1, 1, math.sqrt(2)),
]


def preparar_mascara():
    img = Image.open(MASCARA).convert("L")
    w, h = img.size
    arr = np.asarray(img, dtype=np.uint8)
    road = arr >= 35
    lab, n = label(road, structure=np.ones((3, 3)))
    if n < 1:
        raise SystemExit("mascara sem pixels de estrada")
    sizes = np.bincount(lab.ravel())
    principal = int(np.argmax(sizes[1:])) + 1
    if sizes[principal] < 1000:
        raise SystemExit("componente principal da mascara pequeno demais")

    malha = lab == principal
    dist = distance_transform_edt(~malha)
    vizinho = distance_transform_edt(~malha, return_distances=False, return_indices=True)
    return w, h, arr, road, malha, dist, vizinho


class Gerador:
    def __init__(self, w, h, road, malha, dist, vizinho):
        self.w, self.h = w, h
        self.road = road
        self.malha = malha
        self.dist = dist
        self.vizinho = vizinho
        self.cache = {}

    def snap(self, tile):
        x = int(np.clip(round(tile[0] / WT * self.w), 0, self.w - 1))
        y = int(np.clip(round(tile[1] / HT * self.h), 0, self.h - 1))
        if self.malha[y, x]:
            return x, y
        ny, nx = self.vizinho[0, y, x], self.vizinho[1, y, x]
        return int(nx), int(ny)

    def astar(self, start, goal):
        sx, sy = start
        gx, gy = goal
        if not self.malha[sy, sx] or not self.malha[gy, gx]:
            return None
        if (sx, sy) == (gx, gy):
            return [(sx, sy)]
        chave = (start, goal)
        # O caminho de ida e volta nao e simetrico por causa do custo de centro,
        # mas o custo extra de recachear um trajeto inteiro nao compensa.
        if chave in self.cache:
            return list(self.cache[chave])

        def centro(x, y):
            return 1.0 + 2.4 * max(0.0, 2.8 - self.dist[y, x])

        abertos = [(0.0, 0.0, sx, sy)]
        veio = {}
        g = {(sx, sy): 0.0}
        while abertos:
            _, gc, x, y = heapq.heappop(abertos)
            if (x, y) == (gx, gy):
                caminho = [(x, y)]
                while caminho[-1] in veio:
                    caminho.append(veio[caminho[-1]])
                caminho.reverse()
                self.cache[chave] = caminho
                return caminho
            if gc > g.get((x, y), 1e30) + 1e-9:
                continue
            for dx, dy, base in VIZINHOS:
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= self.w or ny >= self.h:
                    continue
                if not self.malha[ny, nx]:
                    continue
                if dx and dy and not (self.malha[y, x + dx] and self.malha[y + dy, x]):
                    continue
                ng = gc + base * centro(nx, ny)
                if ng < g.get((nx, ny), 1e30) - 1e-9:
                    g[(nx, ny)] = ng
                    veio[(nx, ny)] = (x, y)
                    h = math.hypot(gx - nx, gy - ny)
                    heapq.heappush(abertos, (ng + h * 0.97, 0.0, nx, ny))
        return None

    def segmento_na_estrada(self, p, q):
        dx, dy = q[0] - p[0], q[1] - p[1]
        n = max(2, int(math.hypot(dx, dy) * 4.0))
        for i in range(n + 1):
            t = i / n
            x = int(round(p[0] + dx * t))
            y = int(round(p[1] + dy * t))
            if x < 0 or y < 0 or x >= self.w or y >= self.h or not self.malha[y, x]:
                return False
        return True

    def simplificar(self, caminho):
        n = len(caminho)
        indices = [0]
        i = 0
        while i < n - 1:
            melhor = i + 1
            for k in range(min(n - 1, i + 70), i, -2):
                if k <= i + 1 or self.segmento_na_estrada(caminho[i], caminho[k]):
                    melhor = k
                    break
            if melhor == i + 1:
                for k in range(min(n - 1, i + 8), i + 1, -1):
                    if self.segmento_na_estrada(caminho[i], caminho[k]):
                        melhor = k
                        break
            indices.append(melhor)
            i = melhor

        saida = []
        for k in range(len(indices) - 1):
            a, b = indices[k], indices[k + 1]
            if self.segmento_na_estrada(caminho[a], caminho[b]):
                if not saida or saida[-1] != caminho[a]:
                    saida.append(caminho[a])
                saida.append(caminho[b])
            else:
                # Nao corte a esquina: use o caminho denso do A*, que anda
                # pixel a pixel dentro da malha.
                trecho = caminho[a:b + 1]
                if saida and trecho and saida[-1] == trecho[0]:
                    trecho = trecho[1:]
                saida.extend(trecho)
        limpo = []
        for p in saida:
            if not limpo or limpo[-1] != p:
                limpo.append(p)
        return limpo

    def rota(self, pontos, fechada):
        ancoras = []
        for t in pontos:
            p = self.snap(t)
            if not ancoras or p != ancoras[-1]:
                ancoras.append(p)
        if fechada:
            ancoras.append(ancoras[0])
        cheio = []
        for i in range(len(ancoras) - 1):
            trecho = self.astar(ancoras[i], ancoras[i + 1])
            if trecho is None:
                raise SystemExit(f"sem caminho na mascara: {ancoras[i]} -> {ancoras[i + 1]}")
            if cheio and cheio[-1] == trecho[0]:
                trecho = trecho[1:]
            cheio.extend(trecho)
        simples = self.simplificar(cheio)
        pts = [[round(x / self.w * WT, 2), round(y / self.h * HT, 2)] for x, y in simples]
        comp = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
        maxdist = 0.0
        fora = 0
        total = 0
        for i in range(len(pts) - 1):
            p0 = np.array(pts[i])
            p1 = np.array(pts[i + 1])
            n = max(2, int(np.linalg.norm((p1 - p0) * np.array([self.w / WT, self.h / HT])) * 4))
            for t in np.linspace(0, 1, n):
                p = p0 + (p1 - p0) * t
                x = int(np.clip(round(p[0] / WT * self.w), 0, self.w - 1))
                y = int(np.clip(round(p[1] / HT * self.h), 0, self.h - 1))
                total += 1
                if not self.malha[y, x]:
                    fora += 1
                maxdist = max(maxdist, float(self.dist[y, x]))
        if fora / max(total, 1) > 0.02:
            raise SystemExit(f"rota ainda sai da mascara: {fora}/{total}")
        return {
            "fechada": fechada,
            "pontos": pts,
            "comprimento_tiles": round(comp, 1),
            "_maxdist": round(maxdist, 2),
        }


def main():
    w, h, _, road, malha, dist, vizinho = preparar_mascara()
    print(f"mascara {w}x{h}: {int(road.sum())} px de estrada; malha principal {int(malha.sum())} px")
    gerador = Gerador(w, h, road, malha, dist, vizinho)
    rotas = {}
    for nome, cfg in ROTAS.items():
        r = gerador.rota(cfg["pontos"], bool(cfg["fechada"]))
        maxdist = r.pop("_maxdist")
        rotas[nome] = r
        print(f"{nome:14s} {len(r['pontos']):3d} pts  {r['comprimento_tiles']:7.1f} tiles  maxdist {maxdist}")

    saida = {
        "nota": "Rotas geradas por A* sobre assets/art/road_nav_mask.png, derivada da malha original com fechamento de 1 px. A simplificacao so aceita segmentos inteiros dentro da malha; o WorldView valida a rota e a posicao do veiculo de novo em tempo de execucao.",
        "rotas": rotas,
        "carros": ["centro_norte", "centro_sul", "avenida_norte", "br_oeste", "br_sul"],
        "caminhoes": ["avenida_norte", "br_oeste", "br_sul"],
    }
    SAIDA.write_text(json.dumps(saida, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    base = Image.open(MASCARA).convert("RGB")
    dr = ImageDraw.Draw(base)
    cores = [(255, 60, 60), (60, 255, 80), (255, 220, 50), (80, 180, 255), (255, 100, 255)]
    for i, (nome, r) in enumerate(rotas.items()):
        pp = [(x / WT * w, y / HT * h) for x, y in r["pontos"]]
        dr.line(pp, fill=cores[i % len(cores)], width=2)
        if pp:
            dr.text((pp[0][0] + 4, pp[0][1] + 4), nome, fill=cores[i % len(cores)])
    base.save(CONFERENCIA)
    print(f"ok: {SAIDA} ({SAIDA.stat().st_size} bytes); conferencia {CONFERENCIA}")


if __name__ == "__main__":
    main()
