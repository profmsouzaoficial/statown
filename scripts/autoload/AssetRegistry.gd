extends Node
## AssetRegistry - acesso centralizado aos sprites do jogo.
##
## Carrega uma vez os PNGs de assets/art/sprites e os chunkes do mapa-mundi,
## oferecendo nomes estaveis para o resto do codigo. Nunca acesse caminhos de
## arquivo diretamente nos paineis: peca ao Assets.

const DIR_SPRITES := "res://assets/art/sprites/"
const DIR_VEICULOS := "res://assets/art/vehicles/"
const DIR_ASAS := "res://assets/art/gliders/"
const DIR_MUNDO := "res://assets/art/world/"
const DIR_DECOR := "res://assets/art/decor/"
const DECOR_MESTRE := "res://assets/art/decor.png"
const CHUNKS_X := 4
const CHUNKS_Y := 4

# Listas explicitas: DirAccess.get_files_at() nao lista os recursos remapeados
# dentro do PCK web, entao carros, barcos e planadores sumiam no navegador.
const NOMES_VEICULOS := [
	"boat_dinghy_large.png", "boat_dinghy_small.png",
	"car_black_1.png", "car_black_2.png", "car_black_3.png", "car_black_4.png", "car_black_5.png",
	"car_blue_1.png", "car_blue_2.png", "car_blue_3.png", "car_blue_4.png", "car_blue_5.png",
	"car_green_1.png", "car_green_2.png", "car_green_3.png", "car_green_4.png", "car_green_5.png",
	"car_red_1.png", "car_red_2.png", "car_red_3.png", "car_red_4.png", "car_red_5.png",
	"car_yellow_1.png", "car_yellow_2.png", "car_yellow_3.png", "car_yellow_4.png", "car_yellow_5.png",
	"moto_black.png", "moto_blue.png", "moto_green.png", "moto_red.png", "moto_yellow.png",
	"ship_1.png", "ship_19.png",
]
const NOMES_ASAS := [
	"delta_azul.png", "delta_vermelho.png", "delta_verde.png",
	"delta_laranja.png", "delta_roxo.png",
	"parapente_vermelho.png", "parapente_azul.png", "parapente_amarelo.png",
]
const NOMES_DELTAS := [
	"delta_azul.png", "delta_vermelho.png", "delta_verde.png",
	"delta_laranja.png", "delta_roxo.png",
]
# Sprites novas do pacote "Pixel Cars - PNG": uma unica folha com 6 cores,
# 2 linhas de modelos e 6 modelos por linha (4 carros + caminhao de caixa +
# carreta). Todas as celulas olham para a direita; o trafego usa flip_h para
# seguir no sentido contrario. O caminho fica explicito para o PCK web, onde
# DirAccess nao enumera recursos.
const PIXEL_CARS := "res://assets/art/vehicles/pixel_cars.png"
const PIXEL_CORES := ["azul", "vermelho", "verde", "laranja", "azul_escuro", "outros"]
const PIXEL_X := [0, 48, 96, 144, 192, 240]
const PIXEL_LARGURAS := [48, 48, 48, 48, 48, 80]
const PIXEL_ALTURA := 32
const PIXEL_ROWS := 2
const PARAPENTE_SHEET := "res://assets/art/gliders/paraglider_sheet.png"
const PARAPENTE_CORES := ["vermelho", "azul", "amarelo"]
const PARAPENTE_X := [0, 340, 680, 1020, 1361]
const PARAPENTE_Y := [0, 254, 508, 761]
# Os caminhoes antigos usam 8 quadros direcionais. Mantidos como fallback
# historico; o trafego novo usa carros_pixel/caminhoes_pixel.
const CORES_CAMINHAO := ["vermelho", "amarelo", "azul", "verde", "marrom"]
const QUADROS_CAMINHAO := 8

var sprites: Dictionary = {}
# Veiculos vetoriais reduzidos para a escala do tile (11 px de largura nos
# carros). Ficam em assets/art/vehicles/ e nao em Vehicles/, que e a origem
# 71x131 usada apenas para gerar a versao pixelizada.
var carros: Array[Texture2D] = []
var motos: Array[Texture2D] = []
var barcos: Array[Texture2D] = []
var navios: Array[Texture2D] = []
var asas: Array[Texture2D] = []
var deltas: Array[Texture2D] = []
var caminhoes: Array = []       # [cor][quadro] -> Texture2D
# Listas novas do pacote Pixel Cars: cada item guarda uma textura (ja recortada
# no conteudo util), a cor/modelo e a escala ideal para o tile de 16 px. A
# direcao nao troca a textura: o mesmo veiculo e espelhado com flip_h.
var carros_pixel: Array = []
var caminhoes_pixel: Array = []
# Parapentes recortados da folha nova: 3 cores x 4 poses.
var parapentes: Array = []
var chunks: Array = []          # [cy][cx] -> Texture2D
var decor_chunks: Array = []    # [cy][cx] -> Texture2D ou null
var decor_mestre: Texture2D     # usado quando a arte ainda nao foi fatiada
var mini_mapa: Texture2D
var fonte_corpo: Font
var tema: Theme


