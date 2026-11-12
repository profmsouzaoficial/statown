extends Node
## Pente-fino numerico: roda 52 semanas e audita TODO numero exibido na interface.
## Roda como cena (precisa dos autoloads):
##   godot --headless res://tests/TestAudit.tscn

var _falhas := 0
var _avisos := 0
var _main: Control


func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	for i in range(6):
		await get_tree().process_frame
	_main.fechar_modal()
	await get_tree().process_frame

	_auditar_modelo()
	await _auditar_rotulos()

	print("AUDITORIA: %d falhas, %d avisos" % [_falhas, _avisos])
	get_tree().quit(1 if _falhas > 0 else 0)


func _falha(msg: String) -> void:
	_falhas += 1
	if _falhas <= 40:
		print("  FALHA: ", msg)


func _aviso(msg: String) -> void:
	_avisos += 1
	if _avisos <= 40:
		print("  aviso: ", msg)


func _auditar_modelo() -> void:
	print("--- modelo (52 semanas)")
	var pior_prev := 0.0
	var pior_ocup := 0.0
	var pior_soma := 0.0
	for semana in range(52):
		GameState.avancar_semanas(1)
		var pop_total := 0
		var inf_total := 0
		for v in Vilas.vilas:
			var id := int(v["id"])
			var pop := int(v["populacao"])
			var c := Population.contar_por_estado(id)
			var soma := 0
			for k in range(c.size()):
				soma += c[k]
			pop_total += pop
			var inf := Epidemic.infectados(id)
			inf_total += inf
			var mortos := int(v.get("obitos_naturais", 0)) + Epidemic.obitos(id)
			if absi(soma - (pop + mortos)) > 0:
				pior_soma = maxf(pior_soma, absf(float(soma - (pop + mortos))))
				_falha("SE %d vila %d: soma dos estados %d != populacao+obitos %d" % [
					semana, id, soma, pop + mortos])
			var prev := Epidemic.prevalencia(id)
			if prev < -0.0001 or prev > 1.0001:
				_falha("SE %d vila %d: prevalencia %.4f fora de [0,1]" % [semana, id, prev])
			pior_prev = maxf(pior_prev, prev)
			var ocup := Vilas.ocupacao_leitos(id)
			pior_ocup = maxf(pior_ocup, ocup)
			var cob := float(v["cobertura_vacinal"])
			if cob < -0.0001 or cob > 1.0001:
				_falha("SE %d vila %d: cobertura vacinal %.4f fora de [0,1]" % [semana, id, cob])
			var san := float(v["saneamento"])
			if san < -0.0001 or san > 1.0001:
				_falha("SE %d vila %d: saneamento %.4f fora de [0,1]" % [semana, id, san])
			var rt := Epidemic.rt(id)
			if rt < 0.0 or rt > 6.0001:
				_falha("SE %d vila %d: Rt %.3f fora de [0,6]" % [semana, id, rt])
		var g := Epidemic.estatisticas_globais()
		if absi(int(g["populacao_total"]) - pop_total) > 0:
			_aviso("SE %d: populacao global %d != soma das vilas %d" % [
				semana, int(g["populacao_total"]), pop_total])
		if absi(int(g["infectados_total"]) - inf_total) > 0:
			_falha("SE %d: infectados globais %d != soma das vilas %d" % [
				semana, int(g["infectados_total"]), inf_total])
		if float(g["prevalencia"]) > 1.0001:
			_falha("SE %d: prevalencia global %.4f > 1" % [semana, float(g["prevalencia"])])
		if float(g["letalidade"]) > 1.0001:
			_falha("SE %d: letalidade %.4f > 1" % [semana, float(g["letalidade"])])
		if int(g["obitos_total"]) > int(g["casos_total"]):
			_falha("SE %d: obitos %d > casos %d" % [
				semana, int(g["obitos_total"]), int(g["casos_total"])])
		if int(g["casos_total"]) > pop_total:
			_falha("SE %d: casos acumulados %d > populacao %d" % [
				semana, int(g["casos_total"]), pop_total])
	print("  prevalencia maxima %.4f | ocupacao maxima %.2f | erro soma estados %.0f" % [
		pior_prev, pior_ocup, pior_soma])


func _auditar_rotulos() -> void:
	print("--- rotulos exibidos")
	var telas := [
		["vila", func(): _main._abrir_vila(12)],
		["lab", func(): _main._abrir_lab()],
		["jogos", func(): _main._abrir_minigames()],
		["revista", func(): _main._abrir_revista()],
		["siga", func(): _main._abrir_siga()],
		["menu", func(): _main._abrir_menu()],
		["bayes", func(): _main._abrir_bayes()],
		["cenario", func(): _main._abrir_troca_cenario()],
	]
	for par in telas:
		var nome: String = par[0]
		(par[1] as Callable).call()
		await get_tree().process_frame
		await get_tree().process_frame
		var txts: Array = []
		_coletar(get_tree().root, txts)
		for item in txts:
			var t: String = item["texto"]
			var ctx: String = item["contexto"].to_upper()
			for m in _pcts(t):
				if m > 100.5:
					var ocupacao := ctx.contains("OCUPACAO") or ctx.contains("LEITOS") 						or ctx.contains("SUPERLOT") or ctx.contains("GRAVES")
					if ocupacao:
						_aviso("[%s] ocupacao (pode passar de 100%%): %.0f%%" % [nome, m])
					else:
						_falha("[%s] %.1f%% em: %s" % [nome, m, t.strip_edges().left(90)])
		print("  %-8s %d textos" % [nome, txts.size()])
		_main.fechar_modal()
		await get_tree().process_frame


func _coletar(no: Node, out: Array) -> void:
	if no is Label or no is Button:
		var s: String = (no as Control).get("text")
		if s.contains("%"):
			out.append({"texto": s, "contexto": _contexto(no)})
	for filho in no.get_children():
		_coletar(filho, out)


## Texto dos irmaos/pai: serve para saber se o "126%" e ocupacao de leitos
## (que pode passar de 100%) ou uma proporcao que nunca poderia.
func _contexto(no: Node) -> String:
	var partes: Array[String] = []
	var pai := no.get_parent()
	if pai != null:
		for irmao in pai.get_children():
			if irmao is Label or irmao is Button:
				partes.append((irmao as Control).get("text"))
		var avo := pai.get_parent()
		if avo != null:
			for tio in avo.get_children():
				if tio is Label or tio is Button:
					partes.append((tio as Control).get("text"))
	return " ".join(partes)


func _pcts(texto: String) -> Array[float]:
	var out: Array[float] = []
	var re := RegEx.new()
	re.compile("(-?[0-9]+(?:[.,][0-9]+)?)\\s*%")
	for m in re.search_all(texto):
		out.append(float(m.get_string(1).replace(",", ".")))
	return out
