# Créditos e licenças — arte de veículos e voo livre

Este documento cobre apenas os sprites de **carros, caminhões, asas-deltas e parapentes**.
Mapa, fontes e áudio têm créditos próprios em `README.md` e `docs/CREDITOS_AUDIO.md`.

## O que veio de onde

| Recurso no jogo | Origem | Situação da licença |
|---|---|---|
| `assets/art/vehicles/pixel_cars.png` | Folha **Pixel Cars - PNG**, enviada pelo autor do projeto nesta conversa (7 PNGs, incluindo `AllColors.png`) | O ZIP não traz `LICENSE`/`README`; uso no projeto autorizado pelo envio. Confirmar os termos com o autor antes de redistribuir o sprite isoladamente ou de publicar comercialmente. |
| `assets/art/gliders/paraglider_sheet.png` | Imagem **“parapente fundo transparente”**, 1361×761, enviada pelo autor do projeto; organizada em 4 colunas × 3 linhas (3 cores × 4 poses) | O arquivo não declara autor nem licença. Uso no projeto autorizado pelo envio; confirmar a origem antes de redistribuir. |
| `assets/art/gliders/asa_delta_*.png` | Arte anterior do projeto | Mantida como estava; ver histórico do projeto. |
| `assets/art/road_mask.png` | Malha viária enviada pelo autor | Referência visual do projeto; ver abaixo a versão derivada. |

Os arquivos originais ficam em `assets/art/source/` (com `.gdignore`, fora do PCK) para
auditoria. As versões usadas no jogo são derivadas, não redimensionadas em runtime.

## Transformações feitas

1. **Carros e caminhões**: os seis PNGs por cor foram empilhados em uma folha de
   320×384 px, com 6 colunas (4 carros, 1 caminhão de caixa, 1 carreta) e 12 linhas
   (6 cores × 2 linhas de modelos). Cada célula é recortada no conteúdo útil e
   carregada por `AtlasTexture` em runtime; são 48 carros e 24 caminhões. Todas as
   células têm o nariz para a direita; para andar no sentido contrário o jogo usa
   `flip_h` e compensa o giro com `-PI`, sem trocar de modelo.
2. **Parapentes**: a imagem 4×3 foi recortada em 12 células (3 cores × 4 poses) e
   carregada por caminhos explícitos. A cada partida o `WorldView` sorteia 4 células
   distintas, com pelo menos três cores.
3. **Malha viária**: `road_nav_mask.png` é uma cópia binária da máscara original com
   fechamento morfológico de 1 px. Ela só reconecta microfuros de antialias para o A*
   e para a validação de rota; a máscara visual original não foi alterada.

## Pendência antes de publicação comercial

O envio dos arquivos pelo autor é suficiente para o uso neste projeto, mas não
substitui uma licença formal. Antes de vender o jogo ou redistribuir a arte em outro
produto, peça ao autor a licença por escrito (nome do artista, URL de origem e termos).
Se a licença não for confirmada, a alternativa segura é substituir por arte CC0/MIT
compatível com o estilo pixel art.
