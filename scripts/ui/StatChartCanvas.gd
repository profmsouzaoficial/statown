class_name StatChartCanvas
extends Control
## StatChartCanvas - graficos estatisticos desenhados em canvas.
##
## Um unico controle cobre os tipos usados no jogo: linha/serie temporal,
## barras verticais e horizontais, histograma, boxplot, dispersao com reta de
## regressao, curva ROC e grafico de pontos com faixa (IC). Os eixos usam
## "numeros redondos" (1-2-2,5-5) e os rotulos seguem a fonte do tema.
##
## Uso:
##   var g := StatChartCanvas.new()
##   g.titulo = "Prevalencia"
##   g.definir_linhas([{nome="Vila 17", cor=..., pontos=...}])
##   add_child(g)

var tipo := "linha"
var titulo := ""
var subtitulo := ""
var eixo_x := ""
var eixo_y := ""
var series: Array = []              # [{nome, cor, pontos, tracejado}]
var categorias: Array = []          # barras
var valores: Array = []             # barras
var cores_barras: Array = []
var caixas: Array = []              # boxplot [{rotulo,min,q1,med,q3,max}]
var pontos_extra: Array = []        # [{p,cor,raio,rotulo}]
var linhas_ref: Array = []          # [{y, cor, rotulo}]
var faixa_ic: Array = []            # [{pontos_inf, pontos_sup, cor}] para linha
var compacto := false
var mostrar_legenda := true
var mostrar_grade := true
var interativo := true
var eixo_y_min := NAN
var eixo_y_max := NAN
var eixo_x_min := NAN
var eixo_x_max := NAN
var formato_y := "auto"             # "auto" | "pct" | "int" | "dec"
var casas_decimais := 2

var _hover: Vector2 = Vector2(-9999, -9999)
var _plot := Rect2()
var _dados_plot: Array = []

const MARGEM_ESQ := 62.0
const MARGEM_DIR := 16.0
const MARGEM_TOPO := 46.0
const MARGEM_BASE := 40.0


func _ready() -> void:
	# nao sobrescrever o tamanho minimo que o painel ja definiu (ex.: 230 de altura)
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 240.0),
		maxf(custom_minimum_size.y, 160.0))
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = false
	if interativo:
		mouse_exited.connect(func():
			_hover = Vector2(-9999, -9999)
			queue_redraw())
	set_process(false)


# ============================================================================
# API
# ============================================================================

func limpar() -> void:
	series = []
	categorias = []
	valores = []
	cores_barras = []
	caixas = []
	pontos_extra = []
	linhas_ref = []
	faixa_ic = []
	queue_redraw()


func definir_linhas(novas_series: Array, rot_x: String = "", rot_y: String = "") -> void:
	tipo = "linha"
	series = novas_series
	eixo_x = rot_x
	eixo_y = rot_y
	queue_redraw()


func definir_barras(rotulos: Array, val: Array, cores: Array = [], rot_y: String = "") -> void:
	tipo = "barras"
	categorias = rotulos
	valores = val
	cores_barras = cores
	eixo_y = rot_y
	queue_redraw()


func definir_barras_h(rotulos: Array, val: Array, cores: Array = []) -> void:
	tipo = "barras_h"
	categorias = rotulos
	valores = val
	cores_barras = cores
	queue_redraw()


func definir_histograma(centros: Array, alturas, rot_x: String = "") -> void:
	tipo = "histograma"
	categorias = centros
	valores = alturas
	eixo_x = rot_x
	queue_redraw()


func definir_boxplot(lista: Array, rot_y: String = "") -> void:
	tipo = "boxplot"
	caixas = lista
	eixo_y = rot_y
	# eixo x do boxplot e categorico: os rotulos dos grupos ja saem sob cada caixa
	eixo_x = ""
	queue_redraw()


