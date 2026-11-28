#!/usr/bin/env python3
"""Lanca a nota do StaTown na avaliacao "Game Educativo Statown" do SIGA.

Regra: 1000 moedas ganhas = nota maxima da avaliacao (peso do SIGA).
A nota e truncada em uma casa decimal e limitada ao peso.

Seguranca:
  * so aceita a avaliacao "Game Educativo Statown";
  * nunca cria avaliacao (nao existe chamada de criacao neste script);
  * exige --confirmar para escrever; sem ele, apenas mostra o plano;
  * limita a 5 alunos por execucao, a menos que --max-alunos seja ampliado;
  * grava um backup local das notas atuais antes do POST (modo 600);
  * mascara matriculas na saida e nunca imprime chaves/tokens.

Exemplos:
  # conferir o plano, sem escrever
  python3 scripts/lancar_nota_siga.py --turma CBV018GV-A \
      --indice 1=333

  # escrever de verdade
  python3 scripts/lancar_nota_siga.py --turma CBV018GV-A \
      --indice 1=333 --confirmar

  # usar matriculas explicitas (valores abaixo sao exemplos sinteticos)
  python3 scripts/lancar_nota_siga.py --turma CBV044GV-A \
      --aluno 000000001=500 --aluno 000000002=999 --confirmar
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

API_PADRAO = "https://siga-api.sparklingtech.com.br"
PERIODO_PADRAO = "2026/3"
AVALIACAO = "Game Educativo Statown"
NOTA_MAXIMA_PADRAO = 40.0
MOEDAS_TETO = 1000
MAX_ALUNOS_PADRAO = 5
ENV_PADRAO = Path.home() / ".dsh" / "secrets" / "statown.env"
BACKUP_PADRAO = Path.home() / ".dsh" / "dados" / "siga_backups"


class ErroSiga(RuntimeError):
    pass


def carregar_env(caminho: Path) -> dict[str, str]:
    if not caminho.is_file():
        raise ErroSiga(f"arquivo de segredos nao encontrado: {caminho}")
    dados: dict[str, str] = {}
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        dados[chave.strip()] = valor.strip().strip('"').strip("'")
    return dados


def mascarar(valor: str) -> str:
    """Identificador estavel para log, sem revelar a matricula."""
    return "aluno-" + hashlib.sha256(valor.encode("utf-8")).hexdigest()[:8]


def normalizar(texto: str) -> str:
    return re.sub(r"\s+", " ", texto.strip()).casefold()


def calcular_nota(moedas: int, peso: float) -> float:
    """Nota em decimos, truncada, com a mesma aritmetica do jogo.

    Multiplicar antes de dividir evita o artefato binario que transformava
    285 moedas em 11,3 (285 * 40 / 1000 = 11,4).
    """
    moedas = min(max(int(moedas), 0), MOEDAS_TETO)
    limite_decimos = max(1, int(round(float(peso) * 10.0)))
    decimos = min(limite_decimos, (moedas * limite_decimos) // MOEDAS_TETO)
    return decimos / 10.0


class Siga:
    def __init__(self, base: str, chave: str) -> None:
        self.base = base.rstrip("/")
        self.chave = chave

    def _pedido(self, metodo: str, caminho: str, corpo: dict[str, Any] | None = None) -> Any:
        dados = None
        headers = {"X-API-Key": self.chave, "Accept": "application/json"}
        if corpo is not None:
            dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + caminho, data=dados,
                                     headers=headers, method=metodo)
        ultimo: Exception | None = None
        for tentativa in range(3):
            try:
                with urllib.request.urlopen(req, timeout=90) as resp:
                    bruto = resp.read()
                    return json.loads(bruto) if bruto else None
            except urllib.error.HTTPError as erro:
                texto = erro.read().decode("utf-8", "replace")
                if erro.code in (429, 502, 503, 504) and tentativa < 2:
                    time.sleep(2 ** tentativa)
                    continue
                raise ErroSiga(f"{metodo} {caminho}: HTTP {erro.code}: {texto[:500]}") from erro
            except (urllib.error.URLError, TimeoutError) as erro:
                ultimo = erro
                if tentativa < 2:
                    time.sleep(2 ** tentativa)
                    continue
                raise ErroSiga(f"{metodo} {caminho}: falha de rede: {erro}") from erro
        raise ErroSiga(f"{metodo} {caminho}: falha de rede: {ultimo}")

    def notas(self, turma: str, periodo: str) -> dict[str, Any]:
        q = urllib.parse.urlencode({"turma": turma, "periodo": periodo})
        dados = self._pedido("GET", "/api/notas?" + q)
        if not isinstance(dados, dict):
            raise ErroSiga("GET /api/notas nao retornou um objeto")
        return dados

    def lancar(self, turma: str, periodo: str, notas: dict[str, float]) -> Any:
        corpo = {
            "turma": turma,
            "descricao_avaliacao": AVALIACAO,
            "notas_json": notas,
            "periodo": periodo,
        }
        return self._pedido("POST", "/api/lancar-notas", corpo)


def extrair_alvo(dados: dict[str, Any]) -> dict[str, Any]:
    alvos = [a for a in dados.get("avaliacoes", [])
             if normalizar(str(a.get("descricao", ""))) == normalizar(AVALIACAO)]
    if not alvos:
        raise ErroSiga(f'a avaliacao "{AVALIACAO}" nao existe nesta turma; nada sera feito')
    if len(alvos) > 1:
        raise ErroSiga(f'ha {len(alvos)} avaliacoes com o nome "{AVALIACAO}"; abortando por seguranca')
    return alvos[0]


def nota_do_aluno(aluno: dict[str, Any], alvo: dict[str, Any]) -> Any:
    """A API historica indexa notas pela descricao; versoes novas podem usar o id."""
    notas = aluno.get("notas") or {}
    if not isinstance(notas, dict):
        return None
    for chave in (str(alvo.get("id")), AVALIACAO, str(alvo.get("descricao", ""))):
        if chave and chave in notas:
            return notas[chave]
    for chave, valor in notas.items():
        if normalizar(str(chave)) == normalizar(AVALIACAO):
            return valor
    return None


def plano_por_indices(args: argparse.Namespace, alunos: list[dict[str, Any]]) -> list[tuple[str, int]]:
    plano: list[tuple[str, int]] = []
    for item in args.indice:
        if "=" not in item:
            raise ErroSiga(f"--indice invalido: {item!r}; use N=MOEDAS")
        n_txt, moedas_txt = item.split("=", 1)
        try:
            n = int(n_txt)
            moedas = int(moedas_txt)
        except ValueError as erro:
            raise ErroSiga(f"--indice invalido: {item!r}; use N=MOEDAS") from erro
        if n < 1 or n > len(alunos):
            raise ErroSiga(f"indice {n} fora da turma (1..{len(alunos)})")
        m = str(alunos[n - 1].get("matricula", "")).strip()
        if not m:
            raise ErroSiga(f"aluno no indice {n} sem matricula")
        plano.append((m, moedas))
    return plano


def plano_por_matriculas(args: argparse.Namespace, alunos: list[dict[str, Any]]) -> list[tuple[str, int]]:
    existentes = {str(a.get("matricula", "")).strip() for a in alunos}
    plano: list[tuple[str, int]] = []
    for item in args.aluno:
        if "=" not in item:
            raise ErroSiga(f"--aluno invalido: {item!r}; use MATRICULA=MOEDAS")
        matricula, moedas_txt = item.split("=", 1)
        matricula = matricula.strip()
        try:
            moedas = int(moedas_txt)
        except ValueError as erro:
            raise ErroSiga(f"moedas invalidas em {mascarar(matricula)}") from erro
        if matricula not in existentes:
            raise ErroSiga(f"matricula {mascarar(matricula)} nao pertence a esta turma")
        plano.append((matricula, moedas))
    return plano


def validar_plano(plano: list[tuple[str, int]], limite: int) -> None:
    if not plano:
        raise ErroSiga("informe pelo menos um --aluno MATRICULA=MOEDAS ou --indice N=MOEDAS")
    if len(plano) > limite:
        raise ErroSiga(f"{len(plano)} alunos no plano; o limite desta execucao e {limite}. "
                       "Ajuste --max-alunos conscientemente se for necessario.")
    vistos: set[str] = set()
    for matricula, moedas in plano:
        if matricula in vistos:
            raise ErroSiga(f"matricula repetida no plano: {mascarar(matricula)}")
        vistos.add(matricula)
        if moedas < 0 or moedas > 100000:
            raise ErroSiga(f"moedas fora da faixa em {mascarar(matricula)}: {moedas}")


def backup(dados: dict[str, Any], alvo: dict[str, Any], plano: list[tuple[str, int]],
           pasta: Path) -> Path:
    pasta.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        pasta.chmod(0o700)
    except OSError:
        pass
    notas_antigas: dict[str, Any] = {}
    for aluno in dados.get("alunos", []):
        m = str(aluno.get("matricula", "")).strip()
        if any(m == x for x, _ in plano):
            notas_antigas[m] = nota_do_aluno(aluno, alvo)
    registro = {
        "quando": datetime.now(timezone.utc).isoformat(),
        "turma": dados.get("consulta", {}).get("turma") if isinstance(dados.get("consulta"), dict) else None,
        "periodo": dados.get("consulta", {}).get("periodo") if isinstance(dados.get("consulta"), dict) else None,
        "avaliacao": AVALIACAO,
        "avaliacao_id": alvo.get("id"),
        "peso": alvo.get("peso"),
        "notas_antes": notas_antigas,
    }
    nome = "siga_backup_%s_%s.json" % (
        re.sub(r"[^A-Za-z0-9_-]+", "_", str(registro["turma"] or "turma")),
        datetime.now().strftime("%Y%m%d_%H%M%S"))
    caminho = pasta / nome
    caminho.write_text(json.dumps(registro, ensure_ascii=False, indent=2), encoding="utf-8")
    caminho.chmod(0o600)
    return caminho


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--turma", required=True)
    ap.add_argument("--periodo", default=PERIODO_PADRAO)
    ap.add_argument("--base", default=os.environ.get("SIGA_API_BASE", API_PADRAO))
    ap.add_argument("--env", type=Path, default=ENV_PADRAO)
    ap.add_argument("--aluno", action="append", default=[], metavar="MATRICULA=MOEDAS")
    ap.add_argument("--indice", action="append", default=[], metavar="N=MOEDAS")
    ap.add_argument("--max-alunos", type=int, default=MAX_ALUNOS_PADRAO)
    ap.add_argument("--nota-maxima-esperada", type=float, default=NOTA_MAXIMA_PADRAO)
    ap.add_argument("--aceitar-peso-diferente", action="store_true")
    ap.add_argument("--backup-dir", type=Path, default=BACKUP_PADRAO)
    ap.add_argument("--confirmar", action="store_true",
                    help="sem esta opcao, apenas mostra o plano e nao escreve")
    args = ap.parse_args()

    if bool(args.aluno) == bool(args.indice):
        raise ErroSiga("use --aluno ... ou --indice ..., nunca os dois juntos")

    env = carregar_env(args.env)
    chave = env.get("SIGA_API_KEY", "")
    if not chave:
        raise ErroSiga("SIGA_API_KEY ausente no arquivo de segredos")
    siga = Siga(args.base, chave)

    dados = siga.notas(args.turma, args.periodo)
    alvo = extrair_alvo(dados)
    peso = float(alvo.get("peso") or 0.0)
    if peso <= 0:
        raise ErroSiga("avaliacao alvo sem peso positivo; abortando")
    if abs(peso - args.nota_maxima_esperada) > 1e-9 and not args.aceitar_peso_diferente:
        raise ErroSiga(f"peso da avaliacao e {peso}, mas o esperado e "
                       f"{args.nota_maxima_esperada}; confira a escala antes de lancar")

    alunos = dados.get("alunos") or []
    if not alunos:
        raise ErroSiga("a turma nao retornou alunos")
    plano = (plano_por_matriculas(args, alunos) if args.aluno
             else plano_por_indices(args, alunos))
    validar_plano(plano, args.max_alunos)

    alvo_id = str(alvo.get("id"))
    por_matricula = {str(a.get("matricula", "")).strip(): a for a in alunos}
    print(f"turma={args.turma} periodo={args.periodo} avaliacao={AVALIACAO!r} id={alvo_id} peso={peso:g}")
    print("plano (moedas -> nota):")
    notas: dict[str, float] = {}
    for matricula, moedas in plano:
        nota = calcular_nota(moedas, peso)
        notas[matricula] = nota
        antes = nota_do_aluno(por_matricula[matricula], alvo)
        print(f"  {mascarar(matricula)}: {moedas} -> {nota:.1f}  (antes: {antes!r})")

    if not args.confirmar:
        print("\nDRY-RUN: nada foi enviado. Repita com --confirmar para lancar.")
        return 0

    caminho_backup = backup(dados, alvo, plano, args.backup_dir)
    print(f"\nbackup local: {caminho_backup}")

    resposta = siga.lancar(args.turma, args.periodo, notas)
    print("POST /api/lancar-notas: aceito")
    if isinstance(resposta, dict):
        # A resposta pode variar; mostre apenas chaves e contagens, sem nomes.
        resumo = {k: (len(v) if isinstance(v, (list, dict)) else v)
                  for k, v in resposta.items() if k in ("mensagem", "sucesso", "total", "erros", "resultados")}
        if resumo:
            print("resposta:", json.dumps(resumo, ensure_ascii=False)[:500])

    # Confere pela mesma fonte que o professor usa, sem confiar so no POST.
    conferencia = siga.notas(args.turma, args.periodo)
    depois = {str(a.get("matricula", "")).strip(): a for a in conferencia.get("alunos", [])}
    falhas: list[str] = []
    print("conferencia:")
    for matricula, esperado in notas.items():
        atual = nota_do_aluno(depois.get(matricula, {}), alvo)
        numero = None
        if atual is not None:
            try:
                numero = float(str(atual).replace(",", "."))
            except (TypeError, ValueError):
                numero = None
        ok = numero is not None and abs(numero - esperado) < 1e-6
        print(f"  {mascarar(matricula)}: esperado={esperado:.1f} atual={atual!r} {'OK' if ok else 'DIVERGENTE'}")
        if not ok:
            falhas.append(mascarar(matricula))
    if falhas:
        print(f"\nERRO: {len(falhas)} nota(s) nao conferem: {', '.join(falhas)}", file=sys.stderr)
        return 2
    print("\nOK: todas as notas do plano foram confirmadas no SIGA.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ErroSiga as erro:
        print(f"ERRO: {erro}", file=sys.stderr)
        raise SystemExit(1)
