extends Node
## RoadMask - mascara binaria das rodovias desenhadas no mapa.
##
## A imagem anexada pelo autor (road_mask.png) e a fonte de verdade. A versao
## road_nav_mask.png e essa mesma malha com fechamento de 1 px para reconectar
## microfuros de antialias; o A* gera as rotas nela e o motor consulta a mesma
## mascara em tempo de execucao para nao deixar um veiculo entrar em quadra.
## A consulta custa um get_pixel por veiculo por frame; e barata para o numero
## pequeno de carros do mapa e evita depender de colisao fisica.

const CAMINHO := "res://assets/art/road_nav_mask.png"
const MUNDO := Vector2(3840.0, 2880.0)
const LIMIAR := 0.50

var _imagem: Image
var _largura := 0
var _altura := 0
var disponivel := false


func _ready() -> void:
	var textura: Texture2D = load(CAMINHO) as Texture2D
	if textura == null:
		push_warning("RoadMask: textura ausente " + CAMINHO)
		return
	_imagem = textura.get_image()
	if _imagem == null:
		push_warning("RoadMask: imagem vazia " + CAMINHO)
		return
	_imagem.convert(Image.FORMAT_L8)
	_largura = _imagem.get_width()
	_altura = _imagem.get_height()
	disponivel = _largura > 0 and _altura > 0


func ponto_em_estrada(pos_mundo: Vector2, raio: float = 0.0) -> bool:
	if not disponivel:
		return true  # falha aberta: nunca paralisa o jogo por falta da mascara
	if raio <= 0.0:
		return _ponto_em_estrada(pos_mundo)
	# Pequena cruz: cobre o offset de faixa sem aceitar um quarteirao inteiro.
	return (_ponto_em_estrada(pos_mundo)
		or _ponto_em_estrada(pos_mundo + Vector2(raio, 0.0))
		or _ponto_em_estrada(pos_mundo + Vector2(-raio, 0.0))
		or _ponto_em_estrada(pos_mundo + Vector2(0.0, raio))
		or _ponto_em_estrada(pos_mundo + Vector2(0.0, -raio)))


func ponto_em_estrada_tile(tx: float, ty: float) -> bool:
	return ponto_em_estrada(Vector2(tx, ty) * 16.0)


## Usado pelo WorldView antes de aceitar uma rota. Recebe pontos em PIXELS do
## mundo (nao em tiles). Amostra o segmento em passos de 6 px e tolera ate 4%
## de amostras na borda antialias da linha.
func rota_valida(pontos_mundo: PackedVector2Array) -> bool:
	if not disponivel or pontos_mundo.size() < 2:
		return true
	var total := 0
	var fora := 0
	for i in range(pontos_mundo.size() - 1):
		var a := pontos_mundo[i]
		var b := pontos_mundo[i + 1]
		var passos := maxi(2, int(a.distance_to(b) / 6.0))
		for k in range(passos + 1):
			total += 1
			if not _ponto_em_estrada(a.lerp(b, float(k) / float(passos))):
				fora += 1
	if total == 0:
		return true
	return float(fora) / float(total) <= 0.04


## Menor ajuste para o pixel de estrada mais proximo. So e chamado quando o
## centro do veiculo caiu na borda; o deslocamento maximo e de 3 px de mascara
## (~11 px de mundo), pequeno o bastante para nao "teleportar" o carro.
func ajustar_para_estrada(pos_mundo: Vector2) -> Vector2:
	if not disponivel or _ponto_em_estrada(pos_mundo):
		return pos_mundo
	var bx := clampi(int(round(pos_mundo.x / MUNDO.x * float(_largura))), 0, _largura - 1)
	var by := clampi(int(round(pos_mundo.y / MUNDO.y * float(_altura))), 0, _altura - 1)
	var melhor := pos_mundo
	var melhor_d := INF
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if dx == 0 and dy == 0:
				continue
			var x := bx + dx
			var y := by + dy
			if x < 0 or y < 0 or x >= _largura or y >= _altura:
				continue
			if _imagem.get_pixel(x, y).r < LIMIAR:
				continue
			var d := float(dx * dx + dy * dy)
			if d < melhor_d:
				melhor_d = d
				melhor = Vector2(
					(float(x) + 0.5) / float(_largura) * MUNDO.x,
					(float(y) + 0.5) / float(_altura) * MUNDO.y)
	return melhor


func _ponto_em_estrada(pos_mundo: Vector2) -> bool:
	if not disponivel:
		return true
	var x := clampi(int(round(pos_mundo.x / MUNDO.x * float(_largura))), 0, _largura - 1)
	var y := clampi(int(round(pos_mundo.y / MUNDO.y * float(_altura))), 0, _altura - 1)
	return _imagem.get_pixel(x, y).r >= LIMIAR