func definir_dispersao(pts: PackedVector2Array, rot_x: String = "", rot_y: String = "") -> void:
	tipo = "dispersao"
	series = [{"nome": "dados", "cor": UITheme.INFO, "pontos": pts}]
	eixo_x = rot_x
	eixo_y = rot_y
	queue_redraw()


func definir_roc(pts: PackedVector2Array, auc: float = NAN) -> void:
	tipo = "roc"
	series = [{"nome": "ROC", "cor": UITheme.ACENTO, "pontos": pts}]
	subtitulo = "AUC = %.3f" % auc if not is_nan(auc) else ""
	eixo_x = "1 - especificidade"
	eixo_y = "sensibilidade"
	queue_redraw()


func adicionar_reta(b0: float, b1: float, cor: Color = UITheme.ACENTO,
		rotulo: String = "") -> void:
	var xmin := _min_x()
	var xmax := _max_x()
	var pts := PackedVector2Array([Vector2(xmin, b0 + b1 * xmin), Vector2(xmax, b0 + b1 * xmax)])
	series.append({"nome": rotulo, "cor": cor, "pontos": pts, "tracejado": true})
	queue_redraw()


func adicionar_ponto(p: Vector2, cor: Color = UITheme.ACENTO, raio: float = 5.0,
		rotulo: String = "") -> void:
	pontos_extra.append({"p": p, "cor": cor, "raio": raio, "rotulo": rotulo})
	queue_redraw()


func adicionar_linha_ref(y: float, cor: Color = UITheme.PERIGO, rotulo: String = "") -> void:
	linhas_ref.append({"y": y, "cor": cor, "rotulo": rotulo})
	queue_redraw()


# ============================================================================
# DESENHO
# ============================================================================

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	_draw_fundo(r)
	var topo := MARGEM_TOPO if titulo != "" else 10.0
	_plot = Rect2(MARGEM_ESQ, topo, maxf(size.x - MARGEM_ESQ - MARGEM_DIR, 10.0),
		maxf(size.y - topo - MARGEM_BASE, 10.0))
	if compacto:
		_plot = Rect2(8, 8, maxf(size.x - 16, 10.0), maxf(size.y - 16, 10.0))
	_dados_plot = []
	match tipo:
		"linha": _draw_linhas()
		"barras": _draw_barras(false)
		"barras_h": _draw_barras(true)
		"histograma": _draw_histograma()
		"boxplot": _draw_boxplot()
		"dispersao": _draw_dispersao()
		"roc": _draw_roc()
		_: _draw_vazio("sem dados")
	_draw_hover()


func _draw_fundo(r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.13, 0.55)
	sb.border_color = UITheme.BORDA
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, r)
	if titulo != "":
		var f := UITheme.titulo_font(true)
		var cor := UITheme.TEXTO
		draw_string(f, Vector2(14, 26), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cor)
		if subtitulo != "":
			var w := f.get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(UITheme.corpo(400), Vector2(22 + w, 26), subtitulo,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXTO_DIM)


func _draw_vazio(msg: String) -> void:
	draw_string(UITheme.corpo(400), _plot.get_center() - Vector2(30, 0), msg,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXTO_FRACO)


func _min_x() -> float:
	if not is_nan(eixo_x_min):
		return eixo_x_min
	var mn := INF
	for s in series:
		for p in s["pontos"]:
			mn = minf(mn, p.x)
	for c in caixas:
		pass
	return 0.0 if mn == INF else mn


func _max_x() -> float:
	if not is_nan(eixo_x_max):
		return eixo_x_max
	var mx := -INF
	for s in series:
		for p in s["pontos"]:
			mx = maxf(mx, p.x)
	return 1.0 if mx == -INF else mx


