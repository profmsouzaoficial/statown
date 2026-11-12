class_name WorldView
extends Node2D
## WorldView - renderizacao do mapa-mundi vivo do Vale do Rio Doce.
##
## Camadas, de baixo para cima:
##   1. 16 chunkes de 960x720 px (mapa pixel art bakeado)  -> estatico
##   1b. camada de decoracao pintada a mao (assets/art/decor.png), opcional
##   2. overlay epidemiologico (shader de coropleta por vila)
##   3. halos pulsantes nas vilas em surto
##   4. trafego veicular, barcos e cidadaos                -> animados
##   5. rotulos das vilas (escala inversa ao zoom)


const TILE := 16
const MAPA := Vector2(3840, 2880)
const CHUNK := Vector2(960, 720)

var camera_ctrl: CameraController
var modo_overlay: String = "prevalencia"

var _chunks_root: Node2D
var _decor: Node2D
var _overlay: Sprite2D
var _overlay_mat: ShaderMaterial
var _rotulos: Node2D
var _veiculos: Node2D
var _pessoas: Node2D
var _barcos: Node2D
var _extras: Node2D
var _asas: Node2D
var _hospitais: Node2D

var _labels: Dictionary = {}          # vila_id -> Label
var _carros: Array = []               # {sprite, rota, t, vel}
var _peds: Array = []                 # {sprite, vila, fase, raio, vel}
var _barcos_dados: Array = []
var _asas_dados: Array = []
var _sombra_asa: Texture2D
var _rng_asas := RandomNumberGenerator.new()
var _tempo := 0.0
var _pulso := 0.0

var _shader_codigo := """
shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform sampler2D zona_tex : filter_nearest;
uniform vec4 cores[21];
uniform float surto[21];
uniform float pulso = 0.0;
uniform float alpha = 0.55;
uniform vec4 cor_surto : source_color = vec4(1.0, 0.36, 0.20, 1.0);
void fragment() {
	float id = floor(texture(zona_tex, UV).r * 255.0 + 0.5);
	int i = int(clamp(id, 0.0, 20.0));
	vec4 c = cores[i];
	vec4 saida = vec4(c.rgb, c.a * alpha);
	// Contorno do surto: so nas bordas da mascara da vila (nunca no rio,
	// porque a textura ja chega com a agua zerada). O retangulo do bbox
	// anterior atravessava o Rio Doce e parecia um borrao sem sentido.
	if (surto[i] > 0.5) {
		vec2 tam = vec2(textureSize(zona_tex, 0));
		vec2 px = 1.0 / tam;
		float l = floor(texture(zona_tex, UV - vec2(px.x, 0.0)).r * 255.0 + 0.5);
		float r = floor(texture(zona_tex, UV + vec2(px.x, 0.0)).r * 255.0 + 0.5);
		float u = floor(texture(zona_tex, UV - vec2(0.0, px.y)).r * 255.0 + 0.5);
		float d = floor(texture(zona_tex, UV + vec2(0.0, px.y)).r * 255.0 + 0.5);
		// posicao dentro do tile 16x16: o contorno fica com ~3 px, em vez de
		// pintar o tile inteiro de vermelho (o "bloco" que parecia vazamento)
		vec2 local = fract(UV * tam);
		bool borda =
			(l != id && local.x < 0.20) ||
			(r != id && local.x > 0.80) ||
			(u != id && local.y < 0.20) ||
			(d != id && local.y > 0.80);
		if (borda) {
			saida = vec4(cor_surto.rgb, 0.55 + 0.30 * pulso);
		}
	}
	COLOR = saida;
}
"""


func _ready() -> void:
	_chunks_root = Node2D.new()
	_chunks_root.name = "Chunks"
	add_child(_chunks_root)
	_montar_chunks()
	# Depois dos chunkes para desenhar por cima deles, antes do overlay e das
	# animacoes (que tem z_index proprio).
	_decor = Node2D.new()
	_decor.name = "Decor"
	add_child(_decor)
	_montar_decor()
	_montar_overlay()
	_extras = Node2D.new()
	_extras.name = "Extras"
	add_child(_extras)
	_hospitais = Node2D.new()
	_hospitais.name = "Hospitais"
	add_child(_hospitais)
	_veiculos = Node2D.new()
	_veiculos.name = "Veiculos"
	add_child(_veiculos)
	_barcos = Node2D.new()
	_barcos.name = "Barcos"
	add_child(_barcos)
	_pessoas = Node2D.new()
	_pessoas.name = "Pessoas"
	add_child(_pessoas)
	_rotulos = Node2D.new()
	_rotulos.name = "Rotulos"
	add_child(_rotulos)
	_montar_hospitais()
	_montar_trafego()
	_montar_barcos()
	_montar_rotulos()
	_montar_asas()
	if not GameState.partida_reiniciada.is_connected(_sortear_asas):
		GameState.partida_reiniciada.connect(_sortear_asas)
	if not Epidemic.atualizado.is_connected(_ao_atualizar_epidemia):
		Epidemic.atualizado.connect(_ao_atualizar_epidemia)
	set_process(true)


