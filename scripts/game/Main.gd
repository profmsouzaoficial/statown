extends Control
## Main - orquestrador da partida.
##
## Constroi em codigo (sem .tscn complexos) o mundo, a camera, a HUD e a
## camada de modais; liga os sinais dos autoloads e cuida da navegacao entre
## paineis. Cada painel e um Control autonome definido em scripts/ui/panels.

const TELA := Vector2(1600, 900)

var mundo: WorldView
var camera_ctrl: CameraController
var hud: CanvasLayer

# HUD - barra superior
var _lbl_se: Label
var _lbl_ano: Label
var _lbl_moedas: Label
var _lbl_doenca: Label
var _lbl_alerta: Label
var _btns_velocidade: Array[Button] = []
var _barra_topo: PanelContainer

# HUD - barra inferior
var _lbl_dica: Label
var _card_vila: PanelContainer
var _vila_sel: int = 0

# Modais
var _dim: ColorRect
var _modal_raiz: Control
var _modal_painel: PanelContainer
var _modal_titulo: Label
var _modal_corpo: Control

# Toasts
var _toasts: VBoxContainer

var _timer_ui := 0.0
var _vila_destaque: int = 0
var _vila_zoom: int = 0
var _ultimo_tick_semana := 0.0


func _ready() -> void:
	UITheme.aplicar_escala(GameState.fonte_grande)
	get_tree().root.theme = UITheme.tema
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# O Control raiz cobre a tela inteira. Com STOP ele aparece como camada de
	# GUI no ponto do mapa (atrapalhando cliques em rotulos no web); os filhos
	# (HUD e modais) continuam recebendo porque cada um tem seu proprio filtro.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_criar_mundo()
	_criar_hud()
	_criar_modais()
	_criar_toasts()
	_conectar()
	_atualizar_hud()
	Audio.modo_mapa()
	Audio.tocar_ambiente_base("amb_parque_urbano")
	# a Vila Central e o que o jogador ve no centro da tela ao abrir o jogo:
	# deixar o cartao do rodape preenchido evita a primeira impressao de "vazio"
	_vila_sel = 1
	_atualizar_card_vila(1)
	abrir_boas_vindas()


func _process(delta: float) -> void:
	_timer_ui -= delta
	if _timer_ui <= 0.0:
		_timer_ui = 0.35
		_atualizar_kpis()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _modal_raiz != null and _modal_raiz.visible:
			fechar_modal()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F1:
		_abrir_manual()
		get_viewport().set_input_as_handled()


# ============================================================================
# CONSTRUCAO
# ============================================================================

func _criar_mundo() -> void:
	var raiz := Node2D.new()
	raiz.name = "Mundo"
	add_child(raiz)
	mundo = WorldView.new()
	mundo.name = "WorldView"
	raiz.add_child(mundo)
	camera_ctrl = CameraController.new()
	camera_ctrl.name = "Camera"
	raiz.add_child(camera_ctrl)
	mundo.camera_ctrl = camera_ctrl
	camera_ctrl.mundo = mundo
	camera_ctrl.configurar(WorldView.MAPA, Vector2(116, 60) * 16.0)
	camera_ctrl.vila_tocada.connect(_ao_tocar_mapa)
	camera_ctrl.zoom_alterado.connect(func(_z): _atualizar_botoes_zoom())


