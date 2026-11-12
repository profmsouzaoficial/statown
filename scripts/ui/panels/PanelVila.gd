class_name PanelVila
extends Control
## Painel de uma vila: indicadores em tempo real, series historicas,
## projecao de leitos e as quatro intervencoes pagas com BioMoedas.

const CUSTO := {"saneamento": 60, "vacinacao": 80, "ubs": 120, "hospital": 260}
const DESCRICAO := {
	"saneamento": "Rede de esgoto e agua tratada (+20 p.p. de cobertura). Reduz a forca de infecção de agravos de veiculação hídrica e a letalidade geral.",
	"vacinacao": "Campanha de vacinação (+25 p.p.). Protege suscetíveis e reduz casos graves — o efeito aparece em 2 a 3 semanas.",
	"ubs": "Unidade Básica de Saúde: +12 leitos e atendimento precoce, reduzindo a letalidade intra-hospitalar.",
	"hospital": "Hospital de campanha: +45 leitos. Principal freio da saturação em surtos rápidos.",
}

var main: Control
var vila_id: int

var _raiz: HBoxContainer
var _col_esq: VBoxContainer
var _col_dir: VBoxContainer


func _init(m: Control, id: int) -> void:
	main = m
	vila_id = id
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# o painel tem muito conteudo (KPIs, graficos e projecao): rola na vertical
	var rol := UITheme.scroll()
	rol.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rol)
	var margem := MarginContainer.new()
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margem.add_theme_constant_override(lado, 16)
	rol.add_child(margem)

	_raiz = HBoxContainer.new()
	_raiz.add_theme_constant_override("separation", 14)
	margem.add_child(_raiz)

	_col_esq = VBoxContainer.new()
	_col_esq.add_theme_constant_override("separation", 12)
	_col_esq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_esq.size_flags_stretch_ratio = 2.1
	_raiz.add_child(_col_esq)

	_col_dir = VBoxContainer.new()
	_col_dir.add_theme_constant_override("separation", 12)
	_col_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_dir.size_flags_stretch_ratio = 1.0
	_raiz.add_child(_col_dir)

	_reconstruir()


func _reconstruir() -> void:
	for c in _col_esq.get_children():
		c.queue_free()
	for c in _col_dir.get_children():
		c.queue_free()
	var v := Vilas.get_vila(vila_id)
	if v.is_empty():
		return
	_montar_cabecalho(v)
	_montar_kpis(v)
	_montar_graficos(v)
	_montar_projecao(v)
	_montar_intervencoes(v)
	_montar_contexto(v)


# ---------------------------------------------------------------------------

func _montar_cabecalho(v: Dictionary) -> void:
	var p := UITheme.painel(UITheme.BG_CARD, UITheme.BORDA, 10, 14)
	_col_esq.add_child(p)
	var h := UITheme.hbox(14)
	p.add_child(h)

	var ic := TextureRect.new()
	ic.texture = Assets.icone_doenca(GameState.doenca_id)
	ic.custom_minimum_size = Vector2(40, 40)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	h.add_child(ic)

	var vv := UITheme.vbox(2)
	vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vv)
	vv.add_child(UITheme.titulo(str(v["nome"]), 22, UITheme.TEXTO, true))
	vv.add_child(UITheme.rotulo("%s · %s habitantes" % [str(v["perfil"]).to_upper(),
		_fmt_mil(int(v["populacao"]))], 12, UITheme.TEXTO_DIM))

	var badges := UITheme.hbox(6)
	h.add_child(badges)
	if bool(Epidemic.em_surto.get(vila_id, false)):
		badges.add_child(UITheme.badge("SURTO ATIVO", UITheme.PERIGO))
	else:
		badges.add_child(UITheme.badge("SEM SURTO", UITheme.SUCESSO))
	var rt_v := Epidemic.rt(vila_id)
	if rt_v <= 0.0:
		badges.add_child(UITheme.badge("Rt nao estimavel", UITheme.TEXTO_FRACO))
	elif rt_v > 1.0:
		badges.add_child(UITheme.badge("Rt %.2f ↑" % rt_v, UITheme.PERIGO))
	else:
		badges.add_child(UITheme.badge("Rt %.2f ↓" % rt_v, UITheme.ACENTO_2))


