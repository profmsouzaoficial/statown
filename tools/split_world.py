#!/usr/bin/env python3
"""Fatia o mapa-mundi em chunkes (e a camada de decoracao) para o jogo.

O jogo NAO carrega o mapa inteiro de uma vez: ele desenha 16 chunkes de
960x720 (grade 4x4) para gastar pouca memoria no celular. Por isso, depois de
editar a arte a mao, o PNG mestre precisa ser recortado de novo.

Duas fontes possiveis:

  assets/art/world_map.png   3840x2880 RGB   -> assets/art/world/chunk_C_L.png
                                             + assets/art/world_mini.png
  assets/art/decor.png       3840x2880 RGBA  -> assets/art/decor/chunk_C_L.png
                                                 (chunkes vazios sao omitidos)

Uso:
  python3 tools/split_world.py               # mestre -> chunkes + minimapa
  python3 tools/split_world.py --decor       # decoracao -> chunkes de decor
  python3 tools/split_world.py --verificar   # so compara, nao escreve nada
  python3 tools/split_world.py --fonte outro.png

Depois de rodar, no editor do Godot basta apertar F5: o import e automatico.
No build web e preciso exportar de novo (secao 8 do AGENTS.md).
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")

LARG, ALT = 3840, 2880
COLS, LINS = 4, 4
CHUNK_L, CHUNK_A = LARG // COLS, ALT // LINS          # 960x720
MINI_L, MINI_A = 960, 720


def _md5(im: Image.Image) -> str:
    return hashlib.md5(im.tobytes()).hexdigest()[:10]


def _carregar(caminho: str, modo: str) -> Image.Image:
    if not os.path.exists(caminho):
        sys.exit("ERRO: arquivo nao encontrado: %s" % caminho)
    im = Image.open(caminho)
    if im.size != (LARG, ALT):
        sys.exit(
            "ERRO: %s tem %dx%d. O mapa precisa ser %dx%d (240x180 tiles de 16 px).\n"
            "      Se voce redimensionou a imagem, volte ao tamanho original ou\n"
            "      use --fonte com um arquivo 3840x2880."
            % (caminho, im.size[0], im.size[1], LARG, ALT)
        )
    if modo == "RGB":
        if im.mode in ("RGBA", "LA", "P"):
            aviso = "  (aviso: tinha canal alfa; os furos seriam pretos no jogo - achatado sobre branco)"
            print(aviso)
        return im.convert("RGB")
    return im.convert("RGBA")


def _fatias(im: Image.Image):
    for cy in range(LINS):
        for cx in range(COLS):
            box = (cx * CHUNK_L, cy * CHUNK_A, (cx + 1) * CHUNK_L, (cy + 1) * CHUNK_A)
            yield cx, cy, im.crop(box)


def _gravar_chunks(im: Image.Image, pasta: str, prefixo: str, pular_vazios: bool,
                   paleta: bool = False) -> int:
    """Grava os chunkes. Com `paleta`, salva PNG indexado (1 byte/px) usando a
    mesma paleta do mestre - o recorte continua exato, so o arquivo encolhe."""
    os.makedirs(pasta, exist_ok=True)
    ref = None
    if paleta and im.mode == "RGB":
        ref = im.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.NONE)
    escritos = 0
    for cx, cy, pedaco in _fatias(im):
        destino = os.path.join(pasta, "%s_%d_%d.png" % (prefixo, cx, cy))
        vazio = pular_vazios and pedaco.getchannel("A").getextrema()[1] == 0
        if vazio:
            if os.path.exists(destino):
                os.remove(destino)
                print("  chunk_%d_%d  vazio -> removido" % (cx, cy))
            continue
        saida = pedaco.quantize(palette=ref, dither=Image.NONE) if ref is not None else pedaco
        saida.save(destino, optimize=True)
        escritos += 1
        print("  chunk_%d_%d  %s  %6d bytes" % (cx, cy, _md5(pedaco), os.path.getsize(destino)))
    return escritos


def _verificar(im: Image.Image, pasta: str, prefixo: str) -> int:
    diferentes = 0
    for cx, cy, pedaco in _fatias(im):
        destino = os.path.join(pasta, "%s_%d_%d.png" % (prefixo, cx, cy))
        if not os.path.exists(destino):
            print("  chunk_%d_%d  FALTA no disco" % (cx, cy))
            diferentes += 1
            continue
        atual = Image.open(destino).convert(pedaco.mode)
        if _md5(atual) != _md5(pedaco):
            print("  chunk_%d_%d  DIFERENTE (o split nao rodou depois da ultima edicao?)" % (cx, cy))
            diferentes += 1
    return diferentes


def main() -> int:
    ap = argparse.ArgumentParser(description="Fatia o mapa editado a mao em chunkes.")
    ap.add_argument("--fonte", default=None, help="PNG mestre (padrao: world_map.png ou decor.png)")
    ap.add_argument("--decor", action="store_true", help="processa a camada de decoracao (RGBA)")
    ap.add_argument("--verificar", action="store_true", help="apenas compara; nao escreve")
    ap.add_argument("--sem-mini", action="store_true", help="nao regera o minimapa")
    args = ap.parse_args()

    if args.decor:
        fonte = args.fonte or os.path.join(ART, "decor.png")
        pasta = os.path.join(ART, "decor")
        prefixo = "chunk"
        print("DECORACAO: %s" % os.path.relpath(fonte, ROOT))
        im = _carregar(fonte, "RGBA")
        if args.verificar:
            n = _verificar(im, pasta, prefixo)
            print("\n%d chunkes fora de sincronia." % n)
            return 0 if n == 0 else 1
        n = _gravar_chunks(im, pasta, prefixo, pular_vazios=True)
        print("\n%d chunkes de decoracao gravados em %s" % (n, os.path.relpath(pasta, ROOT)))
        if n == 0:
            print("Dica: a imagem esta toda transparente - nada aparece no jogo.")
        return 0

    fonte = args.fonte or os.path.join(ART, "world_map.png")
    pasta = os.path.join(ART, "world")
    print("MAPA: %s" % os.path.relpath(fonte, ROOT))
    im = _carregar(fonte, "RGB")
    if args.verificar:
        n = _verificar(im, pasta, "chunk")
        print("\n%d chunkes fora de sincronia." % n)
        return 0 if n == 0 else 1

    n = _gravar_chunks(im, pasta, "chunk", pular_vazios=False)
    print("\n%d chunkes do mapa gravados em %s" % (n, os.path.relpath(pasta, ROOT)))

    if not args.sem_mini:
        # LANCZOS, igual ao render_world.py: numa reducao de 4x ele preserva
        # estradas finas (o vizinho-mais-proximo faria linhas de 1 px sumirem).
        mini = im.resize((MINI_L, MINI_A), Image.LANCZOS)
        mini = mini.quantize(colors=128, method=Image.MEDIANCUT, dither=Image.NONE)
        destino = os.path.join(ART, "world_mini.png")
        mini.save(destino, optimize=True)
        print("minimapa %dx%d -> %s (%d bytes)"
              % (MINI_L, MINI_A, os.path.relpath(destino, ROOT), os.path.getsize(destino)))

    print("\nPronto. Abra o Godot e aperte F5 (o import e automatico).")
    print("Para o build web: secao 8 do AGENTS.md (reexportar apos a edicao).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