func _montar_chunks() -> void:
	for cy in range(4):
		for cx in range(4):
			var tex := Assets.chunk(cx, cy)
			if tex == null:
				continue
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.position = Vector2(cx, cy) * CHUNK
			_chunks_root.add_child(s)


## Desenha a arte pintada a mao por cima do mapa gerado. Sem arquivo, nao faz nada.
func _montar_decor() -> void:
	if Assets.decor_mestre != null:
		var m := Sprite2D.new()
		m.name = "DecorMestre"
		m.texture = Assets.decor_mestre
		m.centered = false
		_decor.add_child(m)
		return
	for cy in range(4):
		for cx in range(4):
			var tex := Assets.decor(cx, cy)
			if tex == null:
				continue
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.position = Vector2(cx, cy) * CHUNK
			_decor.add_child(s)


func _montar_overlay() -> void:
	_overlay = Sprite2D.new()
	_overlay.name = "Overlay"
	_overlay.centered = false
	_overlay.scale = Vector2(TILE, TILE)
	_overlay.z_index = 2
	var img := Image.create(Vilas.GRID_W, Vilas.GRID_H, false, Image.FORMAT_R8)
	for y in range(Vilas.GRID_H):
		for x in range(Vilas.GRID_W):
			var id := int(Vilas.zone_grid[y * Vilas.GRID_W + x])
			# agua nunca recebe cor de vila: o overlay manchava o Rio Doce
			if int(Vilas.water_grid[y * Vilas.GRID_W + x]) != 0:
				id = 0
			img.set_pixel(x, y, Color8(id, id, id, 255))
	var tex := ImageTexture.create_from_image(img)
	_overlay.texture = tex
	var sh := Shader.new()
	sh.code = _shader_codigo
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = sh
	_overlay_mat.set_shader_parameter("zona_tex", tex)
	var surto0 := PackedFloat32Array()
	surto0.resize(21)
	_overlay_mat.set_shader_parameter("surto", surto0)
	_overlay.material = _overlay_mat
	add_child(_overlay)
	_atualizar_cores_overlay()


func _montar_rotulos() -> void:
	for v in Vilas.vilas:
		var id := int(v["id"])
		var l := Label.new()
		l.text = str(v["nome"]).replace("Vila ", "")
		l.add_theme_font_override("font", UITheme.titulo_font(true))
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", UITheme.TEXTO)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# O rotulo continua sendo desenho, nao um Control que rouba o arrasto do
		# mapa. O clique nele e detectado em coordenadas de mundo por
		# vila_no_rotulo_mundo(), chamado pelo CameraController antes de
		# procurar a zona da vila. Isso conserta os rotulos de Vale Distante e
		# Nascentes sem bloquear o pan (e sem depender do content scale do web).
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.tooltip_text = "Abrir " + str(v["nome"])
		l.position = (v["anchor"] as Vector2) * TILE + Vector2(-60, -26)
		l.custom_minimum_size = Vector2(120, 22)
		l.z_index = 5
		_rotulos.add_child(l)
		_labels[id] = l


## Retorna o id da vila cujo rotulo contem o ponto de tela, ou 0.
## O Label e escalado por 1/zoom para manter o tamanho legivel; por isso a
## checagem usa a transformacao global com canvas, nao apenas position/size.
func vila_no_rotulo(pos_tela: Vector2) -> int:
	var mundo_ponto := get_viewport().get_canvas_transform().affine_inverse() * pos_tela
	return vila_no_rotulo_mundo(mundo_ponto)


## Versao em coordenadas de mundo: o navegador aplica content scale no canvas
## (1280x720 fisico -> 1600x900 logico), e comparar o evento cru com o transform
## do Label falhava no web. O CameraController ja converte o clique para mundo
## para achar a zona; usamos o mesmo ponto aqui.
func vila_no_rotulo_mundo(pos_mundo: Vector2) -> int:
	var melhor := 0
	var melhor_d := INF
	for id in _labels:
		var l: Label = _labels[id]
		if not l.visible:
			continue
		# scale = 1/zoom: o Label e ampliado em mundo para ficar do mesmo
		# tamanho na tela. O retangulo em mundo e size * scale (nao dividir).
		var esc := maxf(l.scale.x, 0.001)
		var tam := l.size * esc
		var r := Rect2(l.global_position, tam).grow(6.0 / maxf(zoom_atual(), 0.05))
		if not r.has_point(pos_mundo):
			continue
		var centro := l.global_position + tam * 0.5
		var d := pos_mundo.distance_squared_to(centro)
		if d < melhor_d:
			melhor_d = d
			melhor = int(id)
	return melhor


