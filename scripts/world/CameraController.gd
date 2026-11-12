class_name CameraController
extends Node2D
## CameraController - pan e zoom para mouse, teclado, roda e gestos de toque.
##
## Cobre os tres modos exigidos pelo projeto:
##   desktop  -> arrastar com o botao esquerdo, roda do mouse, setas/WASD
##   celular  -> arrastar com um dedo, pinca de dois dedos (InputEventMagnifyGesture
##               e, como fallback, o calculo direto da distancia entre dois toques)
##   trackpad -> InputEventPanGesture com dois dedos
##
## O zoom e sempre ancorado no cursor/dedo, para que o ponto sob o dedo
## permaneca sob o dedo durante a pinca.

signal zoom_alterado(z: float)
signal vila_tocada(vila_id: int, pos_mundo: Vector2)

const ZOOM_MIN := 0.26
const ZOOM_MAX := 3.2
const ZOOM_INICIAL := 0.85
const SUAVIZACAO := 14.0

var camera: Camera2D
var mundo: WorldView
var mapa_tamanho := Vector2(3840, 2880)

var _zoom_alvo := ZOOM_INICIAL
var _pos_alvo := Vector2.ZERO
var _arrastando := false
var _ultimo_mouse := Vector2.ZERO
var _toques: Dictionary = {}           # index -> posicao local
var _pinando := false
var _multitouch := false               # houve pinca: nao emitir "toque em vila" no fim
var _dist_pinca := 0.0
var _centro_pinca := Vector2.ZERO
var _usou_toque := 0.0
var _bloquear_input := false
var _clique_inicio := Vector2.ZERO
var _clique_tempo := 0.0


func _ready() -> void:
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()
	zoom_alterado.emit(_zoom_alvo)


func configurar(tamanho_mapa: Vector2, pos: Vector2 = Vector2.ZERO) -> void:
	mapa_tamanho = tamanho_mapa
	if pos != Vector2.ZERO:
		_pos_alvo = pos
	camera.position = _pos_alvo
	camera.zoom = Vector2(_zoom_alvo, _zoom_alvo)
	_limitar()


func ir_para(pos: Vector2, zoom: float = -1.0) -> void:
	_pos_alvo = pos
	if zoom > 0.0:
		_zoom_alvo = clampf(zoom, ZOOM_MIN, ZOOM_MAX)
		camera.zoom = Vector2(_zoom_alvo, _zoom_alvo)
		zoom_alterado.emit(_zoom_alvo)
	_limitar()


func foco_vila(vila_id: int, zoom: float = 1.15) -> void:
	var v := Vilas.get_vila(vila_id)
	if v.is_empty():
		return
	var p: Vector2 = v["anchor"] * 16.0
	ir_para(p, zoom)


func zoom_atual() -> float:
	return camera.zoom.x


func _process(delta: float) -> void:
	var t := 1.0 - exp(-SUAVIZACAO * delta)
	camera.position = camera.position.lerp(_pos_alvo, t)
	var z := lerpf(camera.zoom.x, _zoom_alvo, t)
	camera.zoom = Vector2(z, z)
	if _usou_toque > 0.0:
		_usou_toque -= delta


# ============================================================================
# ENTRADA
# ============================================================================

func definir_bloqueio(b: bool) -> void:
	_bloquear_input = b
	if b:
		_arrastando = false


