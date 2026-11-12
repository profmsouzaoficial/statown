class_name TabelaDados
extends PanelContainer
## Tabela de dados compacta: cabecalho fixo, linhas zebradas, rolagem vertical
## e alinhamento numerico a direita.

var colunas: Array = []          # [{id, rotulo, largura, alinhamento}]
var linhas: Array = []           # Array de Array (na ordem das colunas)
var _grade: GridContainer
var _scroll: ScrollContainer
var _cor_zebra := Color(1, 1, 1, 0.035)
var limite_linhas := 300


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.12, 0.6)
	sb.border_color = UITheme.BORDA
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 6
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	_scroll = UITheme.scroll()
	add_child(_scroll)
	_grade = GridContainer.new()
	_grade.add_theme_constant_override("h_separation", 10)
	_grade.add_theme_constant_override("v_separation", 2)
	_grade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grade)


func definir(cols: Array, rows: Array) -> void:
	colunas = cols
	linhas = rows
	_redesenhar()


func _redesenhar() -> void:
	for c in _grade.get_children():
		c.queue_free()
	_grade.columns = maxi(colunas.size(), 1)
	# cabecalho
	for col in colunas:
		var l := Label.new()
		l.text = str(col.get("rotulo", col.get("id", ""))).to_upper()
		l.add_theme_font_override("font", UITheme.titulo_font(true))
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", UITheme.ACENTO)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = float(col.get("largura", 1.0))
		l.horizontal_alignment = _alinhamento(col)
		_grade.add_child(l)
	var n := mini(linhas.size(), limite_linhas)
	for i in range(n):
		var linha: Array = linhas[i]
		var cor_linha := UITheme.TEXTO if i % 2 == 0 else UITheme.TEXTO_DIM
		for j in range(colunas.size()):
			var l2 := Label.new()
			var v = linha[j] if j < linha.size() else ""
			l2.text = str(v)
			l2.add_theme_font_override("font", UITheme.corpo(400))
			l2.add_theme_font_size_override("font_size", 13)
			l2.add_theme_color_override("font_color", cor_linha)
			l2.clip_text = true
			l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l2.size_flags_stretch_ratio = float(colunas[j].get("largura", 1.0))
			l2.horizontal_alignment = _alinhamento(colunas[j])
			_grade.add_child(l2)


func _alinhamento(col: Dictionary) -> int:
	if col.has("alinhamento"):
		return int(col["alinhamento"])
	if str(col.get("tipo", "")) == "num":
		return HORIZONTAL_ALIGNMENT_RIGHT
	return HORIZONTAL_ALIGNMENT_LEFT
