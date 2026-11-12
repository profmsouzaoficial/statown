# AGENTS.md — convenções do projeto StaTown

Este arquivo é o contrato para quem (humano ou agente) for mexer no jogo. Leia antes de
editar cena, script ou dado. O `README.md` explica o jogo para o jogador; aqui é a parte
técnica.

---

## 1. Regras de ouro

1. **Godot 4.7**, GDScript apenas, renderizador **gl_compatibility** (alvo web/celular).
2. **Toda string visível é PT-BR e sem acento** (`Amostragem`, `Grafico`, `nao`). Motivo:
   o Silkscreen (fonte de display) não tem acentuação confiável e o texto é desenhado em
   muitos lugares com fontes diferentes. Textos longos em Rubik também seguem a regra,
   por consistência visual.
3. **Nunca fabrique dado, citação ou número.** População/ vilas são sintéticas e os
   artigos da Revista são fictícios e rotulados como tal.
4. **Toda estatística passa por `StatCore`.** Se a interface precisa de uma conta nova,
   ela vira função estática em `scripts/stats/StatCore.gd` + verificação em
   `tests/test_statcore.gd`. Nunca calcule média/p-valor inline num painel.
5. **Nada de números mágicos de layout** sem comentário: a UI é escalada por stretch
   (`canvas_items` + `expand`) e precisa funcionar de 1200 a 2000 px lógicos de largura.
6. **Não quebre o contrato dos painéis** (seção 4) nem a ordem dos autoloads (seção 3).

---

## 2. Como rodar

```bash
GODOT=/home/marcio/opt/godot/godot        # binário usado no desenvolvimento

$GODOT --headless --import                                    # gate de compilação
$GODOT --headless --script tests/test_statcore.gd             # 47 verificações
$GODOT --headless res://tests/SmokeUI.tscn                    # 39 passos de UI
$GODOT --headless res://tests/TestCamera.tscn                 # 93 passos de navegação
$GODOT --headless res://tests/TestAudio.tscn                  # 129 verificações de áudio
$GODOT --headless res://tests/TestAudit.tscn                  # 52 semanas de simulação
$GODOT --headless res://tests/TestTrafego.tscn               # 13 passos de tráfego/máscara
DISPLAY=:0 $GODOT --path . res://tests/Capture.tscn --resolution 1600x900
```

- `--headless --script` **não carrega autoloads**: teste que usa `GameState`, `Vilas` etc.
  precisa ser **cena** (`extends Node` + `.tscn`), como `SmokeUI` e `TestCamera`.
- `--check-only --script` falha em identificadores de autoload; use `--import` como gate.
- Captura de tela exige display real (`DISPLAY=:0`); não há Xvfb nesta máquina.
- `read_image` guarda cache por hash: se a captura "não mudou", confira `sha256sum`.

---

## 3. Autoloads (a ordem importa)

| # | Nome | Script | Papel |
|---|---|---|---|
| 1 | `GameState` | `scripts/autoload/GameState.gd` | semana/ano, BioMoedas, progresso, save em `user://statown_save.json` |
| 2 | `Vilas` | `VilaRegistry.gd` | carrega `data/vilas.json`, lookup por id, âncoras no mapa |
| 3 | `Population` | `PopulationManager.gd` | microdados: 41.650 pessoas em `Packed*Array` paralelos |
| 4 | `Epidemic` | `EpidemicManager.gd` | SEIR individual, mobilidade por gravidade, Rt, prevalência |
| 5 | `Assets` | `AssetRegistry.gd` | sprites e texturas carregados uma vez |
| 6 | `RoadMask` | `scripts/autoload/RoadMask.gd` | consulta da malha viária; valida rotas e posição dos veículos |
| 7 | `UITheme` | `UIKit.gd` | paleta, fontes, helpers de layout (`card`, `botao`, `scroll`...) |
| 8 | `Audio` | `scripts/autoload/AudioManager.gd` | temas (crossfade), ambiências, stings, SFX, volumes |

`Vilas` precisa vir antes de `Population`, que precisa vir antes de `Epidemic`.
`Assets` precisa vir antes de `RoadMask` e de `UITheme`; `Audio` fica por último:
lê `GameState` (volumes) e é chamado por todos os painéis.

---

