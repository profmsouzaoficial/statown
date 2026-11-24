# Contas, progresso e nota no Supabase

Este documento é o passo a passo para ativar o login do StaTown. O jogo continua
funcionando **sem** Supabase (modo local); com o projeto configurado, a semana
epidemiológica, o ano, as BioMoedas e o extrato passam a ser gravados por aluno e por
semestre.

> **Princípio:** o build web é público. Qualquer chave embutida no jogo pode ser lida
> no navegador. Por isso a única chave aceitável no cliente é a **anon key**, que é
> pública por projeto. A `service_role` **nunca** entra no jogo, no GitHub ou no
> Vercel. As regras de acesso ficam no banco (RLS + RPCs).

---

## 1. O que o recurso faz

| Situação | Comportamento |
|---|---|
| Sem `config/supabase.json` preenchido | Tela de conta explica que o backend não está configurado e oferece **CONTINUAR SEM CONTA**. O save fica neste navegador. |
| Com Supabase, aluno novo | Cria a conta em `auth.users`; o perfil nasce em `statown_alunos`; o progresso local é enviado ao servidor. |
| Aluno volta em outro computador | Faz login, baixa o save do semestre atual e continua da semana em que parou. |
| Semana avança / moedas mudam | O jogo envia o save ao Supabase a cada ~12 s, ao perder o foco e em pontos importantes. |
| Tela de login aberta | A simulação fica pausada; nenhuma semana passa atrás do formulário. |
| Sem internet | O jogo avisa, mantém o save local e tenta de novo; a nota no servidor pode ficar atrasada. |
| Semestre novo (`2026/1` → `2026/2`) | Começa uma linha nova no banco e uma participação nova; o save do semestre anterior não é reaproveitado. |

O semestre é calculado pela data do sistema: **janeiro a junho = `AAAA/1`**;
**julho a dezembro = `AAAA/2`**.

---

## 2. Criar o projeto Supabase

1. Entre em <https://supabase.com> e crie um projeto novo (plano gratuito serve para
   uma turma).
2. Guarde a **Project URL** e a **anon public key** em
   **Project Settings → API**.
3. Abra **SQL Editor**, cole todo o conteúdo de
   [`docs/SUPABASE.sql`](SUPABASE.sql) e execute. O script é idempotente: pode ser
   rodado de novo após atualizações.
4. Para guardar também o acervo da Revista, execute em seguida
   [`docs/SUPABASE_ARTIGOS.sql`](SUPABASE_ARTIGOS.sql). Ele cria
   `public.statown_artigos` e carrega os 50 artigos reais do PubMed/NLM.
5. Em **Authentication → Providers → Email**, deixe **Enable email provider** ligado.
   Para uma disciplina, o mais simples é **desligar “Confirm email”** enquanto testa;
   em produção, deixe ligado e oriente o aluno a confirmar o e-mail.
6. Em **Authentication → URL Configuration**, coloque a URL pública do jogo (Vercel)
   em **Site URL** e adicione `http://localhost:*` se for testar localmente.
7. Se o projeto usar confirmação de e-mail, configure um remetente em
   **Authentication → Emails**. Sem SMTP próprio, o Supabase tem limite de envio.

### O que o SQL cria

- `statown_alunos`: perfil (nome, e-mail, matrícula, flag `professor`).
- `statown_progresso`: uma linha por `(aluno_id, semestre)`, com semana, ano, saldo,
  moedas ganhas/gastas, `nota` gerada e o save completo em `jsonb`.
- Trigger em `auth.users`: cria/atualiza o perfil no cadastro.
- `statown_carregar(p_semestre)`: devolve só a linha do próprio aluno.
- `statown_salvar(p_semestre, p_save)`: valida e faz upsert do próprio progresso.
- `statown_notas`: visão para o professor consultar a turma.
- `statown_artigos` (script separado): acervo público, somente leitura, com título,
  autores, periódico, ano, DOI, PMID, tipo, resumo original, tradução PT-BR
  (`titulo_pt`, `resumo_pt`, `secoes_pt`) e metadados de fonte.