func _unhandled_input(event: InputEvent) -> void:
	if _bloquear_input:
		return

	if event is InputEventScreenTouch:
		_tratar_toque(event)
		return

	if event is InputEventScreenDrag:
		_tratar_arrasto_toque(event)
		return

	if event is InputEventMagnifyGesture:
		_usou_toque = 1.0
		var f: float = event.factor
		_zoom_para(_zoom_alvo * f, event.position)
		return

	if event is InputEventPanGesture:
		_usou_toque = 0.6
		_pos_alvo -= event.delta * 26.0 / _zoom_alvo
		_limitar()
		return

	if event is InputEventMouseButton:
		if _usou_toque > 0.0:
			return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_para(_zoom_alvo * 1.14, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_para(_zoom_alvo / 1.14, event.position)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_arrastando = true
					_ultimo_mouse = event.position
					_clique_inicio = event.position
					_clique_tempo = Time.get_ticks_msec() / 1000.0
				else:
					if _arrastando and event.position.distance_to(_clique_inicio) < 12.0:
						_emitir_toque(event.position)
					_arrastando = false
			MOUSE_BUTTON_MIDDLE:
				_arrastando = event.pressed
				_ultimo_mouse = event.position
		return

	if event is InputEventMouseMotion and _arrastando:
		if _usou_toque > 0.0:
			return
		var d: Vector2 = event.position - _ultimo_mouse
		_ultimo_mouse = event.position
		_pos_alvo -= d / camera.zoom.x
		_limitar()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var passo := 220.0 / camera.zoom.x
		match event.keycode:
			KEY_LEFT, KEY_A: _pos_alvo.x -= passo
			KEY_RIGHT, KEY_D: _pos_alvo.x += passo
			KEY_UP, KEY_W: _pos_alvo.y -= passo
			KEY_DOWN, KEY_S: _pos_alvo.y += passo
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: _zoom_para(_zoom_alvo * 1.2, get_viewport().get_visible_rect().size * 0.5)
			KEY_MINUS, KEY_KP_SUBTRACT: _zoom_para(_zoom_alvo / 1.2, get_viewport().get_visible_rect().size * 0.5)
			_: return
		_limitar()


func _tratar_toque(e: InputEventScreenTouch) -> void:
	_usou_toque = 1.0
	if e.pressed:
		_toques[e.index] = e.position
		_clique_inicio = e.position
		_clique_tempo = Time.get_ticks_msec() / 1000.0
		if _toques.size() == 2:
			_pinando = true
			_multitouch = true
			_dist_pinca = _distancia_toques()
			_centro_pinca = _centro_toques()
	else:
		var foi_toque := false
		if _toques.has(e.index):
			var p: Vector2 = _toques[e.index]
			foi_toque = p.distance_to(e.position) < 16.0
			_toques.erase(e.index)
		if _pinando and _toques.size() < 2:
			_pinando = false
		# fim de pinca nao pode virar "toque em vila": o dedo que sai por ultimo
		# tambem esta a menos de 16 px do ponto onde encostou
		if _toques.is_empty():
			if foi_toque and not _pinando and not _multitouch:
				_emitir_toque(e.position)
			_multitouch = false


func _tratar_arrasto_toque(e: InputEventScreenDrag) -> void:
	_usou_toque = 1.0
	if not _toques.has(e.index):
		_toques[e.index] = e.position
		return
	_toques[e.index] = e.position
	if _toques.size() >= 2:
		_multitouch = true
	if _pinando and _toques.size() >= 2:
		var d := _distancia_toques()
		var c := _centro_toques()
		if _dist_pinca > 1.0:
			var f := d / _dist_pinca
			_zoom_para(_zoom_alvo * f, c)
		_pos_alvo -= (c - _centro_pinca) / camera.zoom.x
		_dist_pinca = d
		_centro_pinca = c
		_limitar()
	elif _toques.size() == 1:
		_pos_alvo -= e.relative / camera.zoom.x
		_limitar()


func _distancia_toques() -> float:
	var vals := _toques.values()
	if vals.size() < 2:
		return 0.0
	return (vals[0] as Vector2).distance_to(vals[1])


func _centro_toques() -> Vector2:
	var vals := _toques.values()
	var s := Vector2.ZERO
	for v in vals:
		s += v
	return s / float(maxi(vals.size(), 1))


func _emitir_toque(pos_tela: Vector2) -> void:
	var mundo_ponto := get_global_mouse_position()
	if camera:
		mundo_ponto = camera.get_screen_center_position() + (pos_tela - get_viewport_rect().size * 0.5) / camera.zoom.x
	# O rotulo da vila e um Label sobre o mapa. Se o clique/toque cair nele,
	# abre a vila mesmo quando o centro da zona esta alguns pixels ao lado.
	# A checagem e feita em coordenadas de mundo, nao de tela: no web o canvas
	# tem content scale e o evento cru nao coincide com o transform do Label.
	if mundo != null:
		var id_rotulo := mundo.vila_no_rotulo_mundo(mundo_ponto)
		if id_rotulo > 0:
			var v := Vilas.get_vila(id_rotulo)
			var ancora: Vector2 = (v.get("anchor", Vector2.ZERO) as Vector2) * 16.0
			vila_tocada.emit(id_rotulo, ancora)
			return
	var vila := Vilas.vila_em(mundo_ponto.x / 16.0, mundo_ponto.y / 16.0)
	vila_tocada.emit(vila, mundo_ponto)


## Ajusta o zoom mantendo o ponto `pivo` (em coordenadas de tela) fixo.
func _zoom_para(novo: float, pivo: Vector2) -> void:
	var antes := clampf(_zoom_alvo, ZOOM_MIN, ZOOM_MAX)
	var depois := clampf(novo, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(antes, depois):
		return
	var tam := get_viewport_rect().size
	var mundo_pivo := _pos_alvo + (pivo - tam * 0.5) / antes
	_zoom_alvo = depois
	_pos_alvo = mundo_pivo - (pivo - tam * 0.5) / depois
	camera.zoom = Vector2(depois, depois)
	zoom_alterado.emit(depois)
	_limitar()


func _limitar() -> void:
	var tam := get_viewport_rect().size
	var meio := tam / (2.0 * maxf(_zoom_alvo, 0.0001))
	if mapa_tamanho.x <= meio.x * 2.0:
		_pos_alvo.x = mapa_tamanho.x * 0.5
	else:
		_pos_alvo.x = clampf(_pos_alvo.x, meio.x, mapa_tamanho.x - meio.x)
	if mapa_tamanho.y <= meio.y * 2.0:
		_pos_alvo.y = mapa_tamanho.y * 0.5
	else:
		_pos_alvo.y = clampf(_pos_alvo.y, meio.y, mapa_tamanho.y - meio.y)


func enquadrar_tudo() -> void:
	var tam := get_viewport_rect().size
	var z := minf(tam.x / mapa_tamanho.x, tam.y / mapa_tamanho.y)
	ir_para(mapa_tamanho * 0.5, z * 0.98)
