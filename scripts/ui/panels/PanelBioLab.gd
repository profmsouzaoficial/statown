class_name PanelBioLab
extends Control
## Laboratorio de Bioestatistica - o coracao didatico do StaTown.
##
## Abas: Amostragem · Descritiva · Graficos · Distribuicoes · Testes · Regressao.
## Tudo roda sobre a populacao sintetica de 41.650 individuos, com os mesmos
## algoritmos que o jogo usa para validar os numeros (StatCore).

var main: Control

var _amostra := PackedInt32Array()
var _filtro_vila := 0
var _metodo := "aas"
var _n_alvo := 300
var _seed := 7
var _tab: TabContainer
var _lbl_info: Label

# abas construidas sob demanda
var _construidas := {}


func _init(m: Control) -> void:
	main = m
	_amostra = Population.amostrar(_n_alvo, 0, _seed)
	_build()


# ============================================================================
# ESQUELETO
# ============================================================================

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margem.add_theme_constant_override(lado, 14)
	add_child(margem)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margem.add_child(col)

	# ---- barra de status da amostra ----
	var barra := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.17)
	sb.border_color = UITheme.BORDA
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	barra.add_theme_stylebox_override("panel", sb)
	col.add_child(barra)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	barra.add_child(hb)
	hb.add_child(UITheme.rotulo("AMOSTRA ATIVA", 11, UITheme.ACENTO))
	_lbl_info = UITheme.rotulo("", 14, UITheme.TEXTO)
	_lbl_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# sem autowrap o rotulo longo empurra a largura minima do modal
	_lbl_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(_lbl_info)
	hb.add_child(UITheme.botao("Nova amostra", _nova_amostra, null, UITheme.SUCESSO))

	_tab = TabContainer.new()
	_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab.clip_tabs = false
	col.add_child(_tab)

	_aba_amostragem()
	_aba_descritiva()
	_aba_graficos()
	_aba_distribuicoes()
	_aba_testes()
	_aba_regressao()
	_atualizar_info()


func _atualizar_info() -> void:
	var populacao := Vilas.populacao_total() if _filtro_vila == 0 else \
		int(Vilas.get_vila(_filtro_vila).get("populacao", 0))
	var frac := 100.0 * float(_amostra.size()) / float(maxi(populacao, 1))
	var nomes := {"aas": "aleatoria simples", "sistematica": "sistematica",
		"estratificada": "estratificada por faixa etaria", "conglomerados": "por conglomerados"}
	_lbl_info.text = "n = %d  ·  %.1f%% de %s  ·  %s  ·  vila: %s  ·  semente %d" % [
		_amostra.size(), frac, _mil(populacao),
		str(nomes.get(_metodo, _metodo)),
		"todas" if _filtro_vila == 0 else str(Vilas.get_vila(_filtro_vila)["nome"]),
		_seed]


func _placeholder(nome: String) -> VBoxContainer:
	var v := UITheme.vbox(10)
	v.name = nome
	return v


# ============================================================================
# ABA 1 - AMOSTRAGEM
# ============================================================================

func _aba_amostragem() -> void:
	var raiz := HBoxContainer.new()
	raiz.name = "Amostragem"
	raiz.add_theme_constant_override("separation", 12)
	_tab.add_child(raiz)

	# controles
	var p := UITheme.card("PLANO DE AMOSTRAGEM", UITheme.ACENTO_2)
	p.custom_minimum_size.x = 330
	raiz.add_child(p)
	var c := UITheme.conteudo(p)

	c.add_child(UITheme.rotulo("UNIDADE DE ANALISE", 11, UITheme.TEXTO_FRACO))
	var sel_vila := OptionButton.new()
	sel_vila.fit_to_longest_item = false
	sel_vila.clip_text = true
	sel_vila.add_item("Todas as 20 vilas")
	for v in Vilas.vilas:
		sel_vila.add_item(str(v["nome"]))
	sel_vila.item_selected.connect(func(i):
		_filtro_vila = 0 if i == 0 else int(Vilas.vilas[i - 1]["id"]))
	c.add_child(sel_vila)

	c.add_child(UITheme.rotulo("METODO", 11, UITheme.TEXTO_FRACO))
	var sel_met := OptionButton.new()
	sel_met.fit_to_longest_item = false
	sel_met.clip_text = true
	sel_met.add_item("Aleatoria simples (AAS)")
	sel_met.add_item("Sistematica")
	sel_met.add_item("Estratificada por faixa etaria")
	sel_met.add_item("Por conglomerados (vilas)")
	sel_met.item_selected.connect(func(i):
		_metodo = ["aas", "sistematica", "estratificada", "conglomerados"][i])
	c.add_child(sel_met)

	c.add_child(UITheme.rotulo("TAMANHO DA AMOSTRA (n)", 11, UITheme.TEXTO_FRACO))
	var spin := SpinBox.new()
	spin.min_value = 20
	spin.max_value = 3000
	spin.step = 10
	spin.value = _n_alvo
	spin.value_changed.connect(func(v): _n_alvo = int(v))
	c.add_child(spin)

	c.add_child(UITheme.rotulo("SEMENTE (para reprodutibilidade)", 11, UITheme.TEXTO_FRACO))
	var spin2 := SpinBox.new()
	spin2.min_value = 1
	spin2.max_value = 99999
	spin2.value = _seed
	spin2.value_changed.connect(func(v): _seed = int(v))
	c.add_child(spin2)

	var b := UITheme.botao("Sortear amostra", _nova_amostra, null, UITheme.SUCESSO)
	c.add_child(b)
	c.add_child(UITheme.separador())
	var calc := UITheme.botao("Calcular n ideal (formula)", _calc_n, null, UITheme.INFO)
	c.add_child(calc)
	c.add_child(UITheme.paragrafo(
		"A formula devolve o n necessario para estimar uma proporcao com margem de erro "
		+ "de 5 p.p. e 95% de confianca, corrigido para populacao finita.", 12, UITheme.TEXTO_DIM))

	# tabela
	var dir := VBoxContainer.new()
	dir.add_theme_constant_override("separation", 8)
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raiz.add_child(dir)

	var acoes := HBoxContainer.new()
	acoes.add_theme_constant_override("separation", 8)
	dir.add_child(acoes)
	acoes.add_child(UITheme.botao("Copiar CSV da amostra", _copiar_csv, null, UITheme.INFO))
	acoes.add_child(UITheme.botao("Baixar CSV", _baixar_csv, null, UITheme.ACENTO))
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acoes.add_child(esp)
	acoes.add_child(UITheme.rotulo("primeiras 60 linhas", 12, UITheme.TEXTO_FRACO))

	var t := TabelaDados.new()
	t.name = "Tabela"
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dir.add_child(t)
	_atualizar_tabela()


func _atualizar_tabela() -> void:
	var aba := _tab.get_node_or_null("Amostragem")
	if aba == null:
		return
	var t := aba.find_child("Tabela", true, false) as TabelaDados
	if t == null:
		return
	var cols := [
		{"id": "id", "rotulo": "ID", "largura": 0.7, "tipo": "num"},
		{"id": "vila_nome", "rotulo": "Vila", "largura": 1.1},
		{"id": "idade", "rotulo": "Idade", "largura": 0.7, "tipo": "num"},
		{"id": "faixa_etaria", "rotulo": "Faixa", "largura": 1.2},
		{"id": "genero", "rotulo": "Sexo", "largura": 0.9},
		{"id": "renda_familiar_sm", "rotulo": "Renda (SM)", "largura": 0.9, "tipo": "num"},
		{"id": "saneamento_domiciliar", "rotulo": "Saneam.", "largura": 0.8},
		{"id": "status_vacinal", "rotulo": "Vacina", "largura": 1.0},
		{"id": "biomarcador_clinico", "rotulo": "Biomarc.", "largura": 0.9, "tipo": "num"},
		{"id": "estado_epidemiologico", "rotulo": "Estado", "largura": 1.1},
	]
	var ids := PackedStringArray()
	for c in cols:
		ids.append(str(c["id"]))
	var sub := PackedInt32Array()
	for k in range(mini(_amostra.size(), 60)):
		sub.append(_amostra[k])
	var rows: Array = []
	for r in Population.tabela(sub, ids):
		var linha: Array = []
		for c2 in cols:
			var v = r[str(c2["id"])]
			if v == null:
				v = ""
			if typeof(v) == TYPE_FLOAT:
				linha.append("%.1f" % float(v))
			else:
				linha.append(str(v))
		rows.append(linha)
	t.definir(cols, rows)


