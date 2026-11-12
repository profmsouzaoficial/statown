class_name PanelMinigames
extends Control
## Hub dos nove desafios de bioestatistica.
##
## Cada desafio isola um conceito: delineamento, tipos de variavel, forma da
## distribuicao, escolha de grafico, amostragem, familia de distribuicoes,
## logica de hipoteses, leitura de correlacao e auditoria de afirmacoes de IA.

var main: Control
var _grade: GridContainer
var _container_jogo: Control
var _hub: Control
var _jogo_atual: Control

const JOGOS := [
	{"id": "delineamentos", "n": "01", "t": "Detetive de Delineamentos",
		"d": "Transversal, coorte, caso-controle ou ensaio: descubra o desenho pelo relato.",
		"cor": "INFO", "cena": "MGDelineamentos"},
	{"id": "banco_dados", "n": "02", "t": "Arquiteto do Banco de Dados",
		"d": "Classifique cada variavel e decida qual analise ela permite.",
		"cor": "ROXO", "cena": "MGBancoDados"},
	{"id": "assimetria", "n": "03", "t": "Mestre da Assimetria",
		"d": "Leia histogramas e diga para onde a cauda aponta.",
		"cor": "ACENTO_2", "cena": "MGAssimetria"},
	{"id": "grafico", "n": "04", "t": "Oficina do Grafico Perfeito",
		"d": "Escolha o grafico certo para cada pergunta de pesquisa.",
		"cor": "ACENTO", "cena": "MGGrafico"},
	{"id": "amostragem", "n": "05", "t": "Missao Amostragem",
		"d": "Sorteie sem vies e reconheca os quatro vieses classicos.",
		"cor": "INFO", "cena": "MGAmostragem"},
	{"id": "distribuicoes", "n": "06", "t": "Roleta das Distribuicoes",
		"d": "Normal, binomial, Poisson, t ou qui-quadrado: qual se aplica?",
		"cor": "ROXO", "cena": "MGDistribuicoes"},
	{"id": "hipoteses", "n": "07", "t": "Tribunal das Hipoteses",
		"d": "Decida sobre H0 sem cair nas interpretacoes erradas do p-valor.",
		"cor": "PERIGO", "cena": "MGHipoteses"},
	{"id": "tendencias", "n": "08", "t": "Cacador de Tendencias",
		"d": "Estime a forca da correlacao olhando a nuvem de pontos.",
		"cor": "SUCESSO", "cena": "MGTendencias"},
	{"id": "auditoria", "n": "09", "t": "Auditoria de IA",
		"d": "O Dr. Bayes erra de proposito. Encontre a alucinacao.",
		"cor": "ACENTO", "cena": "MGAuditoriaIA"},
]


func _init(m: Control) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_hub = VBoxContainer.new()
	_hub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hub.add_theme_constant_override("separation", 12)
	add_child(_hub)
	_container_jogo = Control.new()
	_container_jogo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container_jogo.visible = false
	add_child(_container_jogo)
	_montar_hub()


func _montar_hub() -> void:
	for c in _hub.get_children():
		c.queue_free()

	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 14)
	_hub.add_child(cab)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(v)
	var t := Label.new()
	t.text = "ESCOLHA UM DESAFIO"
	t.add_theme_font_override("font", UITheme.titulo_font(true))
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", UITheme.ACENTO)
	v.add_child(t)
	v.add_child(UITheme.rotulo(
		"Cada desafio vale BioMoedas. O melhor aproveitamento fica registrado.", 13,
		UITheme.TEXTO_DIM))
	var total := GameState.minigames_concluidos.size()
	cab.add_child(UITheme.badge("%d de 9 concluidos" % total,
		UITheme.SUCESSO if total >= 9 else UITheme.TEXTO_DIM, 14))

	var sc := UITheme.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hub.add_child(sc)
	_grade = GridContainer.new()
	_grade.columns = 3
	_grade.add_theme_constant_override("h_separation", 12)
	_grade.add_theme_constant_override("v_separation", 12)
	_grade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_grade)

	for j in JOGOS:
		_grade.add_child(_card_jogo(j))


func _card_jogo(j: Dictionary) -> Control:
	var cor := _cor(str(j["cor"]))
	var p := UITheme.card("", cor)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c := UITheme.conteudo(p)
	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 10)
	c.add_child(topo)
	var num := Label.new()
	num.text = str(j["n"])
	num.add_theme_font_override("font", UITheme.titulo_font(true))
	num.add_theme_font_size_override("font_size", 34)
	num.add_theme_color_override("font_color", cor)
	topo.add_child(num)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topo.add_child(tv)
	var tit := Label.new()
	tit.text = str(j["t"])
	tit.add_theme_font_override("font", UITheme.corpo(700))
	tit.add_theme_font_size_override("font_size", 16)
	tit.add_theme_color_override("font_color", UITheme.TEXTO)
	tit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(tit)
	var reg: Dictionary = GameState.minigames_concluidos.get(str(j["id"]), {})
	if not reg.is_empty():
		tv.add_child(UITheme.rotulo("melhor: %.0f%%" % (float(reg.get("melhor", 0.0)) * 100.0),
			11, UITheme.SUCESSO))
	else:
		tv.add_child(UITheme.rotulo("nao jogado", 11, UITheme.TEXTO_FRACO))

	var d := UITheme.paragrafo(str(j["d"]), 13, UITheme.TEXTO_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.y = 54
	c.add_child(d)
	var b := UITheme.botao("Jogar", _abrir.bind(j), null, cor)
	c.add_child(b)
	return p


func _abrir(j: Dictionary) -> void:
	if _jogo_atual != null:
		_jogo_atual.queue_free()
		_jogo_atual = null
	for c in _container_jogo.get_children():
		c.queue_free()
	var classe := str(j["cena"])
	var g: Control = null
	match classe:
		"MGDelineamentos": g = MGDelineamentos.new(main)
		"MGBancoDados": g = MGBancoDados.new(main)
		"MGAssimetria": g = MGAssimetria.new(main)
		"MGGrafico": g = MGGrafico.new(main)
		"MGAmostragem": g = MGAmostragem.new(main)
		"MGDistribuicoes": g = MGDistribuicoes.new(main)
		"MGHipoteses": g = MGHipoteses.new(main)
		"MGTendencias": g = MGTendencias.new(main)
		"MGAuditoriaIA": g = MGAuditoriaIA.new(main)
	if g == null:
		return
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container_jogo.add_child(g)
	_jogo_atual = g
	if g.has_signal("encerrado"):
		g.connect("encerrado", _fechar_jogo)
	_hub.visible = false
	_container_jogo.visible = true
	main.mostrar_toast("Desafio iniciado — leia a situacao com calma", "info")


func _fechar_jogo() -> void:
	_container_jogo.visible = false
	_hub.visible = true
	if _jogo_atual != null:
		_jogo_atual.queue_free()
		_jogo_atual = null
	_montar_hub()
	if main.has_method("_atualizar_hud"):
		main._atualizar_hud()


func _cor(nome: String) -> Color:
	match nome:
		"INFO": return UITheme.INFO
		"ROXO": return UITheme.ROXO
		"ACENTO": return UITheme.ACENTO
		"ACENTO_2": return UITheme.ACENTO_2
		"PERIGO": return UITheme.PERIGO
		"SUCESSO": return UITheme.SUCESSO
	return UITheme.TEXTO_DIM
