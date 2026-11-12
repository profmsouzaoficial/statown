class_name MGDelineamentos
extends MinigameBase
## Desafio 1 - Detetive de Delineamentos.


func _init(m: Control) -> void:
	id_jogo = "delineamentos"
	titulo_jogo = "Detetive de Delineamentos"
	subtitulo_jogo = "Identifique o desenho do estudo antes de acreditar na conclusao"
	cor_jogo = UITheme.INFO
	super(m)


func _gerar_rodadas() -> Array:
	var base: Array = [
		{
			"c": "Transversal (seccional)",
			"e": "Uma equipe aplicou um questionario a 1.200 moradores em uma unica semana e, "
				+ "no mesmo momento, mediu saneamento e sorologia positiva.",
			"x": "Tudo foi medido em um unico instante: exposicao e desfecho sao fotografados "
				+ "juntos. Isso descreve prevalencia e associacao, mas nao permite saber o que "
				+ "veio antes.",
		},
		{
			"c": "Coorte",
			"e": "Pesquisadores acompanharam 800 pessoas saudaveis por 3 anos, comparando quem "
				+ "tinha saneamento adequado com quem nao tinha, e registraram os casos novos.",
			"x": "Partiu de pessoas sem a doenca e seguiu no tempo, medindo incidencia. A coorte "
				+ "permite estimar risco relativo e estabelecer temporalidade.",
		},
		{
			"c": "Caso-controle",
			"e": "Foram selecionadas 150 pessoas com a doenca e 300 sem a doenca; todas "
				+ "responderam retrospectivamente sobre exposicao previa.",
			"x": "Partiu do desfecho (doente/nao doente) e olhou para tras. E eficiente para "
				+ "doencas raras, mas sujeito a vies de memoria.",
		},
		{
			"c": "Ensaio clinico randomizado",
			"e": "Quatrocentos voluntarios foram sorteados para receber vacina ou placebo e "
				+ "acompanhados por um ano, sem que pesquisadores e participantes soubessem o grupo.",
			"x": "Sorteio da exposicao + cegamento: o padrao-ouro para inferencia causal. "
				+ "A randomizacao equilibra fatores confundidores conhecidos e desconhecidos.",
		},
		{
			"c": "Transversal (seccional)",
			"e": "Duas vilas tiveram a prevalencia de hipertensao medida no mesmo mes, com a "
				+ "mesma metodologia, para comparar os territorios.",
			"x": "Comparacao de prevalencias em um corte no tempo. Nao ha seguimento, logo nao "
				+ "se mede incidencia nem se estabelece causalidade.",
		},
		{
			"c": "Coorte",
			"e": "Por 10 anos, um grupo de criancas com exposicao a agua contaminada e outro sem "
				+ "exposicao foram seguidos para detectar agravos entericos.",
			"x": "Exposicao definida antes do desfecho e seguimento longitudinal: coorte. O "
				+ "risco relativo sai direto da incidencia em cada grupo.",
		},
	]
	var distratores := ["Coorte", "Caso-controle", "Ensaio clinico randomizado", "Transversal (seccional)"]
	var out: Array = []
	for item in base:
		var correta := str(item["c"])
		var ops: Array = [correta]
		for d in distratores:
			if d != correta and ops.size() < 4:
				ops.append(d)
		var emb := _embaralhar(ops, 0)
		out.append({
			"enunciado": str(item["e"]),
			"opcoes": emb["opcoes"],
			"correta": emb["correta"],
			"explicacao": str(item["x"]),
		})
	return out
