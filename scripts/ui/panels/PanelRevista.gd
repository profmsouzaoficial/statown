class_name PanelRevista
extends Control
## Revista Cientifica do Vale — clube de leitura com avaliacao critica.
##
## ATENCAO: todos os artigos, autores e periodicos desta tela sao FICTICIOS,
## criados para o jogo. Nenhum dado corresponde a publicacao real. O objetivo
## e treinar leitura critica: desenho, medida, vies, interpretacao.

var main: Control
var _lista: VBoxContainer
var _leitor: VBoxContainer
var _artigo_atual := -1
var _mostrar_perguntas := false

const ARTIGOS := [
	{
		"id": "art_saneamento",
		"titulo": "Saneamento basico e prevalencia de arbovirose em 20 comunidades do Vale",
		"autores": "R. Almeida, C. Furtado, M. Teixeira",
		"periodico": "Revista Cientifica do Vale (ficticia) · v. 12, n. 3, 2026",
		"desenho": "Transversal",
		"resumo": "Objetivo: estimar a associacao entre cobertura de saneamento e prevalencia "
			+ "de arbovirose. Metodos: inquerito domiciliar em 20 comunidades, com sorologia "
			+ "conveniencia de 1.842 moradores em uma unica semana. Resultados: a prevalencia "
			+ "foi 11,4% (IC95% 9,8-13,0). Cada aumento de 10 pontos percentuais na cobertura "
			+ "de saneamento associou-se a reducao de 2,1 pontos na prevalencia (p < 0,001).",
		"achados": [
			["Prevalencia global", "11,4% (IC95% 9,8-13,0)"],
			["Comunidades com saneamento < 50%", "15,2%"],
			["Comunidades com saneamento >= 80%", "6,8%"],
			["Associacao ajustada", "RP = 0,79 por 10 p.p. (p < 0,001)"],
		],
		"limitacoes": "Desenho transversal: exposicao e desfecho medidos no mesmo momento, sem "
			+ "temporalidade. Amostra de conveniencia com 1.842 de 41.650 habitantes (4,4%). "
			+ "Saneamento autorreferido. Nao ha ajuste para idade na analise bruta apresentada.",
		"perguntas": [
			["Qual e a pergunta PICO do estudo?",
				"Populacao: moradores das 20 comunidades. Exposicao: cobertura de saneamento. "
				+ "Comparacao: comunidades com mais vs menos saneamento. Desfecho: prevalencia "
				+ "de arbovirose. O desenho responde 'quanto' e 'onde', nao 'por que'."],
			["O desenho permite afirmar causalidade?",
				"Nao. Transversal mede tudo ao mesmo tempo: nao se sabe se o saneamento veio "
				+ "antes da doenca. Alem disso, comunidades com mais saneamento tendem a ter mais "
				+ "renda e escolaridade — confundimento nao controlado no resultado bruto."],
			["A amostra de conveniencia invalida o estudo?",
				"Compromete a representatividade, mas nao invalida tudo. O correto e declarar a "
				+ "limitacao e nao extrapolar para o municipio. Um n grande com vicio de selecao "
				+ "produz estimativa precisa e errada."],
			["O que o IC95% informa aqui?",
				"Que, repetindo o estudo, 95% dos intervalos assim conteriam a verdadeira "
				+ "prevalencia. Ele mede a incerteza amostral — nao corrige vies de desenho."],
		],
	},
	{
		"id": "art_vacina",
		"titulo": "Cobertura vacinal e incidencia de agravo respiratorio: coorte de 12 meses",
		"autores": "L. Bittencourt, A. Nogueira",
		"periodico": "Revista Cientifica do Vale (ficticia) · v. 13, n. 1, 2026",
		"desenho": "Coorte prospectiva",
		"resumo": "Objetivo: estimar a efetividade da vacina contra agravo respiratorio. "
			+ "Metodos: 6.400 adultos sem doenca previa foram classificados por status vacinal "
			+ "e seguidos por 52 semanas, com notificacao semanal. Resultados: incidencia de "
			+ "3,9% nos vacinados e 9,7% nos nao vacinados; RR = 0,40 (IC95% 0,33-0,49); "
			+ "efetividade de 60% (IC95% 51-67).",
		"achados": [
			["Incidencia em vacinados", "3,9% (n = 4.100)"],
			["Incidencia em nao vacinados", "9,7% (n = 2.300)"],
			["Risco relativo", "0,40 (IC95% 0,33-0,49)"],
			["Reducao absoluta / NNT", "5,8 p.p. / NNT = 18"],
		],
		"limitacoes": "Nao randomizado: quem se vacina difere de quem nao se vacina (idade, "
			+ "ocupacao, acesso a servicos). Perda de seguimento de 8%, concentrada nos mais "
			+ "jovens. Desfecho notificado, sujeito a subdiagnostico diferencial.",
		"perguntas": [
			["Por que coorte e melhor que transversal para este objetivo?",
				"Porque parte de pessoas saudaveis e mede incidencia ao longo do tempo. Isso "
				+ "garante temporalidade (vacina antes da doenca) e permite calcular risco "
				+ "relativo diretamente."],
			["Qual a diferenca entre eficacia e efetividade?",
				"Eficacia e o resultado em condicoes ideais (ensaio clinico). Efetividade e o "
				+ "resultado em condicoes reais de servico — que e o que uma coorte observacional "
				+ "estima, com a vantagem e o risco de nao haver randomizacao."],
			["Interprete o NNT = 18.",
				"E preciso vacinar cerca de 18 pessoas para evitar um caso no periodo de um ano. "
				+ "E uma medida de impacto concreto, mais util para gestao do que o RR isolado."],
			["O que o vies de autosselecao pode fazer com o RR?",
				"Se os vacinados forem mais saudaveis e com melhor acesso, o RR ficaria "
				+ "artificialmente menor (superestimando a protecao). Por isso o texto precisa "
				+ "de ajuste multivariado ou de um desenho quasi-experimental."],
		],
	},
	{
		"id": "art_teste",
		"titulo": "Acuracia de um teste rapido na atencao primaria: sensibilidade, especificidade e VPP",
		"autores": "P. Queiroz, F. Andrade, T. Cardoso",
		"periodico": "Revista Cientifica do Vale (ficticia) · v. 11, n. 4, 2025",
		"desenho": "Estudo de acuracia diagnostica",
		"resumo": "Objetivo: avaliar um teste rapido para triagem. Metodos: 1.200 pacientes "
			+ "submetidos ao teste e ao padrao-ouro. Resultados: sensibilidade 88% (IC95% "
			+ "84-91), especificidade 92% (IC95% 89-94). Com prevalencia de 12%, o VPP foi "
			+ "60% e o VPN 98%.",
		"achados": [
			["Sensibilidade", "88% (IC95% 84-91)"],
			["Especificidade", "92% (IC95% 89-94)"],
			["VPP com prevalencia 12%", "60%"],
			["VPN com prevalencia 12%", "98%"],
		],
		"limitacoes": "Estimativas obtidas em servico de referencia, com espectro de doenca "
			+ "mais grave que a atencao primaria (vies de espectro). Nao ha avaliacao de "
			+ "reprodutibilidade entre observadores.",
		"perguntas": [
			["Por que o VPP muda com a prevalencia?",
				"Porque o VPP depende de quantos doentes existem na populacao testada. "
				+ "Sensibilidade e especificidade sao propriedades do teste; VPP e VPN sao "
				+ "propriedades do teste NAQUELA populacao."],
			["Um teste com VPP 60% serve para triagem?",
				"Sim, se o custo de falso positivo for baixo e houver confirmacao posterior. "
				+ "Triagem privilegia sensibilidade (nao perder doentes); confirmacao privilegia "
				+ "especificidade."],
			["O que e vies de espectro?",
				"Quando o teste e validado em pacientes mais graves do que aqueles em quem sera "
				+ "usado, a sensibilidade parece maior. Na pratica real, o desempenho cai."],
			["Como o VPN 98% deve ser comunicado ao paciente?",
				"Como 'se o teste der negativo, a chance de ter a doenca e cerca de 2%'. Nunca "
				+ "como 'o teste garante que voce nao tem' — nenhum teste zera a probabilidade."],
		],
	},
	{
		"id": "art_assimetria",
		"titulo": "Renda, escolaridade e biomarcador inflamatorio: o papel da assimetria na analise",
		"autores": "D. Rezende, S. Moura",
		"periodico": "Revista Cientifica do Vale (ficticia) · v. 12, n. 2, 2026",
		"desenho": "Transversal analitico com regressao",
		"resumo": "Objetivo: modelar determinantes do biomarcador. Metodos: 3.050 individuos; "
			+ "renda apresentou forte assimetria a direita (g1 = 2,4), optando-se por "
			+ "transformacao logaritmica. Resultados: no modelo final, escolaridade superior "
			+ "associou-se a biomarcador 8,2% menor (IC95% 3,1-13,0) e renda (log) a -1,9% por "
			+ "unidade (IC95% 0,4-3,4). R2 ajustado = 0,21.",
		"achados": [
			["Assimetria da renda (g1)", "2,4 (assimetrica a direita)"],
			["Efeito da escolaridade superior", "-8,2% (IC95% 3,1-13,0)"],
			["Efeito de 1 unidade de log-renda", "-1,9% (IC95% 0,4-3,4)"],
			["R2 ajustado", "0,21"],
		],
		"limitacoes": "Desenho transversal; nao se pode descartar causalidade reversa "
			+ "(biomarcador alterado por doenca que tambem afeta renda). R2 de 0,21 indica que "
			+ "79% da variacao permanece inexplicada pelo modelo.",
		"perguntas": [
			["Por que transformar a renda em log?",
				"Porque a renda tem cauda longa a direita. O log comprime os valores extremos, "
				+ "aproxima a distribuicao da simetria e evita que poucos individuos dominem o "
				+ "modelo. O custo e interpretar o coeficiente em escala multiplicativa."],
			["R2 = 0,21 e um resultado ruim?",
				"Depende do objetivo. Para prever individuo a individuo, e fraco. Para estimar "
				+ "efeito medio de um fator com precisao (IC estreito), pode ser suficiente. "
				+ "R2 mede explicacao conjunta, nao qualidade causal do modelo."],
			["Como interpretar '-8,2%' corretamente?",
				"Em modelo com desfecho log-transformado, o coeficiente vira variacao "
				+ "percentual aproximada. Nao e '8,2 pontos' do biomarcador — e 8,2% em relacao "
				+ "a media."],
			["Quais confundidores o estudo nao controlou?",
				"Idade, tempo de doenca, uso de medicacao e acesso a servico. Se idade afeta "
				+ "tanto escolaridade quanto biomarcador, o efeito estimado esta contaminado."],
		],
	},
	{
		"id": "art_custo",
		"titulo": "Custo-efetividade de unidade movel versus unidade fixa no territorio",
		"autores": "M. Prado, E. Lacerda, J. Faria",
		"periodico": "Revista Cientifica do Vale (ficticia) · v. 10, n. 2, 2025",
		"desenho": "Avaliacao economica com modelo de decisao",
		"resumo": "Objetivo: comparar custo por caso evitado entre unidade movel (UM) e "
			+ "unidade fixa (UF). Metodos: modelo de Markov com horizonte de 5 anos, custos "
			+ "do SUS e efetividade derivada de metanalise. Resultados: UM custou R$ 42 mil a "
			+ "mais por ano e evitou 31 casos adicionais; custo por caso evitado de R$ 1.350, "
			+ "abaixo do limiar de R$ 5.000 adotado.",
		"achados": [
			["Custo anual incremental", "R$ 42.000"],
			["Casos adicionais evitados", "31 por ano"],
			["Custo por caso evitado", "R$ 1.350"],
			["Razao de custo-efetividade incremental", "R$ 1.350 / caso evitado"],
		],
		"limitacoes": "Modelo depende de premissas sobre adesao e cobertura. Efetividade "
			+ "transportada de metanalise com populacoes distintas. Nao foram incluidos custos "
			+ "indiretos (deslocamento e perda de renda do paciente).",
		"perguntas": [
			["O que significa ICER neste contexto?",
				"Razao entre custo adicional e efeito adicional: (custo UM - custo UF) / "
				+ "(casos UF - casos UM). Aqui, R$ 42.000 / 31 = R$ 1.350 por caso evitado."],
			["O que e limiar de custo-efetividade?",
				"Valor maximo que o sistema aceita pagar por unidade de efeito. E uma decisao "
				+ "politica, nao estatistica. Sem ele, 'caro' ou 'barato' nao tem significado."],
			["Por que analise de sensibilidade e obrigatoria?",
				"Porque todo modelo economico tem premissas. Testar variacoes mostra se a "
				+ "conclusao sobrevive a mudancas plausiveis — se nao sobrevive, a decisao e "
				+ "fragil."],
			["Que custos ficaram de fora e para quem importam?",
				"Custos indiretos e de deslocamento importam para o paciente e para a "
				+ "sociedade, nao para o orcamento do servico. A perspectiva da analise muda "
				+ "a conclusao."],
		],
	},
	{
		"id": "art_pvalor",
		"titulo": "Auditoria metodologica: como o p-valor foi reportado em 200 artigos",
		"autores": "A. Siqueira, N. Ramos",
		"periodico": "Revista Cientifica do Vale (ficticia) · v. 13, n. 2, 2026",
		"desenho": "Estudo metodologico (meta-pesquisa)",
		"resumo": "Objetivo: descrever praticas de reporte de p-valor. Metodos: 200 artigos "
			+ "avaliados por dois revisores independentes (kappa = 0,81). Resultados: 58% "
			+ "reportaram p sem intervalo de confianca; 34% usaram 'p < 0,05' como unico "
			+ "criterio de conclusao; 12% descreveram p como 'probabilidade de H0'.",
		"achados": [
			["Sem IC junto ao p", "58% dos artigos"],
			["Apenas dicotomia p < 0,05", "34%"],
			["Interpretacao incorreta do p", "12%"],
			["Concordancia entre revisores", "kappa = 0,81"],
		],
		"limitacoes": "Amostra restrita a um periodico e a um ano. Revisores nao cegados ao "
			+ "periodico. Nao se avaliou adequacao do teste estatistico ao desenho.",
		"perguntas": [
			["Por que reportar IC e mais informativo que reportar p?",
				"O IC mostra magnitude e incerteza na unidade da variavel; o p so indica "
				+ "compatibilidade com H0. Dois estudos com p = 0,04 podem ter efeitos de "
				+ "tamanhos muito diferentes."],
			["O que kappa = 0,81 indica?",
				"Concordancia substancial entre avaliadores, acima do esperado pelo acaso. "
				+ "Sem essa medida, a classificacao dos artigos seria opiniao individual."],
			["Qual o risco de dicotomizar em p < 0,05?",
				"Transformar evidencia continua em sim/nao esconde efeitos reais e infla a "
				+ "credibilidade de achados frageis. p = 0,049 e p = 0,051 sao praticamente "
				+ "o mesmo nivel de evidencia."],
			["Como esta auditoria poderia ser melhorada?",
				"Pre-registro do protocolo, amostra probabilistica de periodicos, avaliacao "
				+ "cega e desfechos pre-definidos. Meta-pesquisa tambem precisa de metodo."],
		],
	},
]


