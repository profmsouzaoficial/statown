class_name MGTendencias
extends MinigameBase
## Desafio 8 - Cacador de Tendencias.


func _init(m: Control) -> void:
	id_jogo = "tendencias"
	titulo_jogo = "Cacador de Tendencias"
	subtitulo_jogo = "Estime a forca da relacao antes de calcular o r"
	cor_jogo = UITheme.SUCESSO
	super(m)


func _gerar_rodadas() -> Array:
	var alvos := [0.88, -0.62, 0.12, -0.9, 0.45, 0.72]
	var faixas := [
		{"rot": "-0,9 (forte negativa)", "v": -0.9},
		{"rot": "-0,5 (moderada negativa)", "v": -0.5},
		{"rot": "0,0 (sem relacao linear)", "v": 0.0},
		{"rot": "+0,5 (moderada positiva)", "v": 0.5},
		{"rot": "+0,9 (forte positiva)", "v": 0.9},
	]
	var out: Array = []
	for alvo in alvos:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var a := float(alvo)
		var ruido := sqrt(maxf(0.0001, (1.0 / (a * a)) - 1.0))
		var pts := PackedVector2Array()
		var xs := PackedFloat64Array()
		var ys := PackedFloat64Array()
		for i in range(90):
			var x := rng.randf_range(0.0, 100.0)
			var y := 50.0 + a * (x - 50.0) * 0.6 + rng.randfn(0.0, 1.0) * 12.0 * ruido
			xs.append(x)
			ys.append(y)
			pts.append(Vector2(x, y))
		var r := StatCore.pearson(xs, ys)
		var rv := float(r.get("r", 0.0))
		var g := StatChartCanvas.new()
		g.custom_minimum_size.y = 230
		g.titulo = "Nuvem de pontos"
		g.definir_dispersao(pts, "variavel X", "variavel Y")
		# ancora mais proxima
		var mi := 0
		var melhor := 99.0
		for k in range(faixas.size()):
			var dist := absf(float(faixas[k]["v"]) - rv)
			if dist < melhor:
				melhor = dist
				mi = k
		var ops: Array = []
		var certa := 0
		for k in range(faixas.size()):
			ops.append(str(faixas[k]["rot"]))
		# mantem 4 opcoes, garantindo a correta
		var emb := _embaralhar(ops, mi)
		certa = int(emb["correta"])
		var explicacao := "O r de Pearson desta nuvem e %.2f. " % rv
		if absf(rv) >= 0.75:
			explicacao += "Relacao forte: os pontos seguem uma faixa estreita. "
		elif absf(rv) >= 0.4:
			explicacao += "Relacao moderada: ha tendencia clara, mas com dispersao consideravel. "
		elif absf(rv) >= 0.2:
			explicacao += "Relacao fraca: a tendencia existe, mas quase se confunde com o ruido. "
		else:
			explicacao += "Praticamente sem relacao linear: a nuvem e amorfa. "
		explicacao += "Cuidado: r mede apenas relacao LINEAR. Uma relacao em U teria r proximo de "
		explicacao += "zero e ainda assim seria perfeitamente previsivel — sempre olhe o grafico."
		out.append({"enunciado": "Qual valor de r melhor descreve esta nuvem de pontos?",
			"midia": g, "opcoes": emb["opcoes"], "correta": certa, "explicacao": explicacao})
	return out
