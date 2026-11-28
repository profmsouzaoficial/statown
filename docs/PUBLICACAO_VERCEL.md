# Publicação automática: GitHub → Vercel

Este documento explica como o StaTown sai do repositório e chega a uma URL pública
sem precisar exportar o jogo à mão a cada alteração.

## 1. A ideia em uma frase

O **GitHub Actions** compila o build web; a **Vercel** só serve o resultado.

```text
git push main
      │
      ▼
GitHub Actions
  ├─ baixa Godot 4.7.2
  ├─ instala o template web sem threads
  ├─ roda os testes (inclui economia e desafios)
  ├─ valida config/supabase.json (sem service_role)
  ├─ exporta exports/web
  ├─ copia manual.html + shots/
  └─ força push para a branch deploy
      │
      ▼
Vercel (produção = branch deploy)
      │
      ▼
https://<projeto>.vercel.app
```

Por que não deixar a Vercel compilar diretamente? Porque a imagem de build dela não
tem Godot nem os templates de exportação. Baixar o pacote completo de templates
(~2 GB) em cada deploy seria lento e frágil. O GitHub Actions faz esse trabalho uma
vez e publica apenas os ~52 MB do build pronto.

## 2. O que já está no repositório

| Arquivo | Papel |
|---|---|
| `.github/workflows/publicar-vercel.yml` | Compila, testa e publica a branch `deploy` |
| `ci/templates/4.7.2.stable/web_nothreads_release.zip` | Template web usado no CI (9,8 MB) |
| `ci/templates/4.7.2.stable/version.txt` | Faz a Godot reconhecer o diretório |
| `deploy/vercel.json` | Cabeçalhos de cache do build publicado |
| `.gitignore` | Mantém fora do Git o `.godot/`, `exports/web/` e derivados |
| `config/supabase.json` | URL pública + **anon key** do Supabase (entra no PCK; nunca a `service_role`) |
| `docs/SUPABASE.sql` | Schema, RLS, RPCs e visão de notas para o professor |

O workflow **não precisa de token da Vercel**. Ele usa o `GITHUB_TOKEN` padrão para
atualizar a branch `deploy`; a integração Git da Vercel escuta essa branch.

## 3. Configuração única na Vercel

1. Entre em <https://vercel.com> com a conta do GitHub `profmsouzaoficial`.
2. **Add New → Project** e importe `profmsouzaoficial/statown`.
3. Em **Configure Project**:
   - **Framework Preset:** `Other`
   - **Root Directory:** `./`
   - **Build Command:** deixe vazio
   - **Output Directory:** deixe vazio (se a Vercel exigir, use `.`)
   - **Install Command:** deixe vazio
4. Clique em **Deploy**. O primeiro deploy pode apontar para `main` e não encontrar
   `index.html`; isso é esperado, porque o build ainda não foi publicado.
5. Depois que o GitHub Actions terminar a primeira execução, defina a branch de
   produção. A Vercel mudou o local desse ajuste: ele **não fica mais em Git**.
   Abra **Project → Settings → Environments**, clique no ambiente **Production** e,
   em **Branch Tracking**, troque `main` por **`deploy`**. Clique em **Save**.
6. Ainda não existe deployment da branch `deploy`; criar a regra não dispara um build
   sozinho. Abra **Deployments → Create Deployment**, escolha **Branch-Based**,
   informe **`deploy`** e clique em **Deploy**. Se o resultado aparecer como Preview,
   use **Promote to Production**.
7. A URL de produção passa a servir o jogo.

Se o workflow não conseguir atualizar a branch `deploy`, confira em
**Settings → Actions → General → Workflow permissions** se a opção
**Read and write permissions** está marcada. O workflow já declara
`contents: write`, mas a configuração do repositório precisa permitir.

> **Proteção de deployment:** se a URL pedir login, verifique
> **Settings → Deployment Protection** e desative a proteção para produção. Para um
> site que “todos podem ver”, a produção precisa ser pública.

## 4. O fluxo no dia a dia

```bash
git add .
git commit -m "Ajusta o painel de vacinação"
git push origin main
```

O que acontece:

1. O GitHub Actions roda o workflow **Publicar no Vercel**.
2. Ele roda os testes; se algum falhar, **não publica**.
3. Se tudo passar, ele atualiza a branch `deploy`.
4. A Vercel detecta o push em `deploy` e publica uma nova versão.
5. A mesma URL continua valendo; o save no navegador (IndexedDB) é preservado.

A branch `deploy` é **gerada** e sobrescrita pelo workflow. Não edite nela à mão: a
próxima execução substitui o conteúdo. O histórico de versões e o rollback ficam no
painel da Vercel.

## 5. Cache e “minha alteração não apareceu”

`index.pck`, `index.wasm` e `index.html` têm nomes fixos. Se o navegador guardar a
versão antiga, ele pode continuar rodando o build anterior. O `deploy/vercel.json`
define `Cache-Control: no-cache` para esses arquivos, o que força a revalidação.

Mesmo assim:

- recarregue com `Ctrl+Shift+R` (ou `Cmd+Shift+R` no macOS);
- teste em uma janela anônima;
- confirme no painel da Vercel qual commit está em produção.

Para mudanças grandes, também vale conferir o console do navegador e o `Network`:
`index.wasm` deve voltar como `application/wasm`.

## 6. O que funciona e o que não funciona

| Recurso | Na Vercel |
|---|---|
| Jogo, gráficos, áudio, minigames | Funciona: é o mesmo build web |
| Save em `user://` | Funciona no mesmo domínio (armazenamento do navegador) |
| Manual e figuras | Funcionam: `manual.html` e `shots/` são copiados no CI |
| Login e progresso por aluno | **Opcional**, via Supabase configurado em `config/supabase.json`; a Vercel só serve o frontend |
| Nota/participação no banco | **Opcional**, pela RPC `statown_salvar` e pela visão `statown_notas` |
| Download offline/PWA | Não está habilitado no preset atual |

A Vercel continua sendo **hospedagem estática**. Ela não executa o Postgres nem guarda a
`service_role`: o backend é o projeto Supabase. Se `config/supabase.json` estiver vazio
ou com `habilitado:false`, o build publicado funciona em modo local, como antes.

O passo a passo do backend está em [SUPABASE.md](SUPABASE.md). O aluno entra com e-mail
e senha; o jogo guarda apenas o token de sessão no navegador. A senha vai direto para o
Supabase Auth e nunca é gravada no save.

## 7. Licenças antes de divulgar

Publicar na Vercel é **distribuir** o jogo. As sprites do pacote Pixel Cars e a imagem
do parapente não têm licença explícita no material recebido. Antes de abrir a URL para
o público em geral, confirme a permissão dos autores ou substitua por arte com licença
clara. O restante dos créditos está em `docs/CREDITOS_ARTE.md` e
`docs/CREDITOS_AUDIO.md`.

## 8. Problemas comuns

| Sintoma | Causa provável | Correção |
|---|---|---|
| Vercel mostra 404 na raiz | produção ainda em `main`, sem `index.html` | Settings → Environments → Production → Branch Tracking = `deploy`; crie um deployment da branch |
| Branch `deploy` não existe | workflow ainda não rodou ou falhou | Actions → **Publicar no Vercel** → veja o log |
| Workflow falha no import/export | template ou binário Godot incompatível | confira `GODOT_VERSION` e o template `4.7.2.stable` |
| Workflow falha nos testes | regressão real no jogo | corrija o teste; o deploy é bloqueado de propósito |
| Jogo abre, mas sem áudio | autoplay do navegador | clique na tela/jogo antes de avaliar o som |
| Alteração antiga aparece | cache do navegador/CDN | recarregue forçado; confira o commit na Vercel |
| Tela CONTA diz que o Supabase não está configurado | `config/supabase.json` vazio ou `habilitado:false` | preencha URL/anon key, faça commit e aguarde o workflow |
| Login ou sincronização falha | URL/anon key errada, e-mail não confirmado ou RLS | confira o console/rede e o passo a passo em [SUPABASE.md](SUPABASE.md) |
| URL de produção pede login | Deployment Protection | desative a proteção para produção |

## 9. Rollback

No painel da Vercel, abra **Deployments**, escolha uma versão anterior e use
**Promote to Production** (ou **Redeploy**). Isso não altera o repositório; é útil para
voltar rápido se uma atualização quebrar algo durante uma aula.

## 10. Custo e limites

O plano Hobby da Vercel é suficiente para um projeto educacional desse tamanho, mas
tem limites de banda e de execução. O primeiro carregamento é de ~50 MB; por isso o
build usa compressão do host e o template sem threads. Se o projeto crescer muito,
considere Cloudflare Pages ou GitHub Pages como alternativas estáticas.

## 11. Ativar contas de alunos

1. Crie o projeto Supabase e execute [SUPABASE.sql](SUPABASE.sql).
2. Preencha `config/supabase.json` com a **Project URL** e a **anon public key**
   (nunca a `service_role`).
3. Faça commit; o workflow valida o JSON, roda os testes, exporta e publica.
4. Confirme a URL da Vercel em **Authentication → URL Configuration** no Supabase.
5. Promova a conta do professor e teste a visão `statown_notas`.

Sem esses passos, o jogo continua em modo local e a tela CONTA explica exatamente o que
falta. Com as chaves ativas, o login só libera a simulação depois de baixar o save; se o
download falhar, o botão **JOGAR SEM SINCRONIZAR** permite continuar, mas o upload fica
bloqueado até uma nova tentativa bem-sucedida. A nota é
`min(40,0, truncar_1_casa(moedas_ganhas / 1000 × 40,0))` por semestre: 1000 moedas
valem 40,0, o peso da avaliação **Game Educativo Statown**. O detalhamento, os
limites de segurança e o checklist de LGPD estão em [SUPABASE.md](SUPABASE.md).
O build web é para desktop/notebook ou tablet em paisagem com pelo menos 1200 px
lógicos; celular em retrato não é um alvo suportado.