func _criar_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	# ---------- barra superior ----------
	_barra_topo = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.11, 0.15, 0.94)
	sb.border_color = UITheme.BORDA
	sb.border_width_bottom = 2
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_barra_topo.add_theme_stylebox_override("panel", sb)
	_barra_topo.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_barra_topo.custom_minimum_size.y = 64
	hud.add_child(_barra_topo)

	var linha := HFlowContainer.new()
	linha.add_theme_constant_override("h_separation", 12)
	linha.add_theme_constant_override("v_separation", 6)
	_barra_topo.add_child(linha)

	# logo
	var logo := UITheme.vbox(0)
	var t := UITheme.titulo("StaTown", 26, UITheme.ACENTO, true)
	logo.add_child(t)
	logo.add_child(UITheme.rotulo("Vale do Rio Doce", 11, UITheme.TEXTO_FRACO))
	linha.add_child(logo)

	# relogio
	var rel := UITheme.hbox(8)
	var icone_rel := UITheme.titulo("SE", 18, UITheme.TEXTO_DIM, true)
	rel.add_child(icone_rel)
	_lbl_se = UITheme.titulo("1", 30, UITheme.TEXTO, true)
	rel.add_child(_lbl_se)
	_lbl_ano = UITheme.rotulo("Ano 1", 14, UITheme.TEXTO_DIM)
	rel.add_child(_lbl_ano)
	linha.add_child(rel)

	# velocidades
	var ctrl := UITheme.hbox(4)
	_btns_velocidade.clear()
	for item in [["||", 0.0, "Pausar"], [">", 0.5, "Lento (0,5x)"],
			[">>", 1.0, "Normal (1x)"], [">>>", 3.0, "Rapido (3x)"],
			[">>>>", 8.0, "Ultra (8x)"]]:
		var b := Button.new()
		b.text = str(item[0])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(42, 38)
		b.tooltip_text = str(item[2])
		b.add_theme_font_override("font", UITheme.titulo_font(true))
		b.add_theme_font_size_override("font_size", 12)
		var v: float = float(item[1])
		b.pressed.connect(func(): _definir_velocidade(v))
		b.pressed.connect(func(): Audio.ui("clique"))
		ctrl.add_child(b)
		_btns_velocidade.append(b)
	linha.add_child(ctrl)

	# cenario
	var cen := UITheme.hbox(8)
	_lbl_doenca = UITheme.rotulo("Arbovirose", 14, UITheme.TEXTO)
	cen.add_child(_lbl_doenca)
	var bd := UITheme.botao("Trocar", _abrir_troca_cenario)
	bd.custom_minimum_size = Vector2(72, 32)
	bd.add_theme_font_size_override("font_size", 12)
	cen.add_child(bd)
	linha.add_child(cen)

	# espaco
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(esp)

	# alerta
	_lbl_alerta = UITheme.rotulo("", 14, UITheme.PERIGO)
	linha.add_child(_lbl_alerta)

	# moedas
	var moedas := UITheme.hbox(8)
	moedas.add_child(UITheme.rotulo("BIO", 12, UITheme.TEXTO_FRACO))
	var moeda_icon := TextureRect.new()
	moeda_icon.texture = Assets.sprite("moeda")
	moeda_icon.custom_minimum_size = Vector2(26, 26)
	moeda_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	moeda_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	moedas.add_child(moeda_icon)
	_lbl_moedas = UITheme.titulo("%d" % GameState.moedas, 30, UITheme.ACENTO, true)
	moedas.add_child(_lbl_moedas)
	linha.add_child(moedas)

	# botoes principais
	var acoes := UITheme.hbox(6)
	acoes.add_child(_botao_hud("LAB", "Abrir o laboratorio de bioestatistica", _abrir_lab, UITheme.INFO))
	acoes.add_child(_botao_hud("JOGOS", "Minigames curriculares", _abrir_minigames, UITheme.ROXO))
	acoes.add_child(_botao_hud("REVISTA", "Leitura critica de artigos", _abrir_revista, UITheme.ACENTO_2))
	acoes.add_child(_botao_hud("MANUAL", "Manual do jogo (F1)", _abrir_manual, UITheme.SUCESSO))
	acoes.add_child(_botao_hud("MENU", "Configuracoes", _abrir_menu, UITheme.BORDA_CLARA))
	linha.add_child(acoes)

	# ---------- botoes flutuantes de mapa ----------
	var lateral_wrap := MarginContainer.new()
	lateral_wrap.name = "LateralWrap"
	lateral_wrap.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	lateral_wrap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# ancoras RIGHT_WIDE deixam largura/altura zero: os offsets definem a area real
	lateral_wrap.offset_left = -76
	lateral_wrap.offset_right = -16
	lateral_wrap.offset_top = 84
	lateral_wrap.offset_bottom = 84 + 5 * 52
	lateral_wrap.add_theme_constant_override("margin_top", 0)
	lateral_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(lateral_wrap)
	var lateral := UITheme.vbox(6)
	lateral.name = "Lateral"
	lateral.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	lateral_wrap.add_child(lateral)
	lateral.add_child(_botao_mapa("+", func(): camera_ctrl._zoom_para(camera_ctrl.zoom_atual() * 1.25, TELA * 0.5), "Aproximar"))
	lateral.add_child(_botao_mapa("-", func(): camera_ctrl._zoom_para(camera_ctrl.zoom_atual() / 1.25, TELA * 0.5), "Afastar"))
	lateral.add_child(_botao_mapa("FIT", func(): camera_ctrl.enquadrar_tudo(), "Ver o mapa inteiro"))
	lateral.add_child(_botao_mapa("MAP", _ciclar_overlay, "Camada de dados"))
	lateral.add_child(_botao_mapa("HQ", func(): camera_ctrl.foco_vila(1, 1.15), "Ir para a Vila Central"))

	# ---------- barra inferior ----------
	var baixo := PanelContainer.new()
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0.09, 0.11, 0.15, 0.92)
	sb2.border_color = UITheme.BORDA
	sb2.border_width_top = 2
	sb2.content_margin_left = 18
	sb2.content_margin_right = 18
	sb2.content_margin_top = 10
	sb2.content_margin_bottom = 10
	baixo.add_theme_stylebox_override("panel", sb2)
	baixo.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	baixo.offset_top = -72
	baixo.offset_bottom = 0
	baixo.custom_minimum_size.y = 62
	hud.add_child(baixo)
	var lb := UITheme.hbox(14)
	baixo.add_child(lb)
	_card_vila = _criar_card_vila()
	lb.add_child(_card_vila)
	var esp2 := Control.new()
	esp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.add_child(esp2)
	_lbl_dica = UITheme.rotulo("Toque em uma vila do mapa para ver seus indicadores.", 14, UITheme.TEXTO_DIM)
	lb.add_child(_lbl_dica)