- RLS: aluno lê o próprio perfil/progresso; professor lê a turma; ninguém escreve
  direto nas tabelas — só pelas RPCs.

A nota é `min(100, moedas_ganhas / 10)` (divisão inteira), calculada **no banco**.
Ela usa as moedas **ganhas no semestre**, não o saldo que sobrou: gastar numa
intervenção não reduz a nota duas vezes. O teto de 100 pontos é aplicado no banco.

---

## 3. Configurar o jogo

Edite [`config/supabase.json`](../config/supabase.json):

```json
{
  "habilitado": true,
  "url": "https://SEU-PROJETO.supabase.co",
  "anon_key": "eyJhbGciOi...SUA_ANON_KEY..."
}
```

Regras:

- `url` sem barra no final.
- `anon_key` é a chave **anon public**, não a `service_role`.
- `habilitado: false` ou campos vazios = modo local, sem tentativa de rede.
- O arquivo entra no PCK do build (não é segredo). Não coloque senha, token pessoal
  ou chave administrativa nele.

Depois de editar, rode o jogo localmente e exporte de novo:

```bash
GODOT=/home/marcio/opt/godot/godot
$GODOT --headless --path . --import
$GODOT --headless res://tests/SmokeUI.tscn
$GODOT --headless res://tests/TestEconomia.tscn
$GODOT --headless res://tests/TestDesafios.tscn
$GODOT --headless res://tests/TestRevista.tscn
```

Para publicar, faça commit de `config/supabase.json` e deixe o GitHub Actions
recompilar. O workflow inclui `config/` no build porque o filtro é `all_resources`.

---

## 4. Cadastro e login no jogo

1. Abra o jogo. Se o Supabase estiver configurado e não houver sessão, aparece a
   tela **CONTA DO ALUNO**.
2. **CRIAR CONTA**: informe nome, matrícula (opcional), e-mail e senha (mínimo 6
   caracteres no Supabase por padrão).
3. Se a confirmação de e-mail estiver ligada, confirme antes de entrar.
4. **ENTRAR**: o jogo baixa o progresso do semestre. Se for a primeira vez, sobe o
   save local como primeira fotografia.
5. O botão **CONTA** na HUD permite ver a sessão, sincronizar e sair.
6. Se o download falhar, a tela **não** libera o upload: ela mostra o erro e oferece
   **TENTAR BAIXAR DE NOVO** ou **JOGAR SEM SINCRONIZAR**. A segunda opção deixa
   jogar, mas mantém o envio bloqueado até um download bem-sucedido; é uma proteção
   para não sobrescrever o save de outro computador com uma partida vazia. O progresso
   feito nesse intervalo fica **somente** no cache local e pode ser substituído pelo
   save da nuvem quando o download voltar — avise o aluno e prefira tentar de novo.

O jogo **não guarda a senha**. Ele guarda apenas o token de sessão em
`user://statown_sessao.json`, que é específico daquele navegador/computador. Sair
apaga esse arquivo. Em computador compartilhado, oriente o aluno a usar **SAIR DA
CONTA** ao terminar.

### Onde o save fica

- Com conta: `user://statown_save_<hash-do-id>.json` (hash simples; não é segredo).
- Sem conta: `user://statown_save.json`.
- No navegador, `user://` é o armazenamento do próprio site (IndexedDB/OPFS,
  conforme o build). Limpar dados do site apaga o save local.

O servidor é a fonte de verdade quando há conta: ao entrar, o save baixado substitui
o local. Se o download falhar, o jogo avisa e mantém o local; não faça uma prova
dependendo de sincronização em rede instável.

---

## 5. Professor: promover a conta e ler as notas

1. O professor cria a própria conta pelo jogo (ou pelo painel do Supabase).
2. No SQL Editor:

```sql
update public.statown_alunos
set professor = true
where email = 'professor@instituicao.br';
```

3. Confira a turma:

```sql
select *
from public.statown_notas
where semestre = '2026/2'
order by nome;
```

4. A exportação da turma inteira é feita pela consulta acima (ou pelo Table
   Editor → `statown_notas`). A tela interna **SIGA**, acessível apenas pelo
   código/testes e não pela HUD, gera o CSV de participação de **um** aluno
   (**Baixar CSV de participação**); ela é ferramenta de conferência, não um
   botão do jogador.

