class_name PanelMenu
extends Control
## Configuracoes, persistencia e creditos.

var main: Control


func _init(m: Control) -> void:
	main = m
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margem.add_theme_constant_override(lado, 20)
	add_child(margem)

	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margem.add_child(col)

	# ---------------- coluna esquerda: opcoes ----------------
	# A coluna esquerda cresceu com o mixer de audio: ganha rolagem para caber
	# tambem em telas de celular (onde o modal e reduzido).
	var sc_esq := UITheme.scroll()
	col.add_child(sc_esq)
	var molde := MarginContainer.new()
	molde.add_theme_constant_override("margin_right", 14)
	sc_esq.add_child(molde)
	var esq := VBoxContainer.new()
	esq.add_theme_constant_override("separation", 12)
	esq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	molde.add_child(esq)

	var p1 := UITheme.card("ACESSIBILIDADE", UITheme.ACENTO_2)
	esq.add_child(p1)
	var c1 := UITheme.conteudo(p1)
	var cb := CheckBox.new()
	cb.text = "Fonte grande (A+)"
	cb.button_pressed = GameState.fonte_grande
	cb.toggled.connect(func(on):
		GameState.fonte_grande = on
		UITheme.aplicar_escala(on)
		get_tree().root.theme = UITheme.tema
		main.mostrar_toast("Escala da interface: %s" % ("grande" if on else "normal"), "info"))
	c1.add_child(cb)
	var cb2 := CheckBox.new()
	cb2.text = "Mostrar rotulos das vilas no mapa"
	cb2.button_pressed = GameState.mostrar_rotulos
	cb2.toggled.connect(func(on):
		GameState.mostrar_rotulos = on
		main.mundo._rotulos.visible = on)
	c1.add_child(cb2)
	var cb3 := CheckBox.new()
	cb3.text = "Pausar automaticamente ao abrir paineis"
	cb3.button_pressed = GameState.auto_pausa_lab
	cb3.toggled.connect(func(on): GameState.auto_pausa_lab = on)
	c1.add_child(cb3)

	var p_som := UITheme.card("SOM & MUSICA", UITheme.ACENTO)
	esq.add_child(p_som)
	var c_som := UITheme.conteudo(p_som)
	c_som.add_child(_linha_volume("Musica", GameState.volume_musica, func(v):
		GameState.volume_musica = v
		Audio.aplicar_volumes()))
	c_som.add_child(_linha_volume("Ambiente", GameState.volume_ambiente, func(v):
		GameState.volume_ambiente = v
		Audio.aplicar_volumes()))
	c_som.add_child(_linha_volume("Efeitos", GameState.volume_sfx, func(v):
		GameState.volume_sfx = v
		Audio.aplicar_volumes()))
	var cb_mudo := CheckBox.new()
	cb_mudo.text = "Silenciar tudo"
	cb_mudo.button_pressed = GameState.mudo
	cb_mudo.toggled.connect(func(on):
		GameState.mudo = on
		Audio.aplicar_volumes())
	c_som.add_child(cb_mudo)

	# Teste rapido: se estes botoes nao tocarem, o problema esta no navegador
	# ou no sistema, nao no jogo (ver Manual do Usuario > Solucao de problemas).
	c_som.add_child(UITheme.rotulo("TESTAR SOM", 12, UITheme.ACENTO))
	var linha_teste := UITheme.hbox(8)
	c_som.add_child(linha_teste)
	for par in [["Clique", "clique"], ["Abrir", "abrir"], ["Sucesso", "sucesso"], ["Erro", "erro"]]:
		var sid := str(par[1])
		linha_teste.add_child(UITheme.botao(str(par[0]), func(): Audio.sfx(sid, 0.0)))

	var p2 := UITheme.card("PARTIDA", UITheme.INFO)
	esq.add_child(p2)
	var c2 := UITheme.conteudo(p2)
	var linha_sv := UITheme.hbox(8)
	c2.add_child(linha_sv)
	linha_sv.add_child(UITheme.botao("Salvar", func():
		GameState.salvar_partida()
		main.mostrar_toast("Partida salva em user://statown_save.json", "sucesso"), null, UITheme.SUCESSO))
	linha_sv.add_child(UITheme.botao("Carregar", func():
		if GameState.carregar_partida():
			main.mostrar_toast("Partida carregada", "sucesso")
			main.fechar_modal()
			main._atualizar_hud()
		else:
			main.mostrar_toast("Nenhum save encontrado", "erro"), null, UITheme.INFO))
	linha_sv.add_child(UITheme.botao("Reiniciar tudo", _confirmar_reinicio, null, UITheme.PERIGO))

	var p3 := UITheme.card("SIMULACAO", UITheme.ROXO)
	esq.add_child(p3)
	var c3 := UITheme.conteudo(p3)
	c3.add_child(UITheme.campo("Populacao", "%d individuos sinteticos" % Vilas.populacao_total()))
	c3.add_child(UITheme.campo("Vilas", "20"))
	c3.add_child(UITheme.campo("Semana epidemiologica", "SE %d (ano %d)" % [GameState.semana, GameState.ano]))
	c3.add_child(UITheme.campo("Agravo ativo", str(GameState.info_doenca().get("nome", "-"))))
	c3.add_child(UITheme.botao("Trocar cenario epidemiologico", func(): main.trocar_para("cenario")))

	# ---------------- coluna direita: sobre ----------------
	var sc_dir := UITheme.scroll()
	col.add_child(sc_dir)
	var molde_d := MarginContainer.new()
	molde_d.add_theme_constant_override("margin_right", 14)
	sc_dir.add_child(molde_d)
	var dir := VBoxContainer.new()
	dir.add_theme_constant_override("separation", 12)
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	molde_d.add_child(dir)

	var p_manual := UITheme.card("MANUAL DO JOGO", UITheme.SUCESSO)
	dir.add_child(p_manual)
	var c_manual := UITheme.conteudo(p_manual)
	c_manual.add_child(UITheme.paragrafo(
		"O manual completo tem 23 capitulos, com o mapa das telas, a interpretacao de cada "
		+ "indicador, os roteiros dos minigames e uma secao de solucao de problemas.",
		13, UITheme.TEXTO_DIM))
	c_manual.add_child(UITheme.botao("Abrir manual (F1)",
		func(): main._abrir_manual(), null, UITheme.SUCESSO))

	var p4 := UITheme.card("SOBRE O STATOWN", UITheme.ACENTO)
	dir.add_child(p4)
	var c4 := UITheme.conteudo(p4)
	c4.add_child(UITheme.paragrafo(
		"StaTown e um jogo educacional de bioestatistica e epidemiologia. A populacao e "
		+ "sintetica (gerada por amostragem estratificada com estrutura etaria realista), "
		+ "mas os metodos estatisticos sao os mesmos usados em analise de dados reais: "
		+ "estimacao por intervalo, testes de hipotese, regressao logistica e curva ROC.",
		14, UITheme.TEXTO_DIM))
	c4.add_child(UITheme.separador())
	c4.add_child(UITheme.rotulo("TECNOLOGIA", 11, UITheme.TEXTO_FRACO))
	c4.add_child(UITheme.paragrafo("Godot 4.7 · GDScript · exportacao web/mobile (WebGL2) · "
		+ "pixel art Kenney (CC0) · fontes Silkscreen, Rubik e VT323 (SIL OFL 1.1).",
		13, UITheme.TEXTO_DIM))
	c4.add_child(UITheme.rotulo("COMO OS NUMEROS SAO CALCULADOS", 11, UITheme.TEXTO_FRACO))
	c4.add_child(UITheme.paragrafo(
		"O motor SEIR simula cada um dos individuos a cada semana. A forca de infecao de uma "
		+ "vila combina a prevalencia local com a de quem chega pelas rodovias (matriz de "
		+ "mobilidade gravitacional). A letalidade varia com idade, saneamento, leitos e "
		+ "saturacao — por isso a mesma doenca mata mais em vilas pobres.", 13, UITheme.TEXTO_DIM))

	var p5 := UITheme.card("CONQUISTAS", UITheme.SUCESSO)
	dir.add_child(p5)
	var c5 := UITheme.conteudo(p5)
	var conquistas: Dictionary = GameState.conquistas()
	if conquistas.is_empty():
		c5.add_child(UITheme.paragrafo("Nenhuma conquista ainda. Complete desafios e leia artigos.",
			13, UITheme.TEXTO_DIM))
	else:
		for k in conquistas:
			c5.add_child(UITheme.badge(str(conquistas[k]), UITheme.ACENTO, 12))

	var p6 := UITheme.card("TRILHA SONORA", UITheme.ROXO)
	dir.add_child(p6)
	var c6 := UITheme.conteudo(p6)
	c6.add_child(UITheme.paragrafo(
		"Musica original sintetizada em La menor (mapa, 5 zonas e 9 desafios) para que "
		+ "tema, vila e efeito soem harmonicos entre si. As ambiencias e os acentos "
		+ "diegeticos (vento, passaros, rio, mercado, porto, sino, galo, vaca, bocina, "
		+ "bigorna) sao CC0 do freesound.org — creditos completos em docs/CREDITOS_AUDIO.md.",
		13, UITheme.TEXTO_DIM))

	var b := UITheme.botao("Fechar", func(): main.fechar_modal())
	dir.add_child(b)


