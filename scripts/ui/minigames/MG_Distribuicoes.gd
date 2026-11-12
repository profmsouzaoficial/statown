class_name MGDistribuicoes
extends MinigameBase
## Desafio 6 - Roleta das Distribuicoes.


func _init(m: Control) -> void:
	id_jogo = "distribuicoes"
	titulo_jogo = "Roleta das Distribuicoes"
	subtitulo_jogo = "Escolher a familia errada invalida o p-valor"
	cor_jogo = UITheme.ROXO
	super(m)


func _gerar_rodadas() -> Array:
	var fam := ["Normal", "Binomial", "Poisson", "t de Student", "Qui-quadrado"]
	var itens: Array = [
		{"e": "Altura de adultos de uma mesma vila, medida em centimetros.",
			"c": "Normal", "x": "Soma de muitos fatores pequenos e independentes gera uma "
			+ "distribuicao aproximadamente normal. Altura, pressao e erros de medida sao os "
			+ "exemplos classicos."},
		{"e": "Numero de casos novos de uma doenca rara em uma semana, com media de 3 por semana.",
			"c": "Poisson", "x": "Contagem de eventos raros num intervalo fixo, em que a media e "
			+ "proporcional ao tempo de observacao, segue Poisson. A variancia e igual a media."},
		{"e": "Numero de pessoas vacinadas entre 30 sorteadas, quando a cobertura e 70%.",
			"c": "Binomial", "x": "n tentativas independentes com a mesma probabilidade de sucesso: "
			+ "binomial. Se n e grande e p e pequeno, ela se aproxima de Poisson."},
		{"e": "Diferenca entre a media de uma amostra pequena (n=12) e a media populacional, com "
			+ "sigma desconhecido.",
			"c": "t de Student", "x": "Com n pequeno e sigma desconhecido, a estimativa da "
			+ "variabilidade acrescenta incerteza: a estatistica t tem caudas mais pesadas que a "
			+ "normal. Conforme n cresce, t se aproxima de z."},
		{"e": "Teste de independencia entre saneamento (2 categorias) e infectado (2 categorias).",
			"c": "Qui-quadrado", "x": "Tabelas de contingencia usam qui-quadrado, que mede o "
			+ "afastamento entre frequencias observadas e esperadas sob independencia."},
		{"e": "Soma dos quadrados dos desvios padronizados de 5 categorias independentes.",
			"c": "Qui-quadrado", "x": "Soma de z ao quadrado com k graus de liberdade e, por "
			+ "definicao, qui-quadrado com k gl. Por isso ela e a distribuicao dos testes de "
			+ "aderencia e independencia."},
		{"e": "Tempo ate o proximo atendimento em uma fila, quando os atendimentos sao aleatorios "
			+ "e independentes.",
			"c": "Poisson", "x": "O numero de eventos por intervalo e Poisson; o tempo entre "
			+ "eventos sucessivos segue exponencial. As duas descricoes do mesmo processo se "
			+ "complementam — por isso a contagem aponta para Poisson."},
	]
	var out: Array = []
	for it in itens:
		var correta := str(it["c"])
		var ops: Array = [correta]
		for f in fam:
			if f != correta and ops.size() < 4:
				ops.append(f)
		var emb := _embaralhar(ops, 0)
		out.append({"enunciado": str(it["e"]), "opcoes": emb["opcoes"],
			"correta": emb["correta"], "explicacao": str(it["x"])})
	return out