func _montar_kpis(v: Dictionary) -> void:
	var p := UITheme.painel(UITheme.BG_PANEL, UITheme.BORDA, 10, 12)
	_col_esq.add_child(p)
	var g := UITheme.grade(4, 10, 8)
	p.add_child(g)
	var prev := Epidemic.prevalencia(vila_id)
	var inf := Epidemic.infectados(vila_id)
	var inc := Epidemic.incidencia_semana(vila_id)
	var ocup := Vilas.ocupacao_leitos(vila_id)
	var graves := float(inf) * 0.12
	var leitos := float(v.get("leitos", 0))
	var rt_v := Epidemic.rt(vila_id)
	g.add_child(UITheme.kpi("%.2f%%" % (prev * 100.0), "PREVALENCIA", _cor_prev(prev), 26,
		"Proporcao de moradores com infeccao ativa agora (expostos + infectados) sobre a populacao viva da vila. Por definicao fica entre 0% e 100%."))
	g.add_child(UITheme.kpi(str(inf), "CASOS ATIVOS", UITheme.TEXTO, 26,
		"Pessoas expostas (incubando) ou infectadas hoje. Exposto ainda nao transmite; entra na prevalencia porque ja esta infectado."))
	g.add_child(UITheme.kpi(str(inc), "NOVOS NA SEMANA", UITheme.INFO, 26,
		"Casos novos diagnosticados nesta semana epidemiologica (incidencia)."))
	var rt_txt := "%.2f" % rt_v if rt_v > 0.0 else "—"
	g.add_child(UITheme.kpi(rt_txt, "Rt", _cor_rt(rt_v), 26))
	g.add_child(UITheme.kpi(str(Epidemic.obitos(vila_id)), "OBITOS PELA DOENCA", UITheme.PERIGO, 26,
		"Mortes atribuidas a doenca. Mortes naturais (outras causas) ficam fora deste numero e aparecem no contexto demografico."))
	g.add_child(UITheme.kpi(str(Epidemic.recuperados(vila_id)), "RECUPERADOS", UITheme.SUCESSO, 26))
	# Mostrar "graves/leitos" em vez de "300%" evita um numero que parece erro
	# de conta. A razao continua informando a superlotacao (ex.: 30/10) e o
	# jogador ve a capacidade real ao lado da demanda.
	g.add_child(UITheme.kpi("%d/%d" % [int(round(graves)), int(leitos)], "GRAVES / LEITOS",
		UITheme.PERIGO if ocup > 0.9 else UITheme.TEXTO, 26,
		"Pacientes graves estimados (12% dos infectados) e leitos disponiveis. Quando os graves superam os leitos, a razao mostra a superlotacao sem inventar porcentagens acima de 100%."))
	g.add_child(UITheme.kpi("%d" % int(v["leitos"]), "LEITOS", UITheme.TEXTO, 26))


func _montar_graficos(v: Dictionary) -> void:
	var hist := Vilas.historico(vila_id)
	var linha := StatChartCanvas.new()
	linha.titulo = "Prevalencia por semana epidemiologica"
	linha.formato_y = "pct"
	linha.custom_minimum_size.y = 200
	var pts := PackedVector2Array()
	var ini := maxi(0, hist.size() - 40)
	for k in range(ini, hist.size()):
		var h: Dictionary = hist[k]
		pts.append(Vector2(float(h.get("se", k)), float(h.get("prevalencia", 0.0))))
	if pts.size() >= 2:
		linha.definir_linhas([{"nome": "prevalencia", "cor": UITheme.ACENTO, "pontos": pts}], "SE", "")
	else:
		# Menos de 2 semanas: o canvas mostra "avance a simulacao para ver a curva".
		linha.definir_linhas([{"nome": "aguardando", "cor": UITheme.TEXTO_FRACO,
			"pontos": pts}], "SE", "")
	_col_esq.add_child(linha)

	var barras := StatChartCanvas.new()
	barras.titulo = "Novos casos por semana"
	barras.formato_y = "int"
	barras.custom_minimum_size.y = 170
	var rot: Array = []
	var val: Array = []
	var ini2 := maxi(0, hist.size() - 16)
	for k in range(ini2, hist.size()):
		var h2: Dictionary = hist[k]
		rot.append(str(h2.get("se", k)))
		val.append(float(h2.get("novos", 0)))
	if val.is_empty():
		rot = ["-"]
		val = [0.0]
	barras.definir_barras(rot, val, [], "casos")
	_col_esq.add_child(barras)


