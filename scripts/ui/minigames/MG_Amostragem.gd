class_name MGAmostragem
extends MinigameBase
## Desafio 5 - Missao Amostragem.


func _init(m: Control) -> void:
	id_jogo = "amostragem"
	titulo_jogo = "Missao Amostragem"
	subtitulo_jogo = "Sortear e facil; sortear sem vies e o trabalho"
	cor_jogo = UITheme.INFO
	super(m)


func _gerar_rodadas() -> Array:
	var metodos := ["Aleatoria simples", "Sistematica", "Estratificada", "Por conglomerados"]
	var vieses := ["Vicio de selecao", "Vicio de memoria", "Vicio de confundimento",
		"Vicio de afericao"]
	var itens: Array = [
		{"e": "O territorio tem 20 vilas com tamanhos muito diferentes e a equipe consegue "
			+ "visitar apenas 5 delas. Todos os moradores das vilas sorteadas serao entrevistados.",
			"c": "Por conglomerados", "ops": metodos,
			"x": "Sortear unidades inteiras (vilas) e entrevistar todos dentro delas e amostragem "
				+ "por conglomerados. Economiza deslocamento, mas aumenta o erro padrao: moradores "
				+ "da mesma vila se parecem entre si."},
		{"e": "A prefeitura quer garantir que as tres faixas etarias aparecam na amostra na "
			+ "mesma proporcao da populacao.",
			"c": "Estratificada", "ops": metodos,
			"x": "Dividir a populacao em estratos e sortear dentro de cada um e a amostragem "
				+ "estratificada. Ela reduz a variancia quando o estrato explica parte da "
				+ "variabilidade — e permite comparar os estratos."},
		{"e": "Um pesquisador entrevistou apenas as pessoas que estavam na praca central as 9h "
			+ "de uma terca-feira e concluiu que 80% dos moradores trabalham por conta propria.",
			"c": "Vicio de selecao", "ops": vieses,
			"x": "Quem esta na praca as 9h de terca nao representa os moradores: quem trabalha "
				+ "com carteira nao estava ali. A amostra e de conveniencia, e o erro nao "
				+ "diminui aumentando o n — aumenta a precisao do valor errado."},
		{"e": "Para estimar a prevalencia de uma doenca rara, a equipe percorre as ruas a pe e "
			+ "decide entrevistar uma casa a cada 10, a partir de um ponto sorteado.",
			"c": "Sistematica", "ops": metodos,
			"x": "Ponto de partida aleatorio + intervalo fixo = amostragem sistematica. E pratica "
				+ "em campo e quase equivalente a AAS — desde que a periodicidade do intervalo "
				+ "nao coincida com um padrao do territorio."},
		{"e": "Perguntaram, em 2026, quantas vezes a pessoa teve dengue em 2019. Metade nao "
			+ "lembrava e respondeu 'acho que nenhuma'.",
			"c": "Vicio de memoria", "ops": vieses,
			"x": "Recordar um evento de sete anos atras e pouco confiavel e a falha nao e aleatoria: "
				+ "quem teve caso leve esquece mais. Isso e vicio de memoria (recall bias), tipico de "
				+ "estudos caso-controle."},
		{"e": "Num estudo, quem tem renda alta consulta mais o medico e por isso recebe mais "
			+ "diagnostico — parecendo ter mais doenca que os demais.",
			"c": "Vicio de afericao", "ops": vieses,
			"x": "A doenca existe igual, mas e detectada de forma diferente entre os grupos. "
				+ "Isso e vicio de afericao (detection bias): o instrumento de medida nao e o "
				+ "mesmo para todos."},
	]
	var out: Array = []
	for it in itens:
		var correta := str(it["c"])
		var ops: Array = []
		ops.append(correta)
		for t in it["ops"]:
			if t != correta:
				ops.append(t)
		var emb := _embaralhar(ops, 0)
		out.append({"enunciado": str(it["e"]), "opcoes": emb["opcoes"],
			"correta": emb["correta"], "explicacao": str(it["x"])})
	return out