## Hospitais e unidades de saude ancorados nos pontos vermelhos do mapa
## satelite de referencia. Ficam na camada 2, acima da coropleta e abaixo do
## trafego (3), para nao esconder carros nem rotulos.
func _montar_hospitais() -> void:
	var unidades := [
		{"tex": "hospital_regional", "pos": Vector2(112, 58), "largura": 78.0},
		{"tex": "hospital_geral", "pos": Vector2(135, 44), "largura": 74.0},
		{"tex": "upa", "pos": Vector2(111, 34), "largura": 40.0},
		{"tex": "clinica", "pos": Vector2(108, 48), "largura": 54.0},
		{"tex": "upa", "pos": Vector2(121, 130), "largura": 40.0},
		{"tex": "clinica", "pos": Vector2(106, 150), "largura": 54.0},
		{"tex": "clinica", "pos": Vector2(56, 87), "largura": 54.0},
		{"tex": "clinica", "pos": Vector2(132, 92), "largura": 54.0},
		{"tex": "hospital_campanha", "pos": Vector2(80, 157), "largura": 58.0},
	]
	for u in unidades:
		var tex: Texture2D = Assets.sprite(str(u["tex"]))
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		var esc: float = float(u["largura"]) / maxf(float(tex.get_width()), 1.0)
		s.scale = Vector2(esc, esc)
		s.position = (u["pos"] as Vector2) * TILE
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.z_index = 2
		_hospitais.add_child(s)


func _montar_trafego() -> void:
	# As rotas longas vem de data/traffic_routes.json (A* sobre o asfalto e as
	# BRs). As antigas "roads" do mapa eram fragmentos de 5-15 tiles: nelas o
	# carro batia na ponta, invertia e voltava, o que parecia um veiculo parado
	# piscando. Agora cada carro percorre uma rota inteira, em mao unica.
	var dados := _carregar_rotas_trafego()
	var rotas_carro: Array = []
	var rotas_caminhao: Array = []
	for chave in dados.get("carros", []):
		var r: Dictionary = dados["rotas"].get(str(chave), {})
		if not r.is_empty():
			var rota_ok := _preparar_rota(r["pontos"], bool(r.get("fechada", false)))
			if not rota_ok.is_empty():
				rotas_carro.append(rota_ok)
			else:
				push_warning("WorldView: rota de carro fora da mascara: " + str(chave))
	for chave in dados.get("caminhoes", []):
		var r2: Dictionary = dados["rotas"].get(str(chave), {})
		if not r2.is_empty():
			var rota_ok2 := _preparar_rota(r2["pontos"], bool(r2.get("fechada", false)))
			if not rota_ok2.is_empty():
				rotas_caminhao.append(rota_ok2)
			else:
				push_warning("WorldView: rota de caminhao fora da mascara: " + str(chave))
	if rotas_carro.is_empty():
		# fallback defensivo: mantem o jogo rodando se o JSON nao for importado
		for frag in Vilas.roads:
			if (frag as Array).size() >= 2:
				var fallback := _preparar_rota(frag, false)
				if not fallback.is_empty():
					rotas_carro.append(fallback)
	if rotas_carro.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	# A arte nova e mais legivel que os sprites antigos: 8 carros por rota
	# (40) e 5 caminhoes por BR (15) ja enchem as vias sem parecer enxame.
	var carros_por_rota := 8
	var tem_pixel := not Assets.carros_pixel.is_empty()
	for r_idx in range(rotas_carro.size()):
		var rota: Dictionary = rotas_carro[r_idx]
		var comp := float(rota["comp"])
		for j in range(carros_por_rota):
			var s := Sprite2D.new()
			var veiculo: Dictionary = {}
			if tem_pixel:
				veiculo = Assets.carros_pixel[rng.randi_range(0, Assets.carros_pixel.size() - 1)]
				s.texture = veiculo["textura"]
				s.scale = Vector2.ONE * float(veiculo["escala"])
			elif not Assets.carros.is_empty():
				s.texture = Assets.carros[rng.randi_range(0, Assets.carros.size() - 1)]
				s.scale = Vector2.ONE
			else:
				s.texture = Assets.sprite("carro_a")
				s.scale = Vector2.ONE
			s.centered = true
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			s.z_index = 3
			_veiculos.add_child(s)
			_carros.append({
				"sprite": s, "tipo": "carro", "rota": rota, "veiculo": veiculo,
				"t": comp * (float(j) + 0.35 + rng.randf_range(-0.18, 0.18)) / float(carros_por_rota),
				"vel": rng.randf_range(62.0, 96.0),
				"comp": comp,
				"dir": 1.0 if rng.randf() < 0.5 else -1.0,
				"fade": not bool(rota["fechada"]),
			})
	var tem_caminhao_pixel := not Assets.caminhoes_pixel.is_empty()
	for r_idx in range(rotas_caminhao.size()):
		var rota2: Dictionary = rotas_caminhao[r_idx]
		var comp2 := float(rota2["comp"])
		for j in range(5):
			if not tem_caminhao_pixel:
				break
			var veic: Dictionary = Assets.caminhoes_pixel[rng.randi_range(0, Assets.caminhoes_pixel.size() - 1)]
			var s2 := Sprite2D.new()
			s2.texture = veic["textura"]
			s2.scale = Vector2.ONE * float(veic["escala"])
			s2.centered = true
			s2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			s2.z_index = 3
			_veiculos.add_child(s2)
			_carros.append({
				"sprite": s2, "tipo": "caminhao", "rota": rota2, "veiculo": veic,
				"t": comp2 * (float(j) + 0.5 + rng.randf_range(-0.25, 0.25)) / 5.0,
				"vel": rng.randf_range(78.0, 108.0),
				"comp": comp2, "dir": 1.0 if rng.randf() < 0.5 else -1.0,
				"fade": not bool(rota2["fechada"]),
			})
	# cidadaos caminhando dentro das vilas
	var nomes_p := Assets.pessoas()
	for v in Vilas.vilas:
		var n := clampi(int(v["populacao"]) / 380, 4, 14)
		for k in range(n):
			var s3 := Sprite2D.new()
			s3.texture = Assets.sprite(nomes_p[rng.randi_range(0, nomes_p.size() - 1)])
			s3.scale = Vector2(0.62, 0.62)
			s3.z_index = 3
			s3.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_pessoas.add_child(s3)
			_peds.append({
				"sprite": s3, "centro": (v["anchor"] as Vector2) * TILE,
				"fase": rng.randf() * TAU, "raio": rng.randf_range(14.0, 46.0),
				"vel": rng.randf_range(0.25, 0.6), "vila": int(v["id"]),
			})