func _botao_hud(texto: String, dica: String, cb: Callable, cor: Color) -> Button:
	var b := Button.new()
	b.text = texto
	b.tooltip_text = dica
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_override("font", UITheme.titulo_font(true))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", cor)
	b.pressed.connect(cb)
	b.pressed.connect(func(): Audio.ui("clique"))
	return b


func _botao_mapa(texto: String, cb: Callable, dica: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.tooltip_text = dica
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(52, 46)
	b.add_theme_font_override("font", UITheme.titulo_font(true))
	b.add_theme_font_size_override("font_size", 13 if texto.length() > 1 else 18)
	b.pressed.connect(cb)
	b.pressed.connect(func(): Audio.ui("clique"))
	return b


func _criar_card_vila() -> PanelContainer:
	var p := UITheme.painel(Color(0.12, 0.15, 0.2, 0.9), UITheme.BORDA, 8, 8)
	var h := UITheme.hbox(12)
	p.add_child(h)
	var nome := Label.new()
	nome.name = "Nome"
	nome.text = "--"
	nome.add_theme_font_override("font", UITheme.titulo_font(true))
	nome.add_theme_font_size_override("font_size", 15)
	nome.add_theme_color_override("font_color", UITheme.ACENTO)
	h.add_child(nome)
	for par in [["Prev", "Prev", "prevalencia"], ["Rt", "Rt", "rt"],
			["Grav/Leito", "Grav/Leito", "leitos"], ["Vac", "Vac", "vac"]]:
		var v := UITheme.vbox(0)
		var val := Label.new()
		val.name = str(par[2])
		val.text = "--"
		val.add_theme_font_override("font", UITheme.titulo_font(true))
		val.add_theme_font_size_override("font_size", 16)
		val.tooltip_text = str(_DICAS_HUD.get(str(par[2]), ""))
		v.add_child(val)
		v.add_child(UITheme.rotulo(str(par[1]), 10, UITheme.TEXTO_FRACO))
		h.add_child(v)
	var abrir := UITheme.botao("Investigar", func(): _abrir_vila(_vila_sel))
	abrir.custom_minimum_size = Vector2(110, 34)
	abrir.add_theme_font_size_override("font_size", 13)
	h.add_child(abrir)
	return p


func _criar_modais() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			fechar_modal())
	hud.add_child(_dim)

	_modal_raiz = Control.new()
	_modal_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_raiz.visible = false
	_modal_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_modal_raiz)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_raiz.add_child(centro)

	_modal_painel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_PANEL
	sb.border_color = UITheme.BORDA_CLARA
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 22
	sb.shadow_offset = Vector2(0, 10)
	_modal_painel.add_theme_stylebox_override("panel", sb)
	centro.add_child(_modal_painel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	_modal_painel.add_child(v)

	# cabecalho
	var cab := PanelContainer.new()
	var sbc := StyleBoxFlat.new()
	sbc.bg_color = Color(0.12, 0.15, 0.2)
	sbc.border_color = UITheme.BORDA
	sbc.border_width_bottom = 2
	sbc.corner_radius_top_left = 12
	sbc.corner_radius_top_right = 12
	sbc.content_margin_left = 20
	sbc.content_margin_right = 12
	sbc.content_margin_top = 12
	sbc.content_margin_bottom = 12
	cab.add_theme_stylebox_override("panel", sbc)
	v.add_child(cab)
	var hc := UITheme.hbox(12)
	cab.add_child(hc)
	_modal_titulo = UITheme.titulo("Titulo", 22, UITheme.TEXTO, true)
	_modal_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.add_child(_modal_titulo)
	var fechar := UITheme.botao("X", fechar_modal)
	fechar.custom_minimum_size = Vector2(44, 40)
	fechar.add_theme_color_override("font_color", UITheme.PERIGO)
	hc.add_child(fechar)

	# corpo
	_modal_corpo = Control.new()
	_modal_corpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_modal_corpo)


