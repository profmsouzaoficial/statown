class_name MGAuditoriaIA
extends MinigameBase
## Desafio 9 - Auditoria de IA. O Dr. Bayes erra de proposito.


func _init(m: Control) -> void:
	id_jogo = "auditoria"
	titulo_jogo = "Auditoria de IA"
	subtitulo_jogo = "O Dr. Bayes parece confiavel — encontre o erro no que ele diz"
	cor_jogo = UITheme.INFO
	super(m)


func _gerar_rodadas() -> Array:
	var rotulos := [
		"Afirmacao correta — pode usar",
		"Numero inventado (alucinacao)",
		"Confunde correlacao com causalidade",
		"Confunde p-valor com probabilidade de H0",
		"Confunde risco relativo com risco absoluto",
	]
	var itens: Array = [
		{"t": "Com p = 0,03, a probabilidade de a hipotese nula ser verdadeira e 3%.", "c": 3,
			"x": "Erro classico. O p-valor e P(dados tao extremos | H0 verdadeira), nao P(H0 | dados). "
			+ "Sao probabilidades condicionais invertidas — a confusao que mais aparece em artigos "
			+ "e em respostas de IA."},
		{"t": "O IC95% da media foi [12,4 ; 18,9]; isso significa que 95% dos individuos da "
			+ "populacao estao nesse intervalo.", "c": 2,
			"x": "Erro conceitual. O IC95% e sobre o PARAMETRO (a media), nao sobre os individuos. "
			+ "Ele diz: se repetissemos o estudo muitas vezes, 95% dos intervalos assim conteriam "
			+ "a verdadeira media. Intervalo de referencia e outra coisa."},
		{"t": "A doenca acometeu 2% dos vacinados e 4% dos nao vacinados; portanto a vacina "
			+ "reduziu o risco em 50%.", "c": 0,
			"x": "Correto como risco relativo: RR = 0,5 (reducao relativa de 50%). E util — desde "
			+ "que o risco absoluto acompanhe: de 4% para 2% sao 2 pontos percentuais, e o NNT "
			+ "e 50. As duas leituras juntas evitam alarme ou euforia."},
		{"t": "Como a correlacao entre consumo de acucar e obesidade foi r = 0,62, reduzir o "
			+ "acucar reduzira a obesidade.", "c": 2,
			"x": "Correlacao nao estabelece causalidade. Pode haver confundimento (renda, "
			+ "sedentarismo), causalidade reversa ou bidirecionalidade. Para afirmar efeito, o "
			+ "desenho precisa sustentar a inferencia."},
		{"t": "Estudo com 12 participantes encontrou p = 0,048; logo o efeito e robusto e "
			+ "replicavel.", "c": 1,
			"x": "A conclusao extrapola o dado. Com n = 12 e p proximo de 0,05, o achado e fragil. "
			+ "Alem disso, nenhum p-valor 'prova' replicabilidade — isso exige replicacao, "
			+ "pre-registro e tamanho de efeito."},
		{"t": "A prevalencia estimada foi 12,3% (IC95% 9,8-15,4), com n = 620 e amostragem "
			+ "aleatoria.", "c": 0,
			"x": "Afirmacao coerente: estimativa pontual com incerteza declarada e desenho "
			+ "compativel. Note que o IC e relativamente estreito porque n = 620 — a precisao "
			+ "vem do tamanho e do desenho, nao da sorte."},
	]
	var out: Array = []
	for it in itens:
		var correta := int(it["c"])
		var ops: Array = rotulos.duplicate()
		var emb := _embaralhar(ops, correta)
		out.append({"enunciado": "Dr. Bayes afirma: \"%s\"" % str(it["t"]),
			"opcoes": emb["opcoes"], "correta": emb["correta"], "explicacao": str(it["x"])})
	return out


func _finalizar() -> void:
	GameState.auditorias_ia += 1
	super()