func _init(m: Control) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var raiz := HBoxContainer.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_theme_constant_override("separation", 12)
	add_child(raiz)

	# aviso de ficcao
	var esq := VBoxContainer.new()
	esq.custom_minimum_size.x = 330
	esq.add_theme_constant_override("separation", 8)
	raiz.add_child(esq)
	var aviso := UITheme.card("AVISO", UITheme.PERIGO)
	esq.add_child(aviso)
	UITheme.conteudo(aviso).add_child(UITheme.paragrafo(
		"Todos os artigos, autores e periodicos desta tela sao FICTICIOS, criados para o "
		+ "jogo. Nenhum dado corresponde a publicacao real.", 11, UITheme.PERIGO))
	esq.add_child(UITheme.rotulo("%d ARTIGOS" % ARTIGOS.size(), 11, UITheme.ACENTO))
	var sc := UITheme.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	esq.add_child(sc)
	_lista = UITheme.vbox(8)
	sc.add_child(_lista)
	for i in range(ARTIGOS.size()):
		_lista.add_child(_botao_artigo(i))

	var dir := VBoxContainer.new()
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raiz.add_child(dir)
	var sc2 := UITheme.scroll()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dir.add_child(sc2)
	_leitor = UITheme.vbox(10)
	sc2.add_child(_leitor)

	_abrir_artigo(0)