> A visão `statown_notas` usa `security_invoker = true`: ela respeita a RLS. Um aluno
> autenticado vê apenas a própria linha; um professor vê a turma. A flag
> `professor` é a única coisa que separa os dois papéis, então mantenha o SQL Editor
> e a `service_role` fora do alcance dos alunos.

### Lançar no SIGA

O SIGA é o sistema acadêmico da UFJF; este projeto **não** tem integração automática
com ele. O fluxo seguro é:

1. exportar a consulta/CSV (`nome`, `matricula`, `semestre`, `nota`);
2. conferir manualmente casos de empate, alunos sem matrícula e alunos que não
   jogaram;
3. lançar no SIGA pelo professor responsável.

Não invente uma API do SIGA. Se a instituição fornecer um endpoint oficial, ele pode
virar uma função server-side no Supabase (Edge Function), nunca uma chave no cliente.

---

## 6. Segurança e limites (leia antes de avaliar)

O modelo atual protege **isolamento entre alunos** e **autoria da escrita**: um aluno
não consegue alterar a linha de outro, e a RPC sempre usa `auth.uid()`. Ele **não**
protege contra um aluno que edite o próprio save antes de enviar: as moedas e a nota
vêm do cliente.

| Risco | Situação atual | Mitigação |
|---|---|---|
| Aluno adultera o save | possível | auditoria do extrato, conferência por amostragem, simulação no servidor no futuro |
| Aluno lê a linha de outro | bloqueado pela RLS | manter policies e `security definer` com `search_path` fixo |
| Aluno chama a RPC com outro `aluno_id` | bloqueado: a função ignora o parâmetro e usa `auth.uid()` | não criar RPC que aceite `aluno_id` do cliente |
| Chave `service_role` vaza | catastrófico | nunca embutir; rotacionar se vazar |
| E-mail/telefone vazam | dados pessoais | coletar o mínimo; política de retenção e exclusão |

**Consequência prática:** a nota é uma boa medida de participação e esforço, mas não
é uma prova à prova de fraude. Para valer como nota formal, combine com atividade
presencial, sorteio de desafios, conferência do extrato e/ou uma simulação
autoritativa no servidor.

---

## 7. Teste local sem Supabase

O projeto não tem credenciais de exemplo e não simula login falso. Para testar a
interface sem backend:

1. para abrir o jogo manualmente em modo local, deixe `config/supabase.json` com
   `habilitado: false` e campos vazios;
2. rode `SmokeUI` (ele força o modo local em memória, então funciona mesmo com a
   configuração de produção ativa, e não apaga a sessão real);
3. rode `TestEconomia` (regras de moedas, game over, carregamento e semestre);
4. rode `TestDesafios` (banco do LAB, pagamento único e reset semanal).

Para testar o fluxo HTTP de verdade, use um projeto Supabase de teste ou a stack
local descrita abaixo. Um servidor falso que só devolve JSON não testa a RLS nem as
policies do Postgres.

### 7.1. Stack Supabase local (opcional)

Dá para validar Auth, PostgREST, RPCs, RLS e a view do professor sem criar projeto na
nuvem. É útil antes de divulgar o link da disciplina.

1. Tenha Docker e Node instalados. Em uma pasta **temporária**, rode
   `npx supabase@latest init` e depois `npx supabase@latest start`.
2. Pegue `API_URL` e `ANON_KEY` com `npx supabase@latest status -o env`.
3. Aplique o mesmo SQL de produção no banco local (a senha padrão do CLI é
   `postgres`):

   ```bash
   docker exec -i CONTAINER_DO_BANCO psql -U postgres -d postgres \
     < docs/SUPABASE.sql
   ```

4. Aponte `config/supabase.json` para `http://127.0.0.1:54321` com a `ANON_KEY`
   local e rode os testes do jogo. **Restaure a configuração de produção depois**;
   as chaves locais são públicas e não servem para a nuvem.