func _nova_amostra() -> void:
	_seed += 1
	match _metodo:
		"aas":
			_amostra = Population.amostrar(_n_alvo, _filtro_vila, _seed)
		"sistematica":
			_amostra = Population.amostrar_sistematica(_n_alvo, _filtro_vila, _seed)
		"estratificada":
			var d := Population.amostrar_estratificada(_n_alvo, _filtro_vila, _seed)
			var out := PackedInt32Array()
			var chaves: Array = d.keys()
			chaves.sort()
			for k in chaves:
				for i in d[k]:
					out.append(i)
			_amostra = out
			main.mostrar_toast("Estratos: %s" % _resumo_estratos(d), "info")
		"conglomerados":
			var n_vilas := 6
			var d2 := Population.amostrar_conglomerados(n_vilas, maxi(10, _n_alvo / n_vilas), _seed)
			_amostra = d2["indices"]
			var nomes := PackedStringArray()
			for vid in d2["vilas"]:
				nomes.append(str(Vilas.get_vila(int(vid)).get("nome", "?")))
			main.mostrar_toast("Conglomerados sorteados: " + ", ".join(nomes), "info")
	_atualizar_info()
	_atualizar_tabela()


func _resumo_estratos(d: Dictionary) -> String:
	var partes := PackedStringArray()
	for k in d:
		partes.append("%s=%d" % [k, (d[k] as PackedInt32Array).size()])
	return ", ".join(partes)


func _calc_n() -> void:
	var N := Vilas.populacao_total()
	var p := 0.5
	var r := StatCore.sample_size_proportion(N, p, 0.05, 1.96)
	var n0 := float(r.get("n0", 0.0))
	var n := int(r.get("n", 0))
	main.mostrar_toast("Para p=0,5, e=5%% e 95%%: n0 = %.1f -> n = %d (com correcao para N=%d)" %
		[n0, n, N], "info")


func _copiar_csv() -> void:
	DisplayServer.clipboard_set(Population.gerar_csv(_amostra))
	main.mostrar_toast("CSV da amostra (%d linhas) copiado" % _amostra.size(), "sucesso")


func _baixar_csv() -> void:
	var r := SigaExporter.baixar("statown_amostra_n%d.csv" % _amostra.size(),
		Population.gerar_csv(_amostra))
	main.mostrar_toast(str(r["msg"]), "sucesso" if bool(r["ok"]) else "erro")


# ============================================================================
# ABA 2 - DESCRITIVA
# ============================================================================

func _aba_descritiva() -> void:
	var raiz := VBoxContainer.new()
	raiz.name = "Descritiva"
	raiz.add_theme_constant_override("separation", 10)
	_tab.add_child(raiz)

	var controles := HBoxContainer.new()
	controles.add_theme_constant_override("separation", 10)
	raiz.add_child(controles)
	controles.add_child(UITheme.rotulo("VARIAVEL", 11, UITheme.TEXTO_FRACO))
	var sv := OptionButton.new()
	sv.fit_to_longest_item = false
	sv.clip_text = true
	for v in _numericas():
		sv.add_item(str(v["rotulo"]))
	controles.add_child(sv)
	controles.add_child(UITheme.rotulo("AGRUPAR POR", 11, UITheme.TEXTO_FRACO))
	var sg := OptionButton.new()
	sg.fit_to_longest_item = false
	sg.clip_text = true
	sg.add_item("(sem agrupamento)")
	for v in _categoricas():
		sg.add_item(str(v["rotulo"]))
	controles.add_child(sg)
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controles.add_child(esp)
	controles.add_child(UITheme.rotulo("medidas calculadas na amostra ativa", 12, UITheme.TEXTO_FRACO))

	var corpo := HBoxContainer.new()
	corpo.add_theme_constant_override("separation", 12)
	corpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(corpo)

	var ptab := UITheme.card("MEDIDAS RESUMO", UITheme.ACENTO)
	ptab.custom_minimum_size.x = 380
	corpo.add_child(ptab)
	var tabela_box := UITheme.conteudo(ptab)
	tabela_box.name = "Tabela"

	var graphs := VBoxContainer.new()
	graphs.add_theme_constant_override("separation", 10)
	graphs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	corpo.add_child(graphs)
	var hist := StatChartCanvas.new()
	hist.name = "Hist"
	hist.titulo = "Distribuicao (histograma)"
	hist.custom_minimum_size.y = 230
	graphs.add_child(hist)
	var box := StatChartCanvas.new()
	box.name = "Box"
	box.titulo = "Comparacao entre grupos (boxplot)"
	box.custom_minimum_size.y = 230
	graphs.add_child(box)

	sv.item_selected.connect(func(_i): _atualizar_descritiva())
	sg.item_selected.connect(func(_i): _atualizar_descritiva())
	_atualizar_descritiva()


func _atualizar_descritiva() -> void:
	var aba := _tab.get_node_or_null("Descritiva")
	if aba == null:
		return
	var sv := _primeiro_option(aba)
	var sg := _segundo_option(aba)
	if sv == null or sg == null:
		return
	var nums := _numericas()
	var cats := _categoricas()
	var var_num := str(nums[clampi(sv.selected, 0, nums.size() - 1)]["id"])
	var var_cat := "" if sg.selected <= 0 else str(cats[sg.selected - 1]["id"])

	var v := Population.vetor_numerico(_amostra, var_num)
	var d := StatCore.describe(v)
	var caixa := aba.find_child("Tabela", true, false) as VBoxContainer
	if caixa == null:
		return
	for c in caixa.get_children():
		c.queue_free()
	caixa.add_child(UITheme.campo("n", str(int(d["n"]))))
	caixa.add_child(UITheme.linha_medida("Media", "%.3f" % float(d["media"])))
	caixa.add_child(UITheme.linha_medida("IC95% da media", "[%.3f ; %.3f]" % [
		float(d["media"]) - 1.96 * float(d["erro_padrao"]),
		float(d["media"]) + 1.96 * float(d["erro_padrao"])]))
	caixa.add_child(UITheme.linha_medida("Mediana", "%.3f" % float(d["mediana"])))
	caixa.add_child(UITheme.linha_medida("Desvio padrao", "%.3f" % float(d["desvio_padrao"])))
	caixa.add_child(UITheme.linha_medida("Erro padrao", "%.4f" % float(d["erro_padrao"])))
	caixa.add_child(UITheme.linha_medida("Variancia", "%.3f" % float(d["variancia"])))
	caixa.add_child(UITheme.linha_medida("Coef. de variacao", "%.1f%%" % float(d["cv"])))
	caixa.add_child(UITheme.linha_medida("Minimo / Maximo", "%.1f / %.1f" % [float(d["min"]), float(d["max"])]))
	caixa.add_child(UITheme.linha_medida("Q1 / Q3 (IIQ)", "%.1f / %.1f (%.1f)" % [
		float(d["q1"]), float(d["q3"]), float(d["iqr"])]))
	caixa.add_child(UITheme.linha_medida("Assimetria (g1)", "%.3f  %s" % [
		float(d["assimetria"]), StatCore.interpret_skewness(float(d["assimetria"]))]))
	caixa.add_child(UITheme.linha_medida("Curtose (g2)", "%.3f  %s" % [
		float(d["curtose"]), StatCore.interpret_kurtosis(float(d["curtose"]))]))

	# histograma
	var hist := aba.find_child("Hist", true, false) as StatChartCanvas
	var h := StatCore.histogram(v, 0)
	if hist:
		hist.titulo = "Distribuicao de " + var_num
		hist.formato_y = "int"
		hist.definir_histograma(_centros_de(h), h["counts"], var_num)

	# boxplot por grupo
	var box := aba.find_child("Box", true, false) as StatChartCanvas
	if box:
		if var_cat == "":
			box.titulo = "Distribuicao geral (boxplot)"
			box.definir_boxplot([_caixa_de("amostra", v, UITheme.ACENTO)], var_num)
		else:
			var grupos := _grupos(var_num, var_cat)
			var caixas: Array = []
			var cores := [UITheme.INFO, UITheme.ACENTO_2, UITheme.ROXO, UITheme.ACENTO,
				UITheme.PERIGO, UITheme.SUCESSO]
			var k := 0
			for nome in grupos:
				caixas.append(_caixa_de(nome, grupos[nome], cores[k % cores.size()]))
				k += 1
			box.titulo = "%s por %s" % [var_num, var_cat]
			box.definir_boxplot(caixas, var_num)


