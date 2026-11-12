extends Node
## UIKit - sistema de design do StaTown (tema + fabrica de widgets).
##
## Toda a interface e construida em codigo a partir daqui, para manter
## consistencia visual e permitir o alternador de tamanho de fonte (A / A+)
## sem duplicar cenas.
##
## Tipografia (3 papeis, 3 fontes):
##   Silkscreen  -> titulos, rotulos, indicadores numericos (pixel, digitos nitidos)
##   Rubik       -> corpo de texto e paragrafos (legivel em blocos longos)
##   VT323       -> codigo R/Python e console do Dr. Bayes (monoespacada)

# --- Paleta ----------------------------------------------------------------
const BG_DEEP := Color("#141a23")
const BG_PANEL := Color("#1d2531")
const BG_CARD := Color("#25303e")
const BG_HOVER := Color("#31404f")
const BG_SUNK := Color("#161d26")
const BORDA := Color("#3b4a5c")
const BORDA_CLARA := Color("#5a6d84")
const TEXTO := Color("#e9eff7")
const TEXTO_DIM := Color("#94a6bb")
const TEXTO_FRACO := Color("#6b7d92")
const ACENTO := Color("#ffc95c")      # BioMoedas / destaque
const ACENTO_2 := Color("#4fd1b4")    # saude / acerto
const PERIGO := Color("#e05a4c")
const INFO := Color("#54a9e0")
const SUCESSO := Color("#86cc63")
const ROXO := Color("#9b8cf0")

const FONTE_TITULO := "res://assets/fonts/Silkscreen-Regular.ttf"
const FONTE_TITULO_B := "res://assets/fonts/Silkscreen-Bold.ttf"
const FONTE_CORPO := "res://assets/fonts/Rubik[wght].ttf"
const FONTE_CODIGO := "res://assets/fonts/VT323-Regular.ttf"

const ESCALA_NORMAL := 1.0
const ESCALA_GRANDE := 1.16

var tema: Theme
var escala: float = ESCALA_NORMAL

var _f_titulo: FontFile
var _f_titulo_b: FontFile
var _f_corpo: FontFile
var _f_codigo: FontFile
var _variacoes: Dictionary = {}


func _ready() -> void:
	_f_titulo = load(FONTE_TITULO)
	_f_titulo_b = load(FONTE_TITULO_B)
	_f_corpo = load(FONTE_CORPO)
	_f_codigo = load(FONTE_CODIGO)
	ThemeDB.fallback_font = _f_corpo
	ThemeDB.fallback_font_size = _px(20)
	tema = construir_tema()


# ============================================================================
# TEMA
# ============================================================================

func _px(v: int) -> int:
	return int(round(float(v) * escala))


## Rubik em um peso especifico (fonte variavel).
func corpo(peso: int = 400) -> Font:
	var chave := "corpo_%d" % peso
	if _variacoes.has(chave):
		return _variacoes[chave]
	var fv := FontVariation.new()
	fv.base_font = _f_corpo
	fv.variation_opentype = {"wght": float(peso)}
	_variacoes[chave] = fv
	return fv


func titulo_font(negrito: bool = false) -> Font:
	return _f_titulo_b if negrito else _f_titulo


func codigo_font() -> Font:
	return _f_codigo


