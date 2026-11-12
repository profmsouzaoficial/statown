class_name PanelDrBayes
extends Control
## Dr. Bayes — tutor que responde rapido e, as vezes, erra.
##
## O aluno escolhe um tema, le a resposta e precisa apontar a frase incorreta
## (ou declarar que a resposta esta integralmente correta). E o treino de
## auditoria de IA aplicado a bioestatistica.

var main: Control

var _area_resposta: VBoxContainer
var _lbl_placar: Label
var _tema_atual := 0
var _auditados := {}
var _respondido := false

const TEMAS := [
	{
		"q": "O que significa um intervalo de confianca de 95%?",
		"frases": [
			"O IC95% e um intervalo calculado a partir dos dados da amostra.",
			"Ele indica que, se repetissemos o estudo muitas vezes, cerca de 95% dos intervalos "
				+ "construidos assim conteriam o verdadeiro parametro populacional.",
			"Portanto, ha 95% de probabilidade de o parametro estar dentro deste intervalo "
				+ "especifico ja calculado.",
		],
		"erro": 2,
		"porque": "A interpretacao frequencista classica nao atribui probabilidade ao parametro "
			+ "depois de observado: o intervalo especifico ou contem ou nao contem o valor "
			+ "verdadeiro. Os 95% referem-se ao procedimento, nao ao intervalo particular. "
			+ "(A leitura bayesiana, com priori, e outra conversa — e deve ser declarada.)",
	},
	{
		"q": "Como interpretar p = 0,02 em um teste de comparacao de medias?",
		"frases": [
			"Se a hipotese nula fosse verdadeira, a chance de observar uma diferenca tao grande "
				+ "quanto a encontrada seria de aproximadamente 2%.",
			"Isso indica que os dados sao pouco compativeis com a hipotese nula, ao nivel de "
				+ "significancia de 5%.",
			"Logo, a probabilidade de a hipotese nula ser verdadeira e de 2%.",
		],
		"erro": 2,
		"porque": "p = P(dados | H0), nao P(H0 | dados). Para inverter a condicional seria "
			+ "necessario um prior (teorema de Bayes). E o erro de interpretacao mais comum em "
			+ "artigos e em respostas de IA.",
	},
	{
		"q": "Um estudo achou correlacao de Pearson r = 0,71 entre renda e biomarcador. "
			+ "Posso concluir que a renda eleva o biomarcador?",
		"frases": [
			"r = 0,71 indica associacao linear positiva forte entre as duas variaveis.",
			"Correlacao nao estabelece causalidade: pode haver confundimento por idade, "
				+ "escolaridade ou acesso a servicos.",
			"Como r e alto, a relacao e necessariamente causal e a direcao e da renda para o "
				+ "biomarcador.",
		],
		"erro": 2,
		"porque": "r mede intensidade e direcao de associacao linear, sem informar direcao "
			+ "causal nem descartar confundidores. Para afirmar efeito, o desenho precisa "
			+ "sustentar a inferencia (coorte, quasi-experimento, ensaio).",
	},
	{
		"q": "Um teste tem sensibilidade de 90% e especificidade de 95%. Ele serve para "
			+ "triagem em populacao com prevalencia de 1%?",
		"frases": [
			"Sensibilidade e especificidade sao propriedades do teste e nao variam com a "
				+ "prevalencia.",
			"Com prevalencia de 1%, o valor preditivo positivo sera baixo, porque a maioria dos "
				+ "positivos sera falso-positivo.",
			"Como a sensibilidade e 90%, o VPP tambem sera de 90%.",
		],
		"erro": 2,
		"porque": "VPP depende da prevalencia. Com 1% de prevalencia, 90% de sensibilidade e "
			+ "95% de especificidade, o VPP fica em torno de 15%: a maioria dos positivos e "
			+ "falso-positivo. Para triagem isso pode ser aceitavel, desde que haja confirmacao.",
	},
	{
		"q": "O R0 de uma doenca e 2,8. O que isso quer dizer na pratica?",
		"frases": [
			"R0 e o numero medio de infeccoes secundarias geradas por um caso infeccioso em "
				+ "populacao totalmente suscetivel.",
			"Com R0 = 2,8, a fracao de imunidade necessaria para interromper a transmissao e "
				+ "aproximadamente 1 - 1/2,8 = 64%.",
			"R0 = 2,8 significa que 2,8% da populacao sera infectada em cada semana.",
		],
		"erro": 2,
		"porque": "R0 e uma razao de contagio por caso, nao uma porcentagem semanal da "
			+ "populacao. Alem disso, o R efetivo cai conforme a imunidade sobe — e e o Rt que "
			+ "acompanha a epidemia em tempo real.",
	},
	{
		"q": "Por que a amostragem aleatoria simples e considerada a referencia?",
		"frases": [
			"Porque cada individuo da populacao tem a mesma chance conhecida de ser sorteado.",
			"Isso garante que a estimativa seja nao viesada em expectativa, e o erro amostral "
				+ "pode ser calculado a partir do n.",
			"Porque garante que a amostra seja sempre representativa, sem erro amostral.",
		],
		"erro": 2,
		"porque": "AAS elimina o vies de selecao, mas o erro amostral continua existindo: ele "
			+ "diminui com o aumento de n, nunca zera. 'Representativa' nao e uma garantia "
			+ "automatica — e uma propriedade probabilistica.",
	},
	{
		"q": "Numa regressao logistica, um preditor tem OR = 2,1 (IC95% 1,4-3,2). Como leio?",
		"frases": [
			"OR maior que 1 indica maior chance do desfecho por unidade de aumento do preditor.",
			"Como o IC95% nao inclui 1, a associacao e estatisticamente significativa ao nivel "
				+ "de 5%.",
			"OR = 2,1 significa que o modelo acerta 210% das previsoes.",
		],
		"erro": 2,
		"porque": "OR e uma medida de associacao entre exposicao e desfecho, nao acuracia "
			+ "preditiva. Acuracia, sensibilidade e AUC sao metricas diferentes, calculadas "
			+ "sobre as previsoes do modelo.",
	},
	{
		"q": "Um estudo com 12 participantes encontrou p = 0,048. Posso tratar o achado como "
			+ "solido?",
		"frases": [
			"p = 0,048 esta abaixo de 0,05, portanto rejeita-se H0 ao nivel convencional.",
			"Com n = 12 e p tao proximo do limiar, o resultado e fragil: o IC deve ser largo e "
				+ "pequenas mudancas nos dados poderiam mudar a conclusao.",
			"Como p < 0,05, o achado e robusto e deve ser replicado automaticamente.",
		],
		"erro": 2,
		"porque": "p proximo do limiar com n pequeno e o retrato da fragilidade estatistica. "
			+ "Robustez exige replicacao, tamanho de efeito e IC estreito — nunca apenas "
			+ "p < 0,05. Esta e a base do debate sobre 'p < 0,05 nao e prova'.",
	},
]


