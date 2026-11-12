class_name MGAssimetria
extends MinigameBase
## Desafio 3 - Mestre da Assimetria.


func _init(m: Control) -> void:
	id_jogo = "assimetria"
	titulo_jogo = "Mestre da Assimetria"
	subtitulo_jogo = "Leia a forma da distribuicao antes de olhar para a media"
	cor_jogo = UITheme.ACENTO_2
	super(m)


func _gerar_rodadas() -> Array:
	var out: Array = []
	var configs := [
		{"tipo": "simetrica", "n": 400},
		{"tipo": "direita", "n": 400},
		{"tipo": "esquerda", "n": 400},
		{"tipo": "direita", "n": 300},
		{"tipo": "simetrica", "n": 500},
		{"tipo": "esquerda", "n": 350},
	]
	for cfg in configs:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var dados := PackedFloat64Array()
		var tipo := str(cfg["tipo"])
		for i in range(int(cfg["n"])):
			var z := rng.randfn(0.0, 1.0)
			if tipo == "direita":
				dados.append(exp(z * 0.9) * 12.0)
			elif tipo == "esquerda":
				dados.append(120.0 - exp(z * 0.9) * 10.0)
			else:
				dados.append(60.0 + z * 12.0)

		var g := StatChartCanvas.new()
		g.custom_minimum_size.y = 210
		var h := StatCore.histogram(dados, 14)
		var bins: PackedFloat64Array = h["bins"]
		var counts: PackedFloat64Array = h["counts"]
		var centros: Array = []
		for i in range(counts.size()):
			centros.append((bins[i] + bins[i + 1]) * 0.5)
		g.titulo = "Histograma de %d observacoes" % int(cfg["n"])
		g.formato_y = "int"
		g.definir_histograma(centros, counts, "valor")

		var d := StatCore.describe(dados)
		var media := float(d["media"])
		var mediana := float(d["mediana"])
		var correta := ""
		var ex := ""
		if tipo == "direita":
			correta = "Assimetrica a direita (cauda longa nos valores altos)"
			ex = ("A cauda se estica para a direita. Media (%.1f) maior que mediana (%.1f), "
				+ "porque valores extremos altos puxam a media. Em renda e em dias de "
				+ "internacao esse padrao e a regra, nao a excecao.") % [media, mediana]
		elif tipo == "esquerda":
			correta = "Assimetrica a esquerda (cauda longa nos valores baixos)"
			ex = ("A cauda se estica para a esquerda. Media (%.1f) menor que mediana (%.1f), "
				+ "porque valores extremos baixos puxam a media. Acontece com variaveis que "
				+ "tem um teto natural, como indices de qualidade de vida.") % [media, mediana]
		else:
			correta = "Aproximadamente simetrica"
			ex = ("Os dois lados se parecem. Media (%.1f) e mediana (%.1f) ficam proximas, "
				+ "e a media e um bom resumo. Ainda assim, verifique a curtose antes de "
				+ "assumir normalidade.") % [media, mediana]

		var ops := ["Aproximadamente simetrica",
			"Assimetrica a direita (cauda longa nos valores altos)",
			"Assimetrica a esquerda (cauda longa nos valores baixos)",
			"Bimodal — duas populacoes misturadas"]
		var emb := _embaralhar(ops, ops.find(correta))
		out.append({
			"enunciado": "O histograma abaixo e de uma variavel quantitativa. Como voce "
				+ "descreveria a forma da distribuicao?",
			"midia": g, "opcoes": emb["opcoes"], "correta": emb["correta"], "explicacao": ex,
		})
	return out
