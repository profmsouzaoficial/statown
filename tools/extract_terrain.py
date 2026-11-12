#!/usr/bin/env python3
"""
StaTown - Extracao do terreno a partir da arte de referencia (Gemini FULL-MAP).

Le a ilustracao `assets/Gemini_Generated_FULL-MAP.jpeg` e classifica cada tile
da grade de jogo (240 x 180) em um dos tipos de terreno que o renderizador
sabe pintar com o vocabulario pixel-art do projeto:

    0 grama      1 lavoura     2 areia      3 cidade
    4 mata       5 serra       6 agua       7 asfalto (eixo viario)

Saidas:
    tools/terrain_ids.png       240x180, cinza, id da classe por tile
    tools/water_mask_base.png   240x180, cinza, 255 = agua
    tools/terrain_preview.png   960x720, conferencia colorida

Uso:
    python3 tools/extract_terrain.py [--abrir]

A classificacao e heuristica (cor + textura + espessura). Os limiares ficam
todos em TUNING, no topo, para facilitar o ajuste olhando o preview.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGEM = os.path.join(ROOT, "assets", "Gemini_Generated_FULL-MAP.jpeg")
OUT_DIR = os.path.join(ROOT, "tools")

GX, GY = 240, 180
AMOSTRA = 10  # pixels de referencia por tile (2400/240 e 1800/180)
SUP_W, SUP_H = GX * AMOSTRA, GY * AMOSTRA

# Cores de conferencia (nao entram no jogo; so no preview).
LEGENDA = {
    0: (132, 198, 105),   # grama
    1: (196, 180, 110),   # lavoura
    2: (234, 215, 170),   # areia
    3: (190, 110, 70),    # cidade
    4: (45, 110, 60),     # mata
    5: (120, 110, 110),   # serra
    6: (60, 180, 230),    # agua
    7: (110, 110, 120),   # asfalto
}
NOMES = {0: "grama", 1: "lavoura", 2: "areia", 3: "cidade", 4: "mata",
         5: "serra", 6: "agua", 7: "asfalto"}

# ---------------------------------------------------------------- limiares
TUNING = {
    "agua_forte": 0.45,       # fracao minima de pixels azuis no tile
    "cidade_forte": 0.40,
    "mata_forte": 0.35,
    "serra_forte": 0.30,
    "lavoura_forte": 0.35,
    "areia_forte": 0.30,
    "asfalto_forte": 0.22,
    "peso_agua": 1.9,
    "peso_cidade": 1.25,
    "peso_mata": 1.15,
    "peso_serra": 1.2,
}


def _hsv(arr: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """H (0-360), S (0-1) e V (0-1) vetorizados (sem cv2)."""
    r, g, b = arr[..., 0] / 255.0, arr[..., 1] / 255.0, arr[..., 2] / 255.0
    mx = np.max(arr, axis=-1) / 255.0
    mn = np.min(arr, axis=-1) / 255.0
    delta = mx - mn
    h = np.zeros_like(mx)
    m = delta > 1e-6
    idx = m & (mx == r)
    h[idx] = (60 * ((g[idx] - b[idx]) / delta[idx])) % 360
    idx = m & (mx == g)
    h[idx] = 60 * ((b[idx] - r[idx]) / delta[idx]) + 120
    idx = m & (mx == b)
    h[idx] = 60 * ((r[idx] - g[idx]) / delta[idx]) + 240
    s = np.where(mx > 1e-6, delta / np.maximum(mx, 1e-6), 0.0)
    return h, s, mx


def classificar_pixels(rgb: np.ndarray) -> np.ndarray:
    """Classifica cada pixel da imagem de referencia (2400x1800)."""
    h, s, v = _hsv(rgb.astype(np.float32))
    lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    r, g, b = rgb[..., 0].astype(np.int16), rgb[..., 1].astype(np.int16), rgb[..., 2].astype(np.int16)
    out = np.zeros(rgb.shape[:2], np.uint8)

    # 6 - agua: azul dominante (rio, lagoas, represas)
    agua = (b > r + 18) & (b > g + 4) & (b > 95) & (s > 0.18)
    # 2 - areia: faixa clara da margem
    areia = (~agua) & (r > 196) & (g > 170) & (b > 128) & (s < 0.36) & (v > 0.72)
    # 4 - mata: verde escuro e saturado
    mata = (~agua) & (h >= 70) & (h <= 165) & (v < 0.52) & (s > 0.28)
    # 0 - grama: verde claro (pasto, capim, campos)
    grama = (~agua) & (~mata) & (h >= 65) & (h <= 165) & (v >= 0.42)
    # 1 - lavoura: amarelo-oliva (soja, milho, pasto seco)
    lavoura = (~agua) & (~mata) & (~grama) & (h >= 32) & (h < 70) & (s > 0.30) & (v > 0.45)
    # 3 - cidade: telhado ceramica (laranja) e construcoes claras
    telhado = (h < 32) & (s > 0.30) & (v > 0.42)
    predio = (s < 0.13) & (v > 0.80)
    cidade = (~agua) & (telhado | predio) & (~mata)
    # 7 - asfalto: cinza dessaturado (rodovias e avenidas)
    asfalto = (~agua) & (s < 0.14) & (v > 0.28) & (v < 0.66)
    # 5 - serra: marrom/cinza sombreado, alta variancia local
    serra = (~agua) & (~mata) & (~cidade) & (~lavoura) & (v < 0.55) & (lum < 145)

    out[grama] = 0
    out[lavoura] = 1
    out[areia] = 2
    out[cidade] = 3
    out[mata] = 4
    out[serra] = 5
    out[agua] = 6
    out[asfalto & ~cidade] = 7
    return out


def main() -> int:
    if not os.path.exists(ORIGEM):
        print(f"[terreno] arte nao encontrada: {ORIGEM}")
        return 1
    src = Image.open(ORIGEM).convert("RGB").resize((SUP_W, SUP_H), Image.LANCZOS)
    rgb = np.asarray(src)
    print(f"[terreno] referencia {src.size[0]}x{src.size[1]} -> grade {GX}x{GY}")

    px = classificar_pixels(rgb)
    # 8 classes devidamente separadas: o dicionario do numpy e rapido o bastante
    blocos = px.reshape(GY, AMOSTRA, GX, AMOSTRA)
    frac = np.zeros((8, GY, GX), np.float32)
    for c in range(8):
        frac[c] = blocos.__eq__(c).mean(axis=(1, 3))
    peso = np.ones(8, np.float32)
    peso[6] = TUNING["peso_agua"]
    peso[3] = TUNING["peso_cidade"]
    peso[4] = TUNING["peso_mata"]
    peso[5] = TUNING["peso_serra"]
    score = frac * peso[:, None, None]
    ids = score.argmax(axis=0).astype(np.uint8)
    confianca = score.max(axis=0)

    # agua so vale com massa suficiente (evita veu azul de sombra/hachura)
    ids[(ids == 6) & (frac[6] < TUNING["agua_forte"])] = 0
    ids[(ids == 3) & (frac[3] < TUNING["cidade_forte"])] = 0
    ids[(ids == 4) & (frac[4] < TUNING["mata_forte"])] = 0
    ids[(ids == 5) & (frac[5] < TUNING["serra_forte"])] = 0
    ids[(ids == 1) & (frac[1] < TUNING["lavoura_forte"])] = 0
    ids[(ids == 2) & (frac[2] < TUNING["areia_forte"])] = 2
    ids[(ids == 7) & (frac[7] < TUNING["asfalto_forte"])] = 0

    # limpeza: fecha buracos de 1 tile e remove ruido sal-e-pimenta
    def majoritario(campo: np.ndarray, iteracoes: int = 1) -> np.ndarray:
        for _ in range(iteracoes):
            votos = np.zeros((8, GY, GX), np.float32)
            um = np.moveaxis(np.eye(8, dtype=np.float32)[campo], -1, 0)  # (8, GY, GX)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    votos += np.roll(np.roll(um, dy, axis=1), dx, axis=2)
            novo = votos.argmax(axis=0).astype(np.uint8)
            # nunca deixa a maioria engolir a agua (rio e a espinha do jogo)
            novo[campo == 6] = 6
            campo = novo
        return campo

    ids = majoritario(ids, 2)

    def limpar_componentes(campo: np.ndarray, classes, minimo: int) -> np.ndarray:
        """Absorve manchas pequenas na classe vizinha dominante."""
        for alvo_classe in classes:
            m = campo == alvo_classe
            rot, n = ndimage.label(m, structure=np.ones((3, 3)))
            if not n:
                continue
            tam = ndimage.sum(m, rot, range(1, n + 1))
            for i, t in enumerate(tam, start=1):
                if t >= minimo:
                    continue
                alvo = rot == i
                viz = ndimage.binary_dilation(alvo, np.ones((3, 3))) & ~alvo
                vals = campo[viz]
                if vals.size:
                    campo[alvo] = np.bincount(vals, minlength=8).argmax()
        return campo

    ids = limpar_componentes(ids, (1, 3, 5), 16)

    # rio: preserva o corpo d'agua principal, remove lagos de 1-2 tiles
    agua = ids == 6
    rotulos, n = ndimage.label(agua)
    if n:
        tamanhos = ndimage.sum(agua, rotulos, range(1, n + 1))
        for i, t in enumerate(tamanhos, start=1):
            if t < 6:
                ids[rotulos == i] = 0
        agua = ids == 6

    # asfalto: mantem so eixos continuos (tira manchas de sombra de 1-3 tiles)
    rot, n = ndimage.label(ids == 7, structure=np.ones((3, 3)))
    if n:
        tamanhos = ndimage.sum(ids == 7, rot, range(1, n + 1))
        for i, t in enumerate(tamanhos, start=1):
            if t < 10:
                ids[rot == i] = 0

    # contagens finais
    cont = {int(k): int(v) for k, v in zip(*np.unique(ids, return_counts=True))}
    print("[terreno] tiles por classe:")
    for k in sorted(cont):
        print(f"        {k} {NOMES[k]:<8} {cont[k]:6d}  ({100.0 * cont[k] / (GX * GY):5.1f}%)")

    Image.fromarray(ids, "L").save(os.path.join(OUT_DIR, "terrain_ids.png"))
    Image.fromarray(np.where(agua, 255, 0).astype(np.uint8), "L").save(
        os.path.join(OUT_DIR, "water_mask_base.png"))

    cor = np.zeros((GY, GX, 3), np.uint8)
    for k, c in LEGENDA.items():
        cor[ids == k] = c
    Image.fromarray(cor).resize((GX * 4, GY * 4), Image.NEAREST).save(
        os.path.join(OUT_DIR, "terrain_preview.png"))
    print(f"[terreno] ok -> tools/terrain_ids.png, tools/water_mask_base.png, tools/terrain_preview.png")
    if "--abrir" in sys.argv:
        os.system(f"xdg-open {os.path.join(OUT_DIR, 'terrain_preview.png')} &")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