func _init(m: Control) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var raiz := HBoxContainer.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_theme_constant_override("separation", 12)
	add_child(raiz)

	# coluna esquerda: identidade + temas
	var esq := VBoxContainer.new()
	esq.custom_minimum_size.x = 320
	esq.add_theme_constant_override("separation", 8)
	raiz.add_child(esq)

	var retrato := UITheme.card("", UITheme.INFO)
	esq.add_child(retrato)
	var cr := UITheme.conteudo(retrato)
	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 10)
	cr.add_child(topo)
	var icone := TextureRect.new()
	icone.texture = load("res://assets/art/icon.png")
	icone.custom_minimum_size = Vector2(56, 56)
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	topo.add_child(icone)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	topo.add_child(tv)
	var n := Label.new()
	n.text = "Dr. Bayes"
	n.add_theme_font_override("font", UITheme.titulo_font(true))
	n.add_theme_font_size_override("font_size", 20)
	n.add_theme_color_override("font_color", UITheme.TEXTO)
	tv.add_child(n)
	tv.add_child(UITheme.rotulo("tutor de bioestatistica · versao 0.9", 11, UITheme.TEXTO_FRACO))
	var aviso := UITheme.paragrafo(
		"Este tutor responde com confianca e as vezes erra. Sua tarefa e auditar: "
		+ "encontre a frase incorreta antes de aceitar a resposta.", 11, UITheme.PERIGO)
	aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cr.add_child(aviso)

	esq.add_child(UITheme.rotulo("PERGUNTAS AO TUTOR", 11, UITheme.ACENTO))
	var sc := UITheme.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	esq.add_child(sc)
	var lista := UITheme.vbox(6)
	sc.add_child(lista)
	for i in range(TEMAS.size()):
		var b := UITheme.botao(str(TEMAS[i]["q"]), _abrir_tema.bind(i), null, UITheme.BORDA)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.y = 62
		lista.add_child(b)

	# coluna direita: resposta auditavel
	var dir := VBoxContainer.new()
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir.add_theme_constant_override("separation", 10)
	raiz.add_child(dir)
	var sc2 := UITheme.scroll()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dir.add_child(sc2)
	_area_resposta = UITheme.vbox(10)
	sc2.add_child(_area_resposta)

	var rodape := HBoxContainer.new()
	rodape.add_theme_constant_override("separation", 12)
	dir.add_child(rodape)
	_lbl_placar = UITheme.rotulo("", 13, UITheme.TEXTO_DIM)
	rodape.add_child(_lbl_placar)

	_abrir_tema(0)


