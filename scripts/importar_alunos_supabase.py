#!/usr/bin/env python3
"""Importa as listas de turma do SIGA para o Supabase do StaTown.

Uso (com a service_role em ~/.dsh/secrets/statown.env, nunca no repositorio):

    python3 scripts/importar_alunos_supabase.py --pasta ~/.dsh/dados/2026-3
    python3 scripts/importar_alunos_supabase.py --pasta ~/.dsh/dados/2026-3 --ensaio

O que faz, de forma idempotente:

1. le cada CSV ISO-8859-1/windows-1252 cujo nome e
   CODIGO_A_AAAA_S.csv (ex.: CBV018GV_A_2026_3.csv);
2. deriva turma=CBV018GV-A e periodo_siga=2026/3 do nome do arquivo;
3. cria a conta Auth que ainda nao existe, com login=senha inicial=email
   institucional (E-MAIL CONTA GSUITE) e email ja confirmado;
4. atualiza nome, matricula, turma e periodo no perfil e no user_metadata;
5. nao troca a senha de quem ja existe (preserva a troca feita pelo aluno).

O arquivo de credenciais deve ter SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.
A service_role so e usada aqui, fora do jogo e fora do build web. A migration
docs/SUPABASE_TURMAS.sql precisa ter sido aplicada antes (o script verifica).
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ARQUIVO_RE = re.compile(r"^([A-Z]{3}\d{3}GV)_([A-Z])_(\d{4})_(\d)\.csv$", re.IGNORECASE)
EMAIL_RE = re.compile(r"^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$")
CAMPOS = ("MATRICULA", "NOME", "E-MAIL DE CONTATO", "E-MAIL CONTA GSUITE", "SITUACAO")


@dataclass(frozen=True)
class Aluno:
    turma: str
    periodo_siga: str
    matricula: str
    nome: str
    email: str
    situacao: str
    arquivo: str


class ErroHTTP(RuntimeError):
    def __init__(self, metodo: str, caminho: str, status: int, corpo: str) -> None:
        super().__init__(f"{metodo} {caminho} -> HTTP {status}: {corpo[:300]}")
        self.status = status
        self.corpo = corpo


def carregar_env(caminho: Path) -> None:
    """Le KEY=VALUE sem imprimir valores e sem sobrescrever o ambiente."""
    if not caminho.exists():
        return
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        chave = chave.strip()
        valor = valor.strip().strip('"').strip("'")
        if chave and valor and chave not in os.environ:
            os.environ[chave] = valor


def normalizar_nome(valor: str) -> str:
    valor = valor.replace("\xa0", " ")
    valor = re.sub(r"\s+", " ", valor).strip()
    return valor.rstrip(".").strip()


def ler_lista(caminho: Path) -> list[Aluno]:
    m = ARQUIVO_RE.match(caminho.name)
    if not m:
        raise ValueError(
            f"nome fora do padrao CODIGO_A_AAAA_S.csv: {caminho.name}"
        )
    codigo, letra, ano, semestre = m.groups()
    turma = f"{codigo.upper()}-{letra.upper()}"
    periodo_siga = f"{ano}/{semestre}"

    texto = caminho.read_bytes().decode("cp1252")
    leitor = csv.DictReader(io.StringIO(texto), delimiter=";")
    if leitor.fieldnames is None:
        raise ValueError(f"{caminho.name}: CSV sem cabecalho")
    faltando = [c for c in CAMPOS if c not in leitor.fieldnames]
    if faltando:
        raise ValueError(f"{caminho.name}: colunas ausentes: {', '.join(faltando)}")

    alunos: list[Aluno] = []
    for numero, linha in enumerate(leitor, start=2):
        matricula = (linha.get("MATRICULA") or "").strip()
        nome = normalizar_nome(linha.get("NOME") or "")
        email = (linha.get("E-MAIL CONTA GSUITE") or "").strip().lower()
        situacao = (linha.get("SITUACAO") or "").strip()
        if not matricula and not nome and not email:
            continue
        if not matricula or not nome:
            raise ValueError(f"{caminho.name}:{numero}: matricula/nome vazio")
        if not email:
            raise ValueError(
                f"{caminho.name}:{numero}: {matricula} sem E-MAIL CONTA GSUITE"
            )
        if len(email) > 254 or not EMAIL_RE.match(email) or ".." in email:
            raise ValueError(f"{caminho.name}:{numero}: e-mail invalido: {email}")
        alunos.append(
            Aluno(
                turma=turma,
                periodo_siga=periodo_siga,
                matricula=matricula,
                nome=nome,
                email=email,
                situacao=situacao,
                arquivo=caminho.name,
            )
        )
    return alunos


def reunir_alunos(pasta: Path) -> list[Aluno]:
    arquivos = sorted(p for p in pasta.iterdir() if p.is_file() and ARQUIVO_RE.match(p.name))
    if not arquivos:
        raise ValueError(
            f"nenhum CSV de turma em {pasta}; esperado algo como CBV018GV_A_2026_3.csv"
        )
    alunos: list[Aluno] = []
    for arquivo in arquivos:
        alunos.extend(ler_lista(arquivo))
    if not alunos:
        raise ValueError("as listas estao vazias")
    emails = [a.email for a in alunos]
    matriculas = [a.matricula for a in alunos]
    if len(set(emails)) != len(emails):
        repetidos = sorted({e for e in emails if emails.count(e) > 1})
        raise ValueError(f"e-mails duplicados nas listas: {', '.join(repetidos)}")
    if len(set(matriculas)) != len(matriculas):
        repetidos = sorted({m for m in matriculas if matriculas.count(m) > 1})
        raise ValueError(f"matriculas duplicadas nas listas: {', '.join(repetidos)}")
    return alunos


class Supabase:
    def __init__(self, url: str, chave: str) -> None:
        self.url = url.rstrip("/")
        self.chave = chave

    def _pedido(
        self,
        metodo: str,
        caminho: str,
        corpo: dict[str, Any] | list[dict[str, Any]] | None = None,
        prefer: str | None = None,
    ) -> Any:
        dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8") if corpo is not None else None
        headers = {
            "apikey": self.chave,
            "Authorization": f"Bearer {self.chave}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        if prefer:
            headers["Prefer"] = prefer
        req = urllib.request.Request(
            self.url + caminho,
            data=dados,
            headers=headers,
            method=metodo,
        )
        ultimo_erro: Exception | None = None
        for tentativa in range(4):
            try:
                with urllib.request.urlopen(req, timeout=45) as resposta:
                    bruto = resposta.read()
                    return json.loads(bruto) if bruto else None
            except urllib.error.HTTPError as erro:
                texto = erro.read().decode("utf-8", "replace")
                if erro.code in (429, 502, 503, 504) and tentativa < 3:
                    time.sleep(2 ** tentativa)
                    continue
                raise ErroHTTP(metodo, caminho, erro.code, texto) from erro
            except (urllib.error.URLError, TimeoutError) as erro:
                ultimo_erro = erro
                if tentativa < 3:
                    time.sleep(2 ** tentativa)
                    continue
                raise RuntimeError(f"falha de rede em {caminho}: {erro}") from erro
        raise RuntimeError(f"falha de rede em {caminho}: {ultimo_erro}")

    def verificar_admin(self) -> None:
        dados = self._pedido("GET", "/auth/v1/admin/users?page=1&per_page=1")
        if not isinstance(dados, dict) or "users" not in dados:
            raise RuntimeError("a Auth Admin API nao respondeu como esperado")

    def verificar_schema(self) -> None:
        try:
            self._pedido(
                "GET",
                "/rest/v1/statown_alunos?select=id,turma,periodo_siga&limit=1",
            )
        except ErroHTTP as erro:
            if erro.status in (400, 404) and (
                "turma" in erro.corpo or "periodo_siga" in erro.corpo
            ):
                raise RuntimeError(
                    "a coluna turma/periodo_siga ainda nao existe; aplique "
                    "docs/SUPABASE_TURMAS.sql antes de importar"
                ) from erro
            raise

    def perfis(self) -> dict[str, dict[str, Any]]:
        """Mapa matricula -> perfil, para nao criar uma segunda conta da mesma pessoa."""
        dados = self._pedido(
            "GET",
            "/rest/v1/statown_alunos?select=id,email,matricula&limit=1000",
        )
        mapa: dict[str, dict[str, Any]] = {}
        for perfil in dados if isinstance(dados, list) else []:
            matricula = str(perfil.get("matricula") or "").strip()
            if matricula:
                mapa[matricula] = perfil
        return mapa

    def usuarios(self) -> dict[str, dict[str, Any]]:
        mapa: dict[str, dict[str, Any]] = {}
        for pagina in range(1, 31):
            dados = self._pedido(
                "GET", f"/auth/v1/admin/users?page={pagina}&per_page=200"
            )
            usuarios = dados.get("users", []) if isinstance(dados, dict) else []
            for usuario in usuarios:
                email = str(usuario.get("email", "")).lower()
                if email:
                    mapa[email] = usuario
            if len(usuarios) < 200:
                break
        return mapa

    def criar_usuario(self, aluno: Aluno) -> dict[str, Any]:
        corpo = {
            "email": aluno.email,
            "password": aluno.email,
            "email_confirm": True,
            "user_metadata": {
                "nome": aluno.nome,
                "matricula": aluno.matricula,
                "turma": aluno.turma,
                "periodo_siga": aluno.periodo_siga,
            },
        }
        try:
            return self._pedido("POST", "/auth/v1/admin/users", corpo)
        except ErroHTTP as erro:
            if erro.status == 422 and "already" in erro.corpo.lower():
                existentes = self.usuarios()
                if aluno.email in existentes:
                    return existentes[aluno.email]
            raise

    def atualizar_usuario(self, usuario_id: str, aluno: Aluno, metadata: dict[str, Any]) -> None:
        mesclado = dict(metadata)
        mesclado.update(
            {
                "nome": aluno.nome,
                "matricula": aluno.matricula,
                "turma": aluno.turma,
                "periodo_siga": aluno.periodo_siga,
            }
        )
        corpo: dict[str, Any] = {"user_metadata": mesclado, "email_confirm": True}
        if not usuario_id:
            raise RuntimeError(f"usuario sem id para {aluno.email}")
        self._pedido("PUT", f"/auth/v1/admin/users/{usuario_id}", corpo)

    def sincronizar_perfil(self, aluno: Aluno, usuario_id: str) -> None:
        corpo = [
            {
                "id": usuario_id,
                "email": aluno.email,
                "nome": aluno.nome,
                "matricula": aluno.matricula,
                "turma": aluno.turma,
                "periodo_siga": aluno.periodo_siga,
            }
        ]
        self._pedido(
            "POST",
            "/rest/v1/statown_alunos?on_conflict=id",
            corpo,
            prefer="resolution=merge-duplicates,return=minimal",
        )


def resumo_por_turma(alunos: list[Aluno]) -> dict[str, dict[str, Any]]:
    resumo: dict[str, dict[str, Any]] = {}
    for aluno in alunos:
        item = resumo.setdefault(
            aluno.turma, {"periodo": aluno.periodo_siga, "total": 0}
        )
        item["total"] += 1
        if item["periodo"] != aluno.periodo_siga:
            raise ValueError(f"a turma {aluno.turma} aparece em mais de um periodo")
    return resumo


def mascarar(email: str) -> str:
    local, _, dominio = email.partition("@")
    if len(local) <= 2:
        return f"**@{dominio}"
    return f"{local[0]}***{local[-1]}@{dominio}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pasta",
        type=Path,
        default=Path.home() / ".dsh" / "dados" / "2026-3",
        help="pasta com os CSVs das turmas",
    )
    parser.add_argument(
        "--env-file",
        type=Path,
        default=Path.home() / ".dsh" / "secrets" / "statown.env",
        help="arquivo local com SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY",
    )
    parser.add_argument(
        "--ensaio",
        action="store_true",
        help="valida as listas e o acesso, mas nao grava nada",
    )
    args = parser.parse_args()

    carregar_env(args.env_file)
    url = os.environ.get("SUPABASE_URL", "").strip()
    chave = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not chave:
        print(
            "ERRO: preencha SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY em "
            f"{args.env_file} (arquivo local, fora do repositorio).",
            file=sys.stderr,
        )
        return 2
    if not url.startswith("https://"):
        print("ERRO: SUPABASE_URL deve comecar com https://", file=sys.stderr)
        return 2

    try:
        alunos = reunir_alunos(args.pasta)
    except (OSError, ValueError) as erro:
        print(f"ERRO nas listas: {erro}", file=sys.stderr)
        return 2

    resumo = resumo_por_turma(alunos)
    print(f"Listas: {len(alunos)} alunos em {len(resumo)} turmas")
    for turma in sorted(resumo):
        item = resumo[turma]
        print(f"  {turma} ({item['periodo']}): {item['total']} alunos")

    api = Supabase(url, chave)
    try:
        api.verificar_admin()
        api.verificar_schema()
        existentes = api.usuarios()
        perfis = api.perfis()
    except (ErroHTTP, RuntimeError) as erro:
        print(f"ERRO de acesso ao Supabase: {erro}", file=sys.stderr)
        if isinstance(erro, ErroHTTP) and erro.status in (401, 403):
            print(
                "Confira a service_role (Project Settings > API Keys) no arquivo local.",
                file=sys.stderr,
            )
        return 2

    # A conta antiga pode ter sido criada com e-mail pessoal. Nesse caso, criar
    # outra conta com o e-mail institucional duplicaria a pessoa; o professor
    # precisa decidir manualmente qual conta manter.
    conflitos: list[str] = []
    for aluno in alunos:
        perfil = perfis.get(aluno.matricula)
        if perfil is not None:
            email_perfil = str(perfil.get("email") or "").strip().lower()
            if email_perfil != aluno.email:
                conflitos.append(
                    f"matricula {aluno.matricula}: perfil usa {mascarar(email_perfil)}; "
                    f"lista usa {mascarar(aluno.email)}"
                )
    if conflitos:
        print("ERRO: ha alunos ja cadastrados com outro e-mail:", file=sys.stderr)
        for conflito in conflitos:
            print(f"  - {conflito}", file=sys.stderr)
        print(
            "Resolva no Supabase (mantenha uma conta por matricula) e rode de novo; "
            "nada foi gravado.",
            file=sys.stderr,
        )
        return 1

    novos = [a for a in alunos if a.email not in existentes]
    atuais = [a for a in alunos if a.email in existentes]
    print(f"Contas: {len(atuais)} ja existem, {len(novos)} serao criadas")
    if args.ensaio:
        print("ENSAIO: nada foi gravado.")
        for aluno in alunos:
            estado = "existe" if aluno.email in existentes else "criar"
            print(f"  {aluno.turma:12} {aluno.matricula:14} {mascarar(aluno.email):40} {estado}")
        return 0

    criadas = 0
    atualizadas = 0
    perfis = 0
    falhas: list[str] = []
    for indice, aluno in enumerate(alunos, start=1):
        try:
            usuario = existentes.get(aluno.email)
            if usuario is None:
                usuario = api.criar_usuario(aluno)
                criadas += 1
            else:
                metadata = usuario.get("user_metadata") or {}
                api.atualizar_usuario(str(usuario.get("id", "")), aluno, metadata)
                atualizadas += 1
            usuario_id = str(usuario.get("id", ""))
            if not usuario_id:
                raise RuntimeError(f"Auth nao retornou id para {aluno.email}")
            api.sincronizar_perfil(aluno, usuario_id)
            perfis += 1
            if indice % 10 == 0 or indice == len(alunos):
                print(f"  ... {indice}/{len(alunos)}")
        except (ErroHTTP, RuntimeError) as erro:
            falhas.append(f"{aluno.matricula} ({mascarar(aluno.email)}): {erro}")
            print(f"  FALHA {aluno.matricula}: {erro}", file=sys.stderr)

    print(
        f"Concluido: {criadas} conta(s) criada(s), {atualizadas} existente(s), "
        f"{perfis} perfil(is) sincronizado(s), {len(falhas)} falha(s)."
    )
    if falhas:
        print("Falhas:", file=sys.stderr)
        for falha in falhas:
            print(f"  - {falha}", file=sys.stderr)
        return 1
    print("Senha inicial dos novos alunos = e-mail institucional (GSUITE).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