func _montar_projecao(v: Dictionary) -> void:
	var p := UITheme.painel(UITheme.BG_PANEL, UITheme.BORDA, 10, 12)
	_col_esq.add_child(p)
	var vv := UITheme.vbox(6)
	p.add_child(vv)
	vv.add_child(UITheme.rotulo("PROJECAO DE LEITOS (8 SEMANAS, Rt CONSTANTE)", 12, UITheme.ACENTO))
	var proj := Epidemic.projetar_leitos(vila_id, 8)
	var leitos := float(proj["leitos"])
	var cab := UITheme.linha_tabela(["SE", "Infectados", "Graves (12%)", "Leitos", "Graves/Leitos"],
		[1.0, 1.4, 1.4, 1.0, 1.4], [UITheme.TEXTO_FRACO, UITheme.TEXTO_FRACO,
		UITheme.TEXTO_FRACO, UITheme.TEXTO_FRACO, UITheme.TEXTO_FRACO], 12, true)
	vv.add_child(cab)
	for k in range(8):
		var inf_k := float(proj["infectados"][k])
		var graves := inf_k * 0.12
		var ocup := float(proj["ocupacao"][k])
		var graves_k := float(proj["graves"][k]) if proj.has("graves") else inf_k * 0.12
		var cor := UITheme.TEXTO
		if ocup > 1.0:
			cor = UITheme.PERIGO
		elif ocup > 0.8:
			cor = UITheme.ACENTO
		vv.add_child(UITheme.linha_tabela([
			"+%d" % (k + 1), str(int(round(inf_k))), "%.1f" % graves, str(int(leitos)),
			"%d/%d" % [int(round(graves_k)), int(leitos)]],
			[1.0, 1.4, 1.4, 1.0, 1.4],
			[UITheme.TEXTO_DIM, UITheme.TEXTO, UITheme.TEXTO, UITheme.TEXTO_DIM, cor], 13))
	var ps := Epidemic.prob_superlotacao(vila_id, 4)
	vv.add_child(UITheme.separador())
	vv.add_child(UITheme.paragrafo(
		"P(superlotacao em 4 SE) = %.1f%%   ·   graves esperados = %.1f   ·   leitos = %d   ·   n = %d   ·   p = 0,12" % [
			float(ps["p"]) * 100.0, float(ps["graves_esperados"]), int(float(ps["leitos"])),
			int(ps["n"])],
		13, UITheme.TEXTO_DIM))
	vv.add_child(UITheme.paragrafo(
		"Ocupacao acima de 100% significa mais pacientes graves do que leitos: e superlotacao, nao erro de conta. A projecao mantem o Rt atual constante.",
		12, UITheme.TEXTO_FRACO))


func _montar_intervencoes(v: Dictionary) -> void:
	var p := UITheme.card("INTERVENCOES", UITheme.ACENTO)
	_col_dir.add_child(p)
	var vv := UITheme.conteudo(p)
	vv.add_child(UITheme.paragrafo("Cada acao custa BioMoedas e altera os parametros da vila imediatamente.",
		13, UITheme.TEXTO_DIM))
	for chave in ["saneamento", "vacinacao", "ubs", "hospital"]:
		var custo: int = CUSTO[chave]
		var ja := ""
		if chave == "saneamento":
			ja = "atual %d%%" % int(float(v["saneamento"]) * 100.0)
		elif chave == "vacinacao":
			ja = "atual %d%%" % int(float(v["cobertura_vacinal"]) * 100.0)
		elif chave == "ubs":
			ja = "%d unidade(s)" % int(v["ubs"])
		else:
			ja = "%d unidade(s)" % int(v["hospital"])
		var b := UITheme.botao("%s  ·  %s  ·  %d B" % [chave.capitalize(), ja, custo],
			func(): _comprar(chave), null,
			UITheme.SUCESSO if GameState.moedas >= custo else UITheme.BORDA)
		b.tooltip_text = DESCRICAO[chave]
		b.disabled = GameState.moedas < custo
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		vv.add_child(b)