## Remove todos os avisos flutuantes (usado pelas capturas de tela).
func limpar_toasts() -> void:
	if _toasts == null:
		return
	for c in _toasts.get_children():
		c.queue_free()


func _criar_toasts() -> void:
	_toasts = UITheme.vbox(6)
	_toasts.name = "Toasts"
	# canto inferior direito, acima da barra de status (nao cobre o X do modal)
	_toasts.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toasts.offset_left = -440
	_toasts.offset_right = -20
	_toasts.offset_top = -320
	_toasts.offset_bottom = -92
	_toasts.custom_minimum_size = Vector2(420, 0)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_toasts)


func _conectar() -> void:
	GameState.semana_avancou.connect(func(_se, _ano):
		_atualizar_hud()
		# Em 8x as semanas passam em fracao de segundo; sem throttle os ticks
		# de 0,6 s se sobrepoem e soam como um zumbido continuo.
		var agora := Time.get_ticks_msec() / 1000.0
		if agora - _ultimo_tick_semana >= 0.9:
			_ultimo_tick_semana = agora
			Audio.sfx("semana", -10.0))
	GameState.moedas_alteradas.connect(_ao_mudar_moedas)
	GameState.velocidade_alterada.connect(func(_v): _atualizar_botoes_velocidade())
	GameState.pausa_alterada.connect(func(_p): _atualizar_botoes_velocidade())
	GameState.doenca_alterada.connect(func(_id): _atualizar_hud())
	GameState.notificacao.connect(mostrar_toast)
	GameState.conquista_desbloqueada.connect(func(_id, titulo):
		mostrar_toast("Conquista: " + titulo, "conquista")
		Audio.sfx("descoberta", -4.0))
	GameState.partida_reiniciada.connect(func():
		_vila_sel = 0
		mundo.definir_overlay(GameState.overlay_ativo)
		_atualizar_hud())
	camera_ctrl.zoom_alterado.connect(_ao_mudar_zoom)
	Vilas.vila_atualizada.connect(func(_id): _atualizar_kpis())
	Epidemic.atualizado.connect(_ao_atualizar_epidemia)
	Epidemic.surto_iniciado.connect(func(vid, casos):
		mostrar_toast("Surto em %s (%d novos casos)" % [Vilas.get_vila(vid).get("nome", "?"), casos], "erro")
		Audio.sfx("alerta", -6.0))
	Epidemic.surto_encerrado.connect(func(vid):
		mostrar_toast("Surto controlado em %s" % Vilas.get_vila(vid).get("nome", "?"), "sucesso")
		Audio.sfx("sucesso", -8.0))