func _ready() -> void:
	_carregar_sprites()
	_carregar_veiculos()
	_carregar_caminhoes()
	_carregar_pixel_cars()
	_carregar_asas()
	_carregar_chunks()
	_carregar_decor()


func _carregar_veiculos() -> void:
	carros.clear()
	motos.clear()
	barcos.clear()
	navios.clear()
	for nome in NOMES_VEICULOS:
		var tex: Texture2D = load(DIR_VEICULOS + nome)
		if tex == null:
			continue
		if nome.begins_with("car_"):
			carros.append(tex)
		elif nome.begins_with("moto_"):
			motos.append(tex)
		elif nome.begins_with("ship_"):
			navios.append(tex)
		elif nome.begins_with("boat_"):
			barcos.append(tex)


func _carregar_pixel_cars() -> void:
	carros_pixel.clear()
	caminhoes_pixel.clear()
	var folha: Texture2D = load(PIXEL_CARS) as Texture2D
	if folha == null:
		push_warning("Assets: atlas Pixel Cars ausente " + PIXEL_CARS)
		return
	# A folha tem margens transparentes diferentes por modelo (a carreta de
	# baixo e bem mais curta que a de cima, por exemplo). Recortar cada celula
	# no conteudo util centraliza o desenho no Sprite2D e evita que o veiculo
	# pareca deslocado da pista ao ser rotacionado/espelhado.
	var imagem: Image = folha.get_image()
	var recortar := imagem != null and not imagem.is_empty()
	for cor_i in range(PIXEL_CORES.size()):
		for linha in range(PIXEL_ROWS):
			var base_y := cor_i * PIXEL_ROWS * PIXEL_ALTURA + linha * PIXEL_ALTURA
			for col in range(PIXEL_X.size()):
				var regiao := Rect2(float(PIXEL_X[col]), float(base_y),
					float(PIXEL_LARGURAS[col]), float(PIXEL_ALTURA))
				if recortar:
					var celula := imagem.get_region(Rect2i(
						PIXEL_X[col], base_y, PIXEL_LARGURAS[col], PIXEL_ALTURA))
					var usado := celula.get_used_rect()
					if usado.size.x > 0 and usado.size.y > 0:
						regiao = Rect2(
							float(PIXEL_X[col] + usado.position.x),
							float(base_y + usado.position.y),
							float(usado.size.x), float(usado.size.y))
				var textura := AtlasTexture.new()
				textura.atlas = folha
				textura.region = regiao
				textura.filter_clip = true
				var item := {
					"textura": textura, "cor": PIXEL_CORES[cor_i],
					"modelo": col, "linha": linha, "escala": 0.62,
				}
				if col <= 3:
					carros_pixel.append(item)
				else:
					# Caixa (col 4) e carreta (col 5) sao mais longas: escala menor
					# para o caminhao de caixa medir ~15 px e a carreta ~24 px sem invadir a calcada.
					item["escala"] = 0.55 if col == 4 else 0.40
					caminhoes_pixel.append(item)
	# O sorteio de cor/modelo acontece no trafego; manter uma lista estavel evita
	# que o mesmo carro mude de cor no meio da animacao.


func _carregar_caminhoes() -> void:
	caminhoes.clear()
	for cor in CORES_CAMINHAO:
		var quadros: Array[Texture2D] = []
		for i in range(QUADROS_CAMINHAO):
			var tex: Texture2D = load("%struck_%s_%d.png" % [DIR_VEICULOS, cor, i]) as Texture2D
			if tex != null:
				quadros.append(tex)
		if quadros.size() == QUADROS_CAMINHAO:
			caminhoes.append(quadros)
		else:
			push_warning("Assets: caminhao incompleto " + str(cor))


func _carregar_sprites() -> void:
	var nomes := ["carro_a", "carro_b", "caminhao_a", "caminhao_b", "van",
		"pessoa_f1", "pessoa_m1", "pessoa_f2", "pessoa_m2",
		"arvore_ouro", "arvore_verde", "arvore_peq", "planta", "banco", "cerca",
		"lampada", "placa", "icone_chat", "pedra", "hospital", "ubs", "moeda",
		"hospital_regional", "hospital_geral", "clinica", "upa", "hospital_campanha",
		"icone_mosquito", "icone_virus", "icone_gota", "icone_coracao"]
	for n in nomes:
		var caminho: String = DIR_SPRITES + str(n) + ".png"
		if ResourceLoader.exists(caminho):
			sprites[n] = load(caminho)
		else:
			push_warning("Assets: sprite ausente " + caminho)