func _centros_de(h: Dictionary) -> Array:
	var bins: PackedFloat64Array = h["bins"]
	var counts: PackedFloat64Array = h["counts"]
	var out: Array = []
	for i in range(counts.size()):
		out.append((bins[i] + bins[i + 1]) * 0.5)
	return out


func _caixa_de(rotulo: String, v: PackedFloat64Array, cor: Color) -> Dictionary:
	var s := StatCore.describe(v)
	var outlier: Array = []
	return {"rotulo": rotulo, "min": float(s["min"]), "q1": float(s["q1"]),
		"med": float(s["mediana"]), "q3": float(s["q3"]), "max": float(s["max"]),
		"cor": cor, "outliers": outlier}


# ============================================================================
# ABA 3 - GRAFICOS
# ============================================================================

func _aba_graficos() -> void:
	var raiz := VBoxContainer.new()
	raiz.name = "Graficos"
	raiz.add_theme_constant_override("separation", 10)
	_tab.add_child(raiz)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 8)
	raiz.add_child(ctrl)
	var st := OptionButton.new()
	st.fit_to_longest_item = false
	st.clip_text = true
	st.custom_minimum_size = Vector2(210, 34)
	st.add_item("Dispersao (X vs Y)")
	st.add_item("Barras (categorias)")
	st.add_item("Histograma")
	ctrl.add_child(st)
	var sx := OptionButton.new()
	sx.fit_to_longest_item = false
	sx.clip_text = true
	sx.custom_minimum_size = Vector2(165, 34)
	for v in _numericas():
		sx.add_item(str(v["rotulo"]))
	ctrl.add_child(sx)
	var sy := OptionButton.new()
	sy.fit_to_longest_item = false
	sy.clip_text = true
	sy.custom_minimum_size = Vector2(165, 34)
	for v in _numericas():
		sy.add_item(str(v["rotulo"]))
	sy.select(mini(1, sy.item_count - 1))
	ctrl.add_child(sy)
	var sc := OptionButton.new()
	sc.fit_to_longest_item = false
	sc.clip_text = true
	sc.custom_minimum_size = Vector2(165, 34)
	sc.add_item("(categoria)")
	for v in _categoricas():
		sc.add_item(str(v["rotulo"]))
	ctrl.add_child(sc)
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.add_child(esp)
	var b := UITheme.botao("Desenhar", func(): _desenhar_grafico(), null, UITheme.SUCESSO)
	ctrl.add_child(b)

	var g := StatChartCanvas.new()
	g.name = "Canvas"
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(g)

	var nota := UITheme.paragrafo(
		"Dica: antes de escolher o grafico, pergunte-se qual e o tipo das duas variaveis. "
		+ "Quantitativa x quantitativa pede dispersao; categorica pede barras; uma unica "
		+ "quantitativa pede histograma. Grafico errado distorce a leitura dos dados.", 13,
		UITheme.TEXTO_DIM)
	raiz.add_child(nota)

	st.item_selected.connect(func(i):
		sx.visible = i != 1
		sy.visible = i == 0
		sc.visible = i == 1)


func _desenhar_grafico() -> void:
	var aba := _tab.get_node_or_null("Graficos")
	if aba == null:
		return
	var opts := _options(aba)
	if opts.size() < 4:
		return
	var tipo_i: int = opts[0].selected
	var nums := _numericas()
	var cats := _categoricas()
	var g := aba.find_child("Canvas", true, false) as StatChartCanvas
	if g == null:
		return
	g.limpar()
	if tipo_i == 0:
		var vx := Population.vetor_numerico(_amostra, str(nums[opts[1].selected]["id"]))
		var vy := Population.vetor_numerico(_amostra, str(nums[opts[2].selected]["id"]))
		var n := mini(vx.size(), vy.size())
		var pts := PackedVector2Array()
		for i in range(n):
			pts.append(Vector2(vx[i], vy[i]))
		g.titulo = "%s vs %s" % [nums[opts[1].selected]["rotulo"], nums[opts[2].selected]["rotulo"]]
		g.formato_y = "dec"
		g.definir_dispersao(pts, str(nums[opts[1].selected]["rotulo"]),
			str(nums[opts[2].selected]["rotulo"]))
		var reg := StatCore.linear_regression(vx, vy)
		if not reg.has("erro"):
			g.adicionar_reta(float(reg["b0"]), float(reg["b1"]), UITheme.ACENTO,
				"R2 = %.3f" % float(reg["r2"]))
			main.mostrar_toast("r = %.3f  ·  R2 = %.3f  ·  reta: y = %.2f + %.3f x" % [
				float(reg["r"]), float(reg["r2"]), float(reg["b0"]), float(reg["b1"])], "info")
	elif tipo_i == 1:
		var var_cat := str(cats[opts[3].selected - 1]["id"])
		var ft := StatCore.frequency_table(Population.vetor_categorico(_amostra, var_cat))
		var rot: Array = []
		var val: Array = []
		var cores: Array = []
		var paleta := [UITheme.INFO, UITheme.ACENTO_2, UITheme.ROXO, UITheme.ACENTO,
			UITheme.PERIGO, UITheme.SUCESSO]
		var k := 0
		for item in ft:
			rot.append(str(item["categoria"]))
			val.append(float(item["n"]))
			cores.append(paleta[k % paleta.size()])
			k += 1
		g.titulo = "Frequencia de " + var_cat
		g.formato_y = "int"
		g.definir_barras(rot, val, cores, "n")
	else:
		var vv := Population.vetor_numerico(_amostra, str(nums[opts[1].selected]["id"]))
		var h2 := StatCore.histogram(vv, 0)
		g.titulo = "Histograma de " + str(nums[opts[1].selected]["rotulo"])
		g.formato_y = "int"
		g.definir_histograma(_centros_de(h2), h2["counts"], str(nums[opts[1].selected]["rotulo"]))


# ============================================================================
# ABA 4 - DISTRIBUICOES
# ============================================================================

func _aba_distribuicoes() -> void:
	var raiz := HBoxContainer.new()
	raiz.name = "Distribuicoes"
	raiz.add_theme_constant_override("separation", 12)
	_tab.add_child(raiz)

	var p := UITheme.card("FAMILIA E PARAMETROS", UITheme.INFO)
	p.custom_minimum_size.x = 360
	raiz.add_child(p)
	var c := UITheme.conteudo(p)
	c.name = "Controles"

	var dir := VBoxContainer.new()
	dir.add_theme_constant_override("separation", 10)
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raiz.add_child(dir)
	var g := StatChartCanvas.new()
	g.name = "Canvas"
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dir.add_child(g)
	var res := UITheme.card("PROBABILIDADES", UITheme.ACENTO_2)
	res.name = "Resultados"
	dir.add_child(res)

	_construir_distribuicoes()


