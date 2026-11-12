class_name MGGrafico
extends MinigameBase
## Desafio 4 - Oficina do Grafico Perfeito.


func _init(m: Control) -> void:
	id_jogo = "grafico"
	titulo_jogo = "Oficina do Grafico Perfeito"
	subtitulo_jogo = "O tipo das variaveis escolhe o grafico — nao o gosto pessoal"
	cor_jogo = UITheme.ACENTO
	super(m)


func _gerar_rodadas() -> Array:
	var itens: Array = [
		{"e": "Duas variaveis quantitativas: idade (anos) e biomarcador clinico, em 400 pessoas. "
			+ "O objetivo e ver se existe relacao entre elas.",
			"c": "Dispersao (X vs Y)", "x": "Duas quantitativas pedem dispersao: cada ponto e uma "
			+ "pessoa. E o unico grafico que mostra a nuvem, a tendencia e os outliers ao mesmo tempo."},
		{"e": "Uma variavel categorica com 20 vilas e o numero de casos em cada uma.",
			"c": "Barras horizontais", "x": "Categorias com nomes longos ficam legiveis na horizontal. "
			+ "Barras verticais com 20 rotulos giram a cabeca do leitor; o ranking horizontal le melhor."},
		{"e": "Uma unica variavel quantitativa (renda familiar) em 500 individuos.",
			"c": "Histograma", "x": "Histograma mostra a forma da distribuicao — assimetria, modas, "
			+ "caudas. Barras de categorias nao servem: os intervalos sao numericos e continuos."},
		{"e": "Comparar a distribuicao de dias de sintomas entre quatro faixas etarias.",
			"c": "Boxplot por grupo", "x": "O boxplot compara medianas, dispersao e outliers entre "
			+ "grupos com um unico desenho. Histogramas lado a lado ocupam muito espaco e dificultam a comparacao."},
		{"e": "Evolucao semanal de casos notificados ao longo de 52 semanas.",
			"c": "Linha (serie temporal)", "x": "Tempo no eixo x pede linha: a continuidade do traco "
			+ "comunica tendencia, e o leitor compara semanas sem esforco."},
		{"e": "Proporcao de domicilios com saneamento adequado em 5 bairros.",
			"c": "Barras verticais", "x": "Poucas categorias com rotulos curtos: barras verticais "
			+ "funcionam bem e a altura e comparada com precisao. Nunca use pizza com 5+ fatias."},
	]
	var tipos := ["Dispersao (X vs Y)", "Barras verticais", "Barras horizontais",
		"Histograma", "Boxplot por grupo", "Linha (serie temporal)"]
	var out: Array = []
	for it in itens:
		var correta := str(it["c"])
		var ops: Array = [correta]
		for t in tipos:
			if t != correta and ops.size() < 4:
				ops.append(t)
		var emb := _embaralhar(ops, 0)
		out.append({"enunciado": "Qual grafico voce escolheria? " + str(it["e"]),
			"opcoes": emb["opcoes"], "correta": emb["correta"], "explicacao": str(it["x"])})
	return out
