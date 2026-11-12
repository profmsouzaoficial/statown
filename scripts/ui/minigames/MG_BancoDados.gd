class_name MGBancoDados
extends MinigameBase
## Desafio 2 - Arquiteto do Banco de Dados.


func _init(m: Control) -> void:
	id_jogo = "banco_dados"
	titulo_jogo = "Arquiteto do Banco de Dados"
	subtitulo_jogo = "Cada variavel tem um tipo — e o tipo decide a analise possivel"
	cor_jogo = UITheme.ROXO
	super(m)


func _gerar_rodadas() -> Array:
	var itens: Array = [
		{"v": "Idade em anos completos", "t": "Quantitativa continua",
			"x": "A idade e medida em escala numerica com infinitos valores intermediarios "
				+ "(42,7 anos). Continua, mesmo que seja registrada arredondada."},
		{"v": "Numero de doses de vacina recebidas (0, 1 ou 2)", "t": "Quantitativa discreta",
			"x": "Contagem em valores inteiros sem intermediarios possiveis: nao existe 1,4 dose."},
		{"v": "Sexo registrado (Feminino / Masculino)", "t": "Qualitativa nominal",
			"x": "Categorias sem ordem. Media de sexo nao existe; o resumo correto e frequencia "
				+ "e proporcao."},
		{"v": "Escolaridade (Fundamental / Medio / Superior)", "t": "Qualitativa ordinal",
			"x": "Ha ordem natural entre as categorias, mas a distancia entre elas nao e "
				+ "mensuravel. Mediana e valida; media, nao."},
		{"v": "Renda familiar em salarios minimos", "t": "Quantitativa continua",
			"x": "Razao entre duas grandezas numericas: aceita media, desvio padrao e "
				+ "transformacoes (log, por exemplo)."},
		{"v": "Dias com sintomas no momento da entrevista", "t": "Quantitativa discreta",
			"x": "Contagem de dias inteiros. Interessa a distribuicao assimetrica a direita — "
				+ "muitos com poucos dias, poucos com muitos."},
		{"v": "Vila de residencia (20 categorias)", "t": "Qualitativa nominal",
			"x": "Identificador territorial sem hierarquia. Serve para agrupar e comparar, "
				+ "nunca para calcular media."},
		{"v": "Estrato de renda (Baixa / Media / Alta)", "t": "Qualitativa ordinal",
			"x": "Categoria derivada de uma variavel continua, com ordem. Ao agrupar em faixas, "
				+ "voce perde informacao — e isso precisa ser assumido no relatorio."},
		{"v": "Pressao arterial sistolica (mmHg)", "t": "Quantitativa continua",
			"x": "Grandeza fisica continua. Cuidado: classificada em faixas, vira ordinal e "
				+ "nao aceita mais media com o mesmo rigor."},
	]
	var tipos := ["Quantitativa continua", "Quantitativa discreta",
		"Qualitativa nominal", "Qualitativa ordinal"]
	var out: Array = []
	for it in itens:
		var correta := str(it["t"])
		var ops: Array = [correta]
		for t in tipos:
			if t != correta and ops.size() < 4:
				ops.append(t)
		var emb := _embaralhar(ops, 0)
		out.append({
			"enunciado": "Como voce classificaria a variavel: \"%s\"?" % str(it["v"]),
			"opcoes": emb["opcoes"], "correta": emb["correta"],
			"explicacao": str(it["x"]),
		})
	return out
