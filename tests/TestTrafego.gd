extends Node
## Teste de aceite do trafego, da malha viaria e do voo livre.
## Roda sem display: valida contagens, texturas, posicao na mascara e reinicio.
## Uso: godot --headless --path . res://tests/TestTrafego.tscn

var _falhas := 0
var _passos := 0


func _ready() -> void:
	var cena: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(cena)
	await _esperar(30)
	cena.fechar_modal()
	await _esperar(10)
	var mundo = cena.mundo

	_ok(RoadMask.disponivel, "RoadMask carregou road_nav_mask.png")

	_ok(Assets.carros_pixel.size() == 48, "48 variantes de carro no atlas (6 cores x 2 linhas x 4 modelos)")
	_ok(Assets.caminhoes_pixel.size() == 24, "24 variantes de caminhao no atlas (6 cores x 2 linhas x 2 modelos)")
	_ok(Assets.parapentes.size() == 12, "12 variantes de parapente (3 cores x 4 poses)")
	_ok(Assets.deltas.size() >= 2, "asas-deltas antigas ainda carregam")

	_ok(mundo._carros.size() == 55, "55 veiculos na cena")
	var deltas := 0
	var paras := 0
	for a in mundo._asas_dados:
		if str(a["tipo"]) == "delta":
			deltas += 1
		else:
			paras += 1
	_ok(deltas == 2, "exatamente 2 asas-deltas")
	_ok(paras == 4, "exatamente 4 parapentes")

	# Deixa a animacao rodar e confere o centro de cada veiculo contra a malha.
	await _esperar(3)
	var fora := 0
	for c in mundo._carros:
		var spr := c["sprite"] as Sprite2D
		if spr == null or spr.texture == null:
			_ok(false, "veiculo sem sprite/textura")
			continue
		if not RoadMask.ponto_em_estrada(spr.position):
			fora += 1
	_ok(fora == 0, "todos os veiculos com centro na malha viaria")

	# Anda mais um pouco e confirma duas propriedades da correcao: o modelo nao
	# muda quando o veiculo inverte o sentido, e flip_h e o oposto de `lado`.
	var texturas_antes: Array = []
	for c in mundo._carros:
		texturas_antes.append((c["sprite"] as Sprite2D).texture)
	await _esperar(45)
	var trocas := 0
	var flips_errados := 0
	for i in range(mundo._carros.size()):
		var c: Dictionary = mundo._carros[i]
		var spr: Sprite2D = c["sprite"]
		if spr.texture != texturas_antes[i]:
			trocas += 1
		if spr.flip_h == bool(c.get("lado", true)):
			flips_errados += 1
	_ok(trocas == 0 and flips_errados == 0,
		"mesma textura ao mudar de sentido e flip_h coerente com lado")

	# Reiniciar a partida nao pode mudar a quantidade nem quebrar as texturas.
	var antes: Array = []
	for a in mundo._asas_dados:
		antes.append((a["sprite"] as Sprite2D).texture)
	cena.fechar_modal()
	GameState.reiniciar_partida()
	await _esperar(6)
	var deltas2 := 0
	var paras2 := 0
	var texturas_ok := true
	for a in mundo._asas_dados:
		var spr := a["sprite"] as Sprite2D
		if spr == null or spr.texture == null:
			texturas_ok = false
		if str(a["tipo"]) == "delta":
			deltas2 += 1
		else:
			paras2 += 1
	_ok(texturas_ok, "asas com textura apos reiniciar")
	_ok(deltas2 == 2 and paras2 == 4, "2 deltas + 4 parapentes apos reiniciar")
	_ok(mundo._asas_dados.size() == antes.size(), "slots de voo preservados no reinicio")

	print("TESTE TRAFEGO: ", _passos, " passos, ", _falhas, " falhas")
	get_tree().quit(1 if _falhas > 0 else 0)


func _ok(condicao: bool, descricao: String) -> void:
	_passos += 1
	if not condicao:
		_falhas += 1
		print("FALHA: ", descricao)


func _esperar(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