## 4. Contrato dos painéis e minigames

**Painel** (`scripts/ui/panels/*.gd`):

```gdscript
extends Control
var _main: Node

func _init(main: Node) -> void:
    _main = main

func _ready() -> void:
    # montar a UI aqui
```

Aberto por `main.abrir_modal(titulo, painel, largura := 1180, altura := 760)`; o modal
é limitado a `TELA - (60, 70)`. Conteúdo longo **precisa** de `UITheme.scroll()`.

**Minigame** (`scripts/ui/minigames/*.gd`): estende `MinigameBase`, implementa
`_montar()` e chama `_registrar(acertos, total)` no fim (a recompensa é
`10 + round(60 * acertos/total)` BioMoedas via `GameState.registrar_minigame`).

---

## 5. Bibliotecas internas

### `StatCore` (estático)

Chaves de retorno já verificadas por teste — **não renomeie sem atualizar os painéis**:

| Função | Chaves principais |
|---|---|
| `describe` | `n`, `media`, `mediana`, `desvio`, `min`, `q1`, `q3`, `max`, `ic95` |
| `histogram` | `bins`, `contagens`, `rotulos` |
| `t_test_independent` | `n1`, `n2`, `media1`, `media2`, `diff`, `se`, `gl`, `t`, `p`, `ic95`, `d_cohen` |
| `anova_one_way` | `F`, `p`, `gl_entre`, `gl_dentro`, `grupos` |
| `posthoc` | lista de pares com `p_ajustado` (Bonferroni) |
| `mann_whitney` / `kruskal` | `U`/`H`, `p`, `n1`/`n2` |
| `chi2` / `fisher` | `chi2`, `p`, `gl`, `esperado`, `v_cramer` |
| `pearson` / `linear_regression` | `r`, `r2`, `p`, `coef`, `erro_padrao`, `previsao` |
| `logistic_regression` | `coef`, `or`, `ic95_or`, `p`, `auc` |
| `roc`, `metrics`, `odds_ratio`, `relative_risk`, `sample_size`, `proportion_ci` | ver testes |

`fmt_p(p)` formata p-valor (`< 0,001`); `interpret_p(p)` devolve frase em PT-BR.

### `StatChartCanvas`

`Control` que desenha todos os gráficos em `_draw()` (sem nós por ponto). Tipos:
`definir_barras`, `definir_histograma`, `definir_boxplot`, `definir_dispersao`,
`definir_linha`, `definir_roc`, `definir_qq`. Sempre chamar `limpar()` antes de trocar.
`eixo_y_min`/`eixo_y_max` fixam a escala vertical; o BioLab usa **um eixo Y comum por
família** (Normal, t, binomial/Poisson, qui-quadrado) para que mudar sigma/gl/n mostre
**achatamento e mudança de cauda**, em vez de reescalar a curva e manter a mesma forma.

### `Assets` (autoload)

`chunk(cx, cy)`, `decor(cx, cy)`, `sprite(nome)`, `veiculos()`, `pessoas()`,
`carros`, `motos`, `barcos`, `navios`, `asas`, `carros_pixel`, `caminhoes_pixel`,
`deltas`, `parapentes`. As listas de veículos e planadores são **explícitas** em
`AssetRegistry.NOMES_VEICULOS` / `NOMES_ASAS` e nos caminhos fixos do atlas pixel:
`DirAccess.get_files_at()` não lista os recursos remapeados dentro do PCK web, e o mapa
ficava sem tráfego e sem voo livre só no navegador. Ao adicionar arte nova, acrescente o
nome ou o caminho explícito. O mapa é desenhado em **16 chunkes** de 960×720; a camada
`decor` é opcional. `assets/art/vehicles/`, `assets/art/gliders/` e
`assets/art/road_nav_mask.png` são derivados, não mestres: para trocar um veículo, edite
o PNG derivado e reimporte. A folha de carros tem 6 colunas × 12 linhas; a de parapentes,
4 × 3.

### `UIKit` (autoload `UITheme`)

`card(titulo, cor)`, `conteudo(card)`, `botao(texto, cb, icone, cor)`, `rotulo`,
`paragrafo`, `badge`, `separador`, `scroll()`, `painel()`, `vbox/hbox`,
`titulo_font(bold)`, `corpo(weight)`, `mono_font()`.