5. Crie duas contas, salve semanas diferentes e confira a view `statown_notas`.
   Promova uma conta a professor no SQL local e veja a turma; para o aluno, a mesma
   view deve devolver só a própria linha.

Na validação desta entrega (24/11/2026), o SQL rodou em um Supabase local
(PostgreSQL 17 + GoTrue + PostgREST), com **22 verificações de API**, **10
verificações do cliente Godot** e um teste de CORS no navegador, todos verdes:

- cadastro no GoTrue e criação automática do perfil pelo trigger;
- conta nova carrega vazio; upsert de SE 7/ano 2 com 285 moedas gera nota 28;
- outro aluno não lê a linha alheia; a view mostra só a linha permitida pela RLS;
- professor promovido vê os dois alunos; 1390 moedas viram nota 100;
- semestre divergente, semana 0 e saldo negativo são rejeitados; `anon` não chama a
  RPC;
- o cliente Godot fez login real, baixou SE 7/ano 2, subiu SE 9/ano 3 e, depois de
  sair e entrar de novo, retomou SE 9/ano 3;
- no navegador, `fetch` de outra origem autenticou e chamou a RPC (HTTP 200), então o
  CORS não bloqueia o build web.

O CLI local sobe Studio, e-mail de teste e outras ferramentas **sem autenticação**
por padrão. Use apenas em uma máquina de desenvolvimento e derrube a stack com
`npx supabase@latest stop --no-backup` ao terminar.

### 7.2. Validação no projeto real (24/11/2026)

O projeto Supabase de produção do StaTown foi testado com o build web exportado,
a configuração ativa e a confirmação de e-mail ligada:

- o login de uma conta existente funcionou e carregou o perfil;
- no primeiro login sem linha no servidor, o cliente subiu a partida inicial
  (SE 1/ano 1, 150 moedas) e a linha foi confirmada pela API;
- em um navegador limpo, o login baixou o save e a partida retomou na SE 4/ano 1,
  com o cabeçalho e as moedas vindos do servidor;
- **SINCRONIZAR AGORA** enviou o save, o painel trocou “Sincronizando...” por
  “sincronizado &lt;hora&gt;” e a linha do servidor foi atualizada;
- ao final, a linha de teste foi restaurada para SE 1/ano 1, 150 moedas, nota 0.

**Armadilha de transporte web encontrada nessa validação:** o Cloudflare do
Supabase devolve `Content-Encoding: gzip`; o `fetch` do navegador já entrega o
corpo descompactado e o `HTTPRequest` do Godot tentava descompactar de novo. A
leitura do progresso falhava com `resultado 8`
(`RESULT_BODY_DECOMPRESS_FAILED`) e a tela mostrava “Sem conexao com o servidor”.
A correção é manter `_http.accept_gzip = false` em `ContaManager._ready()` e
reexportar o build web. Isso não altera Auth, RLS nem o formato do save; evita
apenas a dupla descompactação no navegador.

Não foram cobertos nesta rodada: cadastro novo com um e-mail real (o domínio
`@example.com` é recusado pelo GoTrue) e a URL final da Vercel. Antes de divulgar
o link, faça um cadastro de teste com e-mail real, confirme a mensagem e cadastre
a origem em **Authentication → URL Configuration**. Se a conta usada na validação
tem senha provisória, troque-a antes de liberar o jogo para os alunos.

---

## 8. Problemas comuns

| Sintoma | Causa provável | Correção |
|---|---|---|
| “O Supabase ainda nao foi configurado” | `habilitado:false`, URL ou chave vazias | preencha `config/supabase.json` e reexporte |
| 401 ao salvar | sessão expirada ou anon key errada | saia e entre de novo; confira a chave **anon** |
| 404 nas RPCs | SQL não executado ou nome do projeto errado | rode `docs/SUPABASE.sql`; confira a URL |
| “new row violates row-level security” | tentativa de escrita direta ou policy faltando | use as RPCs; confira as policies do script |
| Aluno não vê nota | ainda não ganhou moedas ou está em outro semestre | confira `semestre` e `moedas_ganhas` na linha |
| Professor não vê a turma | `professor` não está `true` ou e-mail difere | rode o `update` e confira maiúsculas/espaços |
| Login diz “confirme o e-mail” | confirmação ligada | confirme a caixa de entrada ou desligue durante o teste |
| Progresso não sobe | offline, RLS, download inicial falhou ou save grande | veja o console/rede; confira `Conta.progresso_pronto()`; o limite do SQL é 120 KB |
| “Sem conexao com o servidor (resultado 8)” depois do login no web | Cloudflare/Supabase responde gzip e o navegador já descompacta; o `HTTPRequest` tenta de novo | mantenha `_http.accept_gzip = false` em `ContaManager._ready()` e reexporte; não é RLS |
| Tela CONTA presa em “Baixando…” | rede/Supabase indisponível | use **TENTAR BAIXAR DE NOVO**; se persistir, **JOGAR SEM SINCRONIZAR** e retome quando a conexão voltar |