func _carregar_rotas_trafego() -> Dictionary:
	var f := FileAccess.open("res://data/traffic_routes.json", FileAccess.READ)
	if f == null:
		push_warning("WorldView: data/traffic_routes.json ausente")
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("WorldView: traffic_routes.json invalido")
		return {}
	return parsed as Dictionary


## Converte pontos em tiles para pixels e pre-calcula a distancia acumulada.
## A rota fechada ganha um ponto final igual ao inicial para o laco ser continuo.
func _preparar_rota(pontos: Array, fechada: bool) -> Dictionary:
	var pts := PackedVector2Array()
	for p in pontos:
		pts.append(_v2(p))
	if pts.size() < 2:
		return {}
	if fechada and pts[0].distance_to(pts[pts.size() - 1]) > 0.01:
		pts.append(pts[0])
	if not RoadMask.rota_valida(pts):
		return {}
	var acum := PackedFloat32Array()
	acum.resize(pts.size())
	acum[0] = 0.0
	for i in range(1, pts.size()):
		acum[i] = acum[i - 1] + pts[i - 1].distance_to(pts[i])
	return {"pontos": pts, "acum": acum, "comp": acum[acum.size() - 1], "fechada": fechada}

func _montar_barcos() -> void:
	var rota := Vilas.boat_route
	if rota.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for k in range(4):
		var s := Sprite2D.new()
		var navio := k == 3 and not Assets.navios.is_empty()
		if navio:
			s.texture = Assets.navios[k % Assets.navios.size()]
			s.scale = Vector2(1.5, 1.5)
		elif not Assets.barcos.is_empty():
			s.texture = Assets.barcos[k % Assets.barcos.size()]
			s.scale = Vector2(2.2, 2.2)
		else:
			s.texture = Assets.sprite("van")
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.z_index = 3
		_barcos.add_child(s)
		_barcos_dados.append({
			"sprite": s, "t": rng.randf(),
			"vel": rng.randf_range(0.003, 0.006) if navio else rng.randf_range(0.006, 0.012),
			"navio": navio,
		})


## Converte um ponto da rota ([x, y] em unidades de tile) para pixels.
func _v2(p) -> Vector2:
	if p is Vector2:
		return p * TILE
	if p is Vector2i:
		return Vector2(p) * TILE
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1])) * TILE
	return Vector2.ZERO


func _comprimento(rota: Array) -> float:
	var total := 0.0
	for i in range(1, rota.size()):
		total += _v2(rota[i - 1]).distance_to(_v2(rota[i]))
	return total


# ============================================================================
# CICLO
# ============================================================================