func _montar_contexto(v: Dictionary) -> void:
	var p := UITheme.card("CONTEXTO E MOBILIDADE", UITheme.INFO)
	_col_dir.add_child(p)
	var vv := UITheme.conteudo(p)
	vv.add_child(UITheme.campo("Saneamento", "%d%%" % int(float(v["saneamento"]) * 100.0)))
	vv.add_child(UITheme.campo("Cobertura vacinal", "%d%%" % int(float(v["cobertura_vacinal"]) * 100.0)))
	vv.add_child(UITheme.campo("Leitos por mil habitantes",
		"%.2f" % (float(v["leitos"]) / maxf(float(v["populacao"]), 1.0) * 1000.0)))
	vv.add_child(UITheme.campo("Renda media", "%.1f salarios minimos" % float(v["renda_media_sm"])))
	vv.add_child(UITheme.campo("Obitos naturais (outras causas)",
		str(int(v.get("obitos_naturais", 0))),
		"Mortes esperadas por idade e saneamento, fora do calculo da letalidade da doenca."))

	# quem chega aqui (mobilidade gravitacional)
	var vindos: Array = []
	for i in range(Vilas.vilas.size()):
		var outra := Vilas.vilas[i]
		if int(outra["id"]) == vila_id:
			continue
		var frac: float = float(Vilas.mobilidade[i][vila_id - 1])
		if frac > 0.012:
			vindos.append([str(outra["nome"]), frac])
	vindos.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var txt := ""
	for k in range(mini(3, vindos.size())):
		txt += "%s (%.1f%%)\n" % [vindos[k][0], float(vindos[k][1]) * 100.0]
	if txt != "":
		vv.add_child(UITheme.separador())
		vv.add_child(UITheme.rotulo("PRINCIPAIS FLUXOS DE ENTRADA", 11, UITheme.TEXTO_FRACO))
		vv.add_child(UITheme.paragrafo(txt.strip_edges(), 13, UITheme.TEXTO_DIM))

	vv.add_child(UITheme.separador())
	var b := UITheme.botao("Investigar no BioLab", func(): _abrir_lab(), null, UITheme.ROXO)
	vv.add_child(b)
	vv.add_child(UITheme.botao("Ver historico completo", func(): _ver_historico(), null, UITheme.INFO))


# ---------------------------------------------------------------------------

func _comprar(chave: String) -> void:
	var custo: int = CUSTO[chave]
	if not GameState.gastar_moedas(custo):
		main.mostrar_toast("BioMoedas insuficientes (%.0f B)" % custo, "erro")
		return
	match chave:
		"saneamento":
			Vilas.aplicar_saneamento(vila_id)
			main.animar_entrega(vila_id)
		"vacinacao":
			Vilas.aplicar_vacina(vila_id)
			main.animar_entrega(vila_id)
		"ubs":
			Vilas.construir_ubs(vila_id)
			main.animar_construcao(vila_id, "ubs")
		"hospital":
			Vilas.construir_hospital(vila_id)
			main.animar_construcao(vila_id, "hospital")
	main.mostrar_toast("%s aplicado em %s" % [chave.capitalize(),
		str(Vilas.get_vila(vila_id)["nome"])], "sucesso")
	_reconstruir()


func _abrir_lab() -> void:
	main.trocar_para("lab")


func _ver_historico() -> void:
	var hist := Vilas.historico(vila_id)
	var txt := "SE\tnovos\tativos\tobitos\tprev\n"
	for h in hist:
		txt += "%d\t%d\t%d\t%d\t%.4f\n" % [int(h.get("se", 0)), int(h.get("novos", 0)),
			int(h.get("infectados", 0)), int(h.get("obitos", 0)), float(h.get("prevalencia", 0.0))]
	DisplayServer.clipboard_set(txt)
	main.mostrar_toast("Historico da vila copiado para a area de transferencia (%d semanas)" % hist.size(),
		"info")


# ---------------------------------------------------------------------------

func _cor_prev(p: float) -> Color:
	if p > 0.08:
		return UITheme.PERIGO
	if p > 0.03:
		return UITheme.ACENTO
	return UITheme.SUCESSO


func _cor_rt(r: float) -> Color:
	if r > 1.2:
		return UITheme.PERIGO
	if r > 1.0:
		return UITheme.ACENTO
	return UITheme.SUCESSO


func _fmt_mil(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return out