func _sb(cor: Color, borda: Color, raio: int = 8, largura_borda: int = 2,
		margem_h: int = 14, margem_v: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.border_color = borda
	sb.set_border_width_all(largura_borda)
	sb.set_corner_radius_all(raio)
	sb.content_margin_left = margem_h
	sb.content_margin_right = margem_h
	sb.content_margin_top = margem_v
	sb.content_margin_bottom = margem_v
	sb.anti_aliasing = true
	return sb


func construir_tema() -> Theme:
	var t := Theme.new()
	t.default_font = corpo(400)
	t.default_font_size = _px(20)

	# --- Label ---
	t.set_color("font_color", "Label", TEXTO)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("line_spacing", "Label", _px(4))

	# --- Button ---
	t.set_font("font", "Button", corpo(600))
	t.set_font_size("font_size", "Button", _px(18))
	t.set_color("font_color", "Button", TEXTO)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACENTO)
	t.set_color("font_disabled_color", "Button", TEXTO_FRACO)
	t.set_stylebox("normal", "Button", _sb(BG_CARD, BORDA, 8, 2, 16, 10))
	t.set_stylebox("hover", "Button", _sb(BG_HOVER, ACENTO, 8, 2, 16, 10))
	t.set_stylebox("pressed", "Button", _sb(BG_SUNK, ACENTO, 8, 2, 16, 10))
	t.set_stylebox("disabled", "Button", _sb(BG_SUNK, BORDA, 8, 2, 16, 10))
	t.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), ACENTO_2, 8, 2, 16, 10))

	# --- Panel / PanelContainer ---
	var painel := _sb(BG_PANEL, BORDA, 12, 2, 18, 16)
	painel.shadow_color = Color(0, 0, 0, 0.35)
	painel.shadow_size = 8
	painel.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "Panel", painel)
	t.set_stylebox("panel", "PanelContainer", painel)

	# --- LineEdit / TextEdit ---
	t.set_font("font", "LineEdit", corpo(400))
	t.set_font_size("font_size", "LineEdit", _px(18))
	t.set_color("font_color", "LineEdit", TEXTO)
	t.set_color("font_placeholder_color", "LineEdit", TEXTO_FRACO)
	t.set_color("caret_color", "LineEdit", ACENTO)
	t.set_stylebox("normal", "LineEdit", _sb(BG_SUNK, BORDA, 6, 2, 10, 8))
	t.set_stylebox("focus", "LineEdit", _sb(BG_SUNK, ACENTO, 6, 2, 10, 8))
	t.set_stylebox("read_only", "LineEdit", _sb(BG_DEEP, BORDA, 6, 2, 10, 8))

	# --- OptionButton ---
	t.set_font("font", "OptionButton", corpo(500))
	t.set_font_size("font_size", "OptionButton", _px(18))
	t.set_color("font_color", "OptionButton", TEXTO)
	t.set_stylebox("normal", "OptionButton", _sb(BG_CARD, BORDA, 8, 2, 14, 8))
	t.set_stylebox("hover", "OptionButton", _sb(BG_HOVER, ACENTO, 8, 2, 14, 8))
	t.set_stylebox("pressed", "OptionButton", _sb(BG_SUNK, ACENTO, 8, 2, 14, 8))
	t.set_stylebox("focus", "OptionButton", _sb(Color(0, 0, 0, 0), ACENTO_2, 8, 2, 14, 8))
	t.set_stylebox("panel", "PopupMenu", _sb(BG_CARD, BORDA_CLARA, 8, 2, 8, 8))
	t.set_font("font", "PopupMenu", corpo(500))
	t.set_font_size("font_size", "PopupMenu", _px(18))
	t.set_color("font_color", "PopupMenu", TEXTO)
	t.set_color("font_hover_color", "PopupMenu", ACENTO)
	t.set_stylebox("hover", "PopupMenu", _sb(BG_HOVER, BG_HOVER, 4, 0, 8, 6))

	# --- CheckBox / CheckButton ---
	t.set_font("font", "CheckBox", corpo(500))
	t.set_font_size("font_size", "CheckBox", _px(18))
	t.set_color("font_color", "CheckBox", TEXTO)
	t.set_color("font_hover_color", "CheckBox", ACENTO)
	t.set_stylebox("normal", "CheckBox", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, 6, 4))
	t.set_stylebox("hover", "CheckBox", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, 6, 4))
	t.set_stylebox("pressed", "CheckBox", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, 6, 4))

	# --- ScrollContainer / ScrollBar ---
	t.set_stylebox("panel", "ScrollContainer", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))
	var grab := _sb(BORDA_CLARA, BORDA_CLARA, 4, 0, 0, 0)
	grab.content_margin_left = 0
	grab.content_margin_right = 0
	var track := _sb(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 4, 0, 0, 0)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", _sb(ACENTO, ACENTO, 4, 0, 0, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _sb(ACENTO, ACENTO, 4, 0, 0, 0))
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "HScrollBar", grab)
	t.set_stylebox("grabber_highlight", "HScrollBar", _sb(ACENTO, ACENTO, 4, 0, 0, 0))
	t.set_stylebox("grabber_pressed", "HScrollBar", _sb(ACENTO, ACENTO, 4, 0, 0, 0))
	t.set_stylebox("scroll", "HScrollBar", track)

	# --- ProgressBar ---
	var pbg := _sb(BG_SUNK, BORDA, 6, 1, 0, 0)
	pbg.content_margin_top = 0
	t.set_stylebox("background", "ProgressBar", pbg)
	t.set_stylebox("fill", "ProgressBar", _sb(ACENTO_2, ACENTO_2, 6, 0, 0, 0))
	t.set_color("font_color", "ProgressBar", TEXTO)
	t.set_font_size("font_size", "ProgressBar", _px(15))

	# --- TabContainer ---
	t.set_font("font", "TabContainer", corpo(600))
	t.set_font_size("font_size", "TabContainer", _px(18))
	t.set_color("font_selected_color", "TabContainer", ACENTO)
	t.set_color("font_unselected_color", "TabContainer", TEXTO_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXTO)
	t.set_stylebox("panel", "TabContainer", _sb(BG_PANEL, BORDA, 10, 2, 14, 12))
	t.set_stylebox("tab_selected", "TabContainer", _sb(BG_CARD, ACENTO, 8, 2, 16, 8))
	t.set_stylebox("tab_unselected", "TabContainer", _sb(BG_DEEP, BORDA, 8, 2, 16, 8))
	t.set_stylebox("tab_hovered", "TabContainer", _sb(BG_HOVER, BORDA_CLARA, 8, 2, 16, 8))

	# --- Separator ---
	t.set_constant("separation", "HSeparator", _px(10))
	t.set_stylebox("separator", "HSeparator", _sb(BORDA, BORDA, 0, 0, 0, 0))
	var sep := StyleBoxLine.new()
	sep.color = BORDA
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	var sepv := StyleBoxLine.new()
	sepv.color = BORDA
	sepv.thickness = 2
	sepv.vertical = true
	t.set_stylebox("separator", "VSeparator", sepv)

	# --- Tooltip ---
	t.set_stylebox("panel", "TooltipPanel", _sb(BG_CARD, ACENTO, 6, 2, 10, 6))
	t.set_color("font_color", "TooltipLabel", TEXTO)
	t.set_font("font", "TooltipLabel", corpo(500))
	t.set_font_size("font_size", "TooltipLabel", _px(16))

	# --- ItemList (usado em seletores) ---
	t.set_font("font", "ItemList", corpo(400))
	t.set_font_size("font_size", "ItemList", _px(18))
	t.set_color("font_color", "ItemList", TEXTO)
	t.set_color("font_selected_color", "ItemList", ACENTO)
	t.set_stylebox("panel", "ItemList", _sb(BG_SUNK, BORDA, 8, 2, 6, 6))
	t.set_stylebox("selected", "ItemList", _sb(BG_HOVER, ACENTO, 4, 0, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", _sb(BG_HOVER, ACENTO, 4, 0, 4, 2))

	return t


func aplicar_escala(grande: bool) -> void:
	escala = ESCALA_GRANDE if grande else ESCALA_NORMAL
	tema = construir_tema()
	var raiz := get_tree().root
	if raiz:
		raiz.theme = tema


func aplicar_em(no: Control) -> void:
	if tema:
		no.theme = tema


# ============================================================================
# FABRICA DE WIDGETS
# ============================================================================

func titulo(texto: String, tamanho: int = 26, cor: Color = TEXTO,
		negrito: bool = true) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", titulo_font(negrito))
	l.add_theme_font_size_override("font_size", _px(tamanho))
	l.add_theme_color_override("font_color", cor)
	return l


func rotulo(texto: String, tamanho: int = 14, cor: Color = TEXTO_DIM) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", titulo_font(false))
	l.add_theme_font_size_override("font_size", _px(tamanho))
	l.add_theme_color_override("font_color", cor)
	return l


func paragrafo(texto: String, tamanho: int = 19, cor: Color = TEXTO) -> Label:
	var l := Label.new()
	l.text = texto
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", corpo(400))
	l.add_theme_font_size_override("font_size", _px(tamanho))
	l.add_theme_color_override("font_color", cor)
	l.add_theme_constant_override("line_spacing", _px(6))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func codigo(texto: String, tamanho: int = 17) -> Label:
	var l := Label.new()
	l.text = texto
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_override("font", codigo_font())
	l.add_theme_font_size_override("font_size", _px(tamanho))
	l.add_theme_color_override("font_color", Color("#a8e6a3"))
	l.add_theme_constant_override("line_spacing", _px(2))
	return l


func botao(texto: String, cb: Callable = Callable(), icone: Texture2D = null,
		cor: Color = BORDA) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	if icone:
		b.icon = icone
		b.expand_icon = false
	if cb.is_valid():
		b.pressed.connect(cb)
	# todo botao do jogo tem retorno sonoro (o AudioManager ignora se ainda nao existe)
	b.pressed.connect(func(): Audio.ui("clique"))
	if cor != BORDA:
		b.add_theme_stylebox_override("normal", _sb(BG_CARD, cor, 8, 2, 16, 10))
		b.add_theme_stylebox_override("hover", _sb(BG_HOVER, cor.lightened(0.2), 8, 2, 16, 10))
		b.add_theme_stylebox_override("pressed", _sb(BG_SUNK, cor, 8, 2, 16, 10))
	b.custom_minimum_size.y = _px(44)
	return b


func botao_icone(icone: Texture2D, cb: Callable = Callable(), dica: String = "") -> Button:
	var b := Button.new()
	b.icon = icone
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = dica
	if cb.is_valid():
		b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(_px(46), _px(46))
	return b


func painel(cor: Color = BG_PANEL, borda: Color = BORDA, raio: int = 12,
		margem: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _sb(cor, borda, raio, 2, margem, margem)
	p.add_theme_stylebox_override("panel", sb)
	return p


func card(titulo_txt: String = "", cor_borda: Color = BORDA) -> PanelContainer:
	var p := painel(BG_CARD, cor_borda, 10, 14)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _px(8))
	v.name = "Conteudo"
	p.add_child(v)
	if titulo_txt != "":
		v.add_child(rotulo(titulo_txt.to_upper(), 14, ACENTO))
	return p


func conteudo(p: PanelContainer) -> VBoxContainer:
	return p.get_node("Conteudo") as VBoxContainer


func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", _px(sep))
	return h


func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _px(sep))
	return v


func grade(colunas: int, sep_h: int = 12, sep_v: int = 10) -> GridContainer:
	var g := GridContainer.new()
	g.columns = colunas
	g.add_theme_constant_override("h_separation", _px(sep_h))
	g.add_theme_constant_override("v_separation", _px(sep_v))
	return g


func espacador(altura: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = _px(altura)
	return c


func separador() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", _px(12))
	return s


func esticar(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Etiqueta compacta com fundo colorido (usada para status, Rt, alertas).
func badge(texto: String, cor: Color = ACENTO, tamanho: int = 13) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(cor.r, cor.g, cor.b, 0.16)
	sb.border_color = cor
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = _px(8)
	sb.content_margin_right = _px(8)
	sb.content_margin_top = _px(2)
	sb.content_margin_bottom = _px(2)
	p.add_theme_stylebox_override("panel", sb)
	var l := rotulo(texto, tamanho, cor)
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


## Bloco de indicador: valor grande + rotulo pequeno.
func kpi(valor: String, rotulo_txt: String, cor: Color = TEXTO,
		tamanho: int = 34, dica: String = "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _px(2))
	if dica != "":
		v.tooltip_text = dica
		v.mouse_filter = Control.MOUSE_FILTER_PASS
	var lv := Label.new()
	lv.text = valor
	lv.add_theme_font_override("font", titulo_font(true))
	lv.add_theme_font_size_override("font_size", _px(tamanho))
	lv.add_theme_color_override("font_color", cor)
	v.add_child(lv)
	v.add_child(rotulo(rotulo_txt, 12, TEXTO_DIM))
	return v


func campo(titulo_txt: String, valor: String, dica: String = "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _px(2))
	v.add_child(rotulo(titulo_txt.to_upper(), 12, TEXTO_FRACO))
	var l := Label.new()
	l.text = valor
	l.add_theme_font_override("font", corpo(500))
	l.add_theme_font_size_override("font_size", _px(19))
	l.add_theme_color_override("font_color", TEXTO)
	if dica != "":
		l.tooltip_text = dica
	v.add_child(l)
	return v


## Linha "rotulo ....... valor" usada em tabelas de medidas e saidas de teste.
func linha_medida(rotulo_txt: String, valor_txt: String, cor: Color = TEXTO) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", _px(8))
	var l := rotulo(rotulo_txt, 13, TEXTO_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	var v := Label.new()
	v.text = valor_txt
	v.add_theme_font_override("font", corpo(600))
	v.add_theme_font_size_override("font_size", _px(14))
	v.add_theme_color_override("font_color", cor)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


func barra(valor: float, maximo: float = 1.0, cor: Color = ACENTO_2,
		altura: int = 10) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = maxf(maximo, 0.0001)
	b.value = clampf(valor, 0.0, maximo)
	b.show_percentage = false
	b.custom_minimum_size.y = _px(altura)
	var fill := _sb(cor, cor, 5, 0, 0, 0)
	b.add_theme_stylebox_override("fill", fill)
	var bg := _sb(BG_SUNK, BORDA, 5, 1, 0, 0)
	b.add_theme_stylebox_override("background", bg)
	return b


func caixa_texto(placeholder: String, largura: int = 120) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(_px(largura), _px(40))
	return e


func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Um filho de ScrollContainer so ocupa a largura toda se pedir EXPAND;
	# sem isso ele encolhe ate a largura minima (botoes com autowrap viram
	# uma coluna de 8 px). Garantimos o flag em todo filho que entrar.
	s.child_entered_tree.connect(func(c: Node) -> void:
		if c is Control:
			(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL)
	return s


## Cria uma linha de tabela com colunas de largura proporcional.
func linha_tabela(valores: Array, larguras: Array, cores: Array = [],
		tamanho: int = 17, fonte_titulo_linha: bool = false) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", _px(8))
	for i in range(valores.size()):
		var l := Label.new()
		l.text = str(valores[i])
		l.clip_text = true
		l.add_theme_font_override("font", titulo_font(fonte_titulo_linha) if fonte_titulo_linha else corpo(400))
		l.add_theme_font_size_override("font_size", _px(tamanho))
		l.add_theme_color_override("font_color", cores[i] if i < cores.size() else TEXTO)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = float(larguras[i]) if i < larguras.size() else 1.0
		h.add_child(l)
	return h


func overlay_cor(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.18)


func cor_por_valor(v: float, escala: Array = []) -> Color:
	# gradiente verde -> ambar -> vermelho para prevalencia/risco
	var paradas: Array = escala
	if paradas.is_empty():
		paradas = [[0.0, SUCESSO], [0.05, ACENTO], [0.15, Color("#e08a4c")], [0.30, PERIGO]]
	var anterior: Array = paradas[0]
	for p in paradas:
		if v <= float(p[0]):
			var t := 0.0
			if float(p[0]) > float(anterior[0]):
				t = (v - float(anterior[0])) / (float(p[0]) - float(anterior[0]))
			return (anterior[1] as Color).lerp(p[1], clampf(t, 0.0, 1.0))
		anterior = p
	return paradas[paradas.size() - 1][1]