# ============================================================================
# HUD
# ============================================================================

func _atualizar_hud() -> void:
	_lbl_se.text = str(GameState.semana)
	_lbl_ano.text = "Ano %d" % GameState.ano
	_lbl_moedas.text = str(GameState.moedas)
	var info := GameState.info_doenca()
	_lbl_doenca.text = str(info.get("nome", "?"))
	_lbl_doenca.add_theme_color_override("font_color", Epidemic.cor_doenca())
	_atualizar_botoes_velocidade()
	_atualizar_kpis()


func _atualizar_kpis() -> void:
	var s := Epidemic.estatisticas_globais()
	var alertas := 0
	for v in Vilas.vilas:
		if bool(Epidemic.em_surto.get(int(v["id"]), false)):
			alertas += 1
	if alertas > 0:
		_lbl_alerta.text = "%d surto(s) ativo(s)" % alertas
		_lbl_alerta.add_theme_color_override("font_color", UITheme.PERIGO)
	else:
		_lbl_alerta.text = "situacao estavel"
		_lbl_alerta.add_theme_color_override("font_color", UITheme.SUCESSO)
	if _vila_sel > 0:
		_atualizar_card_vila(_vila_sel)


const _DICAS_HUD := {
	"prevalencia": "Infectados ativos / populacao viva da vila (0 a 100%).",
	"rt": "Numero reprodutivo efetivo: casos desta semana / casos da semana anterior, ajustado pelo tempo de geracao. Acima de 1 a epidemia cresce.",
	"leitos": "Pacientes graves (12% dos infectados) e leitos disponiveis. Quando graves > leitos ha superlotacao; a razao 30/10 e mais honesta que 300%.",
	"vac": "Proporcao de moradores com esquema vacinal completo ou parcial.",
}


func _atualizar_card_vila(id: int) -> void:
	var v := Vilas.get_vila(id)
	if v.is_empty():
		return
	var p := _card_vila.get_child(0) as HBoxContainer
	(p.get_node("Nome") as Label).text = str(v["nome"]).replace("Vila ", "")
	var ocup := Vilas.ocupacao_leitos(id)
	var lp := p.find_child("prevalencia", true, false) as Label
	var lr := p.find_child("rt", true, false) as Label
	var ll := p.find_child("leitos", true, false) as Label
	var lv := p.find_child("vac", true, false) as Label
	if lp != null:
		lp.text = "%.1f%%" % (Epidemic.prevalencia(id) * 100.0)
	if lr != null:
		var rt_v := Epidemic.rt(id)
		# sem casos ou sem historico suficiente o Rt nao e estimavel: mostrar "—"
		lr.text = "%.2f" % rt_v if rt_v > 0.0 else "—"
	if ll != null:
		var graves := float(Epidemic.infectados(id)) * 0.12
		var leitos := float(v.get("leitos", 0))
		ll.text = "%d/%d" % [int(round(graves)), int(leitos)]
		ll.add_theme_color_override("font_color",
			UITheme.PERIGO if ocup > 0.9 else UITheme.TEXTO)
	if lv != null:
		lv.text = "%d%%" % int(float(v["cobertura_vacinal"]) * 100.0)


func _atualizar_botoes_velocidade() -> void:
	if _btns_velocidade.is_empty():
		return
	var vals := [0.0, 0.5, 1.0, 3.0, 8.0]
	for i in range(_btns_velocidade.size()):
		var b := _btns_velocidade[i]
		var ativo: bool = is_equal_approx(float(vals[i]), GameState.velocidade)
		b.add_theme_color_override("font_color", UITheme.ACENTO if ativo else UITheme.TEXTO_DIM)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UITheme.BG_HOVER if ativo else UITheme.BG_CARD
		sb.border_color = UITheme.ACENTO if ativo else UITheme.BORDA
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		b.add_theme_stylebox_override("normal", sb)


func _atualizar_botoes_zoom() -> void:
	pass


func _definir_velocidade(v: float) -> void:
	GameState.definir_velocidade(v)


