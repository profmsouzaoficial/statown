// Testes puros da regra de nota e do semestre interno.
// Nao chamam Supabase nem SIGA; o Deno.serve e substituido antes do import
// para o modulo da funcao nao abrir uma porta durante o teste.
const servidorOriginal = Deno.serve;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = () => ({
  finished: Promise.resolve(),
  shutdown: () => Promise.resolve(),
  ref: () => {},
  unref: () => {},
});
const { calcularNota, semestreAtual } = await import("./index.ts");
// deno-lint-ignore no-explicit-any
(Deno as any).serve = servidorOriginal;

function perto(obtido: number, esperado: number): boolean {
  return Math.abs(obtido - esperado) < 1e-9;
}

Deno.test("nota usa 1000 moedas ganhas como teto do peso", () => {
  const casos: Array<[number, number, number]> = [
    [0, 40, 0],
    [1, 40, 0],
    [333, 40, 13.3],
    [500, 40, 20],
    [999, 40, 39.9],
    [1000, 40, 40],
    [2500, 40, 40],
  ];
  for (const [moedas, peso, esperado] of casos) {
    const obtido = calcularNota(moedas, peso);
    if (!perto(obtido, esperado)) {
      throw new Error(`moedas=${moedas} peso=${peso}: obtido ${obtido}, esperado ${esperado}`);
    }
  }
});

Deno.test("nota respeita peso diferente de 40 sem regra de tres quebrada", () => {
  if (!perto(calcularNota(500, 10), 5)) throw new Error("500/1000 de 10 deveria ser 5");
  if (!perto(calcularNota(1000, 25), 25)) throw new Error("1000/1000 de 25 deveria ser 25");
  if (!perto(calcularNota(100, 7), 0.7)) throw new Error("100/1000 de 7 deveria ser 0,7");
});

Deno.test("semestre interno vira no dia 1 de julho no fuso de Sao Paulo", () => {
  if (semestreAtual(new Date("2026-06-30T23:59:00-03:00")) !== "2026/1") {
    throw new Error("30/06 deveria ser 2026/1");
  }
  if (semestreAtual(new Date("2026-07-01T00:00:00-03:00")) !== "2026/2") {
    throw new Error("01/07 deveria ser 2026/2");
  }
  if (semestreAtual(new Date("2026-12-31T23:59:00-03:00")) !== "2026/2") {
    throw new Error("31/12 deveria ser 2026/2");
  }
  // 01/07 01:00 UTC ainda e 30/06 22:00 em Sao Paulo.
  if (semestreAtual(new Date("2026-07-01T01:00:00Z")) !== "2026/1") {
    throw new Error("a virada deve usar o fuso de Sao Paulo, nao UTC");
  }
});
