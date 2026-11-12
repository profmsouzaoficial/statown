extends Node
## Testa os modos de navegacao da CameraController: roda do mouse, arrasto,
## gesto de magnificacao (trackpad) e pinca de dois dedos (celular).
## Roda como cena, porque precisa de viewport e dos autoloads:
##   godot --headless res://tests/TestCamera.tscn

var _falhas := 0
var _passos := 0


func _ready() -> void:
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in range(4):
		await get_tree().process_frame
	main.fechar_modal()
	var cam: CameraController = main.camera_ctrl
	cam.definir_bloqueio(false)
	cam.ir_para(Vector2(1920, 1440), 1.0)
	await get_tree().process_frame

	_teste_roda(cam)
	_teste_arrasto_mouse(cam)
	_teste_magnify(cam)
	_teste_pinca(cam)
	_teste_limites(cam)
	_teste_teclado(cam)
	_teste_cliques_vilas(main)

	print("TESTE CAMERA: %d passos, %d falhas" % [_passos, _falhas])
	get_tree().quit(1 if _falhas > 0 else 0)


func _ok(cond: bool, nome: String) -> void:
	_passos += 1
	if not cond:
		_falhas += 1
		print("  FALHOU: ", nome)


func _perto(a: float, b: float, tol: float = 0.02) -> bool:
	return absf(a - b) <= tol


## Cobertura de clique: a mascara de zona nao cobre a vila inteira. Para cada
## vila, um ponto a 5 tiles da ancora (fora do miolo urbanizado) ainda deve
## resolver para ela; longe de tudo deve devolver 0. Tambem confere que os
## rotulos nao interceptam o mouse.
func _teste_cliques_vilas(main: Control) -> void:
	for v in Vilas.vilas:
		var id := int(v["id"])
		var a: Vector2 = v["anchor"]
		var fora := Vector2(a.x + 5.0, a.y)
		_ok(Vilas.vila_em(fora.x, fora.y) == id, "clique a 5 tiles resolve vila %d" % id)
	_ok(Vilas.vila_em(5.0, 5.0) == 0, "clique no canto vazio nao abre vila")
	var rotulos: Node = main.mundo._rotulos
	for filho in rotulos.get_children():
		if filho is Label:
			_ok(filho.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"rotulo nao bloqueia o arrasto do mapa")
	for id in main.mundo._labels:
		var lbl: Label = main.mundo._labels[id]
		var centro: Vector2 = lbl.get_global_transform_with_canvas() * (lbl.size * 0.5)
		_ok(main.mundo.vila_no_rotulo(centro) == int(id),
			"rotulo da vila %d abre a vila certa" % int(id))
		var centro_mundo: Vector2 = lbl.global_position + (lbl.size * maxf(lbl.scale.x, 0.001)) * 0.5
		_ok(main.mundo.vila_no_rotulo_mundo(centro_mundo) == int(id),
			"rotulo da vila %d acerta em coordenadas de mundo" % int(id))


func _teste_roda(cam: CameraController) -> void:
	cam._usou_toque = 0.0
	cam.ir_para(Vector2(1920, 1440), 1.0)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	e.position = Vector2(800, 450)
	cam._unhandled_input(e)
	_ok(_perto(cam.zoom_atual(), 1.14), "roda para cima aproxima 14%")

	var e2 := InputEventMouseButton.new()
	e2.button_index = MOUSE_BUTTON_WHEEL_DOWN
	e2.pressed = true
	e2.position = Vector2(800, 450)
	cam._unhandled_input(e2)
	_ok(_perto(cam.zoom_atual(), 1.0, 0.03), "roda para baixo afasta")


func _teste_arrasto_mouse(cam: CameraController) -> void:
	cam._usou_toque = 0.0
	cam.ir_para(Vector2(1920, 1440), 1.0)
	var antes := cam._pos_alvo.x
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(800, 450)
	cam._unhandled_input(press)
	var mov := InputEventMouseMotion.new()
	mov.position = Vector2(900, 450)
	mov.relative = Vector2(100, 0)
	cam._unhandled_input(mov)
	var solta := InputEventMouseButton.new()
	solta.button_index = MOUSE_BUTTON_LEFT
	solta.pressed = false
	solta.position = Vector2(900, 450)
	cam._unhandled_input(solta)
	_ok(cam._pos_alvo.x < antes - 50.0, "arrastar move o mapa no sentido oposto")


func _teste_magnify(cam: CameraController) -> void:
	cam._usou_toque = 0.0
	cam.ir_para(Vector2(1920, 1440), 1.0)
	var e := InputEventMagnifyGesture.new()
	e.factor = 1.5
	e.position = Vector2(800, 450)
	cam._unhandled_input(e)
	_ok(_perto(cam.zoom_atual(), 1.5), "gesto de magnificacao (trackpad) amplia")


func _teste_pinca(cam: CameraController) -> void:
	cam._usou_toque = 0.0
	var toques := [0]
	cam.vila_tocada.connect(func(_id: int, _p: Vector2) -> void: toques[0] += 1)
	cam.ir_para(Vector2(1920, 1440), 1.0)
	var t0 := InputEventScreenTouch.new()
	t0.index = 0
	t0.pressed = true
	t0.position = Vector2(600, 450)
	cam._unhandled_input(t0)
	var t1 := InputEventScreenTouch.new()
	t1.index = 1
	t1.pressed = true
	t1.position = Vector2(800, 450)
	cam._unhandled_input(t1)
	_ok(cam._pinando, "dois dedos entram em modo pinca")
	var d := InputEventScreenDrag.new()
	d.index = 1
	d.position = Vector2(1000, 450)
	d.relative = Vector2(200, 0)
	cam._unhandled_input(d)
	_ok(cam.zoom_atual() > 1.6, "afastar os dedos aproxima (zoom cresce)")
	# soltar os dedos encerra a pinca
	var s0 := InputEventScreenTouch.new()
	s0.index = 0
	s0.pressed = false
	s0.position = Vector2(600, 450)
	cam._unhandled_input(s0)
	var s1 := InputEventScreenTouch.new()
	s1.index = 1
	s1.pressed = false
	s1.position = Vector2(1000, 450)
	cam._unhandled_input(s1)
	_ok(not cam._pinando, "soltar os dedos encerra a pinca")
	_ok(int(toques[0]) == 0, "pinca nao abre o painel da vila ao soltar")


func _teste_limites(cam: CameraController) -> void:
	cam._usou_toque = 0.0
	cam.ir_para(Vector2(1920, 1440), 1.0)
	var e := InputEventMagnifyGesture.new()
	e.factor = 100.0
	e.position = Vector2(800, 450)
	cam._unhandled_input(e)
	_ok(cam.zoom_atual() <= CameraController.ZOOM_MAX + 0.001, "zoom respeita o maximo")
	e.factor = 0.0001
	cam._unhandled_input(e)
	_ok(cam.zoom_atual() >= CameraController.ZOOM_MIN - 0.001, "zoom respeita o minimo")
	cam.ir_para(Vector2(0, 0), 1.0)
	_ok(cam._pos_alvo.x >= 0.0 and cam._pos_alvo.y >= 0.0, "pan nao sai do mapa")


func _teste_teclado(cam: CameraController) -> void:
	cam._usou_toque = 0.0
	cam.definir_bloqueio(false)
	cam.ir_para(Vector2(1920, 1440), 1.0)
	var antes := cam._pos_alvo.x
	var k := InputEventKey.new()
	k.keycode = KEY_RIGHT
	k.pressed = true
	cam._unhandled_input(k)
	_ok(cam._pos_alvo.x > antes, "seta direita move o mapa")
