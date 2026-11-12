class_name MinigameBase
extends Control
## Base dos nove desafios do StaTown.
##
## Cada desafio devolve um Array de rodadas:
##   {enunciado, midia (Control opcional), opcoes: Array[String],
##    correta: int, explicacao: String}
## A base cuida do layout, do placar, do feedback e da recompensa em BioMoedas.

signal encerrado

var main: Control
var id_jogo := "desafio"
var titulo_jogo := "Desafio"
var subtitulo_jogo := ""
var cor_jogo := UITheme.ACENTO
var rodadas: Array = []
var indice := 0
var acertos := 0
var respondido := false

var _progresso: ProgressBar
var _lbl_progresso: Label
var _bloco_questao: VBoxContainer
var _bloco_opcoes: VBoxContainer
var _bloco_feedback: VBoxContainer
var _botao_proxima: Button


func _init(m: Control) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_montar()
	_iniciar()


func _montar() -> void:
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margem.add_theme_constant_override(lado, 18)
	add_child(margem)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margem.add_child(col)

	# cabecalho
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 12)
	col.add_child(cab)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(v)
	var t := Label.new()
	t.text = titulo_jogo
	t.add_theme_font_override("font", UITheme.titulo_font(true))
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", cor_jogo)
	v.add_child(t)
	v.add_child(UITheme.rotulo(subtitulo_jogo, 13, UITheme.TEXTO_DIM))
	cab.add_child(UITheme.botao("Sair", func(): encerrado.emit(), null, UITheme.PERIGO))

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 10)
	col.add_child(linha)
	_progresso = UITheme.barra(0.0, 1.0, cor_jogo, 10)
	_progresso.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(_progresso)
	_lbl_progresso = UITheme.rotulo("", 13, UITheme.TEXTO_DIM)
	linha.add_child(_lbl_progresso)

	# cartao da questao
	var cartao := UITheme.card("", cor_jogo)
	cartao.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cartao)
	var corpo := UITheme.conteudo(cartao)
	_bloco_questao = UITheme.vbox(10)
	corpo.add_child(_bloco_questao)
	_bloco_opcoes = UITheme.vbox(8)
	corpo.add_child(_bloco_opcoes)
	_bloco_feedback = UITheme.vbox(8)
	corpo.add_child(_bloco_feedback)

	var rodape := HBoxContainer.new()
	rodape.add_theme_constant_override("separation", 10)
	col.add_child(rodape)
	_botao_proxima = UITheme.botao("Proxima", _proxima, null, UITheme.SUCESSO)
	_botao_proxima.visible = false
	rodape.add_child(_botao_proxima)
	rodape.add_child(UITheme.rotulo("Responda para liberar a proxima rodada.", 12, UITheme.TEXTO_FRACO))


func _iniciar() -> void:
	rodadas = _gerar_rodadas()
	indice = 0
	acertos = 0
	_mostrar()


func _gerar_rodadas() -> Array:
	return []


func _limpar(no: Node) -> void:
	for c in no.get_children():
		c.queue_free()


func _mostrar() -> void:
	respondido = false
	_botao_proxima.visible = false
	_limpar(_bloco_questao)
	_limpar(_bloco_opcoes)
	_limpar(_bloco_feedback)
	if indice >= rodadas.size():
		_finalizar()
		return
	var total := rodadas.size()
	_progresso.value = float(indice) / float(total)
	_lbl_progresso.text = "Rodada %d de %d  ·  %d acerto(s)" % [indice + 1, total, acertos]

	var r: Dictionary = rodadas[indice]
	_bloco_questao.add_child(UITheme.rotulo("SITUACAO %d" % (indice + 1), 12, UITheme.TEXTO_FRACO))
	var enun := UITheme.paragrafo(str(r.get("enunciado", "")), 17, UITheme.TEXTO)
	enun.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bloco_questao.add_child(enun)
	if r.has("midia") and r["midia"] != null:
		var mid: Control = r["midia"]
		mid.custom_minimum_size.y = maxf(mid.custom_minimum_size.y, 190.0)
		_bloco_questao.add_child(mid)

	var opcoes: Array = r.get("opcoes", [])
	for k in range(opcoes.size()):
		var b := UITheme.botao("%s. %s" % [str("ABCDEFGH")[k], str(opcoes[k])],
			_botao_resposta.bind(k), null, UITheme.INFO)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.y = 46
		_bloco_opcoes.add_child(b)