func _process(delta: float) -> void:
	_tempo += delta
	_pulso = 0.5 + 0.5 * sin(_tempo * 3.0)
	_animar_carros(delta)
	_animar_pessoas(delta)
	_animar_barcos(delta)
	_animar_asas(delta)
	_escalar_rotulos()
	if _overlay_mat != null:
		_overlay_mat.set_shader_parameter("pulso", _pulso)


func zoom_atual() -> float:
	return camera_ctrl.zoom_atual() if camera_ctrl else 1.0


func _escalar_rotulos() -> void:
	var z := zoom_atual()
	var s := 1.0 / maxf(z, 0.05)
	var mostrar := z >= 0.52
	for id in _labels:
		var l: Label = _labels[id]
		l.scale = Vector2(s, s)
		var destaque: bool = id == 1 or id == 7 or id == 16 or id == 17
		l.visible = mostrar or destaque or z < 0.35


func _animar_carros(delta: float) -> void:
	for c in _carros:
		var comp := float(c["comp"])
		if comp <= 0.01:
			continue
		var fechada := bool((c["rota"] as Dictionary)["fechada"])
		var dir := float(c["dir"])
		c["t"] = float(c["t"]) + float(c["vel"]) * delta * dir
		if fechada:
			c["t"] = fposmod(float(c["t"]), comp)
		else:
			if float(c["t"]) > comp:
				c["t"] = 0.0
			elif float(c["t"]) < 0.0:
				c["t"] = comp
		var r := _ponto_rota(c["rota"], float(c["t"]))
		var s: Sprite2D = c["sprite"]
		var ang := float(r[1])
		if dir < 0.0:
			ang += PI
		# O deslocamento perpendicular separa as duas maos: no Brasil, cada um
		# anda do seu lado da via. "ang" ja e a direcao de viagem (inclui o PI
		# de quem volta), entao o offset nao leva outro "dir".
		var perp := Vector2(-sin(ang), cos(ang)) * 2.5
		var destino := (r[0] as Vector2) + perp
		# A mascara e a ultima linha de defesa: se a faixa encostar na calcada,
		# o carro volta ao eixo da rua em vez de atravessar a casa.
		if not RoadMask.ponto_em_estrada(destino):
			destino = r[0]
			if not RoadMask.ponto_em_estrada(destino):
				destino = RoadMask.ajustar_para_estrada(destino)
		s.position = destino
		var veiculo: Dictionary = c.get("veiculo", {})
		if not veiculo.is_empty():
			_aplicar_pose_veiculo(c, s, ang, delta)
		else:
			# Fallback historico: arte antiga dos carros aponta para cima.
			s.rotation = ang + PI * 0.5
		if bool(c.get("fade", false)):
			# Rotas abertas teleportam do fim para o inicio; 180 px de fade
			# deixam o veiculo praticamente invisivel nesse instante.
			var d := float(c["t"]) if dir > 0.0 else comp - float(c["t"])
			s.modulate.a = clampf(d / 180.0, 0.0, 1.0)
		else:
			s.modulate.a = 1.0


## Aplica a pose do carro/caminhao novo. Todas as celulas da folha olham para
## a direita; para andar no sentido contrario, o mesmo sprite e espelhado com
## `flip_h`, sem trocar de modelo. Assim o carro nao "muda de forma" quando
## cruza uma esquina ou inverte o sentido.
##
## A direcao visual e amortecida: a posicao anda no polyline, mas o sprite
## nao gira 90 graus de um frame para o outro nas esquinas. Guardamos o
## "heading" em radianos no proprio dicionario do veiculo; o espelhamento e o
## giro sao recalculados a partir dele, entao trocar de lado nao muda o nariz
## visual. O `lado` tem histerese (limiar de 0,15 no cosseno) para nao piscar
## quando a rota fica exatamente na vertical.
func _aplicar_pose_veiculo(c: Dictionary, s: Sprite2D, ang: float, delta: float) -> void:
	var veiculo: Dictionary = c["veiculo"]
	var dx := cos(ang)
	var lado := bool(c.get("lado", true))
	if absf(dx) > 0.15:
		lado = dx > 0.0
		c["lado"] = lado
	var k := clampf(1.0 - exp(-12.0 * maxf(delta, 0.0)), 0.0, 0.45)
	var heading := lerp_angle(float(c.get("heading", ang)), ang, k)
	c["heading"] = heading
	s.texture = veiculo["textura"]
	s.flip_h = not lado
	s.flip_v = false
	s.scale = Vector2.ONE * float(veiculo["escala"])
	# Base: 0 = nariz para a direita. Se `lado` e falso, flip_h espelha a arte
	# (nariz passa para a esquerda) e o giro compensa com -PI; o nariz visual
	# continua exatamente no heading.
	s.rotation = heading - (0.0 if lado else PI)