## Linha "rotulo [slider] 55%" que grava em GameState e reaplica os buses.
func _linha_volume(texto: String, valor: float, ao_mudar: Callable) -> Control:
	var l := HBoxContainer.new()
	l.add_theme_constant_override("separation", 10)
	var nome := UITheme.rotulo(texto, 14, UITheme.TEXTO)
	nome.custom_minimum_size.x = 96
	l.add_child(nome)
	var h := HSlider.new()
	h.min_value = 0.0
	h.max_value = 100.0
	h.step = 1.0
	h.value = clampf(valor * 100.0, 0.0, 100.0)
	h.custom_minimum_size = Vector2(180, 26)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_child(h)
	var pct := UITheme.rotulo("%d%%" % int(h.value), 13, UITheme.TEXTO_DIM)
	pct.custom_minimum_size.x = 46
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_child(pct)
	h.value_changed.connect(func(x: float):
		pct.text = "%d%%" % int(x)
		ao_mudar.call(x / 100.0))
	return l


func _confirmar_reinicio() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Reiniciar a partida?"
	dlg.dialog_text = "Toda a populacao, o historico epidemiologico e as BioMoedas voltam ao inicio. Esta acao nao pode ser desfeita."
	dlg.ok_button_text = "Reiniciar"
	dlg.cancel_button_text = "Cancelar"
	add_child(dlg)
	dlg.confirmed.connect(func():
		GameState.reiniciar_partida()
		main.fechar_modal()
		main.mostrar_toast("Nova partida iniciada", "info"))
	dlg.popup_centered()
