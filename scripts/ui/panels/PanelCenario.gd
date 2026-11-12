class_name PanelCenario
extends Control
## Escolha do agravo epidemiologico que sera simulado.
##
## O painel usa uma grade 2x2 dentro de um ScrollContainer: os cards tem altura
## propria (nunca sao comprimidos pelo modal) e o titulo quebra em duas linhas
## quando o nome do agravo e longo. Sem isso, nomes como "Virus Respiratorio
## Agudo" estouravam a borda direita e o botao "Ativar" vazava para fora do card
## em telas de 900 px.
##
## Largura/altura sao definidas por Main._abrir_troca_cenario() (1180x800).

var main: Control


func _init(m: Control) -> void:
	main = m
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margem.add_theme_constant_override(lado, 14)
	add_child(margem)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margem.add_child(col)

	col.add_child(UITheme.paragrafo(
		"O cenario define o agravo que circula no vale. Trocar de cenario reinicia a "
		+ "simulacao epidemiologica (a populacao e as BioMoedas sao mantidas). Cada agravo "
		+ "responde a um conjunto diferente de determinantes — e permite uma analise "
		+ "estatistica diferente.", 14, UITheme.TEXTO_DIM))

	var rolagem := UITheme.scroll()
	rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(rolagem)

	var grade := UITheme.grade(2, 14, 14)
	grade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(grade)

	for d in Epidemic.doencas.values():
		grade.add_child(_card(d))

	var rodape := UITheme.hbox(10)
	rodape.add_child(UITheme.rotulo(
		"A troca nao apaga o progresso: apenas reinicia a curva da doenca.", 12,
		UITheme.TEXTO_FRACO))
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rodape.add_child(esp)
	var cancelar := UITheme.botao("Cancelar", func(): main.fechar_modal())
	cancelar.custom_minimum_size = Vector2(140, 40)
	rodape.add_child(cancelar)
	col.add_child(rodape)


func _card(d: Dictionary) -> PanelContainer:
	var id := str(d["id"])
	var cor := Color(str(d["cor"]))
	var atual := id == GameState.doenca_id
	var p := UITheme.painel(UITheme.BG_CARD, cor if atual else UITheme.BORDA, 10, 12)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)

	# ---------------------------------------------------------------- cabecalho
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 10)
	v.add_child(cab)

	var ic := TextureRect.new()
	ic.texture = Assets.icone_doenca(id)
	ic.custom_minimum_size = Vector2(36, 36)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cab.add_child(ic)

	var vv := VBoxContainer.new()
	vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vv.add_theme_constant_override("separation", 2)
	cab.add_child(vv)
	var nome := UITheme.titulo(str(d["nome"]), 15, cor, true)
	nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vv.add_child(nome)
	var insp := UITheme.rotulo("inspirado em: " + str(d["inspiracao"]), 10,
		UITheme.TEXTO_FRACO)
	insp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vv.add_child(insp)
	if atual:
		var selo := UITheme.badge("ATIVO", cor)
		selo.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		cab.add_child(selo)

	# ---------------------------------------------------------------- descricao
	var desc := UITheme.paragrafo(str(d["descricao"]), 12, UITheme.TEXTO_DIM)
	desc.add_theme_constant_override("line_spacing", 1)
	v.add_child(desc)

	# ---------------------------------------------------------------- numeros
	var g := UITheme.grade(3, 6, 4)
	v.add_child(g)
	g.add_child(_mini("R0", "%.1f" % float(d.get("R0", 0.0)), cor))
	g.add_child(_mini("Incubacao", "%.1f SE" % float(d.get("incubacao_se", 0.0)), UITheme.TEXTO))
	g.add_child(_mini("Infeccioso", "%.1f SE" % float(d.get("infeccioso_se", 0.0)), UITheme.TEXTO))
	g.add_child(_mini("Letalidade", "%.1f%%" % (float(d.get("cfr_saturado", 0.0)) * 100.0), UITheme.PERIGO))
	g.add_child(_mini("Saneamento", "%.2f" % float(d.get("peso_saneamento", 0.0)), UITheme.SUCESSO))
	g.add_child(_mini("Vacina", "%.0f%%" % (float(d.get("eficacia_vacina", 0.0)) * 100.0), UITheme.INFO))

	# ---------------------------------------------------------------- textos
	var sintomas := UITheme.rotulo("SINTOMAS: " + str(d.get("sintomas", "")).to_upper(),
		9, UITheme.TEXTO_FRACO)
	sintomas.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sintomas)
	var bio := UITheme.rotulo("BIOMARCADOR: " + str(d.get("biomarcador", "")).to_upper(),
		9, UITheme.TEXTO_FRACO)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(bio)

	var b := UITheme.botao("Cenario ativo" if atual else "Ativar este cenario",
		func(): _trocar(id), null, cor if not atual else UITheme.BORDA)
	b.disabled = atual
	b.custom_minimum_size.y = 40
	v.add_child(b)
	return p


func _mini(rot: String, val: String, cor: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	# sem EXPAND a grade encolhe as colunas para a largura do texto e
	# "LETALIDADE"/"SANEAMENTO" quebram no meio da palavra
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	var l := Label.new()
	l.text = val
	l.add_theme_font_override("font", UITheme.titulo_font(true))
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", cor)
	v.add_child(l)
	var r := UITheme.rotulo(rot.to_upper(), 8, UITheme.TEXTO_FRACO)
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(r)
	return v


func _trocar(id: String) -> void:
	GameState.definir_doenca(id)
	Epidemic.reiniciar()
	Epidemic._semear()
	main.fechar_modal()
	# GameState.definir_doenca ja notifica; nao duplicar o toast
	main._atualizar_hud()