func _ponto_rota(rota: Dictionary, dist: float) -> Array:
	var pts: PackedVector2Array = rota["pontos"]
	var acum: PackedFloat32Array = rota["acum"]
	var comp := float(rota["comp"])
	if bool(rota["fechada"]):
		dist = fposmod(dist, comp)
	else:
		dist = clampf(dist, 0.0, comp)
	for i in range(1, pts.size()):
		if acum[i] >= dist:
			var seg := maxf(acum[i] - acum[i - 1], 0.0001)
			var t := (dist - acum[i - 1]) / seg
			return [pts[i - 1].lerp(pts[i], t), (pts[i] - pts[i - 1]).angle()]
	return [pts[pts.size() - 1], (pts[pts.size() - 1] - pts[pts.size() - 2]).angle()]

func _animar_pessoas(delta: float) -> void:
	for p in _peds:
		p["fase"] = float(p["fase"]) + float(p["vel"]) * delta
		var fase: float = p["fase"]
		var r: float = p["raio"]
		var s: Sprite2D = p["sprite"]
		s.position = (p["centro"] as Vector2) + Vector2(cos(fase) * r, sin(fase) * r * 0.62)
		s.z_index = 3 + int(s.position.y / 64.0) % 2


## Asa-deltas e parapentes sobre o vale.
##
## A cena tem exatamente 2 asas-deltas e 4 parapentes, sem poluir o mapa.
## Cada novo jogo sorteia as cores/poses: as asas-deltas usam a arte antiga
## (bico para cima) e os parapentes usam a folha nova de 3 cores x 4 poses.
## A posicao segue uma orbita eliptica; a asa-delta gira pela VELOCIDADE, e o
## parapente apenas espelha a pose conforme o lado para onde esta indo.
func _montar_asas() -> void:
	if Assets.deltas.is_empty() and Assets.parapentes.is_empty():
		return
	_sombra_asa = _gerar_sombra_asa()
	_rng_asas.randomize()
	_asas = Node2D.new()
	_asas.name = "Asas"
	# acima do trafego (3), abaixo dos rotulos (5): o texto da vila continua legivel
	_asas.z_index = 4
	add_child(_asas)
	# centros espalhados pelo vale; a orbita pode cruzar o rio, como no voo livre
	var centros := [
		Vector2(116, 60), Vector2(104, 45), Vector2(148, 48),
		Vector2(126, 86), Vector2(168, 94), Vector2(88, 58),
	]
	var tipos := ["delta", "delta", "parapente", "parapente", "parapente", "parapente"]
	for i in range(centros.size()):
		var tipo: String = tipos[i]
		var variantes: Array = Assets.deltas if tipo == "delta" else Assets.parapentes
		if variantes.is_empty():
			continue
		var textura_inicial: Texture2D = (variantes[0] as Texture2D) if tipo == "delta" else (variantes[0]["textura"] as Texture2D)
		var s := Sprite2D.new()
		s.texture = textura_inicial
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.scale = Vector2.ONE
		s.z_index = 1
		_asas.add_child(s)
		var sombra := Sprite2D.new()
		sombra.texture = _sombra_asa
		sombra.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sombra.z_index = 0
		_asas.add_child(sombra)
		var centro: Vector2 = centros[i] * TILE
		var vel := _rng_asas.randf_range(0.20, 0.32)
		if i % 2 == 1:
			vel = -vel
		_asas_dados.append({
			"sprite": s, "sombra": sombra, "centro": centro, "tipo": tipo,
			"variantes": variantes, "indice": 0,
			"rx": _rng_asas.randf_range(150.0, 270.0),
			"ry": _rng_asas.randf_range(80.0, 155.0),
			"fase": i * 2.399963 + 0.4 + _rng_asas.randf_range(-0.12, 0.12),
			"vel": vel,
			"alt": 12.0 + _rng_asas.randf_range(0.0, 18.0),
			"bob": _rng_asas.randf() * TAU,
			"escala": 1.0,
			"alvo": 56.0 if tipo == "delta" else 80.0,
		})
	_sortear_asas()