func _ciclar_overlay() -> void:
	var ordem := ["prevalencia", "incidencia", "vacinacao", "saneamento", "nenhum"]
	var i := ordem.find(GameState.overlay_ativo)
	GameState.overlay_ativo = ordem[(i + 1) % ordem.size()]
	mundo.definir_overlay(GameState.overlay_ativo)
	var nomes := {"prevalencia": "Prevalencia", "incidencia": "Incidencia",
		"vacinacao": "Cobertura vacinal", "saneamento": "Saneamento", "nenhum": "Sem camada"}
	mostrar_toast("Camada: %s" % nomes[GameState.overlay_ativo], "info")


func _ao_mudar_moedas(valor: int, delta: int) -> void:
	_lbl_moedas.text = str(valor)
	if delta != 0:
		var tw := create_tween()
		_lbl_moedas.pivot_offset = _lbl_moedas.size * 0.5
		tw.tween_property(_lbl_moedas, "scale", Vector2(1.25, 1.25), 0.12)
		tw.tween_property(_lbl_moedas, "scale", Vector2.ONE, 0.18)


func _ao_atualizar_epidemia() -> void:
	_atualizar_kpis()


func mostrar_toast(texto: String, tipo: String = "info") -> void:
	var cores := {"info": UITheme.INFO, "sucesso": UITheme.SUCESSO,
		"erro": UITheme.PERIGO, "conquista": UITheme.ACENTO}
	var cor: Color = cores.get(tipo, UITheme.INFO)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.13, 0.17, 0.96)
	sb.border_color = cor
	sb.border_width_left = 4
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var l := UITheme.paragrafo(texto, 15, cor)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(3.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.45)
	tw.tween_callback(p.queue_free)
	while _toasts.get_child_count() > 5:
		var velho := _toasts.get_child(0)
		_toasts.remove_child(velho)
		velho.queue_free()


# ============================================================================
# MODAIS
# ============================================================================

func abrir_modal(titulo: String, conteudo: Control, largura: int = 1180,
		altura: int = 760) -> void:
	Audio.sfx("abrir", -4.0)
	Audio.duck(-7.0)
	if conteudo is MinigameBase:
		Audio.tema_minigame((conteudo as MinigameBase).id_jogo)
	_modal_titulo.text = titulo
	if _modal_corpo.get_child_count() > 0:
		for c in _modal_corpo.get_children():
			c.queue_free()
	_modal_corpo.add_child(conteudo)
	conteudo.set_anchors_preset(Control.PRESET_FULL_RECT)
	var w := mini(largura, int(TELA.x) - 60)
	var h := mini(altura, int(TELA.y) - 70)
	_modal_painel.custom_minimum_size = Vector2(w, h)
	_modal_corpo.custom_minimum_size = Vector2(w - 8, h - 74)
	_modal_raiz.visible = true
	_dim.visible = true
	GameState.modal_aberto = true
	camera_ctrl.definir_bloqueio(true)


func fechar_modal(restaurar_audio: bool = true) -> void:
	if restaurar_audio:
		Audio.sfx("fechar", -5.0)
		Audio.duck(0.0)
		Audio.restaurar_exploracao(_vila_sel)
	_modal_raiz.visible = false
	_dim.visible = false
	GameState.modal_aberto = false
	camera_ctrl.definir_bloqueio(false)
	if _modal_corpo.get_child_count() > 0:
		for c in _modal_corpo.get_children():
			c.queue_free()


func _ao_tocar_mapa(vila_id: int, _pos: Vector2) -> void:
	if vila_id <= 0:
		return
	Audio.tocar_vila(vila_id)
	_vila_sel = vila_id
	_atualizar_card_vila(vila_id)
	_abrir_vila(vila_id)


# ============================================================================
# NAVEGACAO
# ============================================================================

func abrir_boas_vindas() -> void:
	var p := PanelBoasVindas.new(self)
	abrir_modal("StaTown", p, 1180, 730)


func _abrir_vila(id: int) -> void:
	if id <= 0:
		id = _vila_sel if _vila_sel > 0 else 1
	_vila_sel = id
	var p := PanelVila.new(self, id)
	abrir_modal("Vila - " + str(Vilas.get_vila(id).get("nome", "")), p, 1240, 800)