### Áudio (`Audio`)

Quatro camadas, todas em **Lá menor** para serem harmonicamente compatíveis
(detalhes e créditos em `docs/CREDITOS_AUDIO.md`):

| Camada | API | Comportamento |
|---|---|---|
| Tema | `Audio.tocar_tema(id, fade)`, `Audio.modo_mapa()`, `Audio.tema_minigame(id)` | 2 players em crossfade; loop via `AudioStreamOggVorbis.loop = true` em runtime |
| Ambiência | `Audio.tocar_ambiente_base(id)`, `Audio.tocar_ambiente(id)` | loop do mapa (parque urbano) + loop da vila, players separados |
| Vila | `Audio.tocar_vila(id)` | trilha da zona + ambiência + sting (throttle de 3 s e guarda de 10 s por vila) |
| SFX | `Audio.sfx(id, db)`, `Audio.ui(id)` | pool de 8 players; escolhe um player ocioso antes de usar round-robin |

Buses criados em runtime: **Music**, **Ambient**, **SFX** (todos → Master). Volumes
lineares em `GameState.volume_musica/ambiente/sfx` + `GameState.mudo`, aplicados por
`Audio.aplicar_volumes()`; `Audio.duck(db)` abaixa a música quando um modal abre.

**Mapeamento** (`data/audio.json`) é fonte única para o Python e o jogo:

```json
"vilas": { "10": { "zona": "rural", "acento": "acc_galo", "inicio": 0.0,
                   "dur": 2.6, "ambiente": "amb_parque_urbano" } }
```

Gatilhos no jogo: `Main._ready` (mapa + parque), `focar_vila`/`_ao_tocar_mapa`
(sting), `_ao_mudar_zoom` (zoom ≥ 1,55 e vila a menos de 230 px do centro →
`tocar_vila`; zoom < 1,55 → `modo_mapa`), `abrir_modal` (ducking + tema do
minigame), `fechar_modal` (restaura sem repetir sting), `MinigameBase` (acerto/erro/
moeda), `UITheme.botao` (clique em todo botão). Todo som curto é renderizado com
fade de borda; só música/ambiência têm `loop = true`.

Regenerar o áudio:

```bash
python3 tools/audio/fetch_freesound.py   # prévias CC0 -> assets/audio/raw/ (fora do build)
python3 tools/audio/render_audio.py      # sintetiza música/SFX e faz o loop das ambiências
```

**Exceção:** `amb_parque_urbano` não é gerado por `render_audio.py`. Ele é um mix manual
de duas gravações CC BY 3.0 do Freesound (Park 3/Park 5, KarlSalamander), com corte no
cruzamento de zero para o loop não estalar. Se rodar o renderizador, ele recria o antigo
`amb_vento`; **não sobrescreva** `amb_parque_urbano` sem refazer o mix e a atribuição.
Detalhes em `docs/CREDITOS_AUDIO.md`.

---

## 6. Armadilhas do Godot 4.7 já pagas neste projeto