## Sorteia as texturas de cada asa. E chamado na montagem e de novo quando
## GameState reinicia a partida; os 6 slots e as posicoes permanecem, mas as
## cores/poses mudam. Para os 4 parapentes, garante pelo menos 3 cores
## diferentes em vez de sortear quatro variantes iguais por acaso.
func _sortear_asas() -> void:
	if _asas_dados.is_empty():
		return
	_rng_asas.randomize()
	var sorteio_delta: Array = range(Assets.deltas.size())
	sorteio_delta.shuffle()
	var escolhas_para := _sortear_parapentes()
	var id_delta := 0
	var id_para := 0
	for a in _asas_dados:
		var s: Sprite2D = a["sprite"]
		var tipo := str(a["tipo"])
		if tipo == "delta":
			if Assets.deltas.is_empty():
				continue
			var tex_d: Texture2D = Assets.deltas[int(sorteio_delta[id_delta % sorteio_delta.size()])]
			id_delta += 1
			a["indice"] = 0
			s.texture = tex_d
			a["escala"] = float(a["alvo"]) / maxf(float(tex_d.get_width()), 1.0)
		else:
			if escolhas_para.is_empty():
				continue
			var escolha: Dictionary = escolhas_para[id_para % escolhas_para.size()]
			id_para += 1
			a["indice"] = int(escolha["indice"])
			s.texture = escolha["textura"]
			a["escala"] = float(a["alvo"]) / maxf(float((escolha["textura"] as Texture2D).get_width()), 1.0)
		s.flip_h = false
		s.rotation = 0.0
		s.scale = Vector2.ONE * float(a["escala"])


func _sortear_parapentes() -> Array:
	var out: Array = []
	if Assets.parapentes.is_empty():
		return out
	var usados: Dictionary = {}
	# Uma pose por cor (linhas 0, 1 e 2), mais uma quarta pose sorteada.
	var linhas := mini(3, Assets.parapentes.size() / 4)
	for linha in range(linhas):
		var col := _rng_asas.randi_range(0, 3)
		var idx := linha * 4 + col
		usados[idx] = true
		out.append({"indice": idx, "textura": Assets.parapentes[idx]["textura"]})
	while out.size() < 4 and usados.size() < Assets.parapentes.size():
		var extra := _rng_asas.randi_range(0, Assets.parapentes.size() - 1)
		if usados.has(extra):
			continue
		usados[extra] = true
		out.append({"indice": extra, "textura": Assets.parapentes[extra]["textura"]})
	out.shuffle()
	return out


func _gerar_sombra_asa() -> Texture2D:
	var img := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	for y in range(20):
		for x in range(40):
			var dx := (x - 19.5) / 19.0
			var dy := (y - 9.5) / 9.0
			var d := dx * dx + dy * dy
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.02, 0.03, 0.05, pow(a, 1.5) * 0.55))
	var tex := ImageTexture.create_from_image(img)
	return tex


func _animar_asas(delta: float) -> void:
	# tamanho aproximadamente constante na tela: planador e alto, nao deve virar
	# um outdoor sobre a rua no zoom maximo.
	var z := 1.0
	if camera_ctrl != null:
		z = maxf(camera_ctrl.camera.zoom.x, 0.001)
	var inv := clampf(1.0 / z, 0.55, 1.50)
	for a in _asas_dados:
		var fase: float = float(a["fase"]) + float(a["vel"]) * delta
		a["fase"] = fase
		var centro: Vector2 = a["centro"]
		var rx: float = a["rx"]
		var ry: float = a["ry"]
		var vel: float = a["vel"]
		var pos := centro + Vector2(cos(fase) * rx, sin(fase) * ry * 0.62)
		var alt := float(a["alt"]) + 12.0 * sin(fase * 1.7 + float(a["bob"]))
		# derivada da orbita = direcao real do voo
		var vx := -sin(fase) * rx * vel
		var vy := cos(fase) * ry * 0.62 * vel
		var s: Sprite2D = a["sprite"]
		s.position = pos + Vector2(0, -alt)
		s.scale = Vector2.ONE * float(a["escala"]) * inv
		if str(a["tipo"]) == "delta":
			# A arte da asa-delta aponta para cima: +90 graus alinha o bico.
			s.rotation = Vector2(vx, vy).angle() + PI * 0.5
			s.flip_h = false
		else:
			# O parapente novo e uma arte de perfil/pose. Nao rotacionamos a
			# folha inteira (o piloto ficaria de cabeca para baixo); apenas
			# espelhamos para a canopy apontar no sentido horizontal do voo.
			s.rotation = 0.0
			s.flip_h = vx < -1.0
		var sombra: Sprite2D = a["sombra"]
		sombra.position = pos + Vector2(12, 20) * inv
		sombra.rotation = s.rotation if str(a["tipo"]) == "delta" else 0.0
		sombra.scale = Vector2.ONE * (0.85 + alt * 0.008) * float(a["escala"]) * inv
		sombra.modulate = Color(1, 1, 1, 0.30 + 0.12 * (1.0 - alt / 32.0))

