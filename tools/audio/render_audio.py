#!/usr/bin/env python3
"""Gera a trilha sonora do StaTown (procedural) e processa os sons do freesound.

Filosofia: a MUSICA e sintetizada aqui, toda na mesma tonica (La menor), para que
mapa, zonas, vilas e minigames sejam harmonicamente compativeis de verdade. Os
sons organicos (vento, passaros, rio, mercado, sino, galo...) vem do freesound
(CC0) e sao apenas textura/identidade - nunca a base musical.

Saida em assets/audio/{mus,vila,amb,sfx}/*.ogg + assets/audio/manifest.json
Requer: numpy, scipy, ffmpeg.
"""
import json
import math
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy import signal

SR = 44100
RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(RAIZ, "assets", "audio")
RAW = os.path.join(OUT, "raw")


# ---------------------------------------------------------------------------
# utilidades de audio
# ---------------------------------------------------------------------------

def seg(duracao):
    return np.zeros(int(round(duracao * SR)), dtype=np.float64)


def tempo(duracao):
    # int() e nao round(): todas as funcoes usam int(dur * SR) para o tamanho
    return np.arange(int(duracao * SR)) / SR


def env_adsr(n, a=0.01, d=0.15, s=0.7, r=0.3):
    a_n = max(1, int(a * SR))
    d_n = max(1, int(d * SR))
    r_n = max(1, int(r * SR))
    s_n = max(0, n - a_n - d_n - r_n)
    env = np.concatenate([
        np.linspace(0.0, 1.0, a_n, endpoint=False),
        np.linspace(1.0, s, d_n, endpoint=False) if d_n else np.array([]),
        np.full(s_n, s),
        np.linspace(s, 0.0, r_n) if r_n else np.array([]),
    ])
    if len(env) < n:
        env = np.pad(env, (0, n - len(env)))
    return env[:n]


def exp_env(n, ataque=0.005, decaimento=0.3):
    t = np.arange(n) / SR
    return np.minimum(1.0, t / max(ataque, 1e-4)) * np.exp(-t / max(decaimento, 1e-4))