| Sintoma | Causa / correção |
|---|---|
| `Invalid argument` ao converter | `String(x)` só aceita `String`/`StringName` — use **`str(x)`** |
| erro no `%` de formatação | `%` aceita apenas `%s %d %f %x %c %v %%` — não existe `%e`, `%g`, `%-42s` |
| linha interpretada como nó | linha física começando com `%` é node-path: envolva em parênteses |
| `Vector2(array)` inválido | use `Vector2i(array)` ou `Vector2(a[0], a[1])` |
| `:=` não infere | não dá para inferir de `Variant`: anote o tipo |
| controle some da tela | `set_anchors_preset()` deixa offsets em 0: para RIGHT/BOTTOM, defina offsets negativos e `grow_horizontal/vertical = GROW_DIRECTION_BEGIN` |
| coluna de 8 px e botões de 1400 px de altura | filho de `ScrollContainer` só ocupa a largura com `size_flags_horizontal = SIZE_EXPAND_FILL` (já centralizado em `UITheme.scroll()`) |
| `custom_minimum_size` "ignorado" | `_ready()` do filho sobrescreve o que o pai definiu: **mescle com `maxf`** |
| modal gigante | `OptionButton` assume a largura do maior item: `fit_to_longest_item = false` + `clip_text = true` |
| dicionário com arrays vazios | `PackedFloat64Array` é **tipo por valor**: ler, alterar e gravar de volta; `(d[k] as PackedFloat64Array).append(x)` descarta o append |
| texto girado no gráfico | `draw_string` não gira: `draw_set_transform(centro, -PI/2, ONE)`, desenha e reseta |
| fonte esticada no HUD | Silkscreen é pixel font: use múltiplos de 8 px quando possível |
| áudio "não toca" no navegador | política de autoplay: o `AudioContext` só sai de *suspended* após gesto do usuário |
| `AudioStreamOggVorbis` em loop infinito | o `.import` não define loop: setar `stream.loop = true` **antes** do `play()` |
| "editei o PNG e o jogo não mudou" | rodando **fora** do editor, ninguém reimporta: `godot --headless --import` (ou exporte de novo) |
| mapa com buracos pretos | PNG mestre salvo com alfa: o mapa é RGB, transparência vira preto |
| clique em rotulo/vila "nao faz nada" no web | o `Control` raiz do `Main` cobre a tela e, com `MOUSE_FILTER_STOP`, engolia o evento antes do `_unhandled_input` em alguns pontos; deixe o raiz em `MOUSE_FILTER_IGNORE` e teste os rotulos em **coordenadas de mundo** (`WorldView.vila_no_rotulo_mundo`), nao pelo transform de tela |

---

## 7. Capturas e documentação

`tests/Capture.tscn` percorre o jogo e salva 21 PNGs em `docs/shots/`. O roteiro usa
`_pressionar(texto)` (acha um `Button` visível pelo texto), `_aba(i)` e `_esperar(n)`.
Ao adicionar tela nova, acrescente um passo e rode de novo; o teste imprime
`SCRIPT ERROR` se algo quebrar — o alvo é **zero**.

O **manual do usuário** é `docs/manual.html`: arquivo único, 23 capítulos, 17 figuras e
hiperlinks internos (`href="#cap..."`). As capturas vêm de `docs/shots/`; os números
circulares sobre as figuras (`.pin`) são posicionados em porcentagem da imagem — se
recapturar uma tela, confira os pins no navegador antes de publicar. A checagem de links
e imagens cabe em poucas linhas de Python (percorrer `href="#..."` contra os `id` e
`src="..."` contra o disco) e deve dar zero.

No celular (390 px), o sumário vira gaveta: `aside.toc` precisa de `align-self:auto` na
media query — sem isso o Chromium ignora o `position:fixed` dentro do grid e a gaveta
fica com a altura do conteúdo. O fundo da gaveta é opaco (`#090e1a`); translucidez
deixa o texto do herói aparecer por cima.

`docs/` tem `.gdignore`: as capturas não entram no build nem são importadas.
`assets/audio/raw/` (MP3 originais do freesound, ~3,7 MB) também tem `.gdignore` e
está no `exclude_filter` — se entrar no pacote, o build web cresce sem necessidade.

---

## 7.5 Mapa e arte — edição manual

O mapa **não é tilemap**: ele é uma imagem de 3840×2880 (240×180 tiles de 16 px) fatiada
em 16 chunkes de 960×720. A arte atual é um **bake da ilustração**
`assets/Gemini_Generated_FULL-MAP.jpeg`, feito por `tools/extract_terrain.py` (classifica o
terreno) + `tools/bake_map.py` (pixeliza, extrai as rotas do asfalto, calcula o barco e grava
arte + `data/map_data.json`). O gerador antigo, `tools/render_world.py`, continua no
repositório (estilo Kenney; `--terreno` = releitura da ilustração em tiles). Guia completo em
`docs/MAPA.md`; resumo operacional:

| Quero… | Faça | Custo |
|---|---|---|
| desenhar por cima (placas, marcos, detalhes) | pinte `assets/art/decor.png` (RGBA 3840×2880, vem transparente) e rode `python3 tools/split_world.py --decor` | zero risco: o gerador nunca toca nessa camada |
| trocar o mapa inteiro pela ilustração | substitua o JPEG e rode `python3 tools/extract_terrain.py && python3 tools/bake_map.py` | regera arte, chunkes e `map_data.json` |
| mudar terreno/quarteirões | edite `assets/art/world_map.png` e rode `python3 tools/split_world.py` | pintura é perdida se rodar `bake_map.py`/`render_world.py` |
| mudança sistemática (paleta, densidade, ruas) | edite `tools/bake_map.py` (cores, blocos) ou `tools/render_world.py` e rode | regera tudo, inclusive `map_data.json` |
| tilemap no editor | **não é possível hoje** (mapa bakeado, sem grade de índices) | exigiria reescrever gerador + `WorldView` |

