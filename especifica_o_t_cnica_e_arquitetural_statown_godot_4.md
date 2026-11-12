# StaTown: Especificação Técnica e Arquitetural para Implementação em Godot 4.x
**Documento de Engenharia de Software e Game Design Instrucional para Execução via DeepSeek Harness (DSH)**

---

## 1. Visão Geral do Sistema e Diretrizes Operacionais para o Agente (DSH)

### 1.1 Objetivo do Produto
**StaTown** é um *serious game* 2D em estilo *pixel art* de simulação epidemiológica, demográfica, urbanística e de ciência de dados aplicada à saúde, desenvolvido em **Godot Engine 4.x (GDScript 2.0 com tipagem estática estrita)**. O jogo simula um ecossistema composto por **20 Vilas** inspiradas fielmente no zoneamento espacial e na morfologia urbana/rural de **Governador Valadares (MG)**, cortadas pelo **Rio Doce** e emolduradas por formações rochosas (como o maciço inspirado no **Pico da Ibituruna**), florestas, córregos, pontes e túneis.

O objetivo central do jogador (estudante de graduação na área da saúde/biociências) é elevar e manter o **Escore Global de Saúde ($E_{\text{saúde}} \in [0, 100]$)** de todas as 20 Vilas. Para obter recursos financeiros (**BioMoedas**), o jogador deve coletar amostras populacionais, estruturar variáveis em bancos de dados, executar análises bioestatísticas descritivas e inferenciais, construir gráficos, avaliar criticamente artigos científicos e utilizar modelos de Inteligência Artificial de maneira ética e consciente. Com as BioMoedas conquistadas, o jogador financia **cobertura vacinal**, **saneamento básico** e **construção de hospitais/UBS**. Ao final do período letivo (ou ciclo simulado), o sistema gera um relatório auditável com conversão automática para nota acadêmica de participação no **SIGA**.

### 1.2 Caminhos Absolutos do Ambiente de Trabalho
O DeepSeek Harness deve operar diretamente sobre os seguintes diretórios locais:
- **Raiz do Workspace / Projeto Godot:** `/home/marcio/Documentos/deepseek-harness/default-workspace/statown`
- **Mapa de Referência Geoespacial (Zoneamento 01 a 20):** localizado em `/home/marcio/Documentos/deepseek-harness/default-workspace/statown` (arquivo PDF/imagem de setorização municipal — `Mapa_de_setorizacao_do_municipio_Zoneamento_Fiscal.pdf` ou equivalente rasterizado no diretório).
- **Repositório de Assets Gráficos (Arquivos Compactados):** `/home/marcio/Documentos/deepseek-harness/default-workspace/statown/assets`