func _construir_distribuicoes() -> void:
	var aba := _tab.get_node_or_null("Distribuicoes")
	if aba == null:
		return
	var c := aba.find_child("Controles", true, false) as VBoxContainer
	if c == null:
		return
	for ch in c.get_children():
		ch.queue_free()
	c.add_child(UITheme.paragrafo(
		"A mesma pergunta ('qual a chance de observar um valor tao extremo assim?') "
		+ "muda de resposta conforme a familia de distribuicoes. Escolher a familia errada "
		+ "produz p-valores errados.", 12, UITheme.TEXTO_DIM))
	var sel := OptionButton.new()
	sel.fit_to_longest_item = false
	sel.clip_text = true
	sel.custom_minimum_size = Vector2(220, 34)
	sel.add_item("Normal")
	sel.add_item("t de Student")
	sel.add_item("Binomial")
	sel.add_item("Poisson")
	sel.add_item("Qui-quadrado")
	c.add_child(sel)

	var campos := GridContainer.new()
	campos.columns = 2
	campos.add_theme_constant_override("h_separation", 8)
	campos.add_theme_constant_override("v_separation", 6)
	c.add_child(campos)
	var par1 := _campo_numerico(campos, "mu / n / lambda", 0.0)
	var par2 := _campo_numerico(campos, "sigma / p / gl", 1.0)
	var par3 := _campo_numerico(campos, "x observado", 1.96)

	var bloco := VBoxContainer.new()
	bloco.name = "Resultado"
	bloco.add_theme_constant_override("separation", 4)
	var res := aba.find_child("Resultados", true, false) as PanelContainer
	if res:
		UITheme.conteudo(res).add_child(bloco)

	var atualizar := func(_i = 0):
		_atualizar_distribuicao(sel.selected, par1.value, par2.value, par3.value, par1, par2, par3)
	sel.item_selected.connect(func(i):
		# O passo das setas depende da familia: sigma 0.5, gl 1, p 0.01.
		# Digitar continua aceitando qualquer valor exato.
		_ajustar_passos(i, par1, par2, par3)
		atualizar.call(i))
	for w in [par1, par2, par3]:
		(w as SpinBox).value_changed.connect(func(_v): atualizar.call(0))
	_ajustar_passos(sel.selected, par1, par2, par3)
	_atualizar_distribuicao(sel.selected, par1.value, par2.value, par3.value, par1, par2, par3)


func _ajustar_passos(familia: int, s1: SpinBox, s2: SpinBox, s3: SpinBox) -> void:
	match familia:
		0:  # Normal
			s1.step = 0.1
			s2.step = 0.5
			s3.step = 0.1
		1:  # t de Student
			s1.step = 0.1
			s2.step = 1.0
			s3.step = 0.1
		2:  # Binomial
			s1.step = 1.0
			s2.step = 0.01
			s3.step = 1.0
		3:  # Poisson
			s1.step = 0.1
			s2.step = 1.0
			s3.step = 1.0
		4:  # Qui-quadrado
			s1.step = 1.0
			s2.step = 1.0
			s3.step = 0.1


func _campo_numerico(pai: GridContainer, rotulo: String, valor: float) -> SpinBox:
	var l := UITheme.rotulo(rotulo.to_upper(), 10, UITheme.TEXTO_FRACO)
	pai.add_child(l)
	var s := SpinBox.new()
	s.min_value = -100000
	s.max_value = 100000
	s.step = 0.01
	s.value = valor
	s.tooltip_text = "Digite ou use as setas; o passo muda com a familia."
	s.custom_minimum_size.x = 130
	pai.add_child(s)
	return s


func _atualizar_distribuicao(familia: int, p1: float, p2: float, p3: float,
		s1: SpinBox, s2: SpinBox, s3: SpinBox) -> void:
	var aba := _tab.get_node_or_null("Distribuicoes")
	if aba == null:
		return
	var g := aba.find_child("Canvas", true, false) as StatChartCanvas
	var res := aba.find_child("Resultado", true, false) as VBoxContainer
	if g == null or res == null:
		return
	for ch in res.get_children():
		ch.queue_free()
	g.limpar()
	var xs := PackedVector2Array()
	var dens := PackedVector2Array()
	var rotulo := ""
	var y_marca := 0.0
	match familia:
		0:
			var mu := p1
			var sigma := maxf(absf(p2), 0.001)
			var x := mu - 4.2 * sigma
			while x <= mu + 4.2 * sigma:
				xs.append(Vector2(x, StatCore.normal_pdf(x, mu, sigma)))
				x += sigma / 24.0
			rotulo = "Normal(mu=%.2f, sigma=%.2f)" % [mu, sigma]
			y_marca = StatCore.normal_pdf(p3, mu, sigma)
			_s1_label(s1, "mu"); _s2_label(s2, "sigma"); _s1_label(s3, "x")
			res.add_child(UITheme.linha_medida("P(X <= x)", "%.4f" %
				StatCore.normal_cdf(p3, mu, sigma)))
			res.add_child(UITheme.linha_medida("P(X > x)", "%.4f" %
				(1.0 - StatCore.normal_cdf(p3, mu, sigma))))
			res.add_child(UITheme.linha_medida("Quantil 97,5%", "%.4f" %
				StatCore.normal_quantile(0.975, mu, sigma)))
			res.add_child(UITheme.linha_medida("escore z", "%.3f" % StatCore.z_score(p3, mu, sigma)))
		1:
			var df := maxf(absf(p2), 1.0)
			var x2 := -5.0
			while x2 <= 5.0:
				var num := exp(StatCore.ln_gamma((df + 1.0) * 0.5) - StatCore.ln_gamma(df * 0.5))
				var den := sqrt(df * PI) * pow(1.0 + x2 * x2 / df, (df + 1.0) * 0.5)
				xs.append(Vector2(x2, num / den))
				x2 += 0.05
			rotulo = "t de Student (gl = %.0f)" % df
			var num_m := exp(StatCore.ln_gamma((df + 1.0) * 0.5) - StatCore.ln_gamma(df * 0.5))
			y_marca = num_m / (sqrt(df * PI) * pow(1.0 + p3 * p3 / df, (df + 1.0) * 0.5))
			_s1_label(s1, "(n/a)"); _s2_label(s2, "gl"); _s1_label(s3, "t")
			res.add_child(UITheme.linha_medida("P(T <= t)", "%.4f" % StatCore.t_cdf(p3, df)))
			res.add_child(UITheme.linha_medida("p bilateral", "%.4f" %
				StatCore.t_two_sided_p(p3, df)))
			res.add_child(UITheme.linha_medida("t critico 95%", "%.4f" %
				StatCore.t_quantile(0.975, df)))
		2:
			var n := int(round(maxf(absf(p1), 1.0)))
			var pr := clampf(p2, 0.0001, 0.9999)
			for k in range(0, n + 1):
				xs.append(Vector2(k, StatCore.binomial_pmf(k, n, pr)))
			rotulo = "Binomial(n=%d, p=%.3f)" % [n, pr]
			y_marca = StatCore.binomial_pmf(int(round(p3)), n, pr)
			_s1_label(s1, "n"); _s2_label(s2, "p"); _s1_label(s3, "k")
			var kk := int(round(p3))
			res.add_child(UITheme.linha_medida("P(X = k)", "%.5f" %
				StatCore.binomial_pmf(kk, n, pr)))
			res.add_child(UITheme.linha_medida("P(X <= k)", "%.5f" %
				StatCore.binomial_cdf(kk, n, pr)))
			res.add_child(UITheme.linha_medida("Media / variancia", "%.2f / %.2f" %
				[n * pr, n * pr * (1.0 - pr)]))
		3:
			var lam := maxf(absf(p1), 0.01)
			var top := int(ceil(lam + 4.0 * sqrt(lam) + 3.0))
			for k2 in range(0, top + 1):
				xs.append(Vector2(k2, StatCore.poisson_pmf(k2, lam)))
			rotulo = "Poisson(lambda=%.2f)" % lam
			y_marca = StatCore.poisson_pmf(int(round(p3)), lam)
			_s1_label(s1, "lambda"); _s2_label(s2, "(n/a)"); _s1_label(s3, "k")
			var k3 := int(round(p3))
			res.add_child(UITheme.linha_medida("P(X <= k)", "%.5f" %
				StatCore.poisson_cdf(k3, lam)))
			res.add_child(UITheme.linha_medida("P(X = k)", "%.5f" % StatCore.poisson_pmf(k3, lam)))
			res.add_child(UITheme.linha_medida("Media = variancia", "%.2f" % lam))
		4:
			var df2 := maxf(absf(p1), 1.0)
			var x3 := 0.001
			var top2 := maxf(df2 + 5.0 * sqrt(2.0 * df2), 12.0)
			while x3 <= top2:
				var dens2 := exp((df2 * 0.5 - 1.0) * log(x3) - x3 * 0.5 -
					(df2 * 0.5) * log(2.0) - StatCore.ln_gamma(df2 * 0.5))
				xs.append(Vector2(x3, dens2))
				x3 += top2 / 180.0
			rotulo = "Qui-quadrado (gl = %.0f)" % df2
			if p3 > 0.0:
				y_marca = exp((df2 * 0.5 - 1.0) * log(p3) - p3 * 0.5 -
					(df2 * 0.5) * log(2.0) - StatCore.ln_gamma(df2 * 0.5))
			_s1_label(s1, "gl"); _s2_label(s2, "(n/a)"); _s1_label(s3, "x")
			res.add_child(UITheme.linha_medida("P(X <= x)", "%.4f" % StatCore.chi2_cdf(p3, df2)))
			res.add_child(UITheme.linha_medida("p (cauda direita)", "%.4f" %
				StatCore.chi2_p_value(p3, df2)))
			res.add_child(UITheme.linha_medida("Media", "%.2f" % df2))
	if xs.size() > 1:
		var pico := 0.0
		for p in xs:
			pico = maxf(pico, p.y)
		# A escala do eixo Y nao e recalculada de forma independente para cada
		# curva: se fosse, aumentar sigma (ou gl) apenas "esticaria" a mesma
		# imagem e o aluno nao veria o achatamento. Cada familia usa uma escala
		# comum, com folga apenas quando o pico realmente passa dela.
		var ymax := 0.45
		match familia:
			0:
				ymax = maxf(0.45, pico * 1.08)
			1:
				ymax = maxf(0.42, pico * 1.08)
			2, 3:
				ymax = maxf(0.45, pico * 1.15)
			4:
				ymax = maxf(0.45, pico * 1.12)
		g.eixo_y_min = 0.0
		g.eixo_y_max = ymax
		g.titulo = rotulo
		g.subtitulo = "eixo y comum a familia: comparar parametros muda a altura"
		g.formato_y = "dec"
		g.definir_linhas([{"nome": rotulo, "cor": UITheme.ACENTO_2, "pontos": xs}],
			"x", "densidade / probabilidade")
		g.adicionar_ponto(Vector2(p3, minf(y_marca, ymax)), UITheme.PERIGO, 4.0)