def passa_baixa(x, corte, ordem=2):
    corte = min(corte, SR * 0.45)
    sos = signal.butter(ordem, corte, "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def passa_alta(x, corte, ordem=2):
    sos = signal.butter(ordem, max(corte, 20), "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def passa_banda(x, f1, f2, ordem=2):
    sos = signal.butter(ordem, [max(f1, 20), min(f2, SR * 0.45)], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def hz(semi, oitava=4):
    """Semi = semitons a partir de La; oitava 4 -> La 440."""
    return 440.0 * 2.0 ** ((semi + 12.0 * (oitava - 4)) / 12.0)


def normalizar_pico(x, alvo=0.89):
    p = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (alvo / p) if p > 1e-9 else x


def normalizar_rms(x, alvo_db=-20.0):
    r = float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0
    if r < 1e-9:
        return x
    alvo = 10.0 ** (alvo_db / 20.0)
    return x * (alvo / r)


def reverb(x, decay=2.2, wet=0.3, predelay=0.02, brilho=6000.0, seed=7, estéreo=True):
    """Reverberacao por convolucao com resposta ao impulso sintetica."""
    rng = np.random.default_rng(seed)
    n_ir = int(decay * SR)
    t = np.arange(n_ir) / SR
    ir = rng.normal(0, 1, n_ir) * np.exp(-t * (5.0 / max(decay, 0.2)))
    ir = passa_baixa(ir, brilho)
    ir[: int(predelay * SR)] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9

    if x.ndim == 1:
        y = signal.fftconvolve(x, ir)[: len(x)]
        return (1 - wet) * x + wet * y

    saida = np.zeros_like(x)
    for c in range(x.shape[1]):
        ir_c = ir if c == 0 else passa_baixa(ir, brilho * 0.85) * 1.02
        y = signal.fftconvolve(x[:, c], ir_c)[: x.shape[0]]
        saida[:, c] = (1 - wet) * x[:, c] + wet * y
    return saida


def eco(x, atraso=0.28, repeticoes=3, decaimento=0.45, mix=0.25):
    y = x.copy()
    n = int(atraso * SR)
    for k in range(1, repeticoes + 1):
        g = mix * (decaimento ** k)
        if k * n >= len(x):
            break
        y[k * n:] += g * x[: len(x) - k * n]
    return y


def dobra_loop(x, cauda):
    """Torna o loop continuo: a cauda do render volta para o inicio."""
    n_c = int(cauda * SR)
    if n_c <= 0 or n_c >= len(x):
        return x
    y = x.copy()
    fim = y[-n_c:]
    y = y[:-n_c]
    fade = np.linspace(1.0, 0.0, n_c)[:, None] if y.ndim == 2 else np.linspace(1.0, 0.0, n_c)
    y[:n_c] += fim * fade
    return y


def fade_bordas(x, entrada=0.004, saida=0.02):
    """Zera o inicio e o fim para nao estalar no play/stop.

    Os SFX e os stings sao cortados em um ponto qualquer do envelope; sem esse
    fade o alto-falante recebe um degrau (o "toc" que parece loop travando).
    """
    y = x.copy()
    n_in = max(1, int(entrada * SR))
    n_out = max(1, int(saida * SR))
    if y.ndim == 2:
        y[:n_in] *= np.linspace(0.0, 1.0, n_in)[:, None]
        y[-n_out:] *= np.linspace(1.0, 0.0, n_out)[:, None]
    else:
        y[:n_in] *= np.linspace(0.0, 1.0, n_in)
        y[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return y


def estereofoniza(x, largura=0.35, atraso_ms=7.0):
    """Converte mono em estereo com pequeno atraso/ganho diferente por canal."""
    atraso = int(SR * atraso_ms / 1000.0)
    esq = x
    dir_ = np.concatenate([np.zeros(atraso), x[:-atraso]]) if atraso else x.copy()
    return np.stack([esq, largura * esq + (1 - largura) * dir_], axis=1)


def mixar(dest, src, inicio_s, ganho=1.0):
    i = int(round(inicio_s * SR))
    if dest.ndim == 1 and src.ndim == 2:
        src = src.mean(axis=1)
    if dest.ndim == 2 and src.ndim == 1:
        src = np.stack([src, src], axis=1)
    n = min(len(src), len(dest) - i)
    if n <= 0:
        return
    dest[i:i + n] += src[:n] * ganho


def salvar_ogg(x, caminho, qualidade=2, mono=False, loop_ok=True, fade_saida=0.02):
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    if x.ndim == 2 and mono:
        x = x.mean(axis=1)
    if not loop_ok:
        x = fade_bordas(x, saida=fade_saida)
    if x.ndim == 1:
        dados = (np.clip(x, -1, 1) * 32767).astype("<i2")
        canais = 1
    else:
        dados = (np.clip(x, -1, 1) * 32767).astype("<i2")
        canais = 2
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wav_path = f.name
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(canais)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(dados.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
                    "-c:a", "libvorbis", "-q:a", str(qualidade), caminho], check=True)
    os.unlink(wav_path)
    kb = os.path.getsize(caminho) // 1024
    print("  %-42s %5d KB %s" % (os.path.relpath(caminho, RAIZ), kb,
                                 "(loop)" if loop_ok else ""))


# ---------------------------------------------------------------------------
# instrumentos
# ---------------------------------------------------------------------------

def pad(freq, dur, ganho=0.2, brilho=1800.0, detune=0.006, seed=1):
    n = int(dur * SR)
    t = tempo(dur)
    rng = np.random.default_rng(seed)
    y = np.zeros(n)
    for k, (mult, amp) in enumerate([(1.0, 1.0), (1.003, 0.8), (0.997, 0.8),
                                     (2.0, 0.25), (3.0, 0.12)]):
        fase = rng.uniform(0, 2 * np.pi)
        # dente-de-serra suavizado por soma de harmonicos (menos alias)
        onda = np.zeros(n)
        for h in range(1, 7):
            onda += np.sin(2 * np.pi * freq * mult * h * t + fase * h) / (h ** 1.6)
        y += onda * amp
    y = passa_baixa(y, brilho, ordem=2)
    y *= env_adsr(n, a=min(1.6, dur * 0.35), d=0.6, s=0.55, r=min(2.4, dur * 0.5))
    # movimento lento (coro)
    lfo = 1.0 + 0.12 * np.sin(2 * np.pi * 0.13 * t + rng.uniform(0, 6))
    return y * lfo * ganho


def sino_tone(freq, dur, ganho=0.3, indice=3.2, razao=2.41, decai=0.55):
    n = int(dur * SR)
    t = tempo(dur)
    idx = indice * np.exp(-t / max(decai, 0.05))
    y = np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * razao * t))
    y += 0.35 * np.sin(2 * np.pi * freq * 2.0 * t) * np.exp(-t / (decai * 0.7))
    y *= exp_env(n, ataque=0.004, decaimento=decai)
    return y * ganho


def pluck(freq, dur, ganho=0.25, brilho=2600.0, amortecimento=0.9965):
    """Karplus-Strong via filtro comb (y[n] = x[n] + a*y[n-N])."""
    n = int(dur * SR)
    n_atraso = max(2, int(SR / freq))
    rng = np.random.default_rng(int(freq * 13) % 99991)
    exc = rng.uniform(-1, 1, n_atraso)
    exc = passa_baixa(exc, brilho)
    a = np.zeros(n_atraso + 1)
    a[0] = 1.0
    a[n_atraso] = -amortecimento
    y = signal.lfilter([1.0], a, np.concatenate([exc, np.zeros(n - n_atraso + 1)]))[:n]
    y *= exp_env(n, ataque=0.002, decaimento=dur * 0.4)
    return y * ganho


def mallet(freq, dur, ganho=0.25, decai=0.35):
    n = int(dur * SR)
    t = tempo(dur)
    y = np.sin(2 * np.pi * freq * t) * np.exp(-t / decai)
    y += 0.4 * np.sin(2 * np.pi * freq * 3.01 * t) * np.exp(-t / (decai * 0.4))
    y += 0.2 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t / (decai * 0.25))
    return y * exp_env(n, ataque=0.001, decaimento=decai) * ganho


