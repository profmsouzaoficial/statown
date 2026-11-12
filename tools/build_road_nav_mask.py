#!/usr/bin/env python3
"""Deriva a mascara navegavel do trafego a partir da malha original do autor.

`road_mask.png` e o desenho de referencia e nunca e alterado. O jogo consulta
`road_nav_mask.png`, uma versao binaria que:

1. considera estrada todo pixel com luminosidade >= 35;
2. mantem apenas o maior componente conectado (a cidade/BRs sem ilhas soltas);
3. aplica um fechamento morfologico de 1 px para reconectar microfuros de
   antialias nas bordas, sem criar pontes largas entre bairros;
4. mantem apenas o maior componente resultante.

Essa derivacao reproduz exatamente o PNG usado pelo projeto. O fechamento e
deliberadamente pequeno: quem manda no desenho continua sendo a malha anexada.

Uso:
    python3 tools/build_road_nav_mask.py          # grava road_nav_mask.png
    python3 tools/build_road_nav_mask.py --check  # so confere, nao grava

Requer numpy, Pillow e scipy (as mesmas dependencias de
tools/build_traffic_routes.py).
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_closing, label

RAIZ = Path(__file__).resolve().parent.parent
ORIGEM = RAIZ / "assets" / "art" / "road_mask.png"
DESTINO = RAIZ / "assets" / "art" / "road_nav_mask.png"
LIMIAR = 35


def construir() -> np.ndarray:
    img = Image.open(ORIGEM).convert("L")
    estrada = np.asarray(img, dtype=np.uint8) >= LIMIAR
    rotulos, n = label(estrada, structure=np.ones((3, 3)))
    if n < 1:
        raise SystemExit("mascara sem pixels de estrada")
    tamanhos = np.bincount(rotulos.ravel())
    principal = int(np.argmax(tamanhos[1:])) + 1
    if tamanhos[principal] < 1000:
        raise SystemExit("componente principal da mascara pequeno demais")

    malha = rotulos == principal
    malha = binary_closing(malha, structure=np.ones((3, 3)), iterations=1)
    rotulos2, n2 = label(malha, structure=np.ones((3, 3)))
    tamanhos2 = np.bincount(rotulos2.ravel())
    principal2 = int(np.argmax(tamanhos2[1:])) + 1
    return rotulos2 == principal2


def main() -> int:
    nav = construir()
    if "--check" in sys.argv:
        atual = np.asarray(Image.open(DESTINO).convert("L")) >= 127
        if atual.shape != nav.shape:
            print(f"DIVERGE: dimensoes {atual.shape} != {nav.shape}")
            return 1
        diferenca = int(np.count_nonzero(atual != nav))
        print(f"road_nav_mask.png: {atual.shape[1]}x{atual.shape[0]}, "
              f"{int(nav.sum())} px de estrada, {diferenca} px de diferenca")
        return 1 if diferenca else 0
    Image.fromarray((nav.astype(np.uint8) * 255), mode="L").save(DESTINO, optimize=True)
    print(f"gravado {DESTINO} ({DESTINO.stat().st_size} bytes, "
          f"{int(nav.sum())} px de estrada)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