func _s1_label(s: SpinBox, txt: String) -> void:
	var par := s.get_parent() as GridContainer
	if par == null:
		return
	var idx := s.get_index()
	if idx > 0:
		var l := par.get_child(idx - 1) as Label
		if l:
			l.text = txt.to_upper()


func _s2_label(s: SpinBox, txt: String) -> void:
	_s1_label(s, txt)


# ============================================================================
# ABA 5 - TESTES
# ============================================================================

func _aba_testes() -> void:
	var raiz := HBoxContainer.new()
	raiz.name = "Testes"
	raiz.add_theme_constant_override("separation", 12)
	_tab.add_child(raiz)

	var p := UITheme.card("DELINEAMENTO DO TESTE", UITheme.ROXO)
	p.custom_minimum_size.x = 380
	raiz.add_child(p)
	var c := UITheme.conteudo(p)
	c.name = "Controles"

	var dir := VBoxContainer.new()
	dir.add_theme_constant_override("separation", 10)
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raiz.add_child(dir)
	var g := StatChartCanvas.new()
	g.name = "Canvas"
	g.custom_minimum_size.y = 260
	dir.add_child(g)
	var saida := UITheme.card("RESULTADO", UITheme.ACENTO_2)
	saida.name = "Saida"
	dir.add_child(saida)

	_construir_testes()


func _construir_testes() -> void:
	var aba := _tab.get_node_or_null("Testes")
	if aba == null:
		return
	var c := aba.find_child("Controles", true, false) as VBoxContainer
	if c == null:
		return
	for ch in c.get_children():
		ch.queue_free()
	c.add_child(UITheme.paragrafo(
		"Escolha o desenho do estudo. O laboratorio seleciona o teste adequado, roda, "
		+ "e explica o resultado em portugues — inclusive quando o resultado e 'nao "
		+ "significativo'.", 12, UITheme.TEXTO_DIM))
	var sel := OptionButton.new()
	sel.fit_to_longest_item = false
	sel.clip_text = true
	sel.custom_minimum_size = Vector2(220, 34)
	sel.add_item("2 medias independentes (t)")
	sel.add_item("3+ medias (ANOVA + Bonferroni)")
	sel.add_item("2 grupos, nao-parametrico (Mann-Whitney)")
	sel.add_item("3+ grupos, nao-parametrico (Kruskal-Wallis)")
	sel.add_item("Associacao entre categorias (qui-quadrado)")
	sel.add_item("Proporcoes 2x2 (OR e RR)")
	c.add_child(sel)

	var nums := _numericas()
	var cats := _categoricas()
	c.add_child(UITheme.rotulo("VARIAVEL RESPOSTA (numerica)", 10, UITheme.TEXTO_FRACO))
	var sy := OptionButton.new()
	sy.fit_to_longest_item = false
	sy.clip_text = true
	sy.custom_minimum_size = Vector2(165, 34)
	for v in nums:
		sy.add_item(str(v["rotulo"]))
	c.add_child(sy)
	c.add_child(UITheme.rotulo("GRUPO / EXPOSICAO (categorica)", 10, UITheme.TEXTO_FRACO))
	var sg := OptionButton.new()
	sg.fit_to_longest_item = false
	sg.clip_text = true
	for v in cats:
		sg.add_item(str(v["rotulo"]))
	sg.select(0)
	c.add_child(sg)

	var rodar := UITheme.botao("Executar teste", _rodar_teste, null, UITheme.SUCESSO)
	c.add_child(rodar)
	c.add_child(UITheme.separador())
	c.add_child(UITheme.paragrafo(
		"Memoria de calculo sempre visivel: sem isso o p-valor vira oraculo. "
		+ "alfa = 0,05 bilateral em todos os testes.", 11, UITheme.TEXTO_DIM))