Regras: 16 px por tile, NEAREST sempre, RGB no mestre, RGBA na decoração, PNG (nunca
JPEG), tamanho fixo 3840×2880. O fatiador falha com mensagem clara se o tamanho mudar.
O mestre (`world_map.png`) e a ilustração-fonte ficam **fora do pacote** (`exclude_filter`
em `export_presets.cfg`): o jogo só usa os 16 chunkes e o minimapa.

**Ordem de desenho** (`WorldView`): chunkes → `Decor` → overlay epidemiológico (z_index 2)
→ hospitais (2) → tráfego/barcos (3) → asas/planadores (4) → rótulos (5) → efeitos de
entrega/construção (6/7). Os rótulos ficam com `mouse_filter = IGNORE` para não roubar o
arrasto; o clique neles é resolvido em **coordenadas de mundo** por
`WorldView.vila_no_rotulo_mundo()`, chamado pelo `CameraController` antes de procurar a
zona. O `Control` raiz do `Main` fica em `MOUSE_FILTER_IGNORE` para não engolir o evento.
Isso conserta os rótulos de Vale Distante e Nascentes sem transformar o texto num Control
que intercepta o mapa.

`data/traffic_routes.json` guarda as rotas longas de carros e caminhões. Elas são
geradas por `python3 tools/build_traffic_routes.py` com A* sobre
`assets/art/road_nav_mask.png`, uma versão da malha original (`road_mask.png`) com
fechamento de 1 px para reconectar microfuros de antialias. O derivador é
`python3 tools/build_road_nav_mask.py`; `--check` compara o PNG atual com a derivação
e deve imprimir `0 px de diferenca` (foi assim que validei). As antigas `roads` de
`map_data.json` são fragmentos curtos e continuam existindo para compatibilidade; não
as use como pista principal.

Os veículos usam `assets/art/vehicles/pixel_cars.png` (6 colunas × 12 linhas; 6 cores,
2 linhas de modelos e 6 modelos por linha, total de 48 carros e 24 caminhões). Todas as
células olham para a direita; a escala é 0,62 para carros, 0,55 para caminhão de caixa e
0,40 para carreta. Cada célula é recortada no conteúdo útil para o centro do `Sprite2D`
ficar no centro do desenho; para andar no sentido contrário, o mesmo sprite recebe
`flip_h` e o giro compensa com `-PI`. A faixa anda a 2,5 px do eixo; antes de desenhar,
`RoadMask.ponto_em_estrada()` confere o centro e, se preciso, `ajustar_para_estrada()`
puxa o veículo de volta para a malha. Rotas inválidas são descartadas na montagem (com
`push_warning`), em vez de deixar carro atravessar quadra.

A cena tem **2 asas-deltas e 4 parapentes**, não mais. As asas-deltas usam a arte antiga
com o bico para cima e `rotation = atan2(vy,vx) + PI/2`. Os parapentes usam
`assets/art/gliders/paraglider_sheet.png` (3 cores × 4 poses); na montagem e em cada
`GameState.partida_reiniciada` o `WorldView` sorteia cores e poses novas, com pelo menos
três cores entre os quatro. Barcos têm o bico para baixo e usam `-PI/2`.

**Cuidado com a lógica:** `data/map_data.json` guarda `anchor`, `bbox`, `zone_rle`,
`water_rle`, `roads`, `boats`. Mexer na arte sem atualizar isso desalinha clique, câmera,
tráfego e barcos. Detalhe visual não exige nada; mudar de lugar vila/rio/ponte exige regerar
ou editar o JSON.

`AssetRegistry._carregar_decor()` aceita os dois modos: chunkes (`assets/art/decor/`) ou o
mestre inteiro quando ainda não foi fatiado — e, no editor, escolhe o mestre se ele for mais
novo que os chunkes (evita arte "presa" depois de editar). Mestre todo transparente é
descartado com `Image.is_invisible()` para não gastar 42 MB de VRAM.

