// Edge Function: envia ao SIGA somente a nota do proprio aluno autenticado.
//
// A SIGA_API_KEY fica nos segredos da funcao, nunca no jogo. O cliente envia
// apenas o semestre interno; a funcao le perfil e progresso pelo JWT do aluno
// (RLS), confere que a avaliacao "Game Educativo Statown" ja existe na turma,
// recalcula a nota pelas moedas ganhas e grava a matricula do proprio aluno.
//
// Deploy: docs/SUPABASE.md, secao "Botao ENVIAR AO SIGA (aluno)".
// Variaveis de ambiente: SIGA_API_KEY (obrigatoria); SIGA_API_BASE (opcional).

const AVALIACAO = "Game Educativo Statown";
const SIGA_BASE = (Deno.env.get("SIGA_API_BASE") ?? "https://siga-api.sparklingtech.com.br")
  .replace(/\/+$/, "");
const SIGA_KEY = Deno.env.get("SIGA_API_KEY") ?? "";
const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SUPABASE_ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

type Corpo = Record<string, unknown>;

function responder(status: number, corpo: Corpo): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" },
  });
}

function erro(status: number, mensagem: string): Response {
  return responder(status, { ok: false, erro: mensagem });
}

function normalizar(texto: string): string {
  return texto.normalize("NFD").replace(/\p{Diacritic}/gu, "").trim().toLowerCase();
}

export function calcularNota(moedas: number, peso: number): number {
  const limite = Math.max(1, Math.round(peso * 10));
  const moedasValidas = Math.min(Math.max(0, Math.trunc(moedas)), 1000);
  const decimos = Math.min(limite, Math.floor((moedasValidas * limite) / 1000));
  return decimos / 10;
}

/** Semestre interno do jogo no fuso de Sao Paulo: ano/1 ate junho, ano/2 de julho em diante. */
export function semestreAtual(agora: Date = new Date()): string {
  const partes = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
  }).formatToParts(agora);
  const ano = partes.find((p) => p.type === "year")?.value ?? "";
  const mes = Number(partes.find((p) => p.type === "month")?.value ?? "1");
  return `${ano}/${mes >= 7 ? 2 : 1}`;
}

function formatarNota(nota: number): string {
  return nota.toFixed(1).replace(".", ",");
}

function lerNotaDoAluno(aluno: Corpo, alvo: Corpo): number | null {
  const notas = aluno["notas"];
  if (notas === null || typeof notas !== "object" || Array.isArray(notas)) return null;
  const mapa = notas as Record<string, unknown>;
  const chaves = [String(alvo["id"] ?? ""), AVALIACAO, String(alvo["descricao"] ?? "")];
  for (const chave of chaves) {
    if (chave !== "" && Object.prototype.hasOwnProperty.call(mapa, chave)) {
      const n = Number(String(mapa[chave]).replace(",", "."));
      return Number.isFinite(n) ? n : null;
    }
  }
  for (const [chave, valor] of Object.entries(mapa)) {
    if (normalizar(chave) === normalizar(AVALIACAO)) {
      const n = Number(String(valor).replace(",", "."));
      return Number.isFinite(n) ? n : null;
    }
  }
  return null;
}

async function lerJson(entrada: Request | Response): Promise<Corpo> {
  const texto = await entrada.text();
  if (texto === "") return {};
  const dados = JSON.parse(texto);
  if (dados === null || typeof dados !== "object" || Array.isArray(dados)) {
    throw new Error("resposta sem objeto JSON");
  }
  return dados as Corpo;
}

async function sigaGet(caminho: string): Promise<Corpo> {
  const resposta = await fetch(SIGA_BASE + caminho, {
    headers: { "X-API-Key": SIGA_KEY, "Accept": "application/json" },
    signal: AbortSignal.timeout(15000),
  });
  if (!resposta.ok) throw new Error("SIGA GET HTTP " + resposta.status);
  return lerJson(resposta);
}