func _botao_artigo(i: int) -> Button:
	var a: Dictionary = ARTIGOS[i]
	var lido := GameState.artigos_lidos.has(str(a["id"]))
	var b := UITheme.botao(("* " if lido else "") + str(a["titulo"]),
		_abrir_artigo.bind(i), null, UITheme.SUCESSO if lido else UITheme.BORDA)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.y = 66
	return b


func _abrir_artigo(i: int) -> void:
	_artigo_atual = i
	_mostrar_perguntas = false
	for c in _leitor.get_children():
		c.queue_free()
	var a: Dictionary = ARTIGOS[i]

	_leitor.add_child(UITheme.rotulo(str(a["desenho"]).to_upper(), 11, UITheme.ACENTO))
	var tit := UITheme.paragrafo(str(a["titulo"]), 24, UITheme.TEXTO)
	tit.add_theme_font_override("font", UITheme.corpo(700))
	tit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_leitor.add_child(tit)
	_leitor.add_child(UITheme.rotulo(str(a["autores"]) + "  ·  " + str(a["periodico"]),
		12, UITheme.TEXTO_FRACO))

	var p := UITheme.card("RESUMO ESTRUTURADO", UITheme.INFO)
	_leitor.add_child(p)
	UITheme.conteudo(p).add_child(_texto(str(a["resumo"])))

	var p2 := UITheme.card("PRINCIPAIS ACHADOS", UITheme.ACENTO_2)
	_leitor.add_child(p2)
	var c2 := UITheme.conteudo(p2)
	for par in a["achados"]:
		c2.add_child(UITheme.linha_medida(str((par as Array)[0]), str((par as Array)[1])))

	var p3 := UITheme.card("LIMITACOES DECLARADAS", UITheme.PERIGO)
	_leitor.add_child(p3)
	UITheme.conteudo(p3).add_child(_texto(str(a["limitacoes"])))

	var acoes := HBoxContainer.new()
	acoes.add_theme_constant_override("separation", 10)
	_leitor.add_child(acoes)
	acoes.add_child(UITheme.botao("Marcar como lido (+20)", _marcar_lido, null, UITheme.SUCESSO))
	acoes.add_child(UITheme.botao("Perguntas de avaliacao critica", _alternar_perguntas,
		null, UITheme.ROXO))
	acoes.add_child(UITheme.botao("Copiar citacao", _copiar_citacao, null, UITheme.INFO))

	var area := VBoxContainer.new()
	area.name = "Perguntas"
	area.add_theme_constant_override("separation", 8)
	_leitor.add_child(area)