func _rodar_teste() -> void:
	var aba := _tab.get_node_or_null("Testes")
	if aba == null:
		return
	var opts := _options(aba)
	if opts.size() < 3:
		return
	var tipo: int = opts[0].selected
	var nums := _numericas()
	var cats := _categoricas()
	var var_y := str(nums[opts[1].selected]["id"])
	var var_g := str(cats[opts[2].selected]["id"])
	var rot_y := str(nums[opts[1].selected]["rotulo"])
	var rot_g := str(cats[opts[2].selected]["rotulo"])
	var saida := aba.find_child("Saida", true, false) as PanelContainer
	var g := aba.find_child("Canvas", true, false) as StatChartCanvas
	if saida == null:
		return
	var corpo := UITheme.conteudo(saida)
	for ch in corpo.get_children():
		ch.queue_free()
	if g:
		g.limpar()

	var grupos := _grupos(var_y, var_g)
	if grupos.size() < 2:
		corpo.add_child(UITheme.paragrafo(
			"A variavel de grupo precisa ter ao menos 2 categorias com dados suficientes.",
			14, UITheme.PERIGO))
		return
	var nomes: Array = grupos.keys()
	nomes.sort()

	# grafico de grupos
	if g and tipo != 4 and tipo != 5:
		var caixas: Array = []
		var paleta := [UITheme.INFO, UITheme.ACENTO_2, UITheme.ROXO, UITheme.ACENTO,
			UITheme.PERIGO, UITheme.SUCESSO]
		for k in range(nomes.size()):
			caixas.append(_caixa_de(nomes[k], grupos[nomes[k]], paleta[k % paleta.size()]))
		g.titulo = "%s por %s" % [rot_y, rot_g]
		g.definir_boxplot(caixas, rot_y)

	match tipo:
		0:
			if nomes.size() < 2:
				_vazio(corpo)
				return
			var r := StatCore.t_test_independent(grupos[nomes[0]], grupos[nomes[1]], true)
			corpo.add_child(_linha_teste("Teste", str(r.get("teste", "t"))))
			corpo.add_child(_linha_teste("Grupos", "%s (n=%d) vs %s (n=%d)" % [
				nomes[0], int(r.get("n1", 0)), nomes[1], int(r.get("n2", 0))]))
			corpo.add_child(_linha_teste("Medias", "%.3f vs %.3f  (diferenca %.3f)" % [
				float(r.get("media1", 0.0)), float(r.get("media2", 0.0)), float(r.get("diff", 0.0))]))
			corpo.add_child(_linha_teste("t (gl)", "%.4f  (%.1f)" % [float(r.get("t", 0.0)),
				float(r.get("gl", 0.0))]))
			corpo.add_child(_linha_teste("p-valor", StatCore.fmt_p(float(r.get("p", 1.0)))))
			var ic: Array = r.get("ic95", [0.0, 0.0])
			corpo.add_child(_linha_teste("IC95% da diferenca", "[%.3f ; %.3f]" % [
				float(ic[0]), float(ic[1])]))
			corpo.add_child(_linha_teste("d de Cohen", "%.3f" % float(r.get("d_cohen", 0.0))))
			corpo.add_child(UITheme.paragrafo(StatCore.interpret_p(float(r.get("p", 1.0))),
				14, UITheme.ACENTO))
			corpo.add_child(UITheme.paragrafo(_texto_t(float(r.get("p", 1.0)),
				float(ic[0]), float(ic[1])), 13, UITheme.TEXTO_DIM))
		1:
			var lista: Array = []
			for k in range(nomes.size()):
				lista.append(grupos[nomes[k]])
			var ra := StatCore.anova_one_way(lista)
			corpo.add_child(_linha_teste("Teste", "ANOVA de um fator"))
			corpo.add_child(_linha_teste("Grupos (k)", "%d grupos" % nomes.size()))
			corpo.add_child(_linha_teste("F (gl1, gl2)", "%.4f  (%.0f, %.0f)" % [
				float(ra.get("F", 0.0)), float(ra.get("gl_entre", 0.0)), float(ra.get("gl_dentro", 0.0))]))
			corpo.add_child(_linha_teste("p-valor", StatCore.fmt_p(float(ra.get("p", 1.0)))))
			corpo.add_child(_linha_teste("eta2", "%.3f" % float(ra.get("eta2", 0.0))))
			var nomes_ps := PackedStringArray()
			for n2 in nomes:
				nomes_ps.append(str(n2))
			var post := StatCore.posthoc_bonferroni(lista, nomes_ps)
			corpo.add_child(UITheme.rotulo("COMPARACOES POST-HOC (BONFERRONI)", 11, UITheme.ACENTO))
			for cmp in post:
				corpo.add_child(UITheme.paragrafo("%s vs %s: diferenca %.3f, p ajustado %s%s" % [
					str(cmp.get("a", "")), str(cmp.get("b", "")),
					float(cmp.get("diff", 0.0)), StatCore.fmt_p(float(cmp.get("p_ajustado", 1.0))),
					"  *" if float(cmp.get("p_ajustado", 1.0)) < 0.05 else ""], 12, UITheme.TEXTO_DIM))
			corpo.add_child(UITheme.paragrafo(StatCore.interpret_p(float(ra.get("p", 1.0))),
				13, UITheme.ACENTO))
		2:
			var r2 := StatCore.mann_whitney(grupos[nomes[0]], grupos[nomes[1]])
			corpo.add_child(_linha_teste("Teste", "Mann-Whitney U"))
			corpo.add_child(_linha_teste("U / z", "%.2f  /  %.4f" % [float(r2.get("U", 0.0)),
				float(r2.get("z", 0.0))]))
			corpo.add_child(_linha_teste("p-valor", StatCore.fmt_p(float(r2.get("p", 1.0)))))
			corpo.add_child(UITheme.paragrafo(StatCore.interpret_p(float(r2.get("p", 1.0))),
				13, UITheme.ACENTO))
			corpo.add_child(UITheme.paragrafo(
				"Use este teste quando a distribuicao e assimetrica, ha outliers fortes ou a "
				+ "variavel e ordinal. Ele compara postos (medianas), nao medias.", 12, UITheme.TEXTO_DIM))
		3:
			var lista3: Array = []
			for k3 in range(nomes.size()):
				lista3.append(grupos[nomes[k3]])
			var rk := StatCore.kruskal_wallis(lista3)
			corpo.add_child(_linha_teste("Teste", "Kruskal-Wallis H"))
			corpo.add_child(_linha_teste("H (gl)", "%.4f  (%.0f)" % [float(rk.get("H", 0.0)),
				float(rk.get("gl", 0.0))]))
			corpo.add_child(_linha_teste("p-valor", StatCore.fmt_p(float(rk.get("p", 1.0)))))
			corpo.add_child(UITheme.paragrafo(StatCore.interpret_p(float(rk.get("p", 1.0))),
				13, UITheme.ACENTO))
		4:
			var ta := _tabela_cruzada(var_y, var_g)
			if ta.is_empty():
				_vazio(corpo)
				return
			var tab_pf: Array = []
			for linha_pf in ta["tabela"]:
				var pf := PackedFloat64Array()
				for cel in linha_pf:
					pf.append(float(cel))
				tab_pf.append(pf)
			var rc := StatCore.chi2_independence(tab_pf, true)
			corpo.add_child(_linha_teste("Teste", "Qui-quadrado de independencia (Yates)"))
			corpo.add_child(_linha_teste("Tabela", "%d x %d" % [
				(ta["tabela"] as Array).size(), ((ta["tabela"] as Array)[0] as Array).size()]))
			corpo.add_child(_linha_teste("Chi2 (gl)", "%.4f  (%.0f)" % [float(rc.get("chi2", 0.0)),
				float(rc.get("gl", 0.0))]))
			corpo.add_child(_linha_teste("p-valor", StatCore.fmt_p(float(rc.get("p", 1.0)))))
			corpo.add_child(_linha_teste("V de Cramer", "%.3f" % float(rc.get("v_cramer", 0.0))))
			corpo.add_child(_linha_teste("Menor valor esperado", "%.2f" % float(rc.get("min_esperado", 0.0))))
			if int(rc.get("celulas_abaixo_5", 0)) > 0:
				corpo.add_child(UITheme.paragrafo(
					("%d celula(s) com frequencia esperada abaixo de 5. O qui-quadrado fica "
					% int(rc["celulas_abaixo_5"]))
					+ "instavel nesse cenario; prefira o teste exato de Fisher.", 12,
					UITheme.ACENTO))
			corpo.add_child(UITheme.paragrafo(StatCore.interpret_p(float(rc.get("p", 1.0))),
				13, UITheme.ACENTO))
			if g:
				var rot: Array = ta["linhas"]
				var vals: Array = []
				for linha in ta["tabela"]:
					vals.append(float((linha as Array)[0]))
				g.titulo = "Primeira coluna por categoria de " + var_y
				g.formato_y = "int"
				g.definir_barras(rot, vals, [], "n")
		5:
			var tab2 := _tabela_2x2(var_g)
			if tab2.is_empty():
				_vazio(corpo)
				return
			var orr := StatCore.odds_ratio(int(tab2["a"]), int(tab2["b"]),
				int(tab2["c"]), int(tab2["d"]))
			var rr := StatCore.relative_risk(int(tab2["a"]), int(tab2["a"]) + int(tab2["b"]),
				int(tab2["c"]), int(tab2["c"]) + int(tab2["d"]))
			var fis := StatCore.fisher_exact(int(tab2["a"]), int(tab2["b"]),
				int(tab2["c"]), int(tab2["d"]))
			corpo.add_child(_linha_teste("Tabela 2x2", "%s x infectado" % var_g))
			corpo.add_child(_linha_teste("Expostos infectados", "%d de %d" % [
				int(tab2["a"]), int(tab2["a"]) + int(tab2["b"])]))
			corpo.add_child(_linha_teste("Nao expostos infectados", "%d de %d" % [
				int(tab2["c"]), int(tab2["c"]) + int(tab2["d"])]))
			corpo.add_child(_linha_teste("Odds ratio", "%.3f  IC95%% [%.3f ; %.3f]" % [
				float(orr.get("or", 0.0)), float((orr.get("ic95", [0.0, 0.0]) as Array)[0]),
				float((orr.get("ic95", [0.0, 0.0]) as Array)[1])]))
			corpo.add_child(_linha_teste("Risco relativo", "%.3f" % float(rr.get("rr", 0.0))))
			corpo.add_child(_linha_teste("Fisher (p)", StatCore.fmt_p(float(fis.get("p", 1.0)))))
			corpo.add_child(UITheme.paragrafo(
				"OR < 1 significa que a exposicao protege; OR > 1 que ela aumenta a chance. "
				+ "Se o IC95% nao inclui 1, a associacao e estatisticamente significativa.",
				13, UITheme.TEXTO_DIM))
	if saida.get_child_count() == 0:
		_vazio(corpo)