func _intervalo_y() -> Vector2:
	if not is_nan(eixo_y_min) and not is_nan(eixo_y_max):
		return Vector2(eixo_y_min, eixo_y_max)
	var mn := INF
	var mx := -INF
	for s in series:
		for p in s["pontos"]:
			mn = minf(mn, p.y)
			mx = maxf(mx, p.y)
	for v in valores:
		mn = minf(mn, float(v))
		mx = maxf(mx, float(v))
	for c in caixas:
		mn = minf(mn, float(c["min"]))
		mx = maxf(mx, float(c["max"]))
	for l in linhas_ref:
		mn = minf(mn, float(l["y"]))
		mx = maxf(mx, float(l["y"]))
	if mn == INF:
		return Vector2(0.0, 1.0)
	var span := mx - mn
	if span < 0.0001:
		var pad := maxf(absf(mx) * 0.1, 1.0)
		return Vector2(mn - pad, mx + pad)
	var pad2 := span * 0.08
	return Vector2(mn - pad2, mx + pad2)


func _mapa(p: Vector2, xi: Vector2, yi: Vector2) -> Vector2:
	var fx := 0.5 if xi.y - xi.x == 0.0 else (p.x - xi.x) / (xi.y - xi.x)
	var fy := 0.5 if yi.y - yi.x == 0.0 else (p.y - yi.x) / (yi.y - yi.x)
	return Vector2(_plot.position.x + fx * _plot.size.x,
		_plot.position.y + _plot.size.y - fy * _plot.size.y)


func _passo_grade(mn: float, mx: float, alvo: int = 5) -> float:
	var bruto := (mx - mn) / float(maxi(alvo, 1))
	if bruto <= 0.0:
		return 1.0
	var mag := pow(10.0, floor(log(bruto) / log(10.0)))
	var n := bruto / mag
	var passo := 1.0
	if n > 5.0: passo = 10.0
	elif n > 2.5: passo = 5.0
	elif n > 2.0: passo = 2.5
	elif n > 1.0: passo = 2.0
	return passo * mag


## Quantas casas decimais o passo da grade exige para nao repetir rotulos.
func _casas_do_passo(passo: float) -> int:
	if passo <= 0.0:
		return 0
	# numero de casas decimais que representa o passo exatamente (2,5 -> 1; 0,02 -> 2)
	for d in range(0, 5):
		var escala := pow(10.0, d)
		if absf(passo * escala - round(passo * escala)) < 0.000001:
			return d
	return 4


## Formata um valor de tick de eixo com a precisao do passo (evita "0,1%" repetido).
func _fmt_eixo(v: float, casas: int) -> String:
	if absf(v) < 0.0000001:
		return "0"
	match formato_y:
		"pct":
			return ("%." + str(maxi(casas, 1)) + "f%%") % (v * 100.0)
		"int":
			return ("%." + str(casas) + "f") % v
		"dec":
			return ("%." + str(maxi(casas, casas_decimais)) + "f") % v
	if absf(v) >= 100000.0:
		return "%.0fk" % (v / 1000.0)
	if absf(v) >= 10.0 and casas == 0:
		return "%.0f" % v
	return String.num(v, maxi(casas, 1))


func _fmt(v: float, eixo: bool = false) -> String:
	if absf(v) < 0.0005:
		return "0"
	match formato_y:
		"pct": return "%.1f%%" % (v * 100.0)
		"int": return "%d" % int(round(v))
		"dec": return ("%." + str(casas_decimais) + "f") % v
	if absf(v) >= 100000.0:
		return "%.0fk" % (v / 1000.0)
	if absf(v) >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	if eixo and absf(v) >= 10.0:
		return "%.0f" % v
	if absf(v) < 1.0 and v != 0.0:
		if absf(v) < 0.001:
			return String.num_scientific(v)
		return String.num(v, 3)
	return "%.1f" % v if eixo else String.num(v, 3)


