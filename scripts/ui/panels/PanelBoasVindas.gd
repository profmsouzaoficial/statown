class_name PanelBoasVindas
extends Control
## Tela de abertura: apresenta o universo, os tres verbos do jogo
## (explorar, investigar, decidir) e as instrucoes de toque/pinca no celular.

var main: Control


func _init(m: Control) -> void:
	main = m
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margem.add_theme_constant_override(lado, 22)
	add_child(margem)

	var scroll := UITheme.scroll()
	margem.add_child(scroll)
	var raiz := VBoxContainer.new()
	raiz.add_theme_constant_override("separation", 14)
	raiz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(raiz)

	# --- faixa de titulo -------------------------------------------------
	var hero := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.14, 0.19)
	sb.border_color = UITheme.ACENTO_2
	sb.border_width_left = 5
	sb.set_border_width_all(1)
	sb.border_width_left = 5
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	hero.add_theme_stylebox_override("panel", sb)
	raiz.add_child(hero)

	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 20)
	hero.add_child(hr)

	var icone := TextureRect.new()
	icone.texture = load("res://assets/art/icon.png")
	icone.custom_minimum_size = Vector2(96, 96)
	icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hr.add_child(icone)

	var hc := VBoxContainer.new()
	hc.add_theme_constant_override("separation", 2)
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(hc)
	hc.add_child(UITheme.titulo("Bem-vindo ao Vale do Rio Doce", 26, UITheme.TEXTO, true))
	hc.add_child(UITheme.paragrafo(
		("Voce e o novo coordenador de vigilancia epidemiologica de StaTown. "
		+ "Sao 20 vilas, %s moradores e um agravo circulando. Seu trabalho: transformar "
		+ "dados brutos em decisoes que salvam vidas — e aprender bioestatistica no caminho.")
		% _formatar(Vilas.populacao_total()),
		17, UITheme.TEXTO_DIM))
	raiz.add_child(UITheme.espacador(2))

	# --- tres verbos -----------------------------------------------------
	var grid := UITheme.grade(3, 14, 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(grid)
	grid.add_child(_card_verbo("1  EXPLORAR", UITheme.INFO, "icone_virus",
		"Arraste e use dois dedos (pinca) para ampliar o mapa. Toque numa vila para abrir o painel "
		+ "de indicadores: prevalencia, Rt, leitos e cobertura vacinal em tempo real."))
	grid.add_child(_card_verbo("2  INVESTIGAR", UITheme.ROXO, "icone_gota",
		"Entre no BioLab: descreva os 41.650 individuos da populacao sintetica, monte "
		+ "graficos, estime intervalos de confianca, teste hipoteses e rode uma regressao "
		+ "logistica de verdade."))
	grid.add_child(_card_verbo("3  DECIDIR", UITheme.SUCESSO, "icone_coracao",
		"Gaste BioMoedas em saneamento, vacina, UBS e hospital. Cada decisao muda o Rt "
		+ "e a ocupacao de leitos na semana seguinte. Os dados ficam registrados e podem "
		+ "ser exportados no formato SIGA pelo backend."))
	raiz.add_child(UITheme.espacador(2))

	# --- rodape ----------------------------------------------------------
	var rodape := HBoxContainer.new()
	rodape.add_theme_constant_override("separation", 18)
	raiz.add_child(rodape)

	var dicas := VBoxContainer.new()
	dicas.add_theme_constant_override("separation", 4)
	dicas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rodape.add_child(dicas)
	dicas.add_child(UITheme.rotulo("COMO JOGAR", 12, UITheme.ACENTO))
	dicas.add_child(UITheme.paragrafo(
		"· No computador: arraste com o mouse, use a roda para o zoom e as setas para andar.\n"
		+ "· No celular: arraste com um dedo e faca pinca com dois dedos para ampliar.\n"
		+ "· Cada vila tem sua propria trilha e ambiencia: aproxime o zoom para ouvi-las.\n"
		+ "· A simulacao roda em semanas epidemiologicas (SE). Use os botoes || > >> >>> para mudar a velocidade.\n"
		+ "· Ganhe BioMoedas acertando os desafios e concluindo auditorias; gaste-as em intervencoes.",
		15, UITheme.TEXTO_DIM))

	var acoes := VBoxContainer.new()
	acoes.add_theme_constant_override("separation", 8)
	acoes.custom_minimum_size.x = 300
	rodape.add_child(acoes)
	var b1 := UITheme.botao("COMECAR A PARTIDA  >", func(): main.fechar_modal(), null, UITheme.ACENTO)
	b1.custom_minimum_size = Vector2(300, 52)
	b1.add_theme_font_size_override("font_size", 17)
	acoes.add_child(b1)
	acoes.add_child(UITheme.botao("Conversar com o Dr. Bayes", func(): main.trocar_para("bayes")))
	acoes.add_child(UITheme.botao("Ver os desafios disponiveis", func(): main.trocar_para("minigames")))
	acoes.add_child(UITheme.botao("Configuracoes do jogo", func(): main.trocar_para("menu")))


func _card_verbo(titulo_txt: String, cor: Color, icone_nome: String, texto: String) -> PanelContainer:
	var p := UITheme.painel(UITheme.BG_CARD, UITheme.BORDA, 10, 16)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 10)
	v.add_child(cab)
	var ic := TextureRect.new()
	var tex := Assets.sprite(icone_nome)
	if tex:
		ic.texture = tex
	ic.custom_minimum_size = Vector2(34, 34)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cab.add_child(ic)
	cab.add_child(UITheme.titulo(titulo_txt, 16, cor, true))
	v.add_child(UITheme.paragrafo(texto, 16, UITheme.TEXTO_DIM))
	return p


func _formatar(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return out


func _formatar_n(v: int) -> String:
	return _formatar(v)