def baixo(freq, dur, ganho=0.35):
    n = int(dur * SR)
    t = tempo(dur)
    y = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 2 * t)
    y = passa_baixa(y, 600)
    y *= env_adsr(n, a=0.02, d=0.2, s=0.6, r=min(0.5, dur * 0.4))
    return y * ganho


def shaker(dur=0.09, ganho=0.12, seed=3):
    n = int(dur * SR)
    rng = np.random.default_rng(seed)
    y = passa_banda(rng.normal(0, 1, n), 6200, 12000)
    y *= np.exp(-tempo(dur) / (dur * 0.22))
    return y * ganho


def pulsar(freq, dur, ganho=0.18):
    n = int(dur * SR)
    t = tempo(dur)
    y = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.12)
    return y * ganho


# ---------------------------------------------------------------------------
# harmonia (tudo em La menor)
# ---------------------------------------------------------------------------

ESCALA_AM = [0, 2, 3, 5, 7, 8, 10]          # menor natural a partir de La
ACORDES = {
    "Am": (0, [0, 3, 7]),
    "F": (8, [0, 4, 7]),
    "C": (3, [0, 4, 7]),
    "G": (10, [0, 4, 7]),
    "Em": (7, [0, 3, 7]),
    "Dm": (5, [0, 3, 7]),
    "E": (7, [0, 4, 7]),
    "D": (5, [0, 4, 7]),
}


def vozes(nome, oitava=3):
    raiz, intervalos = ACORDES[nome]
    return [hz(raiz + i, oitava) for i in intervalos]


def grau(idx, oitava=5):
    """Nota da escala de La menor (idx pode passar da oitava)."""
    o = idx // len(ESCALA_AM)
    return hz(ESCALA_AM[idx % len(ESCALA_AM)] + 12 * o, oitava)