### 1.3 Protocolo Autônomo de Pré-Processamento (Fase Zero do DSH)
Antes de instanciar cenas ou escrever scripts do jogo, o DSH **deve executar um pipeline de inspeção e preparação via shell/Python**:
1. **Inspeção e Extração de Assets:**
   - Listar todos os arquivos compactados (`.zip`, `.tar.gz`, `.7z`, `.rar`) e imagens em `/home/marcio/Documentos/deepseek-harness/default-workspace/statown/assets`.
   - Descompactar de forma organizada todos os pacotes para `/home/marcio/Documentos/deepseek-harness/default-workspace/statown/assets/extracted/` (preservando os arquivos compactados originais intactos).
   - Inspecionar programaticamente (usando Python `PIL`/`Pillow`) as dimensões em pixels, canais alfa (RGBA), espaçamento (*margin*/*separation*) e tamanho base dos *tiles* (tipicamente grades de $16 \times 16$ pixels, verificando também variações de $8 \times 8$ ou $32 \times 32$ pixels).
   - Gerar um manifesto `assets_manifest.json` catalogando os dois grandes grupos visuais disponíveis:
     - **Pacote Urbano/Estratégico Moderno:** águas costeiras e fluviais, corredeiras, ilhotas, rodovias asfaltadas de pista dupla (retas, curvas, cruzamentos, pontes rodoviárias), edifícios residenciais/comerciais/institucionais em múltiplas paletas de cores (cinza, verde, azul, vermelho, amarelo/laranja), fábricas com telhado *shed* industrial, torres/laboratórios, carros de passeio, caminhões/ambulâncias, barcos/navios, aeronaves, pedestres/agentes de saúde e ícones de UI (dígitos `0-9`, `?`, coração de saúde, moeda/caixa, cadeado, bandeiras, cursor).
     - **Pacote Vila Rústica/Suburbana (RPG/Tiny Town):** terrenos de grama (lisa, com tufos, com flores), terra batida, caminhos de pedras (*cobblestone*), árvores coníferas e frondosas (verdes e outonais), cogumelos, arbustos, casas com telhados de ardósia cinza e cerâmica vermelha (paredes de pedra e madeira, chaminés, portas simples e duplas), cercas de madeira, carroças, poços artesianos/manuais de água, colmeias, placas de sinalização, muralhas de pedra e portões em arco (ideais para muros divisórios e bocas de túneis), ferramentas e aldeões.
2. **Rasterização e Vetorização do Mapa de Referência:**
   - Localizar o mapa de setorização em `/home/marcio/Documentos/deepseek-harness/default-workspace/statown`. Caso esteja em PDF, convertê-lo para PNG de alta resolução (`pdftoppm -png -r 300` ou `pymupdf`) em `/home/marcio/Documentos/deepseek-harness/default-workspace/statown/reference_map_raster.png`.
   - Extrair a máscara poligonal aproximada das **20 Zonas** e a calha contínua do **Rio Doce** para alimentar o gerador determinístico do mapa em `TileMapLayer` do Godot 4, combinando fidelidade cartográfica com composição criativa em *pixel art*.

---

## 2. Engenharia Cartográfica, Morfologia das 20 Vilas e Mundo Vivo

### 2.1 Fidelidade Geográfica ao Rio Doce e Relevo de Governador Valadares
O mapa do mundo (`WorldMap.tscn`) deve ter dimensões amplas e navegáveis (recomendado: grade de $240 \times 180$ *tiles* de $16 \times 16$ pixels, totalizando $3840 \times 2880$ pixels, com câmera `Camera2D` dotada de *pan* suave por mouse/WASD e *zoom* progressivo com *pixel snap* perfeito).

1. **O Rio Doce (Eixo Estruturante Intocável):**
   - Deve cruzar o mapa ingressando pelo extremo **Sudoeste (SW)**, fluindo no sentido **Nordeste (NE)** entre a margem oeste/norte (Vilas 16, 13, 08, 01) e a margem leste/sul (Vilas 18, 15, 12, 19).
   - Na porção central do mapa, o rio **abre-se em dois canais contornando integralmente a Vila 07** (inspirada na **Ilha dos Araújos**), formando uma ilha fluvial urbanizada bem definida.
   - Após contornar a Vila 07 e margear a Vila 01, o Rio Doce inflete para **Leste-Nordeste e Leste**, acompanhando toda a extensão sul da **Vila 02** em direção à **Vila 20**, exibindo bancos de areia, ilhotas fluviais, vegetação ciliar e embarcações animadas navegando ao longo do canal principal.
2. **O Maciço Montanhoso Sul/Sudeste e Colinas Norte:**
   - Ao sul/sudeste das Vilas 15, 12 e 19, erguer uma imponente formação montanhosa rochosa e florestada inspirada no **Pico da Ibituruna**, funcionando como barreira geográfica natural e marco visual icônico.
   - Nas bordas norte/noroeste (Vilas 11, 04, 03) e leste (entre Vilas 02 e 20), posicionar colinas, afloramentos de pedra e matas densas, atravessados por **túneis rodoviários** (construídos visualmente acoplando rodovias de asfalto aos portões em arco de pedra encravados em *tiles* de montanha/muralha).
3. **Pontes Estratégicas:**
   - Construir pontes rodoviárias e de pedestres em posições homólogas à malha viária real de Governador Valadares:
     - **Ponte Sul/BR (Eixo Vila 13 $\leftrightarrow$ Vila 12/15):** inspirada na Ponte do São Raimundo (BR-116), com fluxo intenso de caminhões e carros.
     - **Pontes Insulares (Vila 01 $\leftrightarrow$ Vila 07 e Vila 08 $\leftrightarrow$ Vila 07):** conectando a ilha fluvial à malha central.
     - **Pontes sobre Córregos Urbanos:** interligando Vilas separadas por tributários hídricos (ex.: entre Vilas 04, 10, 14, 16 e 17).

### 2.2 Regras Rígidas de Demarcação de Fronteiras entre Zonas (Vilas)
Os limites entre cada uma das **20 Vilas** não podem ser linhas abstratas invisíveis; eles **devem ser fisicamente construídos no mundo com elementos diegéticos claros** combinados a um *overlay* vetorial sutil (ativável/desativável pela tecla `B` ou botão de UI):
- **Muros de Pedra e Portões Urbanos:** separam vilas centrais adensadas (ex.: divisas entre Vilas 01, 05, 06, 08 e o enclave da Vila 09).
- **Cercas de Madeira Contínuas:** delimitam zonas residenciais horizontais, chácaras e áreas periurbanas (ex.: divisas das Vilas 10, 14, 17, 18, 11 e 19).
- **Córregos e Canais de Drenagem:** pequenos cursos d'água de 1 a 2 *tiles* de largura desaguando no Rio Doce, separando bacias urbanas (ex.: divisas entre Vilas 04/10 e 16/13), transpostos por pequenas pontes.
- **Cinturões Florestais e Maciços de Pedra:** fileiras duplas/triplas de pinheiros, árvores frondosas e rochedos isolando zonas periféricas ou distritais (ex.: separação das Vilas 11, 19 e 20).

### 2.3 Matriz Topológica e Socioespacial das 20 Vilas
O DSH deve instanciar exatamente 20 entidades `VilaData` configuradas conforme a morfologia observada no zoneamento municipal e na distribuição espacial real (sem exibir nomes reais de bairros ao jogador, adotando nomes lúdicos que evocam sua vocação geográfica):

| ID | Nome Lúdico no Jogo | Posição Relativa no Mapa (Ref. PDF) | Perfil Urbano e Uso Criativo de Assets | Renda Base ($\mu$ em SM) | Saneamento Inicial ($\%$) | População Inicial ($N_0$) |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: |
| **Vila 01** | Vila Central do Rio | Margem norte do Rio Doce, centro | Alta verticalização (prédios azuis/cinzas), comércio intenso, avenidas duplas, praças, carros | $4.2$ | $92\%$ | $2800$ |
| **Vila 02** | Vila Ribeira Leste | Longo corredor NE/Leste na margem norte do rio | Eixo rodoviário longo, galpões, conjuntos habitacionais espaçados, mata ciliar, barcos | $2.1$ | $68\%$ | $2100$ |
| **Vila 03** | Vila da Encosta Norte | Extremo norte-central (acima de 05, leste de 04) | Casas de telhado vermelho em aclive, colinas rochosas ao norte, ruas mistas | $1.9$ | $65\%$ | $1400$ |
| **Vila 04** | Vila das Nascentes | Grande setor norte/noroeste | Bairros extensos de casas e pequenos prédios verdes, cortada por córregos e bosques | $2.2$ | $72\%$ | $3200$ |
| **Vila 05** | Vila do Mirante | Entre Vilas 04, 03, 01 e 06 | Transição urbana densa, muros de pedra, prédios médios amarelos/vermelhos | $3.1$ | $85\%$ | $1600$ |
| **Vila 06** | Vila Esplanada Real | Oeste da Vila 01, envolvendo Vila 09 | Arborizada, prédios residenciais nobres, clínicas, avenidas bem traçadas | $4.8$ | $95\%$ | $2200$ |
| **Vila 07** | Vila da Ilha | **Ilha fluvial no centro do Rio Doce** | Cercada $100\%$ pelo rio, 2 pontes, casas amplas, parques floridos, quiosques, alta qualidade | $5.2$ | $96\%$ | $1900$ |
| **Vila 08** | Vila Beira-Rio Oeste | Margem oeste/norte em frente à Vila 07 | Comércio e residências mistas, orla pavimentada, tráfego urbano intenso | $3.4$ | $88\%$ | $1750$ |
| **Vila 09** | Vila do Claustro | Enclave compacto entre Vilas 06 e 10 | Delimitada por muros de pedra e portões, alta densidade residencial organizada | $3.6$ | $90\%$ | $1100$ |
| **Vila 10** | Vila das Acácias | Platô centro-oeste (entre 04, 06, 14, 17) | Grande malha residencial horizontal (casas cinza/vermelhas), escolas, avenidas | $2.6$ | $80\%$ | $2900$ |
| **Vila 11** | Vila do Vale Distante | Setor destacado a Noroeste (isolado) | Casas rústicas, cercas de madeira, carroças, poços d'água, ligada por estrada com túnel | $1.4$ | $42\%$ | $950$ |
| **Vila 12** | Vila da Ponte Sul | Margem leste/sudeste do Rio Doce | Cabeceira sul da grande ponte, galpões comerciais, caminhões, casas populares | $2.0$ | $70\%$ | $2300$ |
| **Vila 13** | Vila Entre-Pontes | Margem oeste do rio, ao sul da Vila 08/14 | Entroncamento viário pesado, oficinas, fábricas leves, prédios comerciais | $2.5$ | $78\%$ | $1850$ |
| **Vila 14** | Vila dos Ipês | Centro-oeste (entre 10, 08, 13, 16, 17) | Residencial densa de classe média-baixa, praças de terra/pedra, comércio local | $2.3$ | $76\%$ | $2400$ |
| **Vila 15** | Vila do Pico | Grande setor Sul/Sudeste abaixo da Vila 12 | Sopé da grande montanha sul (estilo Ibituruna), bairros em expansão, cercas e trilhas | $1.8$ | $62\%$ | $3100$ |
| **Vila 16** | Vila Fabril Sudoeste | Extenso eixo Sudoeste na margem norte/oeste + apêndice SW | **Polo Industrial** (fábricas com chaminés, caminhões de carga), rodovia e vilas operárias | $1.7$ | $58\%$ | $3400$ |
| **Vila 17** | Vila Horizonte Oeste | Grande faixa periférica Oeste (borda de 10, 14, 16) | Casas simples, muitos poços manuais, caminhos de terra/pedra, cercas, colinas a oeste | $1.5$ | $48\%$ | $3600$ |
| **Vila 18** | Vila da Várzea Sul | Margem sul do rio, a oeste da Vila 15 | Casas ribeirinhas, pomares (árvores frutíferas/outonais), vulnerável a cheias/doenças hídricas | $1.4$ | $45\%$ | $1350$ |
| **Vila 19** | Vila das Chácaras | Margem leste frente à Ilha (07) + 2 enclaves rurais a leste | Baixa densidade, sítios cercados, colmeias, poços, florestas densas e estradas vicinais | $1.6$ | $40\%$ | $850$ |
| **Vila 20** | Vila da Cachoeira Leste | Enclave extremo Leste após a Vila 02 | Distrito pitoresco junto às corredeiras leste do rio, conectado por estrada/túnel serrano | $1.5$ | $44\%$ | $900$ |

### 2.4 Dinâmica de "Mundo Vivo" (Living World System)
Para tornar o mapa organicamente vivo e responsivo às variáveis bioestatísticas:
- **Tráfego Veicular em Grafo (`RoadTrafficManager.gd`):** Carros e caminhões dos *spritesheets* percorrem um grafo `AStar2D` sobre as rodovias asfaltadas, cruzando as pontes do Rio Doce e atravessando os túneis nas montanhas. Quando o jogador constrói um Hospital ou deflagra uma Campanha de Vacinação, unidades móveis de saúde (veículos brancos/azuis) deslocam-se visualmente até a Vila beneficiada.
- **Cidadãos Visíveis (`CitizenVisualPool.gd`):** Cada Vila exibe entre $15$ e $60$ pequenos *sprites* de aldeões/cidadãos caminhando pelas ruas de pedra e calçadas (proporcional ao tamanho populacional atual).
- **Feedback Visual de Infraestrutura e Epidemia:**
  - Vilas com baixo saneamento exibem **poços rústicos abertos** e terrenos barrentos; ao investir em **Saneamento Básico**, o mapa substitui poços por estações tratadoras limpas, calçamento de pedra e jardins floridos.
  - Ao construir **Hospitais/UBS**, um edifício institucional destacado (com ícone de coração/cruz em *pixel art*) surge fisicamente na Vila com animação de construção.
  - Durante surtos epidêmicos elevados (prevalência $> 10\%$), um halo pulsante âmbar/vermelho suave contorna os limites da Vila no *overlay* epidemiológico e pequenos indicadores visuais alertam o jogador.

---

## 3. Motor de Simulação Demográfica, Socioeconômica e Epidemiológica

### 3.1 Controle Temporal (`SimulationClock.gd`)
- O tempo avança em **Dias Simulados** agrupados em **Semanas Epidemiológicas (SE $1, 2, \dots, 52$)**.
- Botões na HUD superior: `Pausar (0x)`, `Lento (0.5x)`, `Normal (1x = 1 SE a cada 6 segundos reais)`, `Rápido (3x)`, `Ultra (8x)`.
- A simulação continua rodando em tempo real (a menos que o jogador pause explicitamente ou ative a opção de "Auto-Pausa ao abrir Laboratório Estatístico").

### 3.2 Banco de Microdados Sintéticos Dinâmicos (`PopulationRegistry.gd`)
Diferente de simuladores puramente agregados, o **StaTown** mantém para cada Vila $i \in \{1, \dots, 20\}$ uma estrutura híbrida: contadores compartimentais rápidos **sincronizados com uma Tabela de Microdados Individuais** (escala de $1:1$ ou $1:5$ conforme performance, garantindo ao menos $8.000$ a $40.000$ registros individuais ativos em memória utilizando `PackedByteArray` / `PackedFloat32Array` orientados a dados para custo quase zero de CPU).

Cada indivíduo $k$ possui o seguinte vetor de variáveis (acessível para amostragem e exportação):
1. `id_individuo` (`int` único)
2. `vila_id` (`int` de `1` a `20`) e `vila_nome` (`String` — Qualitativa Nominal)
3. `idade` (`float` / `int` em anos completos de $0$ a $100$ — Quantitativa Contínua/Discreta)
4. `faixa_etaria` (`String` — Qualitativa Ordinal: `"0-14 (Jovem)"`, `"15-59 (Adulto)"`, `"60+ (Idoso)"`)
5. `genero` (`String` — Qualitativa Nominal: `"Feminino"`, `"Masculino"`)
6. `renda_familiar_sm` (`float` em salários mínimos, gerada por distribuição Log-Normal $\ln(X) \sim \mathcal{N}(\mu_i, \sigma_i^2)$ produzindo assimetria positiva realista — Quantitativa Contínua)
7. `estrato_renda` (`String` — Qualitativa Ordinal: `"Baixa (< 2 SM)"`, `"Média (2 a 5 SM)"`, `"Alta (> 5 SM)"`)
8. `escolaridade` (`String` — Qualitativa Ordinal: `"Fundamental"`, `"Médio"`, `"Superior"`)
9. `saneamento_domiciliar` (`int` binário `0`/`1` ou `"Não"`/`"Sim"`, governado pelo nível de saneamento $S_i \in [0, 1]$ da Vila)
10. `doses_vacina` (`int` `0`, `1`, `2` — Quantitativa Discreta) e `status_vacinal` (`"Não Vacinado"`, `"Parcial"`, `"Imunizado"`)
11. `estado_epidemiologico` (`"Suscetível"`, `"Exposto"`, `"Infectado"`, `"Recuperado"`, `"Óbito"`)
12. `biomarcador_clinico` (`float` — ex.: Índice Inflamatório / Carga Viral / Pressão Arterial Sistólica em $\text{mmHg}$, modelado com ruído Gaussiano $\mathcal{N}(\mu_{\text{estado}}, \sigma^2)$ ou assimétrico conforme a doença ativa, permitindo testes $t$, ANOVA, Mann-Whitney e Regressão!)
13. `dias_sintomas` (`int` — Quantitativa Discreta, modelada via distribuição de Poisson $\text{Pois}(\lambda)$ nos infectados)

### 3.3 Dinâmica Vital (Natalidade, Envelhecimento e Mortalidade)
A cada Semana Epidemiológica ($\Delta t = 1\text{ SE} = \frac{1}{52}\text{ ano}$), em cada Vila $i$ de população viva $N_i(t)$:
- **Natalidade:** O número de nascimentos segue $B_i(t) \sim \text{Pois}\left(N_i(t) \cdot \frac{\nu_i}{52}\right)$, onde a taxa bruta anual de natalidade $\nu_i$ é inversamente modulada pela renda média da Vila ($\nu_i \in [0.011, 0.022]$). Novos indivíduos nascem com `idade = 0`, `estado = Suscetível` e herdam o estrato socioeconômico/saneamento da Vila.
- **Envelhecimento:** A idade de todos os indivíduos vivos incrementa em $\frac{1}{52}$ ano por SE, atualizando dinamicamente sua `faixa_etaria`.
- **Mortalidade Basal (Natural):** A probabilidade semanal de óbito por causas naturais depende da idade segundo uma curva de Gompertz-Makeham simplificada:
  $$p_{\text{morte\_nat}}(a) = 1 - \exp\left(-\frac{\alpha_0 + \alpha_1 e^{\alpha_2 a}}{52}\right)$$
  reduzida em até $25\%$ pela presença de Hospitais/UBS e saneamento adequado na Vila.

### 3.4 Motor Epidemiológico Compartimental-Estocástico Multi-Doenças (`EpidemicEngine.gd`)
O jogador (ou professor em modo configuração) seleciona no **Menu de Cenários Epidemiológicos** qual patógeno/agravo atuará na simulação (podendo inclusive enfrentar surtos combinados em níveis avançados):

1. **Arbovirose Valadarense (Inspirada em Dengue/Chikungunya):**
   - Forte dependência ambiental e de saneamento: a taxa de transmissão efetiva $\beta_i$ aumenta drasticamente em Vilas com baixo `saneamento_domiciliar` e próximas a áreas alagadiças ($S_i$ baixo), com sazonalidade senoidal simulando o período chuvoso/quente do vale do Rio Doce.
   - Parâmetros padrão: $R_0 = 2.8$, período de incubação $\sigma^{-1} = 1.0\text{ SE}$, recuperação $\gamma^{-1} = 1.5\text{ SE}$, letalidade base $\text{CFR}_0 = 0.8\%$ (sobe para $3.5\%$ se os leitos hospitalares da Vila saturarem).
2. **Vírus Respiratório Agudo (Inspirado em Influenza/SARS):**
   - Alta transmissibilidade interpessoal e forte acoplamento espacial pela matriz de mobilidade pendular $M_{ij}$ (fluxo intenso pelas pontes rumo à Vila 01, Vila 07 e Vila 16).
   - Parâmetros padrão: $R_0 = 3.6$, $\sigma^{-1} = 0.5\text{ SE}$, $\gamma^{-1} = 1.2\text{ SE}$, letalidade fortemente concentrada na faixa `60+ (Idoso)` ($\text{CFR}_{\text{idoso}} = 6.5\%$, $\text{CFR}_{\text{jovem}} = 0.1\%$). Altíssima resposta à **Vacinação**.
3. **Enteropatia Hídrica Aguda (Inspirada em Cólera/Gastroenterite):**
   - Transmissão fecal-oral estritamente ligada à falta de água tratada (poços contaminados). Impacto devastador em `0-14 (Jovem)` e `60+ (Idoso)` nas Vilas de baixa renda.
   - Parâmetros padrão: $R_0 = 2.4$ em áreas sem saneamento ($R_t < 0.6$ quando $S_i > 85\%$), letalidade $\text{CFR}_0 = 2.2\%$ (cai para $0.1\%$ com UBS/hidratação).
4. **Agravo Crônico Não-Transmissível (Modo Epidemiologia de Fatores de Risco — Hipertensão/Diabetes):**
   - Transmissibilidade infecciosa $\beta = 0$; a incidência depende de idade, renda, escolaridade e estilo de vida. Ideal para aulas focadas em **Regressão Linear Simples**, **Correlação** e **Estudos de Coorte/Caso-Controle**.

#### Equações de Transição por Semana Epidemiológica na Vila $i$:
A força de infecção $\lambda_i(t)$ incorpora transmissão interna e mobilidade entre Vilas conectadas por estradas/pontes ($M_{ij}$):
$$\lambda_i(t) = \beta_0 \cdot (1 - \eta_{\text{san}} S_i) \cdot \left[ (1 - m) \frac{I_i(t)}{N_i(t)} + m \sum_{j=1}^{20} M_{ij} \frac{I_j(t)}{N_j(t)} \right]$$
onde $\eta_{\text{san}} \in [0, 0.85]$ é a sensibilidade da doença ao saneamento $S_i \in [0, 1]$, e $m \in [0.05, 0.25]$ é a fração de mobilidade inter-vilas.

Para indivíduos suscetíveis com eficácia vacinal individual $v_k \in \{0, 0.55, 0.90\}$:
$$P(S_k \rightarrow E_k) = 1 - \exp\big(-\lambda_i(t) \cdot (1 - v_k)\big)$$
Transições subsequentes:
$$P(E_k \rightarrow I_k) = 1 - e^{-\sigma}, \qquad P(I_k \rightarrow \text{Desfecho}) = 1 - e^{-\gamma}$$
Dado o desfecho da infecção, a probabilidade de óbito pela doença (Letalidade Efetiva $\text{CFR}_{i,k}$) é:
$$\text{CFR}_{i,k} = \text{CFR}_{\text{base}}(\text{idade}_k) \cdot (1 - \eta_{\text{vac\_grav}} v_k) \cdot \left(1 - \eta_{\text{hosp}} H_i \cdot \min\left(1, \frac{L_i}{I_i(t) + 1}\right)\right)$$
onde $H_i \in [0, 1]$ representa o nível de infraestrutura hospitalar instalada na Vila $i$ e $L_i$ a capacidade de leitos ativos.

#### Indicadores Epidemiológicos Calculados em Tempo Real (por Vila e Global):
- **Taxa de Incidência Semanal (por $1.000$ hab.):** $\text{TI}_i(t) = \frac{\text{Novos Casos na SE } t}{\text{População Suscetível em Risco}} \times 1000$
- **Prevalência Pontual ($\%$):** $\text{Prev}_i(t) = \frac{I_i(t)}{N_i(t)} \times 100$
- **Taxa de Letalidade ($\text{CFR}\%$):** $\text{Let}_i(t) = \frac{\text{Óbitos Acumulados pela Doença}}{\text{Casos Confirmados Acumulados}} \times 100$
- **Taxa de Mortalidade Específica (por $1.000$ hab.):** $\text{TM}_i(t) = \frac{\text{Óbitos pela Doença}}{\text{População Total } N_i(t)} \times 1000$
- **Cobertura Vacinal ($\%$):** $\text{CobVac}_i(t) = \frac{\text{Vacinados com Esquema Completo}}{N_i(t)} \times 100$

---

## 4. Laboratório Interativo de Bioestatística e Ciência de Dados (Workbench UI)

Ao clicar em qualquer uma das **20 Vilas** no mapa ou abrir a barra lateral **BioStat Lab**, o jogador acessa um painel analítico modular completo. **Nenhuma biblioteca binária externa C++ deve ser exigida**; o DSH deve implementar um módulo matemático puro, testado e preciso em GDScript (`res://scripts/stats/StatCore.gd`) mais um renderizador vetorial de gráficos (`res://scripts/ui/charts/StatChartCanvas.gd` usando `Control._draw()`, fontes nítidas, *tooltips* ao passar o mouse e exportação de imagem PNG).

### 4.1 Módulo 1: Delineamento de Estudos e Amostragem (`SamplingPanel.gd`)
1. **Seletor de Tipo de Estudo:** O jogador escolhe o delineamento para investigar o problema de saúde atual:
   - *Estudo Ecológico* (unidade de análise = as 20 Vilas agregadas; alerta didático automático sobre *Falácia Ecológica*).
   - *Estudo Transversal (Seccional)* (retrato instantâneo da prevalência e fatores associados na SE atual; calcula Razão de Prevalência $\text{RP}$).
   - *Estudo Caso-Controle* (seleciona retrospectivamente infectados vs não-infectados pareados e verifica exposição prévia a falta de saneamento/não-vacinação; calcula *Odds Ratio* $\text{OR}$).
   - *Estudo de Coorte* (acompanha prospectivamente por $k$ semanas um grupo exposto vs não-exposto; calcula Risco Relativo $\text{RR}$).
   - *Ensaio Comunitário / Clínico* (aloca vacina em grupo intervenção vs controle).
2. **Calculadora Amostral Integrada:**
   - Realizar censo completo nas 20 Vilas custa caro; coletar uma amostra científica planejada é barato e gera bônus de precisão!
   - O painel exibe as fórmulas para população finita $N$ (estimativa de proporção e de média) e solicita que o aluno preencha ou valide os parâmetros ($\alpha = 0.05 \Rightarrow Z_{1-\alpha/2} = 1.96$, erro amostral máximo $E$, proporção estimada $\hat{p}$ ou desvio-padrão piloto $s$):
     $$n_0 = \frac{Z_{1-\alpha/2}^2 \cdot \hat{p}(1 - \hat{p})}{E^2}, \qquad n = \frac{N \cdot n_0}{N + n_0 - 1}$$
3. **Execução das Técnicas de Amostragem:**
   - **Aleatória Simples (AAS):** sorteio equiprovável sem reposição via gerador Mersenne/PCG.
   - **Sistemática:** sorteio de ponto inicial $r \in [1, k]$ e salto fixo $k = \lfloor N/n \rfloor$.
   - **Estratificada Proporcional ou Ótima:** estratificação por `vila_id`, `faixa_etaria` ou `estrato_renda`.
   - **Por Conglomerados:** sorteio aleatório de $m$ Vilas ou quadras residenciais inteiras.

### 4.2 Módulo 2: Estruturação de Banco de Dados e Exportação Externa (`DataEditorPanel.gd`)
Atende diretamente aos objetivos de *elaboração/inserção de variáveis* e *uso de softwares estatísticos*:
- Exibe uma planilha interativa (`Tree` ou `GridContainer` virtualizado) com os indivíduos amostrados.
- **Dicionário de Variáveis (Codebook):** O jogador deve classificar corretamente cada coluna (Qualitativa Nominal, Qualitativa Ordinal, Quantitativa Discreta, Quantitativa Contínua) e pode **criar variáveis derivadas** via construtor de expressões (ex.: categorizar `biomarcador_clinico` em `"Normal"` vs `"Alterado"`, ou calcular `renda_per_capita`).
- **Auditoria de Dados Sujos (Data Cleaning):** Amostras de campo trazem ocasionalmente erros simulados de digitação (ex.: `idade = 999`, `genero = "Femnino"`, valores ausentes `NA`) que o aluno deve higienizar antes de rodar análises!
- **Exportação `.CSV` e `.JSON` com 1 Clique:** Salva o banco amostrado em `/home/marcio/Documentos/deepseek-harness/default-workspace/statown/exports/` para que o aluno possa abrir no **RStudio, Jamovi, JASP, SPSS ou Python**, permitindo validar os cálculos dentro e fora do jogo.

### 4.3 Módulo 3: Estatística Descritiva Completa e Visualizações (`DescriptivePanel.gd`)
Para qualquer variável (filtrada por Vila ou comparando múltiplas Vilas):
1. **Medidas Numéricas Exatas (`StatCore.gd`):**
   - *Tendência Central e Posição:* Média aritmética ($\bar{x}$), Mediana ($Md$), Moda ($Mo$), Quartis ($Q_1, Q_2, Q_3$) e Percentis ($P_{10}, P_{90}$).
   - *Dispersão:* Variância amostral ($s^2 = \frac{1}{n-1}\sum (x_i - \bar{x})^2$), Desvio-Padrão ($s$), Amplitude Total ($\max - \min$), Intervalo Interquartil ($\text{IIQ} = Q_3 - Q_1$), Coeficiente de Variação ($\text{CV} = \frac{s}{\bar{x}} \times 100\%$).
   - *Assimetria (Skewness de Fisher-Pearson ajustada):*
     $$g_1 = \frac{n}{(n-1)(n-2)} \sum_{i=1}^{n} \left(\frac{x_i - \bar{x}}{s}\right)^3$$
     com interpretação automática (Assimétrica Positiva/à Direita, Simétrica, Assimétrica Negativa/à Esquerda).
   - *Forma / Curtose (Excesso de Curtose Amostral):*
     $$g_2 = \frac{n(n+1)}{(n-1)(n-2)(n-3)} \sum_{i=1}^{n} \left(\frac{x_i - \bar{x}}{s}\right)^4 - \frac{3(n-1)^2}{(n-2)(n-3)}$$
     classificando em Leptocúrtica ($g_2 > 0$), Mesocúrtica ($g_2 \approx 0$) ou Platicúrtica ($g_2 < 0$).
2. **Motor Gráfico Interativo (`StatChartCanvas.gd`):**
   - **Histograma** (com seletor de número de classes pela regra de Sturges $k = \lceil 1 + 3.322 \log_{10}(n) \rceil$ e sobreposição opcional da curva Normal teórica).
   - **Boxplot Comparativo Múltiplo** (comparando lado a lado 2 a 20 Vilas, destacando mediana, caixa $Q_1\text{--}Q_3$, bigodes de $1.5 \times \text{IIQ}$ e *outliers* individuais clicáveis).
   - **Gráfico de Barras / Colunas Agrupadas e Empilhadas** (para variáveis qualitativas como `estrato_renda` e `status_vacinal`).
   - **Curva Epidêmica Temporal** (casos incidentes, prevalência e óbitos por Semana Epidemiológica).
   - **Diagrama de Dispersão (Scatterplot)** com reta de regressão e banda de confiança.
   - **Gerador de Quadros e Tabelas Padronizadas:** tabelas de distribuição de frequências e tabelas de contingência formatadas no padrão científico (bordas horizontais limpas, sem bordas verticais fechadas, título superior e fonte inferior).

### 4.4 Módulo 4: Distribuições de Probabilidade e Testes de Hipóteses (`InferencePanel.gd`)
1. **Simulador de Distribuições de Probabilidade:**
   - Ajuste visual e cálculo de probabilidades exatas/acumuladas para:
     - **Binomial:** $P(X = k) = \binom{n}{k} p^k (1-p)^{n-k}$
     - **Poisson:** $P(X = k) = \frac{e^{-\lambda} \lambda^k}{k!}$
     - **Normal:** $f(x) = \frac{1}{\sigma\sqrt{2\pi}} \exp\left(-\frac{(x-\mu)^2}{2\sigma^2}\right)$, utilizando aproximação numérica de alta precisão para a função erro $\text{erf}(z)$ (erro absoluto $< 1.5 \times 10^{-7}$ via polinômio de Abramowitz & Stegun) para obter $p$-valores exatos!
2. **Comparação entre Grupos (Paramétricos vs Não-Paramétricos):**
   - Antes de liberar o resultado, o jogo pergunta ao aluno: *"Diante da simetria/normalidade ($g_1$, teste de normalidade) e do tipo de variável, qual teste é o mais adequado?"* (Acertar a escolha metodológica concede BioMoedas extras!).
   - **Testes Paramétricos Implementados:**
     - *Teste $t$ de Student para 2 amostras independentes* (versões homocedástica e de Welch) e *Teste $t$ pareado* (pré vs pós-intervenção nas 20 Vilas), reportando $t$, $\text{gl}$, $p$-valor bilateral (via função Beta Incompleta Regularizada $I_x(a,b)$ implementada em `StatCore.gd`) e $\text{IC}_{95\%}$ da diferença de médias.
     - *ANOVA One-Way* para comparar $k \geq 3$ Vilas ou faixas etárias: calcula $\text{SQ}_{\text{entre}}$, $\text{SQ}_{\text{dentro}}$, $\text{QM}$, estatística $F$, $p$-valor e comparações múltiplas *post-hoc* com correção de Bonferroni/Tukey.
   - **Testes Não-Paramétricos Implementados:**
     - *Teste $U$ de Mann-Whitney* (soma de postos com correção para empates e aproximação normal com correção de continuidade para $n_1, n_2$).
     - *Teste $H$ de Kruskal-Wallis* para $k \geq 3$ grupos independentes assimétricos/ordinais.
     - *Teste Qui-Quadrado de Independência de Pearson ($\chi^2$)* (com correção de Yates para tabelas $2 \times 2$ e alerta automático quando frequência esperada $E_{ij} < 5$, acionando cálculo do *Teste Exato de Fisher* via log-fatoriais $\ln(n!)$).

### 4.5 Módulo 5: Correlação, Regressão Linear Simples e Laboratório de IA (`RegressionAIPanel.gd`)
1. **Correlação e Regressão Linear Simples:**
   - Permite cruzar variáveis tanto no nível individual quanto no nível ecológico das 20 Vilas (ex.: $X = \text{Cobertura de Saneamento } (\%)$ vs $Y = \text{Taxa de Incidência}$, ou $X = \text{Renda Familiar}$ vs $Y = \text{Biomarcador Clínico}$).
   - Calcula Coeficiente de Pearson ($r$), Coeficiente de Postos de Spearman ($\rho$), Coeficiente de Determinação ($R^2$), intercepto $\hat{\beta}_0$, inclinação $\hat{\beta}_1$, erro-padrão de $\hat{\beta}_1$, estatística $t$ e $p$-valor da inclinação:
     $$\hat{Y} = \hat{\beta}_0 + \hat{\beta}_1 X, \qquad \hat{\beta}_1 = \frac{\sum (x_i - \bar{x})(y_i - \bar{y})}{\sum (x_i - \bar{x})^2}, \qquad \hat{\beta}_0 = \bar{y} - \hat{\beta}_1 \bar{x}$$
2. **Introdução a Modelos de Inteligência Artificial e Uso Consciente de IA:**
   - **Submódulo Preditivo (Machine Learning Interpretável):** O jogador treina dentro do jogo um classificador de **Regressão Logística Binária** (via Descida de Gradiente em GDScript) ou **Árvore de Decisão Rasa** para prever `risco_hospitalizacao` ou `vila_em_surto_proxima_semana`. Exibe divisão Treino ($70\%$) / Teste ($30\%$), Matriz de Confusão, Acurácia, Sensibilidade, Especificidade e demonstra na prática o **Viés de Seleção Algorítmica** (se o aluno treinar o modelo apenas com dados da rica Vila 07, a acurácia despenca ao aplicar na periférica Vila 17!).
   - **NPC Tutor "Dr. Bayes" (Auditoria de IA Generativa):** Um personagem cientista em *pixel art* simula um assistente de IA. O aluno pode pedir ajuda ao Dr. Bayes para gerar scripts em **R** e **Python (`pandas`/`scipy`/`statsmodels`)** correspondentes aos dados atuais da partida, mas **atenção**: em desafios específicos de "Uso Consciente de IA", o assistente apresenta respostas contendo sutis *alucinações bioestatísticas* (ex.: confundir correlação com causalidade, sugerir média para distribuição fortemente assimétrica, ou afirmar que $p = 0.07$ prova que $H_0$ é verdadeira). O aluno ganha BioMoedas e multiplicadores ao auditar e corrigir criticamente a saída da IA!

---

## 5. Economia Gamificada, Minigames Temáticos e Leitura Crítica de Artigos

### 5.1 Economia das BioMoedas e Custos de Intervenção (`EconomyManager.gd`)
O jogador inicia com um orçamento emergencial modesto ($150$ BioMoedas). Todas as ações estruturais de saúde pública exigem BioMoedas conquistadas pelo domínio intelectual de bioestatística:
- **Lote de Vacinação Local (por Vila, $+25\%$ de cobertura):** $40$ BioMoedas (escala levemente com $N_i$).
- **Campanha de Vacinação Estratificada (ex.: apenas Idosos `60+` em todas as Vilas):** $90$ BioMoedas — ensina alocação custo-efetiva baseada em risco epidemiológico!
- **Expansão de Saneamento Básico ($+20\%$ em uma Vila):** $65$ BioMoedas — reduz permanentemente $\beta_i$ de arboviroses e doenças hídricas e atualiza os *tiles* visuais da Vila.
- **Construção de UBS (Nível 1) / Hospital Regional (Nível 2):** $80$ / $160$ BioMoedas — adiciona edifício no mapa, amplia leitos $L_i$ e reduz letalidade ($\text{CFR}$).

### 5.2 Minigames Pedagógicos (9 Trilhas Curriculares — `MinigameHub.gd`)
Acessíveis a qualquer momento pelo botão **"Desafios & Minigames"** (com banco rico de questões parametrizadas dinamicamente a partir dos próprios dados vivos das 20 Vilas, evitando memorização mecânica!):
1. *Detetive de Delineamentos:* classificar cenários reais de pesquisa nas Vilas em Transversal, Coorte, Caso-Controle, Ecológico ou Ensaio Clínico ($+25$ moedas).
2. *Arquiteto do Banco de Dados:* arrastar e soltar variáveis no tipo estatístico correto e corrigir inconsistências de digitação ($+20$ moedas).
3. *Mestre da Assimetria e Dispersão:* associar histogramas e boxplots das Vilas às suas respectivas medidas ($\bar{x}$ vs $Md$, $\text{IIQ}$ vs $s$, $g_1$, $g_2$) ($+30$ moedas).
4. *Oficina do Gráfico Perfeito:* identificar erros em gráficos enganosos (eixo truncado, gráfico de setores com 15 categorias, falta de título/fonte) e escolher a visualização correta ($+25$ moedas).
5. *Missão Amostragem no Rio Doce:* dimensionar o $n$ amostral mínimo com orçamento limitado para estimar a prevalência na Vila 16 e Vila 17 dentro da margem de erro exigida ($+35$ moedas).
6. *Roleta das Distribuições:* decidir entre Binomial, Poisson e Normal e calcular a probabilidade de superlotação de leitos na Vila 01 ($+30$ moedas).
7. *Tribunal das Hipóteses (Paramétrico vs Não-Paramétrico):* analisar um conjunto de dados real da partida, testar pressupostos e executar o teste correto ($t$, ANOVA, Mann-Whitney, Kruskal-Wallis ou $\chi^2$) interpretando o $p$-valor ($+45$ moedas).
8. *Caçador de Tendências (Correlação e Regressão):* usar a equação $\hat{Y} = \hat{\beta}_0 + \hat{\beta}_1 X$ ajustada nas 20 Vilas para prever a queda na incidência caso o saneamento da Vila 19 suba de $40\%$ para $80\%$ ($+40$ moedas).
9. *Auditoria de IA em Saúde:* revisar um parecer gerado por IA com falhas metodológicas, apontar o viés e validar o modelo preditivo ($+50$ moedas).

### 5.3 Eventos Pop-Up de "Leitura Crítica de Artigos Científicos" (`JournalClubEvent.gd`)
A cada $4$ Semanas Epidemiológicas (ou sob demanda na *"Revista Científica do Vale"*), surge um boletim trazendo um **Resumo Estruturado de Artigo Científico** contextualizado no agravo ativo (contendo Objetivo, Desenho, $n$, Tabela de Resultados com Médias/Medianas, $\text{OR}$ ou $\text{RR}$, $\text{IC}_{95\%}$ e valores de $p$).
- Exemplo de perguntas críticas exigidas do aluno:
  - *"O $\text{OR} = 2.45$ ($\text{IC}_{95\%}: 0.88 \text{ a } 5.12$; $p = 0.09$) para exposição na Vila 18 indica associação estatisticamente significativa ao nível de $5\%$? Por quê?"*
  - *"Os autores usaram teste $t$ de Student para comparar renda familiar ($g_1 = 2.84$, fortemente assimétrica) em $n = 12$ moradores. Qual crítica metodológica você faria?"*
- Acertos concedem **Bolsas de Pesquisa Fapemig/CNPq Lúdicas** ($+80$ BioMoedas) e incrementam o **Multiplicador Científico** da nota final!

---

## 6. Cálculo do Escore Global de Saúde e Integração Acadêmica com o SIGA

### 6.1 Escore Global de Saúde do Mundo ($E_{\text{saúde}} \in [0, 100]$)
Calculado continuamente e consolidado ao encerrar a simulação semestral (`ScoreCalculator.gd`), combinando 4 dimensões epidemiológicas e sanitárias ponderadas pelas 20 Vilas:

$$E_{\text{saúde}} = 0.35 \cdot I_{\text{controle}} + 0.25 \cdot I_{\text{sobrevida}} + 0.25 \cdot I_{\text{infra}} + 0.15 \cdot I_{\text{equidade}}$$

Onde cada subíndice varia em $[0, 100]$:
1. **Controle Epidemiológico ($I_{\text{controle}}$):** função decrescente da prevalência média ponderada $\overline{\text{Prev}}$:
   $$I_{\text{controle}} = 100 \cdot \exp(-0.18 \cdot \overline{\text{Prev}}\%)$$
2. **Sobrevida e Baixa Letalidade ($I_{\text{sobrevida}}$):** penaliza mortalidade evitável pela doença ($\overline{\text{TM}}$ por $1.000$ hab.):
   $$I_{\text{sobrevida}} = \max\big(0, \; 100 - 8.0 \cdot \overline{\text{TM}}\big)$$
3. **Cobertura Vacinal e Sanitária ($I_{\text{infra}}$):** média ponderada entre cobertura vacinal global ($\overline{\text{Vac}}\%$), saneamento médio ($\overline{\text{San}}\%$) e cobertura hospitalar ($\overline{\text{Hosp}}\%$):
   $$I_{\text{infra}} = 0.45 \cdot \overline{\text{Vac}}\% + 0.35 \cdot \overline{\text{San}}\% + 0.20 \cdot \overline{\text{Hosp}}\%$$
4. **Índice de Equidade Territorial ($I_{\text{equidade}}$):** impede que o jogador cuide apenas das Vilas centrais/ricas (como Vilas 01, 06, 07) e abandone as Vilas periféricas/rurais (como Vilas 11, 17, 18, 19, 20). É medido penalizando o desvio-padrão $\sigma_{\text{saúde\_vilas}}$ dos escores individuais das 20 Vilas:
   $$I_{\text{equidade}} = \max\big(0, \; 100 - 3.5 \cdot \sigma_{\text{saúde\_vilas}}\big)$$

### 6.2 Conversão Parametrizável para Pontos de Participação no SIGA (`SigaExporter.gd`)
Na tela de **Configurações do Docente / Fechamento Semestral**, o professor define a pontuação máxima de participação da disciplina no SIGA ($P_{\text{max}}$, padrão configurável, ex.: $2.0$, $3.0$ ou $10.0$ pontos), além da identificação do estudante (Nome Completo e Matrícula).

A conversão incorpora engajamento pedagógico, domínio estatístico e bônus de leitura crítica/IA, respeitando o teto $P_{\text{max}}$:

$$M_{\text{bonus}} = 1.0 + 0.10 \cdot \left(\frac{A_{\text{artigos}}}{A_{\text{total}}}\right) + 0.10 \cdot \left(\frac{C_{\text{IA}}}{C_{\text{IA\_total}}}\right)$$

$$E_{\text{efetivo}} = \min\Big(100.0, \; \big(0.70 \cdot E_{\text{saúde}} + 0.30 \cdot A_{\text{bioestat}}\big) \cdot M_{\text{bonus}}\Big)$$

$$\text{Nota}_{\text{SIGA}} = \text{round}\left( \left(\frac{E_{\text{efetivo}}}{100.0}\right) \cdot P_{\text{max}}, \; 2 \right)$$

Onde:
- $E_{\text{saúde}} \in [0, 100]$: Escore Global de Saúde das 20 Vilas ao final da simulação.
- $A_{\text{bioestat}} \in [0, 100]$: Taxa de aproveitamento e precisão nos minigames e análises dos 9 tópicos curriculares (funciona também como piso justo de participação caso um evento estocástico severo afete temporariamente uma Vila).
- $A_{\text{artigos}} / A_{\text{total}}$: Proporção de desafios de Leitura Crítica de Artigos concluídos com êxito.
- $C_{\text{IA}} / C_{\text{IA\_total}}$: Proporção de auditorias do módulo de Uso Consciente de IA concluídas com êxito.

#### Relatório Verificável de Entrega para Lançamento no SIGA:
Ao clicar em **"Encerrar Semestre e Gerar Comprovante SIGA"**, o jogo exporta na pasta `exports/` três arquivos vinculados:
1. `relatorio_siga_<matricula>.json`: log completo das decisões epidemiológicas, amostras coletadas, testes executados, $E_{\text{saúde}}$, $A_{\text{bioestat}}$, $\text{Nota}_{\text{SIGA}}$ e um **Hash de Integridade SHA-256** (`HashingContext.HASH_SHA256` nativo do Godot 4 combinando os indicadores + *salt* institucional) para impedir adulteração manual pelo aluno.
2. `boletim_siga_<matricula>.html`: relatório visual limpo e imprimível em PDF com gráficos resumo da evolução das 20 Vilas e quadro consolidado da nota SIGA.
3. `consolidado_turma_siga.csv` (modo utilitário para o professor importar múltiplos `.json` de alunos e gerar uma planilha única com colunas `Matricula;Nome;Escore_Saude;Acuracia_Bioestat;Bonus_Artigos_IA;Nota_SIGA`).

---

## 7. Arquitetura de Software no Godot 4.x (Estrutura de Pastas e Cenas)

O DSH deve criar um projeto Godot 4.x válido (`project.godot` configurado em resolução base $1600 \times 900$, modo `canvas_items` stretch, filtro de textura padrão `Nearest` para nitidez absoluta da *pixel art*: `rendering/textures/canvas_textures/default_texture_filter=0`).

```text
/home/marcio/Documentos/deepseek-harness/default-workspace/statown/
├── project.godot
├── assets/
│   ├── [arquivos compactados originais preservados]
│   └── extracted/                  # Gerado pelo script de pré-processamento do DSH
├── tools/
│   ├── prepare_assets_and_map.py   # Extrai zips, rasteriza PDF, gera máscaras JSON das 20 Vilas
│   └── generated_map_data.json     # Polígonos, Rio Doce, rodovias, pontes, túneis e sementes
├── data/
│   ├── vilas_config.json           # Parâmetros iniciais das 20 Vilas
│   ├── diseases_config.json        # Parâmetros das 4 doenças/agravos
│   ├── questions_bank.json         # Templates parametrizados dos 9 minigames
│   └── scientific_articles.json    # Artigos fictícios/adaptados para leitura crítica
├── scenes/
│   ├── Main.tscn                   # Cena raiz integrando WorldMap + HUD + Modals
│   ├── world/
│   │   ├── WorldMap.tscn           # TileMapLayers (Terreno, Água/RioDoce, Estradas, Cercas/Muros, Prédios, Natureza)
│   │   ├── VilaZoneInteractive.tscn# Area2D + Polygon2D de contorno + Label flutuante + Clique
│   │   └── DynamicEntities.tscn    # Veículos, Barcos no Rio Doce e Cidadãos animados
│   └── ui/
│       ├── MainHUD.tscn            # Relógio SE, BioMoedas, Escore Global 0-100, Seletor de Doença
│       ├── VilaInspectorPopup.tscn # Estatísticas rápidas da Vila clicada + botões de intervenção
│       ├── BioStatWorkbench.tscn   # Janela em abas (Amostragem, Banco Dados, Descritiva/Gráficos, Testes, Regressão/IA)
│       ├── MinigameModal.tscn      # Interface gamificada dos 9 tópicos curriculares
│       ├── JournalClubModal.tscn   # Pop-up de Leitura Crítica de Artigos Científicos
│       ├── DrBayesChatModal.tscn   # Assistente de IA Consciente + Gerador de Código R/Python
│       └── SigaReportModal.tscn    # Conversor de Nota SIGA e Exportador Auditável
├── scripts/
│   ├── autoload/
│   │   ├── GameState.gd            # Singleton global (tempo, moedas, doença ativa, configurações SIGA)
│   │   ├── PopulationManager.gd    # Microdados individuais das 20 Vilas + natalidade/mortalidade
│   │   ├── EpidemicManager.gd      # Motor SEIR espacial + matriz de mobilidade pelas pontes
│   │   └── AssetRegistry.gd        # Mapeamento inteligente de AtlasTextures extraídas
│   ├── world/
│   │   ├── ProceduralGVBuilder.gd  # Constrói Rio Doce, 20 Vilas, cercas/muros, Ibituruna, pontes, túneis
│   │   ├── ZoneBoundaryRenderer.gd # Desenha cercas, muros, córregos e highlight interativo
│   │   └── LivingTrafficSim.gd     # Movimenta carros, caminhões, barcos e cidadãos em tempo real
│   ├── stats/
│   │   ├── StatCore.gd             # Biblioteca matemática pura (descritiva, g1, g2, t, ANOVA, MW, KW, Chi2, Regressão)
│   │   ├── SamplingEngine.gd       # AAS, Sistemática, Estratificada, Conglomerados + Cálculo Amostral
│   │   └── SimpleMLEngine.gd       # Regressão Logística / Árvore rasa + Matriz de Confusão e ROC
│   └── ui/
│       ├── StatChartCanvas.gd      # Plotagem vetorial customizada (Histograma, Boxplot, Scatter, Curva Epidêmica)
│       ├── TableFormatter.gd       # Renderizador de tabelas científicas padrão ABNT/IBGE
│       └── SigaExporter.gd         # Cálculo da Nota SIGA + SHA-256 + JSON/HTML/CSV
├── exports/                        # Destino de bancos .csv, scripts .R/.py e relatórios SIGA
└── tests/
    └── headless_validation.gd      # Suite de testes automatizados via CLI (`godot --headless -s`)
```

---

## 8. Regras Criativas de Montagem Procedural das Vilas (`ProceduralGVBuilder.gd`)

Para garantir que o mapa fique visualmente rico, encantador e fiel aos exemplos dos *spritesheets*, o script `ProceduralGVBuilder.gd` deve obedecer às seguintes heurísticas estéticas:
1. **Camadas de TileMap (`TileMapLayer` empilhadas em ordem Z):**
   - `Layer0_Ground`: grama base variada (misturando $75\%$ grama lisa, $18\%$ grama com tufos sutis e $7\%$ flores amarelas nas áreas arborizadas/parques como a Vila 07), manchas de terra batida nas zonas rurais/industriais (Vilas 11, 16, 17, 18, 19).
   - `Layer1_Water`: calha larga do Rio Doce com bordas de margem autotiled (*bitmask* correta de costa superior, inferior, lateral e cantos internos/externos), corredeiras na saída leste (Vila 20) e córregos estreitos nas divisas de zonas.
   - `Layer2_RoadsAndPaths`: malha arterial de rodovias asfaltadas de pista dupla interligando todas as 20 Vilas, cruzando o Rio Doce sobre *tiles* de ponte, complementada por ruas internas de pedra (*cobblestone*) nas vilas residenciais e estradas de terra nas vilas rurais.
   - `Layer3_Boundaries`: aplicação contínua ao longo do perímetro poligonal de cada Vila usando cercas de madeira, muralhas de pedra com portões nos cruzamentos viários, cinturões densos de árvores ou cadeias rochosas.
   - `Layer4_BuildingsAndProps`: posicionamento sem sobreposição (*collision mask* de ocupação na grade) de:
     - **Centros Urbanos (Vilas 01, 05, 06, 08, 09):** edifícios altos multi-pavimentos, sedes administrativas, bandeiras e semáforos/cruzamentos.
     - **Bairros Residenciais e Ilha (Vilas 04, 07, 10, 14):** composição harmoniosa de casas com telhados cerâmicos vermelhos e ardósia cinza, jardins cercados, árvores intercaladas.
     - **Eixos Industriais e Logísticos (Vilas 16, 12, 02, 13):** fábricas de telhado serrilhado (*sawtooth*), depósitos, pátios pavimentados, caminhões estacionados.
     - **Zonas Rurais e Sopé de Montanha (Vilas 11, 15, 17, 18, 19, 20):** cabanas rústicas, cercados com carroças e colmeias, poços d'água, placas de madeira, pomares de árvores verdes e amarelas e encostas montanhosas com bocas de túneis.

---

## 9. Plano de Execução Sequencial e Validação para o DeepSeek Harness

O DSH deve seguir estritamente estas **6 Etapas de Construção** e validar cada uma antes de prosseguir:

1. **Etapa 1 — Descoberta, Extração e Geometria Cartográfica:**
   - Executar script Python em `tools/prepare_assets_and_map.py` para descompactar `/assets`, inspecionar todos os PNGs, processar o mapa de zoneamento na raiz `/statown` e gerar `generated_map_data.json` com a malha exata do Rio Doce (incluindo a ilha da Vila 07) e os polígonos das 20 Vilas.
2. **Etapa 2 — Biblioteca Matemática e Bioestatística (`StatCore.gd` + Testes Unitários):**
   - Implementar todas as funções estatísticas descritivas, distribuições (Binomial, Poisson, Normal), amostragem, testes paramétricos ($t$, ANOVA), não-paramétricos (Mann-Whitney, Kruskal-Wallis, $\chi^2$, Fisher), correlação/regressão e ML básico.
   - Rodar `godot --headless -s tests/headless_validation.gd` comparando resultados com gabaritos analíticos conhecidos (tolerância $< 10^{-4}$).
3. **Etapa 3 — Motor Demográfico, Microdados e Epidemiologia Multi-Doenças:**
   - Implementar `PopulationManager.gd` e `EpidemicManager.gd` com as 20 Vilas, natalidade, envelhecimento, mortalidade, mobilidade pelas pontes e impacto direto de Vacinação, Saneamento e Hospitais. Validar ausência de valores `NaN` ou populações negativas após $104$ Semanas Epidemiológicas simuladas em modo *headless*.
4. **Etapa 4 — Construção Visual Criativa do Mundo e Entidades Vivas:**
   - Implementar `ProceduralGVBuilder.gd`, `AssetRegistry.gd` e `LivingTrafficSim.gd`. Garantir que todas as 20 Vilas sejam clicáveis (`Area2D` poligonal precisa), tenham fronteiras físicas nítidas (cercas, muros, córregos, florestas, montanhas), pontes funcionais sobre o Rio Doce e túneis nas serras.
5. **Etapa 5 — Interface Analítica (`BioStatWorkbench`), Gráficos Vetoriais e Gamificação:**
   - Construir `StatChartCanvas.gd`, editor de variáveis/exportação CSV, painel de intervenções por Vila, os 9 minigames curriculares, eventos de Leitura Crítica de Artigos e o tutor de IA consciente ("Dr. Bayes") com gerador de scripts R/Python.
6. **Etapa 6 — Escore Global de Saúde, Conversor SIGA e Polimento Final:**
   - Integrar `SigaExporter.gd` (com fórmula de nota configurável e hash SHA-256), testar o fluxo completo de uma partida do início ao relatório final e assegurar 60 FPS estáveis e zero erros de compilação/execução no log do Godot 4.