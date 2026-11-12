class_name MGHipoteses
extends MinigameBase
## Desafio 7 - Tribunal das Hipoteses.


func _init(m: Control) -> void:
	id_jogo = "hipoteses"
	titulo_jogo = "Tribunal das Hipoteses"
	subtitulo_jogo = "O p-valor nao e a probabilidade de H0 ser verdadeira"
	cor_jogo = UITheme.PERIGO
	super(m)


func _gerar_rodadas() -> Array:
	var out: Array = []
	var casos: Array = [
		{"p": 0.003, "ctx": "Ensaio com 800 pessoas comparando vacina e placebo: risco de "
			+ "infeccao 3,1% vs 6,4%.",
			"dec": true, "x": "p = 0,003 < 0,05: rejeita-se H0. A diferenca observada e grande e "
			+ "o acaso raramente produziria algo assim. Rejeitar H0 nao prova que a vacina "
			+ "funciona em qualquer contexto — prova que, neste estudo, a diferenca nao e "
			+ "atribuivel ao acaso."},
		{"p": 0.21, "ctx": "Comparacao de saneamento medio entre duas vilas, n = 40 em cada.",
			"dec": false, "x": "p = 0,21: nao se rejeita H0. Nao significa que as vilas sao "
			+ "iguais — significa que os dados nao forneceram evidencia suficiente. Com n = 40, "
			+ "o estudo tem pouco poder para detectar diferencas pequenas."},
		{"p": 0.049, "ctx": "Estudo com 12 participantes comparando dois horarios de coleta.",
			"dec": true, "x": "p = 0,049 < 0,05: rejeita-se H0, mas por pouco. Com n = 12, o "
			+ "resultado e fragil: um unico paciente diferente poderia inverter a conclusao. "
			+ "Reporte o IC e o tamanho de efeito, nao apenas o p."},
		{"p": 0.0001, "ctx": "Correlacao entre renda e biomarcador em 3.000 individuos, mas o "
			+ "desenho e transversal.",
			"dec": true, "x": "p muito pequeno: rejeita-se H0. Mas atencao — significancia "
			+ "estatistica nao e relevancia clinica, nem prova causalidade. Com n grande, "
			+ "diferencas minusculas ficam significativas."},
		{"p": 0.62, "ctx": "Teste de normalidade aplicado a uma variavel com 5.000 observacoes.",
			"dec": false, "x": "p = 0,62: nao se rejeita a hipotese de normalidade. Ausencia de "
			+ "evidencia contra a normalidade nao e prova de normalidade — e, com n enorme, o "
			+ "teste detecta desvios irrelevantes."},
		{"p": 0.04, "ctx": "Um mesmo experimento foi analisado de 5 maneiras diferentes; apenas "
			+ "uma deu p = 0,04.",
			"dec": true, "x": "Tecnicamente p < 0,05, mas o resultado vem de comparacao multipla: "
			+ "com 5 testes, a chance de ao menos um falso positivo e ~23%. Sem correcao "
			+ "(Bonferroni, FDR), o achado e suspeito."},
	]
	for c in casos:
		var rejeitar := bool(c["dec"])
		var ops: Array = [
			"Rejeitar H0 — ha evidencia estatistica contra H0",
			"Nao rejeitar H0 — nao ha evidencia suficiente",
			"Aceitar H0 — os dados provam que H0 e verdadeira",
			"O p-valor e a probabilidade de H0 ser verdadeira",
		]
		var correta := 0 if rejeitar else 1
		var emb := _embaralhar(ops, correta)
		out.append({
			"enunciado": "%s  O teste devolveu p = %s. Qual e a conclusao correta?" % [
				str(c["ctx"]), String.num(float(c["p"]), 4).replace(".", ",")],
			"opcoes": emb["opcoes"], "correta": emb["correta"], "explicacao": str(c["x"]),
		})
	return out