def renderizar_musica(cfg):
    """cfg: nome, bpm, compassos, acordes, instrumentos, seed, reverb."""
    bpm = cfg["bpm"]
    batida = 60.0 / bpm
    dur = cfg["compassos"] * 4 * batida
    cauda = cfg.get("cauda", 2.5)
    total = dur + cauda
    mix = np.zeros((int(total * SR), 2))
    rng = np.random.default_rng(cfg.get("seed", 1))
    acordes = cfg["acordes"]
    n_ac = len(acordes)
    comp_por_acorde = cfg["compassos"] / n_ac

    # pads
    if cfg.get("pad", True):
        for i, ac in enumerate(acordes):
            t0 = i * comp_por_acorde * 4 * batida
            dur_ac = comp_por_acorde * 4 * batida
            for j, f in enumerate(vozes(ac, cfg.get("oitava_pad", 3))):
                p = pad(f, dur_ac + 0.8, ganho=cfg.get("ganho_pad", 0.16) / (1 + 0.25 * j),
                        brilho=cfg.get("brilho_pad", 1500.0 + 120 * j),
                        seed=cfg.get("seed", 1) + i * 7 + j)
                mixar(mix, p, t0, 1.0)

    # baixo
    if cfg.get("baixo", True):
        for i, ac in enumerate(acordes):
            raiz = ACORDES[ac][0]
            f = hz(raiz, 2)
            for b in range(int(comp_por_acorde * 4)):
                t0 = (i * comp_por_acorde * 4 + b) * batida
                if b % 4 in cfg.get("baixo_padrao", [0, 2]):
                    mixar(mix, baixo(f, batida * 1.6, ganho=cfg.get("ganho_baixo", 0.22)), t0)

    # melodia esparsa (motivo)
    if cfg.get("melodia", True):
        densidade = cfg.get("densidade", 0.55)
        n_notas = int(cfg["compassos"] * 4 * densidade)
        usado = set()
        for k in range(n_notas):
            pos = k * (cfg["compassos"] * 4 / max(1, n_notas)) + rng.uniform(0, 0.6)
            grau_i = int(rng.integers(0, 7))
            if grau_i in usado and rng.random() < 0.5:
                continue
            usado.add(grau_i)
            f = grau(grau_i, cfg.get("oitava_melodia", 5))
            d = batida * rng.choice([1.0, 1.5, 2.0])
            if cfg.get("instrumento_melodia") == "pluck":
                y = pluck(f, d + 0.4, ganho=cfg.get("ganho_melodia", 0.18))
            elif cfg.get("instrumento_melodia") == "mallet":
                y = mallet(f, d + 0.4, ganho=cfg.get("ganho_melodia", 0.2), decai=0.28)
            else:
                y = sino_tone(f, d + 1.2, ganho=cfg.get("ganho_melodia", 0.16), decai=0.7)
            if cfg.get("eco", True):
                y = eco(y, atraso=batida * 0.75, repeticoes=3, decaimento=0.42, mix=0.3)
            mixar(mix, y, pos * batida, 1.0)

    # arpejo (8os) para zonas mais vivas
    if cfg.get("arpejo", False):
        padrao = cfg.get("arpejo_padrao", [0, 1, 2, 1])
        for i, ac in enumerate(acordes):
            v = vozes(ac, cfg.get("oitava_arp", 4))
            passos = int(comp_por_acorde * 4 * 2)
            for s in range(passos):
                t0 = (i * comp_por_acorde * 4 + s * 0.5) * batida
                f = v[padrao[s % len(padrao)] % len(v)]
                y = pluck(f, 0.7, ganho=cfg.get("ganho_arp", 0.10), brilho=3000.0)
                mixar(mix, y, t0)

    # percussao suave
    if cfg.get("shaker", False):
        passos = int(cfg["compassos"] * 4 * 2)
        for s in range(passos):
            t0 = s * 0.5 * batida
            g = cfg.get("ganho_shaker", 0.08) * (1.0 if s % 2 == 0 else 0.6)
            mixar(mix, shaker(0.08, g), t0)
    if cfg.get("pulso", False):
        for b in range(int(cfg["compassos"] * 4)):
            t0 = b * batida
            f = hz(ACORDES[acordes[(b // 4) % n_ac]][0], 4)
            mixar(mix, pulsar(f, 0.25, cfg.get("ganho_pulso", 0.08)), t0)

    # ambiente tonal (drone) opcional
    if cfg.get("drone", False):
        d = pad(hz(0, 2), total, ganho=0.10, brilho=700.0, seed=99)
        mixar(mix, d, 0.0)

    mix = reverb(mix, decay=cfg.get("reverb_decay", 2.4), wet=cfg.get("reverb_wet", 0.3),
                 brilho=cfg.get("reverb_brilho", 5200.0), seed=cfg.get("seed", 1) + 5)
    if cfg.get("loop", True):
        mix = dobra_loop(mix, cauda)
    return normalizar_rms(mix, cfg.get("rms_db", -19.0))


# ---------------------------------------------------------------------------
# stings das vilas (identidade + motivo unico)
# ---------------------------------------------------------------------------

def renderizar_sting(vila, accent_path, seed):
    rng = np.random.default_rng(seed)
    dur = 4.2
    cauda = 1.4
    total = dur + cauda
    mix = np.zeros((int(total * SR), 2))
    raiz_grau = (vila["id"] - 1) % 7
    f_raiz = grau(raiz_grau, 2)

    # drone grave (a "assinatura" harmonica da vila)
    mixar(mix, pad(f_raiz, dur + 0.6, ganho=0.13, brilho=900.0, seed=seed), 0.0)

    # motivo de 3 notas (unico por vila)
    base = raiz_grau
    padrao = [(0, 0.0), (2, 0.55), (4, 1.1)] if vila["id"] % 3 else [(0, 0.0), (-1, 0.5), (2, 1.05)]
    for k, (passo, t0) in enumerate(padrao):
        idx = base + passo + (2 if vila["id"] % 2 else 0)
        f = grau(int(idx), 5)
        y = sino_tone(f, 2.2, ganho=0.20, decai=0.8)
        y = eco(y, atraso=0.32, repeticoes=3, decaimento=0.4, mix=0.3)
        mixar(mix, y, t0)
        # reforco com pluck na terceira nota
        if k == 2:
            mixar(mix, pluck(f / 2.0, 1.6, ganho=0.12), t0 + 0.02)

    # acento diegetico do freesound (sino, galo, bocina...)
    if accent_path and os.path.exists(accent_path):
        acc = carregar_audio(accent_path)
        if acc is not None:
            acc = recortar_inicio(acc, float(vila.get("inicio", 0.0)),
                                  float(vila.get("dur_acento", 2.6)))
            acc = normalizar_pico(acc, 0.7)
            if acc.ndim == 1:
                acc = estereofoniza(acc, 0.3)
            mixar(mix, acc, 0.35, 0.55)

    mix = reverb(mix, decay=2.8, wet=0.34, brilho=5000.0, seed=seed + 3)
    mix = normalizar_rms(mix[: int(dur * SR)], -18.0)
    return mix


# ---------------------------------------------------------------------------
# efeitos de interface (curtos, secos, na mesma tonica)
# ---------------------------------------------------------------------------

def sfx_clique():
    d = 0.09
    y = np.zeros(int(d * SR))
    n = len(y)
    t = tempo(d)
    y += 0.7 * np.sin(2 * np.pi * 1320 * t) * np.exp(-t / 0.018)
    y += 0.3 * np.sin(2 * np.pi * 880 * t) * np.exp(-t / 0.03)
    y += 0.12 * passa_alta(np.random.default_rng(5).normal(0, 1, n), 3000) * np.exp(-t / 0.008)
    return y * 0.5


def sfx_abrir():
    """Abrir painel: quinta suave (La3 -> Mi4) de marimba, sem varredura.

    A versao anterior era um sweep 320->768 Hz com ruido, que soava "laser" e
    cansava depois de poucos cliques. Aqui a nota tem ataque curto, corpo curto
    e cauda filtrada; o volume tambem e menor (ver normalizacao em main()).
    """
    d = 0.40
    y = np.zeros(int(d * SR))
    mixar(y, mallet(hz(0, 3), 0.38, ganho=0.55, decai=0.16), 0.0)
    mixar(y, mallet(hz(7, 3), 0.32, ganho=0.32, decai=0.14), 0.085)
    n = len(y)
    ar = passa_banda(np.random.default_rng(6).normal(0, 1, n), 700, 2600)
    ar *= np.exp(-tempo(d) / 0.05) * 0.012
    return passa_baixa(y + ar, 3200)


def sfx_fechar():
    """Fechar painel: o mesmo intervalo ao contrario, ainda mais discreto."""
    d = 0.32
    y = np.zeros(int(d * SR))
    mixar(y, mallet(hz(7, 3), 0.30, ganho=0.40, decai=0.13), 0.0)
    mixar(y, mallet(hz(0, 3), 0.26, ganho=0.28, decai=0.12), 0.075)
    n = len(y)
    ar = passa_banda(np.random.default_rng(7).normal(0, 1, n), 600, 2200)
    ar *= np.exp(-tempo(d) / 0.045) * 0.010
    return passa_baixa(y + ar, 3000)


def sfx_sucesso():
    d = 1.1
    y = np.zeros(int(d * SR))
    for k, semi in enumerate([0, 4, 7, 12]):
        f = hz(semi, 5)
        mixar(y, sino_tone(f, 0.9, ganho=0.3, decai=0.5), k * 0.09)
    return y


def sfx_erro():
    d = 0.55
    t = tempo(d)
    y = np.sin(2 * np.pi * 155 * t) + 0.6 * np.sin(2 * np.pi * 164 * t)
    y *= np.exp(-t / 0.20) * (1 - np.exp(-t / 0.01))
    y = passa_baixa(y, 900)
    return y * 0.55


def sfx_moeda():
    d = 0.55
    y = np.zeros(int(d * SR))
    mixar(y, sino_tone(hz(12, 6), 0.35, ganho=0.35, decai=0.12), 0.0)
    mixar(y, sino_tone(hz(19, 6), 0.45, ganho=0.30, decai=0.18), 0.07)
    return y


def sfx_semana():
    d = 0.6
    y = np.zeros(int(d * SR))
    mixar(y, mallet(hz(0, 4), 0.5, ganho=0.4, decai=0.12), 0.0)
    mixar(y, mallet(hz(7, 4), 0.5, ganho=0.25, decai=0.10), 0.12)
    return passa_baixa(y, 4000)


def sfx_alerta():
    d = 0.9
    y = np.zeros(int(d * SR))
    for k in range(2):
        t0 = k * 0.28
        n = int(0.24 * SR)
        t = np.arange(n) / SR
        tom = np.sin(2 * np.pi * (520 if k == 0 else 440) * t) * np.exp(-t / 0.12)
        mixar(y, tom * 0.5, t0)
    return y


def sfx_pagina():
    d = 0.42
    n = int(d * SR)
    rng = np.random.default_rng(11)
    y = passa_banda(rng.normal(0, 1, n), 1800, 7000)
    env = np.exp(-tempo(d) / 0.10)
    env[: int(0.05 * SR)] *= np.linspace(0, 1, int(0.05 * SR))
    return y * env * 0.5


def sfx_descoberta():
    d = 1.6
    y = np.zeros(int(d * SR))
    for k, idx in enumerate([0, 2, 4, 7, 9]):
        f = grau(idx, 5)
        mixar(y, sino_tone(f, 1.2, ganho=0.22, decai=0.6), k * 0.11)
    y = eco(y, atraso=0.24, repeticoes=3, decaimento=0.4, mix=0.25)
    return y


SFX = {
    "clique": (sfx_clique, 0),
    "abrir": (sfx_abrir, 2),
    "fechar": (sfx_fechar, 2),
    "sucesso": (sfx_sucesso, 3),
    "erro": (sfx_erro, 3),
    "moeda": (sfx_moeda, 4),
    "semana": (sfx_semana, 4),
    "alerta": (sfx_alerta, 5),
    "pagina": (sfx_pagina, 2),
    "descoberta": (sfx_descoberta, 5),
}


# ---------------------------------------------------------------------------
# freesound: recorte, loop e mistura
# ---------------------------------------------------------------------------

def carregar_audio(caminho):
    """Decodifica mp3/ogg/wav para float64 estereo via ffmpeg."""
    cmd = ["ffmpeg", "-v", "error", "-i", caminho, "-f", "f32le", "-acodec", "pcm_f32le",
           "-ac", "2", "-ar", str(SR), "-"]
    r = subprocess.run(cmd, capture_output=True)
    if r.returncode != 0 or not r.stdout:
        return None
    x = np.frombuffer(r.stdout, dtype="<f4").astype(np.float64)
    return x.reshape(-1, 2)


def recortar_inicio(x, inicio_s, dur_s):
    i = int(inicio_s * SR)
    n = int(dur_s * SR)
    y = x[i:i + n]
    if len(y) < n:
        y = np.pad(y, ((0, n - len(y)), (0, 0)))
    return y


def fazer_loop_ambiente(x, dur_alvo, cauda=1.6):
    """Recorta um trecho e costura o fim no inicio para loop perfeito."""
    n = int(dur_alvo * SR)
    if len(x) < n + int(cauda * SR):
        x = np.tile(x, (int(np.ceil((n + cauda * SR) / len(x))) + 1, 1))
    y = x[: n + int(cauda * SR)].copy()
    return dobra_loop(y, cauda)


def processar_ambientes(manifest):
    amb = [
        ("amb_vento", "amb_vento.mp3", 24.0, 0.020, 850.0),
        ("amb_passaros", "amb_passaros.mp3", 22.0, 0.035, 0.0),
        ("amb_rio", "amb_rio.mp3", 14.0, 0.045, 700.0),
        ("amb_mercado", "amb_mercado.mp3", 20.0, 0.030, 900.0),
        ("amb_multidao", "amb_multidao.mp3", 16.0, 0.028, 800.0),
        ("amb_porto", "amb_porto.mp3", 20.0, 0.035, 900.0),
    ]
    for nome, arq, dur, corte, _ in amb:
        caminho = os.path.join(RAW, arq)
        if not os.path.exists(caminho):
            continue
        x = carregar_audio(caminho)
        if x is None:
            continue
        if corte > 0:
            x = passa_alta(x, corte)
        x = fazer_loop_ambiente(x, dur)
        x = normalizar_rms(x, -23.0)
        salvar_ogg(x, os.path.join(OUT, "amb", nome + ".ogg"), qualidade=1)
        manifest["ambientes"].append({"id": nome, "arquivo": "amb/%s.ogg" % nome,
                                      "duracao": round(dur, 2), "loop": True})


# ---------------------------------------------------------------------------
# montagem geral
# ---------------------------------------------------------------------------

ZONAS = {
    "mapa": dict(bpm=64, compassos=8, acordes=["Am", "F", "C", "G"], oitava_pad=3,
                 ganho_pad=0.15, brilho_pad=1400, melodia=True, densidade=0.30,
                 instrumento_melodia="sino", ganho_melodia=0.15, oitava_melodia=5,
                 baixo=True, baixo_padrao=[0], ganho_baixo=0.18, drone=True,
                 reverb_wet=0.38, reverb_decay=3.2, seed=11, rms_db=-20.0),
    "zona_urbana": dict(bpm=86, compassos=8, acordes=["Am", "F", "C", "Em"], oitava_pad=3,
                        ganho_pad=0.13, brilho_pad=1600, melodia=True, densidade=0.35,
                        instrumento_melodia="pluck", arpejo=True, arpejo_padrao=[0, 1, 2, 1],
                        shaker=True, ganho_shaker=0.032, reverb_wet=0.26, seed=21, rms_db=-19.0),
    "zona_rural": dict(bpm=74, compassos=8, acordes=["C", "G", "Am", "F"], oitava_pad=3,
                       ganho_pad=0.14, brilho_pad=1500, melodia=True, densidade=0.30,
                       instrumento_melodia="mallet", oitava_melodia=5, reverb_wet=0.3,
                       seed=31, rms_db=-19.5),
    "zona_rio": dict(bpm=70, compassos=8, acordes=["Am", "Em", "F", "G"], oitava_pad=3,
                     ganho_pad=0.15, brilho_pad=1300, melodia=True, densidade=0.25,
                     instrumento_melodia="pluck", arpejo=True, arpejo_padrao=[0, 2, 1, 2],
                     ganho_arp=0.08, reverb_wet=0.34, reverb_decay=2.8, seed=41, rms_db=-20.0),
    "zona_mata": dict(bpm=58, compassos=8, acordes=["Am", "Dm", "Em", "Am"], oitava_pad=3,
                      ganho_pad=0.13, brilho_pad=1100, melodia=True, densidade=0.22,
                      instrumento_melodia="sino", ganho_melodia=0.13, drone=True,
                      shaker=True, ganho_shaker=0.024, reverb_wet=0.4, reverb_decay=3.4,
                      seed=51, rms_db=-21.0),
    "zona_industrial": dict(bpm=92, compassos=8, acordes=["Am", "Am", "F", "E"], oitava_pad=3,
                            ganho_pad=0.12, brilho_pad=1200, melodia=True, densidade=0.28,
                            instrumento_melodia="mallet", pulso=True, ganho_pulso=0.07,
                            shaker=True, ganho_shaker=0.035, reverb_wet=0.24, seed=61,
                            rms_db=-19.0),
}

MINIGAMES = {
    "delineamentos": dict(bpm=96, acordes=["Am", "F", "G", "Am"], instr="pluck", seed=101),
    "banco_dados": dict(bpm=100, acordes=["C", "Am", "F", "G"], instr="mallet", seed=102),
    "assimetria": dict(bpm=88, acordes=["Am", "Dm", "E", "Am"], instr="sino", seed=103),
    "grafico": dict(bpm=104, acordes=["F", "G", "Am", "Am"], instr="pluck", seed=104),
    "amostragem": dict(bpm=92, acordes=["Am", "C", "F", "G"], instr="mallet", seed=105),
    "distribuicoes": dict(bpm=98, acordes=["Am", "Em", "C", "G"], instr="pluck", seed=106),
    "hipoteses": dict(bpm=90, acordes=["Dm", "Am", "E", "Am"], instr="sino", seed=107),
    "tendencias": dict(bpm=94, acordes=["Am", "F", "C", "E"], instr="mallet", seed=108),
    "auditoria": dict(bpm=102, acordes=["Am", "G", "F", "E"], instr="pluck", seed=109),
}


def _render_stings(manifest):
    audio_cfg = json.load(open(os.path.join(RAIZ, "data", "audio.json")))
    arq_acento = audio_cfg["vilas_acento_arquivo"]
    vilas = json.load(open(os.path.join(RAIZ, "data", "vilas.json")))
    lista = vilas["vilas"] if isinstance(vilas, dict) else vilas
    for v in lista:
        conf = audio_cfg["vilas"][str(v["id"])]
        caminho = os.path.join(RAW, arq_acento[conf["acento"]])
        v = dict(v)
        v["inicio"] = conf.get("inicio", 0.0)
        v["dur_acento"] = conf.get("dur", 2.6)
        y = renderizar_sting(v, caminho, seed=200 + v["id"])
        nome = "vila_%02d" % v["id"]
        salvar_ogg(y, os.path.join(OUT, "vila", nome + ".ogg"), qualidade=2,
                   loop_ok=False, fade_saida=0.30)
        manifest["vilas"].append({"id": int(v["id"]), "arquivo": "vila/%s.ogg" % nome,
                                  "duracao": 4.2})


def _render_sfx(manifest):
    for nome, (fn, q) in SFX.items():
        y = fn()
        if nome in ("abrir", "fechar"):
            # primeiro limita o pico (card de interface nao precisa de soco) e
            # depois fixa o RMS; a ordem inversa voltava a subir o volume.
            y = normalizar_pico(y, 0.35)
            y = normalizar_rms(y, -24.0)
        else:
            y = normalizar_rms(y, -16.0)
            y = normalizar_pico(y, 0.92)
        salvar_ogg(y, os.path.join(OUT, "sfx", nome + ".ogg"), qualidade=q, mono=True,
                   loop_ok=False)
        manifest["sfx"].append({"id": nome, "arquivo": "sfx/%s.ogg" % nome})


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"ambientes": [], "musicas": [], "vilas": [], "sfx": []}
    rapido = "--rapido" in sys.argv[1:]

    if rapido:
        # regenera stings + sfx (usado ao ajustar apenas a camada de interface)
        print("stings das vilas:")
        _render_stings(manifest)
        print("efeitos:")
        _render_sfx(manifest)
        with open(os.path.join(OUT, "manifest.json"), "w") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)
        return

    print("ambientes (freesound):")
    processar_ambientes(manifest)

    print("musicas:")
    for nome, cfg in ZONAS.items():
        cfg = dict(cfg)
        cfg["nome"] = nome
        cfg["seed"] = cfg.get("seed", 1)
        y = renderizar_musica(cfg)
        salvar_ogg(y, os.path.join(OUT, "mus", nome + ".ogg"), qualidade=2)
        manifest["musicas"].append({"id": nome, "arquivo": "mus/%s.ogg" % nome,
                                    "bpm": cfg["bpm"], "compassos": cfg["compassos"],
                                    "loop": True})

    print("minigames:")
    for nome, cfg in MINIGAMES.items():
        c = dict(bpm=cfg["bpm"], compassos=8, acordes=cfg["acordes"],
                 instrumento_melodia=cfg["instr"], melodia=True, densidade=0.5,
                 oitava_pad=3, ganho_pad=0.11, brilho_pad=2000.0,
                 arpejo=True, arpejo_padrao=[0, 1, 2, 1], ganho_arp=0.09,
                 shaker=True, ganho_shaker=0.036, baixo=True, baixo_padrao=[0, 2],
                 reverb_wet=0.2, reverb_decay=1.8, seed=cfg["seed"], rms_db=-18.0,
                 cauda=1.4)
        y = renderizar_musica(c)
        salvar_ogg(y, os.path.join(OUT, "mus", "mg_%s.ogg" % nome), qualidade=2)
        manifest["musicas"].append({"id": "mg_" + nome, "arquivo": "mus/mg_%s.ogg" % nome,
                                    "bpm": cfg["bpm"], "compassos": 8, "loop": True})

    print("stings das vilas:")
    _render_stings(manifest)

    print("efeitos:")
    _render_sfx(manifest)

    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    total = sum(os.path.getsize(os.path.join(dp, f))
                for dp, _, fs in os.walk(OUT) for f in fs if f.endswith(".ogg"))
    print("\ntotal ogg: %.1f MB" % (total / 1e6))


if __name__ == "__main__":
    sys.exit(main())
