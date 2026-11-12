#!/usr/bin/env python3
"""Baixa do freesound.org os previews CC0 listados em freesound_manifest.json.

Nao usa login: os previews (cdn.freesound.org/previews/...) sao publicos.
Salva o audio cru em assets/audio/raw/<slot>.mp3 e um relatorio com titulo/autor/URL.
"""
import json
import os
import re
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = os.path.join(RAIZ, "assets", "audio", "raw")
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"


def curl(args, timeout=90):
    return subprocess.run(["curl", "-sSL", "-m", str(timeout), "-A", UA] + args,
                          capture_output=True)


def pagina(sid):
    r = curl(["https://freesound.org/s/%d/" % sid, "-o", "-"])
    html = r.stdout.decode("utf-8", "replace")
    mp3 = re.search(r'data-mp3="([^"]+)"', html)
    titulo = re.search(r"<title>([^<]*)</title>", html)
    user = re.search(r'/people/([^/"]+)/sounds/%d/' % sid, html)
    return {
        "mp3": mp3.group(1) if mp3 else "",
        "titulo": (titulo.group(1).split("|")[0].strip() if titulo else ""),
        "autor": user.group(1) if user else "",
        "url": "https://freesound.org/s/%d/" % sid,
    }


def main():
    man = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "freesound_manifest.json")))
    os.makedirs(RAW, exist_ok=True)
    relatorio = []
    for s in man["sons"]:
        slot, sid = s["slot"], s["id"]
        dest = os.path.join(RAW, slot + ".mp3")
        if os.path.exists(dest) and os.path.getsize(dest) > 20000:
            print("ja existe:", slot)
        else:
            info = pagina(sid)
            if not info["mp3"]:
                print("SEM PREVIEW:", slot, sid)
                continue
            hq = info["mp3"].replace("-lq.mp3", "-hq.mp3")
            r = curl([hq, "-o", dest, "--max-filesize", "12000000"], timeout=120)
            if not os.path.exists(dest) or os.path.getsize(dest) < 20000:
                print("FALHOU:", slot, r.returncode, hq)
                continue
            print("baixado: %-14s %7d bytes  %s" % (slot, os.path.getsize(dest), info["titulo"]))
            info["slot"] = slot
            info["id"] = sid
            info["uso"] = s["uso"]
            relatorio.append(info)
    if relatorio:
        with open(os.path.join(RAW, "creditos.json"), "w") as f:
            json.dump(relatorio, f, ensure_ascii=False, indent=1)
    print("ok:", len(relatorio), "novos")


if __name__ == "__main__":
    sys.exit(main())