func _draw_eixos(xi: Vector2, yi: Vector2, rot: bool = true, ticks_x: bool = true) -> void:
	if compacto:
		return
	var f := UITheme.corpo(500)
	var ff := UITheme.titulo_font(false)
	# grade horizontal
	if mostrar_grade:
		var passo := _passo_grade(yi.x, yi.y, 5)
		var dec := _casas_do_passo(passo)
		var v := ceilf(yi.x / passo) * passo
		while v <= yi.y + 0.0001:
			var p := _mapa(Vector2(xi.x, v), xi, yi)
			draw_line(Vector2(_plot.position.x, p.y), Vector2(_plot.end.x, p.y),
				Color(1, 1, 1, 0.07), 1.0)
			draw_string(f, Vector2(6, p.y + 4), _fmt_eixo(v, dec), HORIZONTAL_ALIGNMENT_RIGHT,
				MARGEM_ESQ - 12.0, 12, UITheme.TEXTO_FRACO)
			v += passo
	# eixos
	draw_line(Vector2(_plot.position.x, _plot.position.y),
		Vector2(_plot.position.x, _plot.end.y), UITheme.BORDA_CLARA, 1.5)
	draw_line(Vector2(_plot.position.x, _plot.end.y),
		Vector2(_plot.end.x, _plot.end.y), UITheme.BORDA_CLARA, 1.5)
	if not rot:
		return
	# ticks x
	if not ticks_x:
		if eixo_x != "":
			draw_string(ff, Vector2(_plot.get_center().x - 70, size.y - 8), eixo_x,
				HORIZONTAL_ALIGNMENT_CENTER, 140, 11, UITheme.TEXTO_DIM)
		return
	var passox := _passo_grade(xi.x, xi.y, 6)
	var decx := _casas_do_passo(passox)
	var vx := ceilf(xi.x / passox) * passox
	while vx <= xi.y + 0.0001:
		var p2 := _mapa(Vector2(vx, yi.x), xi, yi)
		draw_line(Vector2(p2.x, _plot.end.y), Vector2(p2.x, _plot.end.y + 4), UITheme.BORDA_CLARA, 1.0)
		# o eixo x nao herda o formato do y (semanas nao sao porcentagem)
		var rot_tick := String.num(vx, decx)
		draw_string(f, Vector2(p2.x - 24, _plot.end.y + 18), rot_tick,
			HORIZONTAL_ALIGNMENT_CENTER, 48, 12, UITheme.TEXTO_FRACO)
		vx += passox
	if eixo_x != "":
		draw_string(ff, Vector2(_plot.get_center().x - 70, size.y - 8), eixo_x,
			HORIZONTAL_ALIGNMENT_CENTER, 140, 11, UITheme.TEXTO_DIM)
	_draw_rotulo_y()


