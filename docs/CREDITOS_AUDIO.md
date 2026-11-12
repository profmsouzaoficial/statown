# Creditos de audio — StaTown

Todo o audio do jogo e **CC0 1.0 (dominio publico)** ou **original**, com uma
excecao documentada: a ambiencia base `amb_parque_urbano` usa duas gravacoes
**CC BY 3.0** de KarlSalamander (Freesound), que exigem atribuicao. O restante
nao exige licenca; os creditos abaixo sao cortesia e rastreabilidade.

## 1. Como o audio foi pensado (arquitetura em camadas)

O pedido do projeto era uma **hierarquia sonora**: um som geral para o mapa, um
som por vila, um por minigame, e que tudo soasse harmonico — "ar de misterio, de
descoberta, de aventura". A solucao tem duas metades:

| Camada | Fonte | O que faz |
|---|---|---|
| **1. Tema** | sintetizada aqui (`tools/audio/render_audio.py`) | Musica de fundo: mapa → zona → minigame, com crossfade |
| **2. Ambiencia** | freesound (CC0; base do parque CC BY 3.0) | Loop diegetico do lugar: parque urbano, passaros, rio, mercado, multidao, porto |
| **3. Sting** | sintetizada + acento freesound | Assinatura de 4 s ao entrar numa vila (motivo unico + som real) |
| **4. SFX** | sintetizada aqui | Interface, semana, moeda, alerta, descoberta |

**Por que a musica nao vem do freesound?** Porque pegar 15 musicas de autores
diferentes nunca fecha harmonico: cada uma esta numa tonalidade, temperamento e
mixagem diferentes, e a troca de ambiente soa como radio mudando de estacao. A
trilha inteira foi composta por sintese numerica **em La menor**, com a mesma
paleta de instrumentos (pads de dente-de-serra filtrados, Karplus-Strong,
sinos FM, mallets, baixo senoidal, shaker), a mesma reverberacao por convolucao
e o mesmo plano harmonico (Am–F–C–G e variantes). Resultado: qualquer combinacao
de tema + sting + efeito e consonante, e a passagem mapa → vila → desafio e
percebida como **a mesma peça mudando de arranjo**, nao como outra peca.

Os sons do freesound entram como **identidade organica** — o que a sintese nao
faz bem: o sino da igreja, o galo, a vaca, a bocina do barco, a bigorna, o mercado
publico de Porto Alegre. Sao eles que fazem cada vila "cheirar" a um lugar.

### Mapa harmonico

| Elemento | Tonalidade / modo | BPM |
|---|---|---|
| Mapa (visao geral) | La menor, drone + sino | 64 |
| Zona urbana | La menor, arpejo + shaker | 86 |
| Zona rural | Do–Sol–Am–Fá, mallet | 74 |
| Zona ribeirinha | La menor, arpejo lento | 70 |
| Zona de mata | La menor, drone + passaros | 58 |
| Zona industrial | La menor, pulso + bigorna | 92 |
| Minigames (9) | La menor e relativas | 88–104 |
| Stings das vilas | grau da escala (1..7) por vila | — |

Cada uma das 20 vilas recebe um **grau da escala** diferente (ciclo de 7) e um
**motivo de 3 notas** proprio (duas variantes alternadas por paridade do id),
mais um acento diegetico distinto — inclusive trechos diferentes do mesmo arquivo
(ex.: o mercado de Porto Alegre aparece em duas posicoes diferentes para as vilas
12 e 13).

### Calibragem de nivel

Misturar musica sintetizada com gravacoes de campo exige nivelar por **LUFS**, nao por
pico: medidos os 51 arquivos com `ffmpeg -af ebur128`, a musica ficou entre -19 e
-15 LUFS, as ambiencias entre -21 e -13 e os stings entre -15 e -13. O loop de passaros
era o unico fora da curva (-12,8 LUFS, 6 dB acima da musica), entao cada ambiencia tem
um ajuste em `data/audio.json -> ambiente_ganho_db`, aplicado no crossfade do
`AudioManager`. Os stings tocam a -3 dB e os efeitos a -14 dB (interface) ou -6 a -10 dB
(eventos), o que mantem a hierarquia: musica de fundo < ambiencia < sting < efeito.

## 2. Arquivos originais (sintetizados neste repositorio)

Gerados por `tools/audio/render_audio.py` (numpy + scipy + ffmpeg), sem uso de
samples de terceiros:

- `assets/audio/mus/` — 15 faixas: `mapa`, 5 zonas, 9 minigames (loop perfeito,
  cauda dobrada sobre o inicio).
- `assets/audio/vila/` — 20 stings `vila_01..vila_20` (4,2 s).
- `assets/audio/sfx/` — 10 efeitos: `clique`, `abrir`, `fechar`, `sucesso`,
  `erro`, `moeda`, `semana`, `alerta`, `pagina`, `descoberta`.

Licenca: **CC0 1.0** (mesma do resto do projeto). Voce pode reusar.

## 3. Sons do freesound.org (CC0 1.0, exceto indicado)

Todos baixados pela previa publica em MP3 (128 kbps), sem login, com o filtro de
licenca `Creative Commons 0` aplicado na busca. Depois foram recortados,
equalizados e costurados em loop (crossfade cauda→cabeca) por
`tools/audio/render_audio.py`; os originais ficam em `assets/audio/raw/`
(fora do build web).

| Uso no jogo | Arquivo original | Autor | Link |
|---|---|---|---|
| Parque urbano / base do mapa (`amb_parque_urbano`) | Park 3 + Park 5 (mix, crossfade e loop) | KarlSalamander | https://freesound.org/s/118145/ e https://freesound.org/s/118149/ |
| Passaros / mata (`amb_passaros`) | Forest birds - ambient seamless loop | Magnesus | https://freesound.org/s/723913/ |
| Rio (`amb_rio`) | Relaxing river stream running water seamless loop | steaq | https://freesound.org/s/548767/ |
| Mercado publico (`amb_mercado`) | AMB MERCADO PUBLICO 4 porto alegre brasil | tiagobello | https://freesound.org/s/88421/ |
| Multidao (`amb_multidao`) | Busy Room Ambience / Small crowd | Breviceps | https://freesound.org/s/457043/ |
| Porto (`amb_porto`) | Harbor Ambience 2 | clif_creates | https://freesound.org/s/254130/ |
| Sino da igreja (`acc_sino`) | Church Bell | giordrix | https://freesound.org/s/518343/ |
| Galo (`acc_galo`) | Rooster Crow 1 | BenjaminNelan | https://freesound.org/s/435508/ |
| Vaca (`acc_vaca`) | Cow Moo 2 | invertedturtle | https://freesound.org/s/546479/ |
| Bocina de barco (`acc_bocina`) | 35_Bocina_barco.wav | ChristianAnd | https://freesound.org/s/468846/ |
| Bigorna (`acc_bigorna`) | Anvil - Lokomo 125 kg - Hammer on 6mm steel | ldezem | https://freesound.org/s/386129/ |

Texto e metadados exatos (inclusive o prefixo "Freesound - ... by ...") ficam em
`assets/audio/raw/creditos.json`, gravado pelo downloader.

### Excecao CC BY 3.0: `amb_parque_urbano`

O loop base de 60 s foi montado a partir de duas previas publicas do Freesound:
**Park 3.wav** (id 118145) e **Park 5.wav** (id 118149), de **KarlSalamander**,
licenciadas em **CC BY 3.0**. O processo foi: high-pass 65–75 Hz, low-pass
9,5 kHz, mixagem 0,85/0,60, normalizacao LUFS, crossfade de 2 s, corte/rotacao no cruzamento de zero
para o loop nao estalar e encode OGG. O resultado continua sob CC BY 3.0; a atribuicao acima e
obrigatoria em qualquer redistribuicao do jogo.

## 4. Como regerar

```bash
python3 tools/audio/fetch_freesound.py   # baixa as previas CC0 -> assets/audio/raw/
python3 tools/audio/render_audio.py      # sintetiza musica/sfx e processa o freesound
/home/marcio/opt/godot/godot --headless --import
```

O mapeamento vila → zona → ambiente → acento vive em `data/audio.json` e e lido
tanto pelo Python quanto pelo `AudioManager` (fonte unica, sem duplicar tabela).

## 5. Nota de seguranca

A conta do freesound **nao** foi usada: as previas publicas permitem baixar sem
autenticacao e nao exigem senha em lugar nenhum do codigo. Se em algum momento
for necessario o arquivo original em WAV, o caminho correto e gerar um **token de
API** (freesound.org/apiv2/apply), guarda-lo em variavel de ambiente e **nao**
em arquivo versionado — e, como a senha foi compartilhada em texto, vale troca-la.