func _abrir_lab() -> void:
	var p := PanelBioLab.new(self)
	abrir_modal("Laboratorio de Bioestatistica", p, 1420, 830)


func _abrir_minigames() -> void:
	var p := PanelMinigames.new(self)
	abrir_modal("Desafios & Minigames", p, 1400, 820)


func _abrir_revista() -> void:
	var p := PanelRevista.new(self)
	abrir_modal("Revista Cientifica do Vale", p, 1240, 800)


## Abre o manual do usuario (docs/manual.html).
##
## No navegador o arquivo e copiado para a raiz do build e aberto em outra aba.
## No desktop, abre o HTML no navegador padrao. O SIGA continua existindo como
## tela interna de desenvolvimento/teste, mas nao e mais um botao do HUD.
func _abrir_manual() -> void:
	if OS.has_feature("web"):
		var js := Engine.get_singleton("JavaScriptBridge")
		if js != null:
			js.eval("""
				(function() {
					var w = window.open('manual.html', '_blank');
					if (w) { w.focus(); }
					else { window.location.href = 'manual.html'; }
				})();
			""", true)
			return
		# Sem a ponte JS (build web antiga ou navegador restrito), deixa o
		# proprio Godot abrir a aba; se falhar, o jogador ainda ve o aviso.
		if OS.shell_open("manual.html") == OK:
			return
		mostrar_toast("Nao foi possivel abrir o manual", "erro")
		return
	var caminho := ProjectSettings.globalize_path("res://docs/manual.html")
	if FileAccess.file_exists(caminho):
		OS.shell_open(caminho)
	else:
		mostrar_toast("Manual nao encontrado nesta build", "erro")


func _abrir_siga() -> void:
	var p := PanelSIGA.new(self)
	abrir_modal("Relatorio SIGA", p, 1180, 790)


func _abrir_menu() -> void:
	var p := PanelMenu.new(self)
	abrir_modal("Menu & Configuracoes", p, 980, 760)


func _abrir_troca_cenario() -> void:
	var p := PanelCenario.new(self)
	abrir_modal("Cenario epidemiologico", p, 1180, 800)


func _abrir_bayes() -> void:
	var p := PanelDrBayes.new(self)
	abrir_modal("Dr. Bayes - tutor critico", p, 1180, 780)


## Chamado pelos paineis para navegar entre telas.
func trocar_para(nome: String) -> void:
	fechar_modal(false)
	match nome:
		"lab": _abrir_lab()
		"minigames": _abrir_minigames()
		"revista": _abrir_revista()
		"siga": _abrir_siga()
		"menu": _abrir_menu()
		"cenario": _abrir_troca_cenario()
		"bayes": _abrir_bayes()
		"vila": _abrir_vila(_vila_sel)


## Ao aproximar o zoom, a vila sob o centro da tela assume a trilha e a ambiencia.
func _ao_mudar_zoom(z: float) -> void:
	if GameState.modal_aberto:
		return
	if z < 1.55:
		if _vila_zoom != 0:
			_vila_zoom = 0
			Audio.modo_mapa()
		return
	var id := _vila_no_centro()
	if id <= 0 or id == _vila_zoom:
		return
	_vila_zoom = id
	Audio.tocar_vila(id)


func _vila_no_centro() -> int:
	var centro: Vector2 = camera_ctrl.camera.global_position
	var melhor := 0
	var dist := 230.0
	for v in Vilas.vilas:
		var p: Vector2 = v["anchor"] * 16.0
		var d := p.distance_to(centro)
		if d < dist:
			dist = d
			melhor = int(v["id"])
	return melhor


func focar_vila(id: int, zoom: float = 1.2) -> void:
	_vila_sel = id
	_atualizar_card_vila(id)
	Audio.tocar_vila(id)
	camera_ctrl.foco_vila(id, zoom)


func animar_entrega(id: int) -> void:
	mundo.animar_entrega(id)


func animar_construcao(id: int, tipo: String) -> void:
	mundo.animar_construcao(id, tipo)


func mostrar_boas_vindas_de_novo() -> void:
	abrir_boas_vindas()