## Rotulo do eixo y girado 90 graus (evita colidir com o titulo do grafico).
func _draw_rotulo_y() -> void:
	if eixo_y == "" or compacto:
		return
	var ff := UITheme.titulo_font(false)
	var larg := ff.get_string_size(eixo_y, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_set_transform(Vector2(12.0, _plot.get_center().y), -PI * 0.5, Vector2.ONE)
	draw_string(ff, Vector2(-larg * 0.5, 4.0), eixo_y,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXTO_DIM)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_legenda() -> void:
	if not mostrar_legenda or series.size() < 2 or compacto:
		return
	var f := UITheme.corpo(500)
	var x := _plot.position.x + 6
	var y := _plot.position.y + 12
	for s in series:
		var cor: Color = s.get("cor", UITheme.INFO)
		draw_line(Vector2(x, y - 4), Vector2(x + 14, y - 4), cor, 3.0)
		var nome := str(s.get("nome", ""))
		draw_string(f, Vector2(x + 18, y), nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXTO_DIM)
		x += 26 + f.get_string_size(nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x


func _draw_linhas() -> void:
	if series.is_empty():
		_draw_vazio("sem serie")
		return
	# Uma serie com 1 ponto nao tem curva: mostrar mensagem e melhor que um eixo
	# de -100% a 100% (foi o que aparecia na SE 1 antes de a simulacao avancar).
	var tem_curva := false
	for s0 in series:
		if (s0["pontos"] as PackedVector2Array).size() >= 2:
			tem_curva = true
	if not tem_curva:
		_draw_vazio("avance a simulacao para ver a curva")
		return
	var xi := Vector2(_min_x(), _max_x())
	var yi := _intervalo_y()
	if xi.y <= xi.x:
		xi.y = xi.x + 1.0
	_draw_eixos(xi, yi)
	for i in range(_plot.size.x):
		pass
	for s in series:
		var pts: PackedVector2Array = s["pontos"]
		if pts.size() < 2:
			continue
		var cor: Color = s.get("cor", UITheme.INFO)
		var tracejado: bool = s.get("tracejado", false)
		var ant := _mapa(pts[0], xi, yi)
		for k in range(1, pts.size()):
			var cur := _mapa(pts[k], xi, yi)
			if tracejado:
				_draw_tracejada(ant, cur, cor, 2.0)
			else:
				draw_line(ant, cur, cor, 2.4, true)
			ant = cur
		if pts.size() <= 60:
			for p in pts:
				draw_circle(_mapa(p, xi, yi), 2.2, cor)
	# faixas de IC
	for fx in faixa_ic:
		var inf: PackedVector2Array = fx["inf"]
		var sup: PackedVector2Array = fx["sup"]
		var cor2: Color = fx.get("cor", UITheme.INFO)
		if inf.size() == sup.size() and inf.size() > 1:
			var poli := PackedVector2Array()
			for p in inf:
				poli.append(_mapa(p, xi, yi))
			for k in range(sup.size() - 1, -1, -1):
				poli.append(_mapa(sup[k], xi, yi))
			draw_colored_polygon(poli, Color(cor2.r, cor2.g, cor2.b, 0.16))
	for e in pontos_extra:
		var p2 := _mapa(e["p"], xi, yi)
		draw_circle(p2, float(e.get("raio", 5.0)) + 3.0, Color(0, 0, 0, 0.5))
		draw_circle(p2, float(e.get("raio", 5.0)), e.get("cor", UITheme.ACENTO))
	for l in linhas_ref:
		var y := _mapa(Vector2(xi.x, float(l["y"])), xi, yi).y
		_draw_tracejada(Vector2(_plot.position.x, y), Vector2(_plot.end.x, y), l["cor"], 1.5)
		if str(l.get("rotulo", "")) != "":
			draw_string(UITheme.corpo(500), Vector2(_plot.end.x - 90, y - 4),
				str(l["rotulo"]), HORIZONTAL_ALIGNMENT_RIGHT, 90, 11, l["cor"])
	_draw_legenda()
	if interativo:
		_dados_plot = []
		for s in series:
			for p in s["pontos"]:
				_dados_plot.append({"pos": _mapa(p, xi, yi), "p": p, "nome": str(s.get("nome", "")),
					"cor": s.get("cor", UITheme.INFO)})


func _draw_tracejada(a: Vector2, b: Vector2, cor: Color, larg: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.5:
		return
	var dir := d / L
	var t := 0.0
	while t < L:
		var fim := minf(t + 6.0, L)
		draw_line(a + dir * t, a + dir * fim, cor, larg)
		t += 10.0


func _draw_barras(horizontal: bool) -> void:
	if valores.is_empty():
		_draw_vazio("sem dados")
		return
	var mx := 0.0
	for v in valores:
		mx = maxf(mx, float(v))
	if not is_nan(eixo_y_max):
		mx = eixo_y_max
	# Contagem inteira (casos, obitos, leitos) nao tem 0,0001: sem isso, uma
	# serie toda zerada gerava eixo 0..0.0002 com rotulos repetidos.
	if formato_y == "int":
		mx = maxf(mx, 1.0)
	else:
		mx = maxf(mx, 0.0001)
	var n := valores.size()
	if horizontal:
		var alt := _plot.size.y / float(n)
		for i in range(n):
			var v := float(valores[i])
			var cor: Color = cores_barras[i] if i < cores_barras.size() else UITheme.INFO
			var w := (v / mx) * (_plot.size.x - 120.0)
			var y := _plot.position.y + i * alt + alt * 0.16
			var rr := Rect2(_plot.position.x, y, maxf(w, 1.0), alt * 0.68)
			draw_rect(rr, cor)
			draw_rect(rr, Color(1, 1, 1, 0.15), false, 1.0)
			draw_string(UITheme.corpo(500), Vector2(_plot.end.x - 116, y + alt * 0.5 + 4),
				str(categorias[i]) if i < categorias.size() else "", HORIZONTAL_ALIGNMENT_RIGHT,
				112, 12, UITheme.TEXTO_DIM)
			draw_string(UITheme.titulo_font(false), Vector2(rr.end.x + 6, y + alt * 0.5 + 4),
				_fmt(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXTO)
		return
	var larg := _plot.size.x / float(n)
	for i in range(n):
		var v2 := float(valores[i])
		var cor2: Color = cores_barras[i] if i < cores_barras.size() else UITheme.INFO
		var h := (v2 / mx) * _plot.size.y
		var x := _plot.position.x + i * larg + larg * 0.14
		var rr2 := Rect2(x, _plot.end.y - h, larg * 0.72, maxf(h, 1.0))
		draw_rect(rr2, cor2)
		draw_rect(rr2, Color(1, 1, 1, 0.16), false, 1.0)
		if n <= 24:
			var rot := str(categorias[i]) if i < categorias.size() else ""
			if rot.length() > 9:
				rot = rot.substr(0, 8) + "."
			draw_string(UITheme.corpo(500), Vector2(x - 10, _plot.end.y + 16), rot,
				HORIZONTAL_ALIGNMENT_CENTER, larg * 0.72 + 20, 11, UITheme.TEXTO_DIM)
	# eixo y
	var passo := _passo_grade(0.0, mx, 4)
	if formato_y == "int" and passo < 1.0:
		passo = 1.0
	var casas_y := 0 if formato_y == "int" else _casas_do_passo(passo)
	var v3 := 0.0
	while v3 <= mx + 0.0001:
		var yy := _plot.end.y - (v3 / mx) * _plot.size.y
		draw_line(Vector2(_plot.position.x, yy), Vector2(_plot.end.x, yy), Color(1, 1, 1, 0.07), 1.0)
		draw_string(UITheme.corpo(500), Vector2(6, yy + 4), _fmt_eixo(v3, casas_y),
			HORIZONTAL_ALIGNMENT_RIGHT, MARGEM_ESQ - 12.0, 12, UITheme.TEXTO_FRACO)
		v3 += passo
	_draw_rotulo_y()


func _draw_histograma() -> void:
	if valores.is_empty():
		return
	var xi := Vector2(float(categorias[0]), float(categorias[categorias.size() - 1]))
	if xi.y <= xi.x:
		xi.y = xi.x + 1.0
	var yi := Vector2(0.0, 0.0)
	for v in valores:
		yi.y = maxf(yi.y, float(v))
	_draw_eixos(xi, yi)
	var n := valores.size()
	var passo_x := (xi.y - xi.x) / maxf(float(n - 1), 1.0)
	var larg := (_plot.size.x / maxf(float(n), 1.0)) * 0.88
	for i in range(n):
		var v := float(valores[i])
		var h := (v / maxf(yi.y, 0.0001)) * _plot.size.y
		var cx := _plot.position.x + (float(i) + 0.5) * (_plot.size.x / float(n))
		var rr := Rect2(cx - larg * 0.5, _plot.end.y - h, larg, maxf(h, 1.0))
		var cor := UITheme.INFO.lerp(UITheme.ACENTO_2, float(i) / float(maxi(n - 1, 1)))
		draw_rect(rr, cor)
		draw_rect(rr, Color(1, 1, 1, 0.18), false, 1.0)
	if eixo_x != "":
		draw_string(UITheme.titulo_font(false), Vector2(_plot.get_center().x - 70, size.y - 8),
			eixo_x, HORIZONTAL_ALIGNMENT_CENTER, 140, 11, UITheme.TEXTO_DIM)


func _draw_boxplot() -> void:
	if caixas.is_empty():
		_draw_vazio("sem dados")
		return
	var mn := INF
	var mx := -INF
	for c in caixas:
		mn = minf(mn, float(c["min"]))
		mx = maxf(mx, float(c["max"]))
	if mx - mn < 0.0001:
		mx = mn + 1.0
	var yi := Vector2(mn - (mx - mn) * 0.1, mx + (mx - mn) * 0.1)
	_draw_eixos(Vector2(0, 1), yi, true, false)
	var n := caixas.size()
	var larg := _plot.size.x / float(n)
	for i in range(n):
		var c: Dictionary = caixas[i]
		var valido := true
		for chave in ["min", "q1", "med", "q3", "max"]:
			if not is_finite(float(c.get(chave, NAN))):
				valido = false
		if not valido:
			continue
		var cor: Color = c.get("cor", UITheme.INFO)
		var cx := _plot.position.x + (float(i) + 0.5) * larg
		var y_min := _mapa(Vector2(0, float(c["min"])), Vector2(0, 1), yi).y
		var y_max := _mapa(Vector2(0, float(c["max"])), Vector2(0, 1), yi).y
		var y_q1 := _mapa(Vector2(0, float(c["q1"])), Vector2(0, 1), yi).y
		var y_q3 := _mapa(Vector2(0, float(c["q3"])), Vector2(0, 1), yi).y
		var y_med := _mapa(Vector2(0, float(c["med"])), Vector2(0, 1), yi).y
		var w := larg * 0.44
		if absf(y_max - y_min) > 0.5:
			draw_line(Vector2(cx, y_min), Vector2(cx, y_max), cor, 1.6)
		draw_line(Vector2(cx - w * 0.4, y_min), Vector2(cx + w * 0.4, y_min), cor, 1.6)
		draw_line(Vector2(cx - w * 0.4, y_max), Vector2(cx + w * 0.4, y_max), cor, 1.6)
		var caixa := Rect2(cx - w * 0.5, y_q3, w, maxf(y_q1 - y_q3, 1.0))
		draw_rect(caixa, Color(cor.r, cor.g, cor.b, 0.28))
		draw_rect(caixa, cor, false, 1.6)
		draw_line(Vector2(cx - w * 0.5, y_med), Vector2(cx + w * 0.5, y_med), cor.lightened(0.5), 2.6)
		for out in c.get("outliers", []):
			draw_circle(Vector2(cx, _mapa(Vector2(0, float(out)), Vector2(0, 1), yi).y), 2.0,
				Color(cor.r, cor.g, cor.b, 0.75))
		var rot := str(c.get("rotulo", ""))
		# "0-14 (Jovem)" vira "0-14": o parenteses nao cabe sob a caixa
		if rot.contains(" ("):
			rot = rot.split(" (")[0]
		if rot.length() > 12:
			rot = rot.substr(0, 11) + "."
		draw_string(UITheme.corpo(500), Vector2(cx - 40, _plot.end.y + 18), rot,
			HORIZONTAL_ALIGNMENT_CENTER, 80, 11, UITheme.TEXTO_DIM)


func _draw_dispersao() -> void:
	if series.is_empty():
		return
	var pts: PackedVector2Array = series[0]["pontos"]
	if pts.is_empty():
		return
	var xi := Vector2(_min_x(), _max_x())
	var yi := _intervalo_y()
	if xi.y <= xi.x: xi.y = xi.x + 1.0
	if yi.y <= yi.x: yi.y = yi.x + 1.0
	_draw_eixos(xi, yi)
	var cor: Color = series[0].get("cor", UITheme.INFO)
	for p in pts:
		draw_circle(_mapa(p, xi, yi), 3.4, Color(cor.r, cor.g, cor.b, 0.85))
	for i in range(1, series.size()):
		var s: Dictionary = series[i]
		var p2: PackedVector2Array = s["pontos"]
		if p2.size() < 2:
			continue
		_draw_tracejada(_mapa(p2[0], xi, yi), _mapa(p2[1], xi, yi), s["cor"], 2.2)
	_draw_legenda()
	if interativo:
		_dados_plot = []
		for p in pts:
			_dados_plot.append({"pos": _mapa(p, xi, yi), "p": p, "nome": "ponto", "cor": cor})


func _draw_roc() -> void:
	var xi := Vector2(0.0, 1.0)
	var yi := Vector2(0.0, 1.0)
	_draw_eixos(xi, yi)
	_draw_tracejada(_mapa(Vector2(0, 0), xi, yi), _mapa(Vector2(1, 1), xi, yi),
		Color(1, 1, 1, 0.25), 1.2)
	if not series.is_empty():
		var pts: PackedVector2Array = series[0]["pontos"]
		var cor: Color = series[0].get("cor", UITheme.ACENTO)
		if pts.size() > 1:
			# a curva pode repetir pontos (degraus da ROC); vertice repetido faz
			# o triangulate_polygon do Godot falhar ("Invalid polygon data")
			var poli := PackedVector2Array()
			var empilhar := func(v: Vector2) -> void:
				if poli.is_empty() or poli[poli.size() - 1].distance_squared_to(v) > 0.01:
					poli.append(v)
			empilhar.call(_mapa(Vector2(0, 0), xi, yi))
			for p in pts:
				empilhar.call(_mapa(p, xi, yi))
			empilhar.call(_mapa(Vector2(1, 0), xi, yi))
			var extensao := _mapa(Vector2(1, 1), xi, yi) - _mapa(Vector2(0, 0), xi, yi)
			if extensao.length_squared() > 1.0 and poli.size() >= 3:
				var triangulos := Geometry2D.triangulate_polygon(poli)
				if not triangulos.is_empty():
					for k in range(0, triangulos.size(), 3):
						draw_colored_polygon(PackedVector2Array([
							poli[triangulos[k]], poli[triangulos[k + 1]], poli[triangulos[k + 2]]
						]), Color(cor.r, cor.g, cor.b, 0.18))
			var ant := _mapa(pts[0], xi, yi)
			for k in range(1, pts.size()):
				var cur := _mapa(pts[k], xi, yi)
				draw_line(ant, cur, cor, 2.6, true)
				ant = cur


func _draw_hover() -> void:
	if not interativo or _dados_plot.is_empty():
		return
	var melhor := {}
	var dist := 26.0
	for d in _dados_plot:
		var dd: float = (d["pos"] as Vector2).distance_to(_hover)
		if dd < dist:
			dist = dd
			melhor = d
	if melhor.is_empty():
		return
	var p: Vector2 = melhor["pos"]
	draw_circle(p, 5.0, Color(melhor["cor"]))
	draw_circle(p, 5.0, Color(1, 1, 1, 0.9), false, 1.2)
	var pt: Vector2 = melhor["p"]
	var txt := "(%s, %s)" % [_fmt(pt.x), _fmt(pt.y)]
	var f := UITheme.corpo(600)
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
	var pos := p + Vector2(12, -12)
	if pos.x + w > size.x:
		pos.x = p.x - w - 12
	var rr := Rect2(pos - Vector2(0, 12), Vector2(w, 20))
	draw_rect(rr, Color(0.05, 0.07, 0.09, 0.95))
	draw_rect(rr, melhor["cor"], false, 1.0)
	draw_string(f, pos + Vector2(7, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXTO)


func _gui_input(event: InputEvent) -> void:
	if not interativo:
		return
	if event is InputEventMouseMotion:
		_hover = event.position
		queue_redraw()
