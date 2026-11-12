extends Node
## Captura de telas para documentacao e revisao visual.
##
## Roda com display real (GL Compatibility):
##   godot --path . res://tests/Capture.tscn --resolution 1600x900
##
## Salva PNGs em res://docs/shots/ (pasta criada automaticamente).

const DIR := "res://docs/shots"

var main: Control
var n := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var cena: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(cena)
	main = cena
	await _esperar(30)
	await _shot("01_boas_vindas")

	main.fechar_modal()
	await _esperar(6)
	# roda algumas semanas para os graficos terem dados reais
	GameState.avancar_semanas(16)
	await _esperar(8)
	await _shot("02_mapa")

	main.focar_vila(3)
	await _esperar(20)
	await _shot("03_mapa_zoom")

	main.trocar_para("vila")
	await _esperar(14)
	await _shot("04_vila")

	main.trocar_para("lab")
	await _esperar(12)
	await _shot("05_lab_amostragem")
	await _aba(3)
	await _esperar(8)
	await _shot("05b_lab_dist_normal")
	var spins: Array = []
	for no in main._modal_corpo.find_children("*", "SpinBox", true, false):
		if (no as SpinBox).is_visible_in_tree():
			spins.append(no)
	if spins.size() >= 2:
		(spins[1] as SpinBox).value = 3.0
		await _esperar(8)
		await _shot("05c_lab_dist_sigma3")
	await _aba(1)
	await _shot("06_lab_descritiva")
	await _aba(4)
	await _esperar(6)
	await _shot("07_lab_testes")
	await _aba(5)
	await _esperar(6)
	await _shot("08_lab_regressao")

	await _aba(4)
	await _esperar(4)
	_pressionar("Executar teste")
	await _esperar(40)
	await _shot("07b_lab_teste_rodado")

	main.trocar_para("minigames")
	await _esperar(10)
	await _shot("09_minigames")

	# abre o primeiro desafio pelo fluxo real (hub -> modal)
	_pressionar("Jogar")
	await _esperar(8)
	await _shot("10_mg_delineamentos")
	main.fechar_modal()
	await _esperar(4)
	main.trocar_para("minigames")
	await _esperar(10)
	_pressionar_n("Jogar", 4)
	await _esperar(10)
	await _shot("11_mg_amostragem")
	main.fechar_modal()
	await _esperar(4)

	main.trocar_para("revista")
	await _esperar(10)
	await _shot("12_revista")

	main.trocar_para("siga")
	await _esperar(10)
	await _shot("13_siga")

	main.trocar_para("bayes")
	await _esperar(10)
	await _shot("14_bayes")

	main.trocar_para("menu")
	await _esperar(10)
	await _shot("15_menu")

	main.trocar_para("cenario")
	await _esperar(12)
	await _shot("16_cenario")

	main.trocar_para("minigames")
	await _esperar(10)
	_pressionar_n("Jogar", 6)
	await _esperar(10)
	await _shot("17_mg_hipoteses")
	main.fechar_modal()
	await _esperar(4)

	main.trocar_para("vila")
	await _esperar(12)
	main.focar_vila(11)
	await _esperar(16)
	await _shot("18_vila_secundaria")

	get_tree().quit()


func _pressionar(texto: String) -> void:
	var achados := _botoes(main)
	for b in achados:
		if (b as Button).text.strip_edges().to_lower() == texto.to_lower() and b.is_visible_in_tree():
			(b as Button).pressed.emit()
			return
	push_warning("botao nao encontrado: " + texto)


func _pressionar_n(texto: String, indice: int) -> void:
	var achados := _botoes(main)
	var vistos := 0
	for b in achados:
		if (b as Button).text.strip_edges().to_lower() == texto.to_lower() and b.is_visible_in_tree():
			if vistos == indice:
				(b as Button).pressed.emit()
				return
			vistos += 1
	push_warning("botao nao encontrado: %s[%d]" % [texto, indice])


func _botoes(raiz: Node) -> Array:
	var out: Array = []
	var pilha: Array = [raiz]
	while not pilha.is_empty():
		var no: Node = pilha.pop_back()
		if no is Button:
			out.append(no)
		var filhos := no.get_children()
		for i in range(filhos.size() - 1, -1, -1):
			pilha.append(filhos[i])
	return out


func _esperar(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _aba(i: int) -> void:
	var abas := _achar(main._modal_corpo, "TabContainer") as TabContainer
	if abas != null:
		abas.current_tab = i
		await get_tree().process_frame
		await get_tree().process_frame


func _achar(raiz: Node, tipo: String) -> Node:
	var pilha: Array = [raiz]
	while not pilha.is_empty():
		var no: Node = pilha.pop_back()
		if no.is_class(tipo):
			return no
		var filhos := no.get_children()
		for i in range(filhos.size() - 1, -1, -1):
			pilha.append(filhos[i])
	return null


func _shot(nome: String) -> void:
	# avisos flutuantes nao entram nas capturas (poluem o painel fotografado)
	if main.has_method("limpar_toasts"):
		main.limpar_toasts()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := main.get_viewport().get_texture().get_image()
	var caminho := "%s/%s.png" % [DIR, nome]
	img.save_png(caminho)
	n += 1
	print("captura %02d: %s (%dx%d)" % [n, caminho, img.get_width(), img.get_height()])
