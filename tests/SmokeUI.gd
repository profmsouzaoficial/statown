extends Node
## Smoke test de interface do StaTown.
##
## Abre a cena principal, percorre todos os paineis e abas, pressiona os botoes
## de acao e joga uma rodada completa de cada minigame. Erros de script
## aparecem no console; o processo sai com codigo 1 se algum painel falhar.
##
## Rodar como CENA (os autoloads precisam existir):
##   godot --headless res://tests/SmokeUI.tscn

var main: Control
var falhas: Array[String] = []
var passos := 0


func _ready() -> void:
	var cena: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(cena)
	main = cena
	await get_tree().process_frame
	await get_tree().process_frame
	main.fechar_modal()
	await get_tree().process_frame

	for nome in ["lab", "minigames", "revista", "siga", "menu", "cenario", "bayes"]:
		await _abrir(nome)

	# HUD: SIGA saiu do fluxo do jogador (a integracao sera feita no backend);
	# no lugar entrou o MANUAL. A tela SIGA continua testada acima como interna.
	main.fechar_modal()
	await get_tree().process_frame
	var hud_txt := ""
	var achados := _botoes(main)
	for b in achados:
		if b.is_visible_in_tree():
			hud_txt += " " + (b as Button).text
	_ok(" MANUAL" in hud_txt, "HUD tem o botao MANUAL")
	_ok(not (" SIGA" in hud_txt), "HUD nao expoe mais o botao SIGA")

	await _testar_abas_lab()
	await _testar_minigames()
	await _testar_bayes()
	await _testar_revista()
	await _testar_siga()

	print("\nSMOKE UI: %d passos, %d falhas" % [passos, falhas.size()])
	for f in falhas:
		print("  FALHA: ", f)
	get_tree().quit(0 if falhas.is_empty() else 1)


func _ok(cond: bool, nome: String) -> void:
	passos += 1
	if not cond:
		falhas.append(nome)


func _abrir(nome: String) -> void:
	main.trocar_para(nome)
	await get_tree().process_frame
	await get_tree().process_frame
	passos += 1
	if main._modal_corpo.get_child_count() == 0:
		falhas.append("painel vazio: " + nome)
	if not main._modal_raiz.visible:
		falhas.append("modal invisivel: " + nome)


func _testar_abas_lab() -> void:
	await _abrir("lab")
	var abas := _achar(main._modal_corpo, "TabContainer") as TabContainer
	if abas == null:
		falhas.append("sem TabContainer no laboratorio")
		return
	for i in range(abas.get_tab_count()):
		abas.current_tab = i
		await get_tree().process_frame
		await get_tree().process_frame
		passos += 1
	abas.current_tab = 0
	await get_tree().process_frame
	await _pressionar("Nova amostra")
	await _pressionar("Sortear amostra")
	await _pressionar("Calcular n ideal")
	main.fechar_modal()
	await get_tree().process_frame


func _pressionar(texto: String) -> void:
	var b := _botao_com(texto)
	if b == null:
		falhas.append("botao ausente: " + texto)
		return
	b.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	passos += 1


func _botao_com(texto: String) -> Button:
	var pilha: Array = [main._modal_corpo]
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		if n is Button and (n as Button).text.begins_with(texto):
			return n
		for c in n.get_children():
			pilha.append(c)
	return null


func _botoes(raiz: Node) -> Array:
	var pilha: Array = [raiz]
	var out: Array = []
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		if n is Button:
			out.append(n)
		for c in n.get_children():
			pilha.append(c)
	return out


func _achar(raiz: Node, tipo: String) -> Node:
	var pilha: Array = [raiz]
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		if n.is_class(tipo):
			return n
		for c in n.get_children():
			pilha.append(c)
	return null


func _testar_minigames() -> void:
	var classes := [MGDelineamentos, MGBancoDados, MGAssimetria, MGGrafico,
		MGAmostragem, MGDistribuicoes, MGHipoteses, MGTendencias, MGAuditoriaIA]
	for C in classes:
		var g: Control = C.new(main)
		main.add_child(g)
		await get_tree().process_frame
		if g.get_child_count() == 0:
			falhas.append("minigame vazio: " + g.id_jogo)
			g.queue_free()
			continue
		if not g.rodadas is Array or g.rodadas.size() < 3:
			falhas.append("rodadas insuficientes: " + g.id_jogo)
		var guarda := 0
		var acertos_antes: int = g.acertos
		while g.indice < g.rodadas.size() and guarda < 40:
			guarda += 1
			var r: Dictionary = g.rodadas[g.indice]
			if r.get("opcoes", []).size() < 2:
				falhas.append("rodada sem opcoes: " + g.id_jogo)
				break
			g._botao_resposta(int(r["correta"]))
			await get_tree().process_frame
			if g.acertos <= acertos_antes:
				falhas.append("resposta correta nao contou: " + g.id_jogo)
				break
			acertos_antes = g.acertos
			g._proxima()
			await get_tree().process_frame
		if g.indice < g.rodadas.size():
			falhas.append("nao terminou: " + g.id_jogo)
		passos += 1
		g.queue_free()
		await get_tree().process_frame


func _testar_bayes() -> void:
	await _abrir("bayes")
	var painel: Node = main._modal_corpo.get_child(0)
	if painel == null or not painel.has_method("_auditar"):
		falhas.append("Dr. Bayes sem _auditar")
		return
	painel._auditar(0)
	await get_tree().process_frame
	painel._auditar(1)
	await get_tree().process_frame
	passos += 1
	main.fechar_modal()
	await get_tree().process_frame


func _testar_revista() -> void:
	await _abrir("revista")
	var painel: Node = main._modal_corpo.get_child(0)
	if painel == null or not painel.has_method("_abrir_artigo"):
		falhas.append("Revista sem _abrir_artigo")
		return
	for i in range(painel.ARTIGOS.size()):
		painel._abrir_artigo(i)
		await get_tree().process_frame
		painel._alternar_perguntas()
		await get_tree().process_frame
		passos += 1
	painel._marcar_lido()
	await get_tree().process_frame
	main.fechar_modal()
	await get_tree().process_frame


func _testar_siga() -> void:
	await _abrir("siga")
	var painel: Node = main._modal_corpo.get_child(0)
	if painel == null or not painel.has_method("_gerar"):
		falhas.append("SIGA sem _gerar")
		return
	painel._gerar()
	await get_tree().process_frame
	passos += 1
	main.fechar_modal()
	await get_tree().process_frame
