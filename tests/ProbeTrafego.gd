extends Node
## Sonda visual do trafego e dos planadores. Nao e um teste de aceite:
## abre o mapa real, aproxima no centro e salva uma captura em docs/evidencias.
## Uso: DISPLAY=:0 godot --path . res://tests/ProbeTrafego.tscn --resolution 1600x900

const DESTINO := "res://docs/evidencias/trafego_malha_nova.png"
const DESTINO_CAMINHAO := "res://docs/evidencias/trafego_caminhao.png"
const DESTINO_CARRO := "res://docs/evidencias/trafego_carro.png"


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidencias"))
	var cena: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(cena)
	var main = cena
	await _esperar(30)
	main.fechar_modal()
	await _esperar(8)
	var mundo = main.mundo
	var deltas := 0
	var paras := 0
	for a in mundo._asas_dados:
		if str(a["tipo"]) == "delta": deltas += 1
		else: paras += 1
	print("PROBE carros=", mundo._carros.size(),
		" carros_pixel=", Assets.carros_pixel.size(),
		" caminhoes_pixel=", Assets.caminhoes_pixel.size(),
		" asas=", mundo._asas_dados.size(), " deltas=", deltas, " parapentes=", paras,
		" parapente_variantes=", Assets.parapentes.size())
	var fora := 0
	for c in mundo._carros:
		if not RoadMask.ponto_em_estrada((c["sprite"] as Sprite2D).position, 0.5):
			fora += 1
	print("PROBE fora_da_mascara=", fora)
	main.camera_ctrl.ir_para(Vector2(128, 68) * 16.0, 1.05)
	await _esperar(90)
	var img := get_viewport().get_texture().get_image()
	img.save_png(DESTINO)
	print("PROBE imagem=", DESTINO)
	# Aproxima de um caminhao real para conferir sprite, escala e rotacao.
	var alvo_caminhao := Vector2.ZERO
	var melhor_d := INF
	for c in mundo._carros:
		if str(c["tipo"]) == "caminhao":
			var p := (c["sprite"] as Sprite2D).position
			# prefere um caminhao no miolo urbano, nao na borda do mapa
			var d := p.distance_to(Vector2(1900, 950))
			if d < melhor_d:
				melhor_d = d
				alvo_caminhao = p
	if alvo_caminhao != Vector2.ZERO:
		main.camera_ctrl.ir_para(alvo_caminhao, 2.6)
		await _esperar(8)
		# O caminhao continua andando; recoloca a camera no alvo no ultimo
		# frame para o close-up nao sair com a rua vazia. Desliga o _process
		# do controlador: ele interpola para _pos_alvo e desfaria o ajuste.
		var melhor_d2 := INF
		for c in mundo._carros:
			if str(c["tipo"]) != "caminhao":
				continue
			var cv: Dictionary = c.get("veiculo", {})
			if str(cv.get("cor", "")) == "outros":
				continue
			var p2 := (c["sprite"] as Sprite2D).position
			var d2 := p2.distance_to(Vector2(1900, 950))
			if d2 < melhor_d2:
				melhor_d2 = d2
				alvo_caminhao = p2
		main.camera_ctrl.set_process(false)
		main.camera_ctrl.camera.position = alvo_caminhao
		main.camera_ctrl.camera.zoom = Vector2(3.0, 3.0)
		await _esperar(1)
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png(DESTINO_CAMINHAO)
		print("PROBE imagem_caminhao=", DESTINO_CAMINHAO,
			" alvo=", alvo_caminhao, " camera=", main.camera_ctrl.camera.position)
	# Close-up de um carro andando para a ESQUERDA: confere que o flip_h nao
	# deixa o nariz apontando para tras. A camera fica parada no ultimo frame.
	var alvo_carro := Vector2.ZERO
	var ang_carro := 0.0
	var flip_carro := false
	var melhor_cd := INF
	for c in mundo._carros:
		if str(c["tipo"]) != "carro":
			continue
		var p3 := (c["sprite"] as Sprite2D).position
		var d3 := p3.distance_to(Vector2(1900, 950))
		var ang3 := float(mundo._ponto_rota(c["rota"], float(c["t"]))[1])
		if float(c["dir"]) < 0.0:
			ang3 += PI
		if cos(ang3) < -0.45 and d3 < melhor_cd:
			melhor_cd = d3
			alvo_carro = p3
			ang_carro = ang3
			flip_carro = (c["sprite"] as Sprite2D).flip_h
	if alvo_carro != Vector2.ZERO:
		main.camera_ctrl.set_process(false)
		main.camera_ctrl.camera.position = alvo_carro
		main.camera_ctrl.camera.zoom = Vector2(3.2, 3.2)
		await _esperar(1)
		var img3 := get_viewport().get_texture().get_image()
		img3.save_png(DESTINO_CARRO)
		print("PROBE imagem_carro=", DESTINO_CARRO, " alvo=", alvo_carro,
			" ang=", ang_carro, " flip=", flip_carro)
	# Reinicia a partida e confere que os 6 slots trocaram de textura sem
	# mudar de quantidade. O sorteio e uniforme; um teste visual confirma.
	var antes: Array = []
	for a in mundo._asas_dados:
		antes.append((a["sprite"] as Sprite2D).texture)
	GameState.reiniciar_partida()
	await _esperar(6)
	var depois: Array = []
	for a in mundo._asas_dados:
		depois.append((a["sprite"] as Sprite2D).texture)
	var iguais := 0
	for i in range(antes.size()):
		if antes[i] == depois[i]: iguais += 1
	print("PROBE reinicio slots=", depois.size(), " iguais=", iguais)
	get_tree().quit()


func _esperar(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