func _abrir_tema(i: int) -> void:
	_tema_atual = i
	_respondido = false
	for c in _area_resposta.get_children():
		c.queue_free()
	var t: Dictionary = TEMAS[i]

	var q := UITheme.paragrafo("Voce: " + str(t["q"]), 18, UITheme.ACENTO)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_area_resposta.add_child(q)

	var card := UITheme.card("DR. BAYES RESPONDE", UITheme.INFO)
	_area_resposta.add_child(card)
	var c := UITheme.conteudo(card)
	c.add_child(UITheme.rotulo("clique na frase que voce considera INCORRETA", 11,
		UITheme.TEXTO_FRACO))
	var frases: Array = t["frases"]
	for k in range(frases.size()):
		var b := Button.new()
		b.text = "%d) %s" % [k + 1, str(frases[k])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_override("font", UITheme.corpo(400))
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", UITheme.TEXTO)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UITheme.BG_SUNK
		sb.border_color = UITheme.BORDA
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(_auditar.bind(k))
		c.add_child(b)

	var acoes := HBoxContainer.new()
	acoes.add_theme_constant_override("separation", 10)
	c.add_child(acoes)
	acoes.add_child(UITheme.botao("Esta resposta esta correta", _auditar.bind(-1),
		null, UITheme.SUCESSO))
	acoes.add_child(UITheme.botao("Nova pergunta", func(): _abrir_tema(
		(_tema_atual + 1) % TEMAS.size()), null, UITheme.INFO))

	var area := VBoxContainer.new()
	area.name = "Veredito"
	_area_resposta.add_child(area)

	var dica := UITheme.paragrafo(
		"Voce tambem pode perguntar ao tutor sobre IC, p-valor, correlacao, testes "
		+ "diagnosticos, R0, amostragem, regressao logistica e fragilidade estatistica.",
		12, UITheme.TEXTO_FRACO)
	dica.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_area_resposta.add_child(dica)
	_atualizar_placar()


func _auditar(escolha: int) -> void:
	if _respondido:
		return
	_respondido = true
	var t: Dictionary = TEMAS[_tema_atual]
	var erro := int(t["erro"])
	var acertou := escolha == erro

	var area := _area_resposta.find_child("Veredito", true, false) as VBoxContainer
	if area == null:
		return
	for c in area.get_children():
		c.queue_free()

	var veredito := UITheme.card("", UITheme.SUCESSO if acertou else UITheme.PERIGO)
	area.add_child(veredito)
	var c := UITheme.conteudo(veredito)
	var tit := UITheme.paragrafo("Auditoria correta" if acertou else "Auditoria incorreta",
		20, UITheme.SUCESSO if acertou else UITheme.PERIGO)
	tit.add_theme_font_override("font", UITheme.corpo(700))
	c.add_child(tit)
	if erro < 0:
		c.add_child(UITheme.paragrafo("Esta resposta estava integralmente correta.",
			15, UITheme.TEXTO_DIM))
	else:
		c.add_child(UITheme.paragrafo("A frase %d era a incorreta." % (erro + 1),
			15, UITheme.TEXTO))
	var ex := UITheme.paragrafo(str(t["porque"]), 15, UITheme.TEXTO_DIM)
	ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(ex)

	var id := str(_tema_atual)
	if acertou and not _auditados.has(id):
		_auditados[id] = true
		GameState.auditorias_ia += 1
		GameState.ganhar_moedas(12, "auditoria de IA")
		main.mostrar_toast("Auditoria correta: +12 BioMoedas", "sucesso")
		if GameState.auditorias_ia >= 3:
			GameState.conquistar("auditor_ia", "Auditor de IA")
	_atualizar_placar()
	main._atualizar_hud()


func _atualizar_placar() -> void:
	_lbl_placar.text = "Auditorias corretas: %d de %d  ·  total no jogo: %d" % [
		_auditados.size(), TEMAS.size(), GameState.auditorias_ia]