func _animar_barcos(delta: float) -> void:
	var rota := Vilas.boat_route
	if rota.size() < 2:
		return
	for b in _barcos_dados:
		b["t"] = float(b["t"]) + float(b["vel"]) * delta
		if float(b["t"]) > 1.0:
			b["t"] = 0.0
		var idx := float(b["t"]) * float(rota.size() - 1)
		var i0 := clampi(int(idx), 0, rota.size() - 2)
		var frac := idx - float(i0)
		var a: Vector2 = rota[i0] * TILE
		var c: Vector2 = rota[i0 + 1] * TILE
		var s: Sprite2D = b["sprite"]
		s.position = a.lerp(c, frac)
		s.rotation = (c - a).angle() - PI * 0.5
		# O rio atravessa o mapa de ponta a ponta: no fim da rota o barco nao
		# pode dar re nem teleportar. Ele desvanece na entrada/saida do mapa.
		var beira := minf(float(b["t"]), 1.0 - float(b["t"]))
		s.modulate.a = clampf(beira / 0.035, 0.0, 1.0)
		if bool(b.get("navio", false)):
			s.z_index = 2  # casco grande passa por baixo dos barcos pequenos


# ============================================================================
# OVERLAY EPIDEMIOLOGICO
# ============================================================================

func definir_overlay(modo: String) -> void:
	modo_overlay = modo
	_atualizar_cores_overlay()


func _ao_atualizar_epidemia() -> void:
	_atualizar_cores_overlay()


func _atualizar_cores_overlay() -> void:
	if _overlay_mat == null:
		return
	var cores := PackedColorArray()
	cores.resize(21)
	cores[0] = Color(0, 0, 0, 0)
	for v in Vilas.vilas:
		var id := int(v["id"])
		var c := Color(0, 0, 0, 0)
		match modo_overlay:
			"prevalencia":
				var p := Epidemic.prevalencia(id)
				if p > 0.004:
					c = UITheme.cor_por_valor(p)
					c.a = clampf(0.35 + p * 3.0, 0.3, 0.85)
			"incidencia":
				var inc := Epidemic.incidencia_semana(id)
				var pop := maxf(float(v["populacao"]), 1.0)
				var taxa := float(inc) / pop * 1000.0
				if taxa > 0.01:
					c = UITheme.cor_por_valor(taxa * 0.02)
					c.a = clampf(0.3 + taxa * 0.05, 0.3, 0.85)
			"vacinacao":
				var cob := float(v["cobertura_vacinal"])
				c = Color(0.31, 0.82, 0.71).lerp(Color(0.15, 0.25, 0.4), 1.0 - cob)
				c.a = 0.55
			"saneamento":
				var san := float(v["saneamento"])
				c = Color(0.35, 0.72, 0.4).lerp(Color(0.85, 0.4, 0.25), 1.0 - san)
				c.a = 0.55
			_:
				c = Color(0, 0, 0, 0)
		c.r = minf(c.r, 1.0)
		cores[id] = c
	_overlay_mat.set_shader_parameter("cores", cores)
	var surto := PackedFloat32Array()
	surto.resize(21)
	for v in Vilas.vilas:
		surto[int(v["id"])] = 1.0 if bool(Epidemic.em_surto.get(int(v["id"]), false)) else 0.0
	_overlay_mat.set_shader_parameter("surto", surto)
	_overlay.visible = modo_overlay != "nenhum"


# ============================================================================
# EFEITOS DE ACAO DO JOGADOR
# ============================================================================

## Faz uma unidade movel de saude viajar ate a vila beneficiada.
func animar_entrega(vila_id: int) -> void:
	var v := Vilas.get_vila(vila_id)
	if v.is_empty():
		return
	var destino: Vector2 = (v["anchor"] as Vector2) * TILE
	var s := Sprite2D.new()
	s.texture = (Assets.carros[0] if not Assets.carros.is_empty()
		else Assets.sprite("van"))
	s.modulate = Color(0.85, 0.97, 1.0)
	s.z_index = 6
	var inicio := destino + Vector2(-420, 300)
	s.position = inicio
	s.rotation = (destino - inicio).angle() + PI * 0.5
	_extras.add_child(s)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "position", destino, 2.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "modulate:a", 0.0, 0.6).set_delay(2.0)
	tw.chain().tween_callback(s.queue_free)


## Animacao de construcao: predio surge com "pop" e some depois de um tempo.
func animar_construcao(vila_id: int, tipo: String) -> void:
	var v := Vilas.get_vila(vila_id)
	if v.is_empty():
		return
	var pos: Vector2 = (v["anchor"] as Vector2) * TILE
	var s := Sprite2D.new()
	s.texture = Assets.sprite("hospital" if tipo == "hospital" else "ubs")
	s.scale = Vector2(2.0, 2.0)
	s.z_index = 7
	s.position = pos + Vector2(0, 10)
	_extras.add_child(s)
	s.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(s, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(s, "scale", Vector2(2.4, 2.4), 0.35).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(1.6)
	tw.tween_property(s, "modulate:a", 0.0, 0.8)
	tw.tween_callback(s.queue_free)