func _texto(t: String) -> Label:
	var l := UITheme.paragrafo(t, 15, UITheme.TEXTO)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _alternar_perguntas() -> void:
	if _artigo_atual < 0:
		return
	var area := _leitor.find_child("Perguntas", true, false) as VBoxContainer
	if area == null:
		return
	if area.get_child_count() > 0:
		for c in area.get_children():
			c.queue_free()
		return
	var a: Dictionary = ARTIGOS[_artigo_atual]
	var k := 1
	for par in a["perguntas"]:
		var card := UITheme.card("", UITheme.BORDA_CLARA)
		area.add_child(card)
		var c := UITheme.conteudo(card)
		var q := UITheme.paragrafo("%d. %s" % [k, str((par as Array)[0])], 15, UITheme.ACENTO)
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(q)
		var resp := _texto(str((par as Array)[1]))
		resp.visible = false
		c.add_child(resp)
		var b := UITheme.botao("Mostrar resposta", func():
			resp.visible = not resp.visible, null, UITheme.BORDA)
		c.add_child(b)
		k += 1


func _marcar_lido() -> void:
	if _artigo_atual < 0:
		return
	var id := str(ARTIGOS[_artigo_atual]["id"])
	if GameState.artigos_lidos.has(id):
		main.mostrar_toast("Este artigo ja foi contabilizado", "info")
		return
	GameState.registrar_artigo(id)
	main.mostrar_toast("Artigo lido: +20 BioMoedas", "sucesso")
	for c in _lista.get_children():
		c.queue_free()
	for i in range(ARTIGOS.size()):
		_lista.add_child(_botao_artigo(i))


func _copiar_citacao() -> void:
	if _artigo_atual < 0:
		return
	var a: Dictionary = ARTIGOS[_artigo_atual]
	var cit := "%s. %s. %s. [Artigo ficticio do jogo StaTown]" % [
		str(a["autores"]), str(a["titulo"]), str(a["periodico"])]
	DisplayServer.clipboard_set(cit)
	main.mostrar_toast("Citacao ficticia copiada", "info")