---

## 8. Exportação web

`export_presets.cfg` já configurado (sem threads, `canvas_resize_policy=2`):

```bash
mkdir -p exports/web
$GODOT --headless --path . --export-release "Web" exports/web/index.html
# o manual e as figuras ficam FORA do .pck: copie depois do export
cp docs/manual.html exports/web/manual.html
rm -rf exports/web/shots && mkdir -p exports/web/shots
cp docs/shots/*.png exports/web/shots/
```

### Publicação contínua (GitHub → Vercel)

O workflow `.github/workflows/publicar-vercel.yml` roda em push para `main`:
importa, roda os testes, exporta `exports/web`, copia `docs/manual.html` e
`docs/shots/`, e força push do resultado para a branch **`deploy`**. A Vercel não
compila Godot: ela serve a branch `deploy`, configurada como **Production Branch**.
O template web sem threads fica em `ci/templates/4.7.2.stable/` para não baixar o
pacote completo de 2 GB em cada execução. O guia operacional, com a configuração
única do projeto na Vercel, está em `docs/PUBLICACAO_VERCEL.md`.

O botão **MANUAL** do HUD chama `Main._abrir_manual()`: no navegador abre
`manual.html` em outra aba; no desktop abre `docs/manual.html` pelo `OS.shell_open`.
O SIGA continua como `PanelSIGA`/`trocar_para("siga")`, mas não aparece no HUD —
a geração real é responsabilidade do backend.

Exclui do pacote: `assets/extracted/*`, `assets/audio/raw/*`, `assets/art_backup/*`,
`assets/*.zip`, `assets/Gemini_Generated_FULL-MAP.jpeg`, `assets/art/world_map.png`,
`docs/shots/*`, `tests/*`, `tools/*`. Ou seja: a ilustração-fonte e o PNG mestre não
viajam para o navegador — o jogo usa só os 16 chunkes + `world_mini.png`. O pacote fica
em ~12 MB (o `index.wasm` de ~39,5 MB é a maior parte do download).

Verificação rápida em navegador headless:

```bash
cd exports/web && python3 -m http.server 8099 &
npx --no-install playwright screenshot --wait-for-timeout=45000 \
  --viewport-size=1280,720 http://127.0.0.1:8099/index.html /tmp/web.png
```

---

### Áudio no navegador — ajuste que não pode ser removido

`project.godot` precisa manter:

```ini
[audio]

general/default_playback_type.web=0
```

O padrão do Godot para web é `1` (*Sample*). Com ele, os Ogg Vorbis do projeto tocam em
**silêncio digital** no navegador (o grafo abre, mas a saída é zero). `0` (*Stream*)
restaura música, ambiência e efeitos. Sintoma clássico: “o jogo abre, mas não tem som”.
Para testar de verdade, meça o RMS com um `AnalyserNode` no navegador — `TestAudio` só
cobre buses e volumes, não a decodificação do navegador.

---

## 9. Antes de dizer "pronto"

- [ ] `godot --headless --import` sem erro
- [ ] `tests/test_statcore.gd` 47/47
- [ ] `SmokeUI` 39/39
- [ ] `TestCamera` 93/93
- [ ] `TestAudio` 129/129
- [ ] `TestAudit` 52 semanas, 0 falhas
- [ ] `TestTrafego` 13/13 (55 veículos, 2 deltas, 4 parapentes, máscara, sprites e recarga)
- [ ] `Capture` 21 PNGs, 0 `SCRIPT ERROR`
- [ ] `docs/manual.html`: 0 links internos quebrados, 0 imagens ausentes, sem overflow
      horizontal em 390 px e gaveta do sumário opaca
- [ ] áudio do build web audível (medido, não “no ouvido”)
- [ ] se mexeu na arte: `python3 tools/split_world.py --verificar` → 0 diferenças
- [ ] export web gera `index.html` + `index.wasm` + `index.pck` e abre no navegador
- [ ] GitHub Actions verde e branch `deploy` atualizada (quando publicar no Vercel)
- [ ] texto novo sem acento e em PT-BR
- [ ] nenhuma conta estatística fora de `StatCore`