async function sigaPost(caminho: string, corpo: Corpo): Promise<void> {
  const resposta = await fetch(SIGA_BASE + caminho, {
    method: "POST",
    headers: {
      "X-API-Key": SIGA_KEY,
      "Accept": "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(corpo),
    signal: AbortSignal.timeout(20000),
  });
  // Nunca devolva o corpo do SIGA ao navegador: ele pode conter a turma toda.
  if (!resposta.ok) throw new Error("SIGA POST HTTP " + resposta.status);
}

async function restGet(caminho: string, token: string): Promise<Corpo[]> {
  const resposta = await fetch(`${SUPABASE_URL}/rest/v1/${caminho}`, {
    headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(12000),
  });
  if (!resposta.ok) throw new Error("Supabase HTTP " + resposta.status);
  const dados = await resposta.json();
  return Array.isArray(dados) ? dados as Corpo[] : [];
}

Deno.serve(async (solicitacao: Request): Promise<Response> => {
  if (solicitacao.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }
  if (solicitacao.method !== "POST") {
    return erro(405, "Metodo nao permitido.");
  }
  if (SIGA_KEY === "" || SUPABASE_URL === "" || SUPABASE_ANON === "") {
    return erro(503, "Servico de envio ainda nao configurado. Avise o professor.");
  }

  const autorizacao = solicitacao.headers.get("Authorization") ?? "";
  const token = autorizacao.replace(/^Bearer\s+/i, "").trim();
  if (token === "") return erro(401, "Entre na conta para enviar a nota.");

  let corpo: Corpo;
  try {
    corpo = await lerJson(solicitacao);
  } catch {
    return erro(400, "Pedido de envio invalido.");
  }
  const semestre = String(corpo["semestre"] ?? "").trim();
  if (!/^[0-9]{4}\/[12]$/.test(semestre)) {
    return erro(400, "Semestre interno invalido.");
  }
  if (semestre !== semestreAtual()) {
    return erro(409, "O semestre do jogo nao confere com o calendario atual. Recarregue a pagina.");
  }

  try {
    // O gateway do Supabase ja valida o JWT; esta chamada confirma a identidade
    // e impede confiar apenas no payload decodificado no cliente.
    const usuarioResp = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(10000),
    });
    if (!usuarioResp.ok) return erro(401, "Sessao expirada. Entre novamente.");
    const usuario = await lerJson(usuarioResp);
    const uid = String(usuario["id"] ?? "");
    if (uid === "") return erro(401, "Sessao invalida. Entre novamente.");

    const perfis = await restGet(
      `statown_alunos?select=matricula,turma,periodo_siga&id=eq.${encodeURIComponent(uid)}&limit=1`,
      token,
    );
    if (perfis.length === 0) return erro(422, "Perfil do aluno nao encontrado. Avise o professor.");
    const perfil = perfis[0];
    const matricula = String(perfil["matricula"] ?? "").trim();
    const turma = String(perfil["turma"] ?? "").trim();
    const periodo = String(perfil["periodo_siga"] ?? "").trim();
    if (matricula === "" || turma === "" || periodo === "") {
      return erro(422, "Perfil sem matricula, turma ou periodo do SIGA. Avise o professor.");
    }

    const progressos = await restGet(
      `statown_progresso?select=moedas_ganhas&aluno_id=eq.${encodeURIComponent(uid)}` +
        `&semestre=eq.${encodeURIComponent(semestre)}&limit=1`,
      token,
    );
    if (progressos.length === 0) {
      return erro(409, "Ainda nao ha progresso sincronizado neste semestre. Jogue uma semana primeiro.");
    }
    const moedas = Number(progressos[0]["moedas_ganhas"] ?? 0);
    if (!Number.isFinite(moedas) || moedas < 0) {
      return erro(409, "O progresso sincronizado tem moedas invalidas.");
    }

    const consulta = `/api/notas?turma=${encodeURIComponent(turma)}&periodo=${encodeURIComponent(periodo)}`;
    const dados = await sigaGet(consulta);
    const avaliacoes = Array.isArray(dados["avaliacoes"]) ? dados["avaliacoes"] as Corpo[] : [];
    const alvos = avaliacoes.filter((a) =>
      normalizar(String(a["descricao"] ?? "")) === normalizar(AVALIACAO)
    );
    if (alvos.length === 0) {
      // Nao existe chamada de criacao aqui: a avaliacao tem de existir antes.
      return erro(409, `A avaliacao "${AVALIACAO}" nao existe nesta turma. Nada foi enviado.`);
    }
    if (alvos.length > 1) {
      return erro(409, `Ha mais de uma avaliacao "${AVALIACAO}" nesta turma. Avise o professor.`);
    }
    const alvo = alvos[0];
    const peso = Number(alvo["peso"] ?? 0);
    if (!Number.isFinite(peso) || peso <= 0) {
      return erro(422, "A avaliacao do SIGA esta sem peso valido. Nada foi enviado.");
    }

    const alunos = Array.isArray(dados["alunos"]) ? dados["alunos"] as Corpo[] : [];
    const aluno = alunos.find((a) => String(a["matricula"] ?? "").trim() === matricula);
    if (aluno === undefined) {
      return erro(409, "Sua matricula nao aparece na turma do SIGA. Avise o professor.");
    }

    const nota = calcularNota(moedas, peso);
    const atual = lerNotaDoAluno(aluno, alvo);
    const base = {
      ok: true,
      avaliacao: AVALIACAO,
      nota,
      nota_maxima: peso,
      moedas_ganhas: Math.min(Math.trunc(moedas), 1000),
      semestre,
      turma,
      periodo,
    };

    if (atual !== null && Math.abs(atual - nota) < 0.05) {
      return responder(200, {
        ...base,
        enviado: false,
        mensagem: `Sua nota ${formatarNota(nota)} ja estava registrada no SIGA.`,
      });
    }

    await sigaPost("/api/lancar-notas", {
      turma,
      periodo,
      descricao_avaliacao: AVALIACAO,
      notas_json: { [matricula]: nota },
    });

    // Confere pela mesma fonte que o professor usa, sem confiar so no POST.
    await new Promise((resolver) => setTimeout(resolver, 400));
    const conferencia = await sigaGet(consulta);
    const alunosDepois = Array.isArray(conferencia["alunos"]) ? conferencia["alunos"] as Corpo[] : [];
    const alunoDepois = alunosDepois.find((a) => String(a["matricula"] ?? "").trim() === matricula);
    const confirmada = alunoDepois === undefined ? null : lerNotaDoAluno(alunoDepois, alvo);
    if (confirmada === null || Math.abs(confirmada - nota) >= 0.05) {
      return erro(502, "O SIGA aceitou o envio, mas a conferencia ainda nao retornou a nota. Tente novamente em instantes.");
    }

    return responder(200, {
      ...base,
      enviado: true,
      mensagem: `Nota ${formatarNota(nota)} enviada ao SIGA (${AVALIACAO}).`,
    });
  } catch (falha) {
    // Nao registre corpo de resposta do SIGA: ele contem dados da turma.
    const detalhe = falha instanceof Error ? falha.message : "erro desconhecido";
    if (detalhe.startsWith("SIGA GET") || detalhe.startsWith("SIGA POST")) {
      return erro(502, "O SIGA nao respondeu como esperado. Nada foi confirmado; tente de novo.");
    }
    if (detalhe.startsWith("Supabase HTTP") || detalhe.startsWith("resposta sem objeto")) {
      return erro(502, "Nao foi possivel ler o progresso no servidor. Tente de novo.");
    }
    return erro(502, "Falha ao enviar a nota. Tente novamente em instantes.");
  }
});
