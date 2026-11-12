# StaTown — o Vale do Rio Doce

Jogo educacional de **bioestatística e epidemiologia** feito em **Godot 4.7** (GDScript),
pensado para rodar no **computador e no celular** (exportação web). O jogador é o novo
coordenador de vigilância epidemiológica de um vale fictício com 20 vilas, 41.650
habitantes simulados e um agravo infeccioso circulando.

O objetivo pedagógico é um só: **transformar dados brutos em decisões**, passando por
amostragem, estatística descritiva, gráficos, distribuições, testes de hipótese,
regressão, leitura crítica de artigos e comunicação de resultados.

---

## 1. Como jogar

### No computador

| Ação | Comando |
|---|---|
| Rodar pelo editor | abrir a pasta do projeto no Godot 4.7 e apertar **F5** |
| Rodar pela linha de comando | `godot --path .` |
| Mover o mapa | arrastar com o botão esquerdo, setas/WASD, ou roda do mouse para zoom |
| Abrir uma vila | clicar sobre ela (ou usar o botão *Investigar* no rodapé) |
| Fechar um painel | `X` no canto superior direito ou `Esc` |

### No celular (navegador)

| Gesto | Efeito |
|---|---|
| arrastar com **um dedo** | move o mapa |
| **pinça de dois dedos** | zoom ancorado no ponto entre os dedos |
| toque simples | abre a vila tocada |
| botões `+` `-` `FIT` `MAP` `HQ` | atalhos de zoom, mapa inteiro, camada de dados e retorno à vila central |

O jogo já está configurado com `emulate_mouse_from_touch`, `canvas_items` + `expand` e
resolução de projeto 1600×900 — em telas 20:9 na horizontal o campo de visão lógico
chega a ~2000 px de largura, e a barra superior usa `HFlowContainer` para não estourar.

### Som: a hierarquia sonora

O áudio não é enfeite: ele diz onde você está. São **quatro camadas** que se somam, do
geral para o específico:

| Camada | No mapa | Numa vila | Num minigame |
|---|---|---|---|
| **Tema** (música) | tema do vale, 64 BPM | trilha da *zona* (urbana, rural, ribeirinha, mata, industrial) | tema próprio do desafio |
| **Ambiencia** (loop) | vento | mercado, rio, pássaros ou multidão, conforme a vila | — |
| **Sting** (4 s) | — | motivo único daquela vila + sino, galo, vaca, bocina ou bigorna | — |
| **Efeitos** | semana, moeda, alerta, descoberta | abrir/fechar painel, cliques | acerto, erro, moeda |

Como funciona na prática:

- o tema do mapa toca em loop; ao **aproximar o zoom** de uma vila (ou clicar nela), a
  trilha da zona entra em *crossfade* e o sting daquela vila toca uma vez;
- ao voltar o zoom, o tema do vale retorna — é a "mudança de ambiente" audível;
- abrir um painel **abaixa** a música (*ducking*) para o texto respirar; abrir um
  minigame troca para o tema do desafio;
- **toda a música foi composta na mesma tonalidade (Lá menor)** por síntese numérica,
  então sting, tema e efeito nunca brigam entre si;
