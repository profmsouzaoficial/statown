#!/usr/bin/env python3
"""Deriva os sprites jogaveis das folhas de arte anexadas.

Entradas (mestras, fora do build):
  assets/art/source/gliders_sheet.png      5 linhas x 8 colunas
  assets/art/source/paragliders_sheet.png  3 linhas x 4 colunas
  assets/art/source/trucks_sheet.png       5 linhas x 8 colunas (8 direcoes)
  assets/art/source/hospitals_sheet.png    edificios de saude

Saidas:
  assets/art/gliders/delta_*.png           bico para cima
  assets/art/gliders/parapente_*.png       bico para cima
  assets/art/vehicles/truck_<cor>_<0..7>.png
  assets/art/sprites/hospital_*.png

A limpeza de fundo e flood fill a partir das bordas: sombras e asfalto dos
estacionamentos, que sao mais escuros que o fundo, permanecem.
"""
from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

RAIZ = Path(__file__).resolve().parent.parent
ORIGEM = RAIZ / "assets" / "art" / "source"
DIR_ASAS = RAIZ / "assets" / "art" / "gliders"
DIR_VEIC = RAIZ / "assets" / "art" / "vehicles"
DIR_SPR = RAIZ / "assets" / "art" / "sprites"

CORES_DELTA = ["azul", "vermelho", "verde", "laranja", "roxo"]
CORES_PARA = ["vermelho", "azul", "amarelo"]
CORES_CAMINHAO = ["vermelho", "amarelo", "azul", "verde", "marrom"]


def limpar_fundo(im: Image.Image, tol: int = 14) -> Image.Image:
    """Remove o fundo cinza conectado as bordas, preservando sombras."""
    rgba = im.convert("RGBA")
    arr = np.asarray(rgba).copy()
    h, w = arr.shape[:2]
    rgb = arr[:, :, :3].astype(np.int16)
    # cor de fundo = mediana dos quatro cantos
    cantos = np.concatenate([rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]])
    fundo = np.median(cantos.reshape(-1, 3), axis=0)
    perto = np.max(np.abs(rgb - fundo), axis=2) <= tol
    visto = np.zeros((h, w), dtype=bool)
    fila = deque()
    for x in range(w):
        for y in (0, h - 1):
            if perto[y, x] and not visto[y, x]:
                visto[y, x] = True
                fila.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if perto[y, x] and not visto[y, x]:
                visto[y, x] = True
                fila.append((y, x))
    while fila:
        y, x = fila.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visto[ny, nx] and perto[ny, nx]:
                visto[ny, nx] = True
                fila.append((ny, nx))
    arr[:, :, 3][visto] = 0
    saida = Image.fromarray(arr, "RGBA")
    caixa = saida.getbbox()
    if caixa:
        saida = saida.crop(caixa)
    return saida


def recortar_celula(im: Image.Image, col: int, row: int, cols: int, rows: int):
    w, h = im.size
    x0, y0 = round(col * w / cols), round(row * h / rows)
    x1, y1 = round((col + 1) * w / cols), round((row + 1) * h / rows)
    return im.crop((x0, y0, x1, y1))


def centralizar(im: Image.Image, lado: int = 120) -> Image.Image:
    tela = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    x = (lado - im.width) // 2
    y = (lado - im.height) // 2
    tela.alpha_composite(im, (x, y))
    return tela


def main() -> None:
    DIR_ASAS.mkdir(parents=True, exist_ok=True)
    DIR_VEIC.mkdir(parents=True, exist_ok=True)
    DIR_SPR.mkdir(parents=True, exist_ok=True)

    # --- asas delta: coluna 1 = bico para cima -----------------------------
    folha = Image.open(ORIGEM / "gliders_sheet.png")
    for row, cor in enumerate(CORES_DELTA):
        cel = recortar_celula(folha, 0, row, 8, 5)
        spr = limpar_fundo(cel)
        spr.save(DIR_ASAS / f"delta_{cor}.png")
        print("asa", cor, spr.size)

    # --- parapentes: coluna 1 = bico para cima ----------------------------
    folha = Image.open(ORIGEM / "paragliders_sheet.png")
    for row, cor in enumerate(CORES_PARA):
        cel = recortar_celula(folha, 0, row, 4, 3)
        spr = limpar_fundo(cel)
        spr.save(DIR_ASAS / f"parapente_{cor}.png")
        print("parapente", cor, spr.size)

    # --- caminhoes: 8 direcoes (N, NE, E, SE, S, SW, W, NW) ----------------
    folha = Image.open(ORIGEM / "trucks_sheet.png")
    for row, cor in enumerate(CORES_CAMINHAO):
        for col in range(8):
            cel = recortar_celula(folha, col, row, 8, 5)
            spr = centralizar(limpar_fundo(cel), 120)
            spr.save(DIR_VEIC / f"truck_{cor}_{col}.png")
        print("caminhao", cor, "8 direcoes")

    # --- hospitais: recortes fixos da folha -------------------------------
    folha = Image.open(ORIGEM / "hospitals_sheet.png")
    recortes = {
        "hospital_regional": (20, 8, 480, 305),
        "hospital_geral": (520, 8, 968, 214),
        "clinica": (478, 205, 700, 345),
        "upa": (720, 208, 870, 342),
        "hospital_campanha": (15, 365, 300, 492),
    }
    for nome, caixa in recortes.items():
        spr = limpar_fundo(folha.crop(caixa))
        spr.save(DIR_SPR / f"{nome}.png")
        print(nome, spr.size)


if __name__ == "__main__":
    main()