func _carregar_asas() -> void:
	asas.clear()
	deltas.clear()
	parapentes.clear()
	for nome in NOMES_ASAS:
		var tex: Texture2D = load(DIR_ASAS + nome)
		if tex != null:
			asas.append(tex)
		else:
			push_warning("Assets: asa ausente " + DIR_ASAS + nome)
	for nome in NOMES_DELTAS:
		var tex_d: Texture2D = load(DIR_ASAS + nome)
		if tex_d != null:
			deltas.append(tex_d)
	var folha_pg: Texture2D = load(PARAPENTE_SHEET) as Texture2D
	if folha_pg == null:
		push_warning("Assets: folha de parapentes ausente " + PARAPENTE_SHEET)
		return
	for linha in range(PARAPENTE_CORES.size()):
		for col in range(4):
			var reg := Rect2(
				float(PARAPENTE_X[col]), float(PARAPENTE_Y[linha]),
				float(PARAPENTE_X[col + 1] - PARAPENTE_X[col]),
				float(PARAPENTE_Y[linha + 1] - PARAPENTE_Y[linha]))
			var at := AtlasTexture.new()
			at.atlas = folha_pg
			at.region = reg
			at.filter_clip = true
			parapentes.append({
				"textura": at, "cor": PARAPENTE_CORES[linha], "quadro": col,
			})


func _carregar_chunks() -> void:
	chunks = []
	for cy in range(CHUNKS_Y):
		var linha: Array = []
		for cx in range(CHUNKS_X):
			var caminho := "%schunk_%d_%d.png" % [DIR_MUNDO, cx, cy]
			linha.append(load(caminho) if ResourceLoader.exists(caminho) else null)
		chunks.append(linha)
	if ResourceLoader.exists("res://assets/art/world_mini.png"):
		mini_mapa = load("res://assets/art/world_mini.png")


## Camada de decoracao pintada a mao (assets/art/decor.png).
##
## Dois modos, escolhidos em tempo de carga:
##   - chunkes (assets/art/decor/chunk_*.png): memoria igual a de uma camada so,
##     e o modo que vai para o build web/celular;
##   - mestre inteiro (decor.png): pratico no editor antes de fatiar, pesado.
## Um mestre mais novo que os chunkes significa edicao sem split: nesse caso o
## mestre vence, para a arte recem-pintada aparecer de imediato no editor.
func _carregar_decor() -> void:
	decor_chunks = []
	decor_mestre = null
	var nomes := _arquivos_decor()
	var tem_mestre := ResourceLoader.exists(DECOR_MESTRE)
	var usar_mestre := tem_mestre and nomes.is_empty()
	if tem_mestre and not nomes.is_empty() and OS.has_feature("editor"):
		usar_mestre = FileAccess.get_modified_time(DECOR_MESTRE) > _mtime_mais_novo(nomes)
	if not usar_mestre and not nomes.is_empty():
		for cy in range(CHUNKS_Y):
			var linha: Array = []
			for cx in range(CHUNKS_X):
				var caminho := "%schunk_%d_%d.png" % [DIR_DECOR, cx, cy]
				linha.append(load(caminho) if ResourceLoader.exists(caminho) else null)
			decor_chunks.append(linha)
		return
	if not usar_mestre:
		return
	var tex: Texture2D = load(DECOR_MESTRE)
	if tex == null:
		return
	var img := tex.get_image()
	if img != null and img.is_invisible():
		return  # molde em branco (nada pintado ainda): nao gasta memoria
	decor_mestre = tex


func _arquivos_decor() -> PackedStringArray:
	var out := PackedStringArray()
	if DirAccess.open(DIR_DECOR) == null:
		return out
	for n in DirAccess.get_files_at(DIR_DECOR):
		if n.begins_with("chunk_") and n.ends_with(".png"):
			out.append(n)
	return out


func _mtime_mais_novo(nomes: PackedStringArray) -> int:
	var t := 0
	for n in nomes:
		t = maxi(t, FileAccess.get_modified_time(DIR_DECOR + n))
	return t


func sprite(nome: String) -> Texture2D:
	return sprites.get(nome, null)


func chunk(cx: int, cy: int) -> Texture2D:
	if cy < 0 or cy >= chunks.size():
		return null
	var linha: Array = chunks[cy]
	if cx < 0 or cx >= linha.size():
		return null
	return linha[cx]


func decor(cx: int, cy: int) -> Texture2D:
	if decor_mestre != null:
		return decor_mestre
	if cy < 0 or cy >= decor_chunks.size():
		return null
	var linha: Array = decor_chunks[cy]
	if cx < 0 or cx >= linha.size():
		return null
	return linha[cx]


func icone_doenca(id: String) -> Texture2D:
	var mapa := {"arbovirose": "icone_mosquito", "respiratoria": "icone_virus",
		"enterica": "icone_gota", "cronica": "icone_coracao"}
	return sprite(str(mapa.get(id, "icone_virus")))


## Vetores de veiculos disponiveis (dois angulos para variar o trafego).
func veiculos() -> Array:
	return ["carro_a", "carro_b", "caminhao_a", "caminhao_b", "van"]


func pessoas() -> Array:
	return ["pessoa_f1", "pessoa_m1", "pessoa_f2", "pessoa_m2"]