- os sons "reais" (vento, rio, mercado, sino, galo, vaca, bocina, bigorna) são CC0 do
  [freesound.org](https://freesound.org) — créditos completos em
  [docs/CREDITOS_AUDIO.md](docs/CREDITOS_AUDIO.md).

> Navegador só libera áudio depois do primeiro toque/clique. Se você abrir o jogo e não
> ouvir nada, toque em **Começar a partida** (ou em qualquer botão) uma vez.

No **Menu & Configurações → Som & Música** há três sliders (música, ambiente, efeitos)
e um botão **Silenciar tudo**; os valores ficam no save.

---

## 2. O laço de jogo

1. **Avançar o tempo** — a simulação roda em **semanas epidemiológicas (SE)**. Cada
   avanço integra um modelo SEIR individual (41.650 pessoas) com mobilidade por
   gravidade entre vilas.
2. **Ler indicadores** — prevalência, Rt, casos novos, óbitos, leitos, cobertura
   vacinal e saneamento, por vila e para o vale.
3. **Investigar** — o BioLab tem uma amostra da população real da simulação (n = 20 a
   3.000, com desenho amostral explícito). Tudo o que aparece nos gráficos e testes vem
   dessa amostra, não de números inventados.
4. **Decidir** — gastar **BioMoedas** em saneamento, vacinação, UBS e hospital. Cada
   compra altera os parâmetros daquela vila imediatamente.
5. **Registrar** — o backend gera o relatório semanal (JSON/CSV) no formato de boletim,
   com hash de integridade — o mesmo formato que um serviço de vigilância usa. A tela
   **SIGA** continua no projeto como ferramenta interna de desenvolvimento, fora do HUD.
6. **Ganhar BioMoedas** nos 9 minigames (10 + até 60 por acerto) e na leitura crítica
   da Revista.

### Como ler os números (e por que a ocupação passa de 100%)

| Indicador | Como é calculado | Pode passar de 100%? |
|---|---|---|
| **Prevalência** | (expostos + infectados) ÷ população viva | Não. É proporção de um todo; fica em [0, 100%]. |
| **Incidência** | novos casos da última semana epidemiológica | Não é percentual: é uma contagem por semana. |
| **Letalidade** | óbitos atribuídos à doença ÷ casos confirmados | Não. É proporção; fica em [0, 100%]. |
| **Rt** | razão entre novos desta semana e da anterior (ajustada) | Não é percentual. Acima de 1 = epidemia crescendo. |
| **Ocupação dos leitos** | graves (12% dos ativos) ÷ leitos disponíveis | **Sim.** É razão demanda/capacidade, não proporção de um todo. |
| **Cobertura vacinal** | doses aplicadas ÷ população-alvo | Não. |

A ocupação é o único indicador que pode (e deve) passar de 100%: 12 pacientes graves
para 9,5 leitos dá 126% — matematicamente correto e epidemiologicamente relevante, porque
significa **superlotação**. Acima de 200% o jogo chama de colapso assistencial. Se você
vir 126% no painel da vila, é leito, não prevalência: prevalência e letalidade são
limitadas a 100% no código (`EpidemicManager`), justamente para não gerar leitura falsa.

Os **óbitos naturais** (outras causas) ficam separados dos óbitos pela doença: eles
reduzem a população, mas não entram na letalidade do agravo. É por isso que existe a
linha “Óbitos naturais (outras causas)” no painel.

---

## 3. Conteúdo pedagógico

### BioLab — 6 abas

| Aba | O que ensina |
|---|---|
| **Amostragem** | aleatória simples, estratificada e por conglomerados; erro amostral e tamanho de amostra |
| **Descritiva** | média, mediana, desvio-padrão, quartis, IC95%, tabela de frequências |
| **Gráficos** | histograma, boxplot, barras, dispersão, linha, ROC — e quando cada um mente |
| **Distribuições** | normal, binomial, Poisson, exponencial; teste de aderência e QQ-plot |
| **Testes** | t de Welch, ANOVA + Bonferroni, Mann-Whitney, Kruskal-Wallis, qui-quadrado, OR/RR — com memória de cálculo e interpretação em português |
| **Regressão** | linear e logística, coeficientes, odds ratio, métricas (R², AUC, acurácia, sensibilidade, especificidade) |

### 9 minigames

1. Detetive de Delineamentos
2. Arquiteto do Banco de Dados
3. Mestre da Assimetria
4. Oficina do Gráfico Perfeito
5. Missão Amostragem
6. Roleta das Distribuições
7. Tribunal das Hipóteses
8. Caçador de Tendências
9. Auditoria de IA (erros estatísticos em afirmações — inclusive geradas por IA)

### Outros painéis

- **Revista** — leitura crítica de artigos fictícios, com checklist de viés e
  randomização (conteúdo explicitamente marcado como ficcional).
- **Dr. Bayes** — diálogo sobre probabilidade condicional, sensibilidade,
  especificidade e valor preditivo.
- **Manual** — guia completo em `docs/manual.html`, aberto pelo HUD ou por `F1`.
- **SIGA (interno)** — relatório e conversor de dados; geração pelo backend, sem botão no jogo.
- **Cenário** — quatro agravos com parâmetros diferentes: arbovirose (R₀ 2,8),
  respiratória (R₀ 3,6), entérica (R₀ 2,4) e crônica (R₀ 0).
- **Menu** — salvar/carregar (`user://statown_save.json`), fonte grande, reiniciar.

---

## 4. Transparência dos dados

- **População e vilas são sintéticas** (`data/vilas.json`), com estrutura etária,
  comorbidades, saneamento e cobertura vacinal plausíveis — não são dados reais de
  nenhum município.
- Os **artigos da Revista e as falas do Dr. Bayes são fictícios** e assim rotulados no
  jogo. Nenhuma citação real é inventada.
- Todos os cálculos estatísticos saem de `scripts/stats/StatCore.gd`, uma biblioteca
  única e testada (47 verificações), usada tanto pela interface quanto pelos testes.

---

## 5. Rodar, testar e exportar

```bash
# 1. importar recursos (gate de compilação)
godot --headless --import

# 2. testes da biblioteca estatística (47 verificações)
godot --headless --script tests/test_statcore.gd

# 3. smoke test da interface (abre todos os painéis e joga os 9 minigames)
godot --headless res://tests/SmokeUI.tscn

# 4. áudio: buses, 51 arquivos, mapa vila -> zona, volumes e troca de tema
#    (129 verificações)
godot --headless res://tests/TestAudio.tscn

# 5. navegação: roda, arrasto, pinça, limites e teclado
godot --headless res://tests/TestCamera.tscn

# 6. tráfego: 55 veículos, 2 asas-deltas, 4 parapentes, máscara e reinício
godot --headless res://tests/TestTrafego.tscn

# 7. capturas de tela (precisa de display; gera docs/shots/*.png)
godot --path . res://tests/Capture.tscn --resolution 1600x900

# 8. exportação web
mkdir -p exports/web
godot --headless --path . --export-release "Web" exports/web/index.html
```

### Publicar na web

O preset **Web** (`export_presets.cfg`) sai **sem threads** (`thread_support=false`),
ou seja, não exige os cabeçalhos `COOP/COEP` — funciona em hospedagem estática comum
(GitHub Pages, Netlify, Vercel, um `python3 -m http.server`).

O build tem ~50 MB: `index.wasm` (~39,5 MB) e `index.pck` (~12 MB). **Sirva com gzip/brotli**: o
wasm comprime para ~10 MB e o carregamento em 4G cai de ~40 s para ~10 s.

```bash
# teste local rápido
cd exports/web && python3 -m http.server 8099
# abra http://localhost:8099
```

#### Publicação automática no Vercel

O repositório já traz o workflow `.github/workflows/publicar-vercel.yml`: cada push
na `main` compila o build web no GitHub Actions, roda os testes, copia o manual/figuras
e atualiza a branch `deploy`. A Vercel deve ser configurada uma única vez para usar
`deploy` como **Production Branch**. Não é preciso token da Vercel no GitHub.

O passo a passo, incluindo cache, save, licenças e rollback, está em
[`docs/PUBLICACAO_VERCEL.md`](docs/PUBLICACAO_VERCEL.md).

O preset exclui `assets/extracted/`, `assets/*.zip`, `docs/shots/`, `docs/evidencias/`,
`tests/` e `tools/` do pacote — a pasta `assets/extracted/` também tem `.gdignore` para
não ser importada.

Prova de que roda no navegador: `docs/web_desktop.png` (1280×720) e
`docs/web_celular.png` (844×390, paisagem de celular).

---

### Quero trocar a arte do mapa

A arte atual é um **bake da ilustração** `assets/Gemini_Generated_FULL-MAP.jpeg`:

```bash
python3 tools/extract_terrain.py          # classifica agua/mata/serra/lavoura/cidade/asfalto
python3 tools/bake_map.py                 # gera world_map.png + chunkes + map_data.json
python3 tools/split_world.py --verificar  # confere o recorte (0 diferencas)
```

Para trocar por outra ilustração, substitua o JPEG e repita os três comandos. Também dá
para pintar à mão: a camada **`assets/art/decor.png`** (transparente, do tamanho do mapa)
recebe detalhes sem risco, e `assets/art/world_map.png` aceita repintura seguida de
`python3 tools/split_world.py`. O passo a passo, as regras de pixel art e o que **não** é
arte (âncoras das vilas, máscaras de rio) estão em [docs/MAPA.md](docs/MAPA.md).

Para saber onde pintar, `docs/mapa_vilas.png` mostra as 20 vilas numeradas sobre o mapa
(vila 1 = tile `116,59` = pixel `1856,944`; a tabela completa está no guia).

---

## 6. Estrutura

```
data/                 vilas.json, doencas.json, map_data.json (gerado)
scenes/Main.tscn      cena principal (HUD + mapa + modais)
scripts/autoload/     GameState, VilaRegistry, PopulationManager, EpidemicManager,
                      AssetRegistry, RoadMask, UIKit, AudioManager  (ordem importa!)
scripts/stats/        StatCore.gd — toda a estatística, estática e testável
scripts/ui/           UIKit, StatChartCanvas, TabelaDados
scripts/ui/panels/    um arquivo por painel (contrato: _init(main))
scripts/ui/minigames/ um arquivo por minigame (contrato: MinigameBase)
scripts/world/        WorldView (mapa em chunks) e CameraController (pan/zoom)
assets/art/           mapa bakeado (world_map.png + 16 chunkes), decor.png,
                      road_mask.png + road_nav_mask.png, vehicles/ e gliders/
assets/audio/         mus (15 temas), vila (20 stings), amb (6 loops), sfx (10)
data/audio.json       mapa vila -> zona/ambiente/acento (Python + jogo leem o mesmo)
tests/                test_statcore.gd, SmokeUI, TestCamera, TestAudio, TestAudit,
                      TestTrafego, Capture
tools/                render_world.py (mapa), split_world.py (fatia o mapa editado),
                      extract_map_geometry.py,
                      audio/render_audio.py + audio/fetch_freesound.py
docs/shots/           21 capturas usadas no manual e na documentação
docs/manual.html       manual do usuário (23 capítulos, figuras, links internos)
docs/manual_preview.png captura da capa do manual (para divulgação)
docs/CREDITOS_AUDIO.md  arquitetura sonora e créditos CC0 do freesound
docs/CREDITOS_ARTE.md   origem e licença dos sprites de veículos e parapentes
docs/MAPA.md           como editar a arte do mapa à mão (decor.png ou repintura)
docs/mapa_vilas.png    mapa numerado das 20 vilas (referência de coordenadas)
exports/web/          build web pronto para publicar (gerado)
README.md             este arquivo (visão do jogador)
AGENTS.md             convenções técnicas para quem for editar
```

Arquitetura, convenções, contrato dos painéis e as armadilhas do Godot 4.7 já pagas
neste projeto estão em [AGENTS.md](AGENTS.md).

---

## 7. Créditos e licenças

- **Arte do mapa**: gerada por `tools/render_world.py` a partir de tiles
  [Kenney](https://www.kenney.nl) (CC0) — ver `assets/fonts/LICENSE-Kenney.txt`.
- **Carros, caminhões e parapentes**: sprites fornecidas pelo autor do projeto em
  `assets/art/source/` e derivadas em `assets/art/vehicles/pixel_cars.png` e
  `assets/art/gliders/paraglider_sheet.png`; origem e pendências de licença em
  [docs/CREDITOS_ARTE.md](docs/CREDITOS_ARTE.md).
- **Malha viária**: `assets/art/road_mask.png` fornecida pelo autor; a versão
  `road_nav_mask.png` é derivada por `tools/build_road_nav_mask.py` com fechamento de
  1 px só para validar rotas (`--check` confere sem gravar).
- **Fontes**: Silkscreen (display), Rubik (texto) e VT323 (código), SIL OFL — ver
  `assets/fonts/OFL.txt`.
- **Música e efeitos**: compostos por síntese numérica para o StaTown
  (`tools/audio/render_audio.py`), CC0 — ver
  [docs/CREDITOS_AUDIO.md](docs/CREDITOS_AUDIO.md).
- **Ambiencias e acentos diegéticos**: freesound.org, todos CC0 1.0 (vento, pássaros,
  rio, mercado público, multidão, porto, sino, galo, vaca, bocina, bigorna), com autor
  e link na tabela de créditos.
- **Código e conteúdo pedagógico**: projeto StaTown.

---

## 8. Limitações conhecidas

- A simulação é **qualitativa**: calibrada para gerar sinais interessantes em poucas
  semanas, não para prever cenários reais.
- O áudio é sintetizado (música) e CC0 (ambiências): não há dublagem nem narração.
- Em navegador, o som só começa depois do primeiro clique/toque (política de autoplay).
- O save guarda o estado do jogo, mas não o histórico completo de gráficos.
- Testado em Chrome/Firefox desktop; em Safari iOS o WebGL2 funciona, mas o
  carregamento inicial é mais lento.