func _vazio(corpo: VBoxContainer) -> void:
	corpo.add_child(UITheme.paragrafo("Dados insuficientes para este teste com a amostra atual. "
		+ "Aumente o n na aba Amostragem.", 14, UITheme.PERIGO))


func _linha_teste(rot: String, val: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := UITheme.rotulo(rot.to_upper(), 11, UITheme.TEXTO_FRACO)
	l.custom_minimum_size.x = 190
	h.add_child(l)
	var v := Label.new()
	v.text = val
	v.add_theme_font_override("font", UITheme.corpo(600))
	v.add_theme_font_size_override("font_size", 15)
	v.add_theme_color_override("font_color", UITheme.TEXTO)
	h.add_child(v)
	return h


func _texto_t(p: float, lo: float, hi: float) -> String:
	if p < 0.05:
		if lo > 0.0 or hi < 0.0:
			return "O intervalo de confianca da diferenca exclui o zero: ha evidencia de diferenca real entre os grupos."
		return "O p-valor e pequeno, mas o IC inclui o zero — resultado fragil, tipico de amostra pequena."
	return "O intervalo de confianca inclui o zero: os dados sao compativeis com ausencia de diferenca. Ausencia de evidencia nao e evidencia de ausencia."


# ============================================================================
# ABA 6 - REGRESSAO
# ============================================================================

func _aba_regressao() -> void:
	var raiz := VBoxContainer.new()
	raiz.name = "Regressao"
	raiz.add_theme_constant_override("separation", 10)
	_tab.add_child(raiz)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 8)
	raiz.add_child(ctrl)
	var sel := OptionButton.new()
	sel.fit_to_longest_item = false
	sel.clip_text = true
	sel.custom_minimum_size = Vector2(220, 34)
	sel.add_item("Linear: biomarcador ~ idade")
	sel.add_item("Linear: renda ~ idade")
	sel.add_item("Logistica: chance de estar infectado (idade + renda + saneamento + doses)")
	sel.select(2)
	sel.custom_minimum_size.x = 420
	ctrl.add_child(sel)
	ctrl.add_child(UITheme.botao("Rodar modelo", func(): _rodar_regressao(sel.selected), null, UITheme.SUCESSO))
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.add_child(esp)

	var corpo := HBoxContainer.new()
	corpo.add_theme_constant_override("separation", 12)
	corpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(corpo)
	var g := StatChartCanvas.new()
	g.name = "Canvas"
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.size_flags_stretch_ratio = 1.2
	corpo.add_child(g)
	var out := UITheme.card("SAIDA DO MODELO", UITheme.ACENTO)
	out.name = "Saida"
	out.custom_minimum_size.x = 440
	corpo.add_child(out)

	_rodar_regressao(2)


func _rodar_regressao(tipo: int) -> void:
	var aba := _tab.get_node_or_null("Regressao")
	if aba == null:
		return
	var g := aba.find_child("Canvas", true, false) as StatChartCanvas
	var out := aba.find_child("Saida", true, false) as PanelContainer
	if out == null:
		return
	var corpo := UITheme.conteudo(out)
	for ch in corpo.get_children():
		ch.queue_free()
	if g:
		g.limpar()
	if tipo == 0 or tipo == 1:
		var xv := Population.vetor_numerico(_amostra, "idade")
		var yv := Population.vetor_numerico(_amostra,
			"biomarcador_clinico" if tipo == 0 else "renda_familiar_sm")
		var r := StatCore.linear_regression(xv, yv)
		if r.has("erro"):
			corpo.add_child(UITheme.paragrafo(str(r["erro"]), 14, UITheme.PERIGO))
			return
		var pts := PackedVector2Array()
		var n := mini(xv.size(), yv.size())
		for i in range(n):
			pts.append(Vector2(xv[i], yv[i]))
		if g:
			g.titulo = "Retas de minimos quadrados"
			g.definir_dispersao(pts, "idade", "y")
			g.adicionar_reta(float(r["b0"]), float(r["b1"]), UITheme.ACENTO,
				"y = %.2f + %.3f x" % [float(r["b0"]), float(r["b1"])])
		corpo.add_child(_linha_teste("Modelo", "y = b0 + b1·x"))
		corpo.add_child(_linha_teste("b0 (intercepto)", "%.4f" % float(r["b0"])))
		corpo.add_child(_linha_teste("b1 (inclinacao)", "%.6f" % float(r["b1"])))
		corpo.add_child(_linha_teste("Erro padrao de b1", "%.6f" % float(r.get("se_b1", 0.0))))
		corpo.add_child(_linha_teste("t de b1", "%.4f" % float(r.get("t", 0.0))))
		corpo.add_child(_linha_teste("p", StatCore.fmt_p(float(r.get("p", 1.0)))))
		var pr := StatCore.pearson(xv, yv)
		corpo.add_child(_linha_teste("r de Pearson", "%.4f" % float(pr.get("r", 0.0))))
		corpo.add_child(_linha_teste("R2", "%.4f" % float(r["r2"])))
		corpo.add_child(_linha_teste("n", str(int(r.get("n", n)))))
		corpo.add_child(UITheme.paragrafo(
			("R2 = %.1f%% da variacao de y e explicada por x. Inclinacao de %.4f "
			% [float(r["r2"]) * 100.0, float(r["b1"])])
			+ "indica que y cresce com x. Correlacao nao implica causalidade: aqui as duas "
			+ "variaveis foram geradas pelo simulador com a mesma estrutura de idade.", 12,
			UITheme.TEXTO_DIM))
		return

	# ---- logistica ----
	var y := PackedFloat64Array()
	var X: Array = []
	for i in _amostra:
		var infectado := 1.0 if Population.estado_de(i) == Population.ESTADO_INFECTADO \
			or Population.estado_de(i) == Population.ESTADO_EXPOSTO else 0.0
		y.append(infectado)
		var idade := Population.idade_de(i)
		var renda := float(Population.valor(i, "renda_familiar_sm"))
		var san := 1.0 if str(Population.valor(i, "saneamento_domiciliar")) == "Sim" else 0.0
		var doses := float(Population.doses_de(i))
		X.append(PackedFloat64Array([idade / 10.0, renda, san, doses]))
	var rl := StatCore.logistic_regression(X, y, 0.5, 700)
	if rl.has("erro"):
		corpo.add_child(UITheme.paragrafo(str(rl["erro"]), 14, UITheme.PERIGO))
		return
	var pesos: PackedFloat64Array = rl["pesos"]
	var nomes := ["idade/10", "renda (SM)", "saneamento", "doses"]
	corpo.add_child(UITheme.paragrafo(
		"Desfecho: estar infectado ou exposto no momento da amostra. Modelo logit com 4 "
		+ "preditores, ajustado por descida de gradiente.", 12, UITheme.TEXTO_DIM))
	for k in range(pesos.size()):
		var orv := exp(pesos[k])
		corpo.add_child(_linha_teste("b(%s)" % nomes[k], "%.4f   OR = %.3f" % [pesos[k], orv]))
	corpo.add_child(_linha_teste("b0 (intercepto)", "%.4f" % float(rl["bias"])))
	corpo.add_child(UITheme.separador())
	var tr: Dictionary = rl["treino"]
	var te: Dictionary = rl["teste"]
	corpo.add_child(_linha_teste("Acuracia (treino)", "%.1f%%  n=%d" % [
		float(tr.get("acuracia", 0.0)) * 100.0, int(rl["n_treino"])]))
	corpo.add_child(_linha_teste("Acuracia (teste)", "%.1f%%  n=%d" % [
		float(te.get("acuracia", 0.0)) * 100.0, int(rl["n_teste"])]))
	corpo.add_child(_linha_teste("Sensibilidade", "%.1f%%" % (float(te.get("sensibilidade", 0.0)) * 100.0)))
	corpo.add_child(_linha_teste("Especificidade", "%.1f%%" % (float(te.get("especificidade", 0.0)) * 100.0)))
	var positivos := 0
	for v in y:
		positivos += int(v)
	if positivos < 10 or (float(te.get("sensibilidade", 0.0)) <= 0.0 \
			and float(te.get("acuracia", 0.0)) >= 0.90):
		var aviso := UITheme.card("ATENCAO: DESFECHO RARO", UITheme.PERIGO)
		UITheme.conteudo(aviso).add_child(UITheme.paragrafo(
			"A amostra tem apenas %d %s (infectados ou expostos) em %d individuos. "
			% [positivos, "positivo" if positivos == 1 else "positivos", y.size()]
			+ "Com desfecho raro, a acuracia pode parecer alta so porque o modelo aprendeu a "
			+ "dizer 'todos negativos': a sensibilidade fica em 0%% e nenhum caso real e "
			+ "detectado. Leia sensibilidade, especificidade e AUC — nunca a acuracia isolada. "
			+ "Aumente o n, filtre uma vila com surto ativo ou sorteie uma amostra com mais "
			+ "expostos.", 13, UITheme.TEXTO))
		corpo.add_child(aviso)
	corpo.add_child(UITheme.paragrafo(
		"OR > 1 aumenta a chance do desfecho; OR < 1 protege. Compare as magnitudes: o "
		+ "preditor com OR mais distante de 1 e o que mais pesa no modelo.", 12, UITheme.TEXTO_DIM))
	if g:
		# ROC a partir dos escores previstos (amostra completa)
		var scores: Array = []
		var labels: Array = []
		var p := pesos.size()
		for i in range(X.size()):
			var xi: PackedFloat64Array = X[i]
			var z := float(rl["bias"])
			for k in range(p):
				z += pesos[k] * xi[k]
			scores.append(1.0 / (1.0 + exp(-clampf(z, -30.0, 30.0))))
			labels.append(int(y[i]))
		var auc := StatCore.roc_auc(scores, labels)
		var roc := StatCore.roc_curve(scores, labels)
		var fpr: PackedFloat64Array = roc["fpr"]
		var tpr: PackedFloat64Array = roc["tpr"]
		var pts := PackedVector2Array()
		var passo := maxi(1, fpr.size() / 120)
		var k2 := 0
		while k2 < fpr.size():
			pts.append(Vector2(fpr[k2], tpr[k2]))
			k2 += passo
		pts.append(Vector2(1.0, 1.0))
		g.titulo = "Curva ROC do modelo logistico"
		g.definir_roc(pts, auc)
		corpo.add_child(_linha_teste("AUC (ROC)", "%.4f" % auc))