func _botao_resposta(k: int) -> void:
	if respondido:
		return
	respondido = true
	var r: Dictionary = rodadas[indice]
	var correta := int(r.get("correta", 0))
	if k == correta:
		acertos += 1

	# pinta as opcoes
	var botoes := _bloco_opcoes.get_children()
	for i in range(botoes.size()):
		var b := botoes[i]
		if i == correta:
			_colorir_botao(b, UITheme.SUCESSO)
		elif i == k:
			_colorir_botao(b, UITheme.PERIGO)

	var acertou := k == correta
	if acertou:
		Audio.sfx("sucesso", -8.0)
	else:
		Audio.sfx("erro", -6.0)
	var cab := UITheme.paragrafo(("Correto!" if acertou else "Nao exatamente."), 19,
		UITheme.SUCESSO if acertou else UITheme.PERIGO)
	_bloco_feedback.add_child(cab)
	var ex := UITheme.paragrafo(str(r.get("explicacao", "")), 15, UITheme.TEXTO_DIM)
	ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bloco_feedback.add_child(ex)
	_botao_proxima.visible = true
	_botao_proxima.text = "Ver resultado" if indice + 1 >= rodadas.size() else "Proxima"
	_lbl_progresso.text = "Rodada %d de %d  ·  %d acerto(s)" % [indice + 1, rodadas.size(), acertos]


func _colorir_botao(b: Node, cor: Color) -> void:
	if b is Button:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(cor.r, cor.g, cor.b, 0.28)
		sb.border_color = cor
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(7)
		(b as Button).add_theme_stylebox_override("normal", sb)
		(b as Button).add_theme_color_override("font_color", cor)


func _proxima() -> void:
	indice += 1
	_mostrar()


func _finalizar() -> void:
	_limpar(_bloco_questao)
	_limpar(_bloco_opcoes)
	_limpar(_bloco_feedback)
	_botao_proxima.visible = false
	_progresso.value = 1.0
	_lbl_progresso.text = "Concluido"
	var total := rodadas.size()
	var pct := float(acertos) / float(maxi(total, 1))
	var moedas := 10 + int(round(60.0 * pct))
	GameState.registrar_minigame(id_jogo, acertos, total, moedas)
	Audio.sfx("moeda", -5.0)

	var tit := "Desafio concluido"
	if pct >= 0.9:
		tit = "Excelente — dominio do conceito"
	elif pct >= 0.7:
		tit = "Bom desempenho"
	elif pct >= 0.5:
		tit = "No caminho certo"
	else:
		tit = "Vale revisar o conceito"

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_bloco_questao.add_child(v)
	v.add_child(UITheme.rotulo(tit.to_upper(), 13, cor_jogo))
	v.add_child(UITheme.kpi("%d / %d" % [acertos, total], "acertos", cor_jogo, 46))
	v.add_child(UITheme.rotulo("Aproveitamento: %.0f%%   ·   +%d BioMoedas" % [pct * 100.0, moedas],
		16, UITheme.ACENTO))
	v.add_child(UITheme.paragrafo(_mensagem_final(pct), 15, UITheme.TEXTO_DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	h.add_child(UITheme.botao("Jogar de novo", func():
		indice = 0
		acertos = 0
		_mostrar(), null, UITheme.SUCESSO))
	h.add_child(UITheme.botao("Voltar aos desafios", func(): encerrado.emit(), null, UITheme.INFO))


func _mensagem_final(pct: float) -> String:
	if pct >= 0.9:
		return "Voce ja interpreta esse conceito com seguranca. Tente agora aplicar em uma analise real do BioLab."
	if pct >= 0.6:
		return "Boa base. Reveja as explicacoes das questoes erradas e repita: a repeticao espacada e o que fixa o conceito."
	return "Sem problema — errar aqui e barato. Leia a explicacao de cada rodada e volte em alguns minutos; o objetivo e entender o criterio, nao acertar de primeira."


# ---------------------------------------------------------------------------
# utilitarios compartilhados pelos desafios
# ---------------------------------------------------------------------------

func _embaralhar(opcoes: Array, correta: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pares: Array = []
	for i in range(opcoes.size()):
		pares.append([opcoes[i], i == correta])
	for i in range(pares.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pares[i]
		pares[i] = pares[j]
		pares[j] = tmp
	var out: Array = []
	var nc := 0
	for k in range(pares.size()):
		out.append(pares[k][0])
		if bool(pares[k][1]):
			nc = k
	return {"opcoes": out, "correta": nc}