---

## 9. Base de artigos da Revista

A Revista Científica do Vale usa **50 artigos reais** indexados no PubMed/NLM,
consultados em **24/11/2026**. O jogo carrega a cópia versionada
[`data/revista_artigos.json`](../data/revista_artigos.json) para funcionar offline
e sorteia **6 por semana epidemiológica** (o lote é estável dentro da semana).

Para espelhar a base no Supabase:

1. execute [`docs/SUPABASE_ARTIGOS.sql`](SUPABASE_ARTIGOS.sql) no SQL Editor;
2. confira com `select tema, count(*) from public.statown_artigos group by tema;`
   — devem aparecer 10 linhas em cada uma das cinco áreas;
   `select count(*) from public.statown_artigos where titulo_pt <> '' and resumo_pt <> '';`
   deve devolver 50;
3. a tabela é **somente leitura** para `anon`/`authenticated`; alterações são feitas
   pelo SQL Editor ou por uma futura RPC de professor, nunca pelo cliente do jogo.

| Campo | Uso |
|---|---|
| `pmid`, `doi`, `url` | rastreabilidade e acesso ao artigo completo |
| `titulo`, `autores`, `periodico`, `ano`, volume/número/páginas | citação |
| `tipo`, `desenho`, `tema` | classificação didática |
| `resumo`, `secoes` | texto original reproduzido da ficha PubMed, sem reescrita |
| `titulo_pt`, `resumo_pt`, `secoes_pt` | tradução editorial para PT-BR exibida no jogo |
| `fonte`, `consultado_em` | data e origem da consulta |

**Limite importante:** o resumo não substitui o artigo completo. O botão
**Abrir original no DOI** leva à versão do editor; o jogo não baixa nem redistribui
PDFs. A tradução é editorial e didática; o texto em inglês na tabela é a referência
para citação e conferência.
Os metadados foram conferidos contra o Crossref, mas a disponibilidade do texto
completo depende do acesso da instituição.

---

## 10. LGPD e uso em sala

- O jogo coleta **e-mail, nome e matrícula** para identificar o aluno e a nota.
- Informe a turma, no início do semestre, o que é coletado, por quê, onde fica e por
  quanto tempo.
- Prefira matrícula a CPF; não peça telefone, endereço ou dado sensível.
- Defina uma rotina de exclusão ao fim do semestre/curso e um responsável
  (o professor) por atendimentos de acesso/correção.
- O Supabase gratuito tem região e retenção próprias; leia os termos antes de usar
  com dados de alunos.

---

## 11. Checklist de publicação

- [ ] SQL executado no projeto de produção.
- [ ] `config/supabase.json` com URL e **anon key**, `habilitado: true`.
- [ ] Nenhuma `service_role` no repositório, no build ou em variável pública.
- [ ] Confirmação de e-mail decidida (ligada em produção, desligada só em teste).
- [ ] URL da Vercel cadastrada em **Authentication → URL Configuration**.
- [ ] Professor promovido e consulta `statown_notas` testada.
- [ ] Testes `SmokeUI`, `TestEconomia`, `TestDesafios` e `TestRevista` verdes no CI.
- [ ] `docs/SUPABASE_ARTIGOS.sql` executado e `statown_artigos` com 50 linhas.
- [ ] Aviso de privacidade e plano de exclusão definidos com a turma.