# ============================================================================
# AUXILIARES DE DADOS
# ============================================================================

func _numericas() -> Array:
	var out: Array = []
	for v in Population.VARIAVEIS:
		if str(v["tipo"]).begins_with("quantitativa"):
			out.append(v)
	out.append({"id": "risco_hospitalizacao", "rotulo": "Risco de hospitalizacao (0-1)",
		"tipo": "quantitativa_continua"})
	return out


func _categoricas() -> Array:
	var out: Array = []
	for v in Population.VARIAVEIS:
		if str(v["tipo"]).begins_with("qualitativa"):
			out.append(v)
	out.append({"id": "infectado_agora", "rotulo": "Infectado agora (Sim/Nao)",
		"tipo": "qualitativa_nominal"})
	out.append({"id": "vacinado", "rotulo": "Vacinado (Sim/Nao)", "tipo": "qualitativa_nominal"})
	return out


func _valor_cat(i: int, nome: String) -> String:
	match nome:
		"infectado_agora":
			var e := Population.estado_de(i)
			return "Sim" if e == Population.ESTADO_INFECTADO or e == Population.ESTADO_EXPOSTO else "Nao"
		"vacinado":
			return "Sim" if Population.doses_de(i) > 0 else "Nao"
	return str(Population.valor(i, nome))


func _valor_num(i: int, nome: String) -> float:
	if nome == "risco_hospitalizacao":
		return Population.risco_de(i)
	return float(Population.valor(i, nome))


func _grupos(var_num: String, var_cat: String) -> Dictionary:
	var out := {}
	for i in _amostra:
		var g := _valor_cat(i, var_cat)
		# PackedFloat64Array e tipo por valor: precisamos ler, alterar e gravar de volta
		var arr: PackedFloat64Array = out.get(g, PackedFloat64Array())
		arr.append(_valor_num(i, var_num))
		out[g] = arr
	return out


func _tabela_cruzada(var_a: String, var_b: String) -> Dictionary:
	var linhas_idx := {}
	var cols_idx := {}
	for i in _amostra:
		linhas_idx[_valor_cat(i, var_a)] = true
		cols_idx[_valor_cat(i, var_b)] = true
	var linhas: Array = linhas_idx.keys()
	var colunas: Array = cols_idx.keys()
	linhas.sort()
	colunas.sort()
	if linhas.size() < 2 or colunas.size() < 2:
		return {}
	var tab: Array = []
	for _l in linhas:
		var linha: Array = []
		for _c in colunas:
			linha.append(0)
		tab.append(linha)
	for i in _amostra:
		var li := linhas.find(_valor_cat(i, var_a))
		var ci := colunas.find(_valor_cat(i, var_b))
		if li >= 0 and ci >= 0:
			(tab[li] as Array)[ci] = int((tab[li] as Array)[ci]) + 1
	return {"tabela": tab, "linhas": linhas, "colunas": colunas}


func _tabela_2x2(var_exp: String) -> Dictionary:
	var niveis := {}
	for i in _amostra:
		niveis[_valor_cat(i, var_exp)] = true
	var chaves: Array = niveis.keys()
	if chaves.size() != 2:
		return {}
	chaves.sort()
	var a := 0
	var b := 0
	var c := 0
	var d := 0
	for i in _amostra:
		var exposto := _valor_cat(i, var_exp) == str(chaves[0])
		var e := Population.estado_de(i)
		var infectado := e == Population.ESTADO_INFECTADO or e == Population.ESTADO_EXPOSTO
		if exposto and infectado:
			a += 1
		elif exposto:
			b += 1
		elif infectado:
			c += 1
		else:
			d += 1
	return {"a": a, "b": b, "c": c, "d": d, "nivel": chaves[0]}


# ---------------------------------------------------------------------------
func _options(no: Node) -> Array:
	var out: Array = []
	_coletar_options(no, out)
	return out


func _coletar_options(no: Node, out: Array) -> void:
	for c in no.get_children():
		if c is OptionButton:
			out.append(c)
		else:
			_coletar_options(c, out)


func _primeiro_option(no: Node) -> OptionButton:
	var o := _options(no)
	return o[0] if o.size() > 0 else null


func _segundo_option(no: Node) -> OptionButton:
	var o := _options(no)
	return o[1] if o.size() > 1 else null


func _mil(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return out
