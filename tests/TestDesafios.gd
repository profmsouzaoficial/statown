extends Node
const SAVE_TESTE := "user://test_desafios.json"

## Verifica o banco de desafios do LAB, a checagem por estado real e o
## pagamento unico por contexto/semana. Roda como cena (usa autoloads):
##   godot --headless res://tests/TestDesafios.tscn

var _falhas := 0
var _checks := 0
var _main: Control
var _lab: Control


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_falhas += 1
		print("  FALHA: ", msg)


func _ready() -> void:
	GameState.caminho_save = SAVE_TESTE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TESTE))
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	for i in range(6):
		await get_tree().process_frame
	_main.fechar_modal()
	GameState.reiniciar_partida()
	_main._abrir_lab()
	for i in range(4):
		await get_tree().process_frame
	_lab = _main._modal_corpo.get_child(0)
	_ok(_lab != null, "painel do LAB deveria abrir")
	if _lab == null:
		_finalizar()
		return
	_ok(_texto_de(_lab).contains("DESAFIO DO LABORATORIO"),
		"cartao de desafio deveria aparecer no LAB")
	_testar_checagens()
	await _testar_pagamento()
	_testar_reset_semana()
	_finalizar()


func _finalizar() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TESTE))
	print("DESAFIOS: %d verificacoes, %d falhas" % [_checks, _falhas])
	get_tree().quit(1 if _falhas > 0 else 0)


func _texto_de(raiz: Node) -> String:
	var out := ""
	var pilha: Array = [raiz]
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		if n is Label:
			out += " " + (n as Label).text
		for c in n.get_children():
			pilha.append(c)
	return out


func _estado_base(ctx: String) -> void:
	_lab._desafio_contexto = ctx
	_lab._acoes = {ctx: 1}
	_lab._ultima_descritiva = {}
	_lab._ultimo_grafico = {}
	_lab._ultima_dist = {}
	_lab._ultimo_teste = {}
	_lab._ultima_regressao = {}


func _testar_checagens() -> void:
	_estado_base("amostragem")
	_lab._metodo = "aas"
	_lab._amostra = PackedInt32Array()
	for i in range(200):
		_lab._amostra.append(0)
	_ok(_lab._checar_desafio("amostra_aas_200"), "AAS com 200 deveria cumprir o desafio")
	_lab._metodo = "estratificada"
	_ok(_lab._checar_desafio("amostra_estratificada_150"),
		"estratificada com 200 deveria cumprir o desafio")

	_estado_base("descritiva")
	_lab._ultima_descritiva = {"var": "idade", "grupo": ""}
	_ok(_lab._checar_desafio("descritiva_idade_ic"), "idade sem grupo deveria cumprir")
	_lab._ultima_descritiva = {"var": "renda_familiar_sm", "grupo": "genero"}
	_ok(_lab._checar_desafio("descritiva_renda_por_sexo"), "renda por sexo deveria cumprir")

	_estado_base("graficos")
	_lab._ultimo_grafico = {"tipo": 2, "x": "idade"}
	_ok(_lab._checar_desafio("grafico_histograma_idade"), "histograma de idade deveria cumprir")
	_lab._ultimo_grafico = {"tipo": 0, "x": "idade", "y": "biomarcador_clinico", "r2": 0.01}
	_ok(_lab._checar_desafio("grafico_dispersao_r2"), "dispersao com reta deveria cumprir")

	_estado_base("distribuicoes")
	_lab._ultima_dist = {"familia": 0, "p2": 2.0}
	_ok(_lab._checar_desafio("dist_normal_sigma2"), "normal com sigma 2 deveria cumprir")
	_lab._ultima_dist = {"familia": 1, "p2": 5.0}
	_ok(_lab._checar_desafio("dist_t_gl5"), "t com 5 gl deveria cumprir")

	_estado_base("testes")
	_lab._ultimo_teste = {"tipo": 0, "p": 0.01}
	_ok(_lab._checar_desafio("teste_t_p_menor_005"), "t com p < 0,05 deveria cumprir")
	_lab._ultimo_teste = {"tipo": 2}
	_ok(_lab._checar_desafio("teste_nao_parametrico"), "Mann-Whitney deveria cumprir")

	_estado_base("regressao")
	_lab._ultima_regressao = {"tipo": 0, "r2": 0.004}
	_ok(_lab._checar_desafio("regressao_linear_r2"),
		"linear com R2 baixo deveria cumprir (a tarefa e ler o R2)")
	_lab._ultima_regressao = {"tipo": 2, "or_maior_1": false}
	_ok(_lab._checar_desafio("regressao_logistica_or"),
		"logistica deveria cumprir ao exibir as OR")

	# Sem acao nesta semana/contexto, nada passa.
	_estado_base("amostragem")
	_lab._acoes = {}
	_ok(not _lab._checar_desafio("amostra_aas_200"), "sem acao registrada nao pode cumprir")


func _testar_pagamento() -> void:
	GameState.reiniciar_partida()
	GameState.desafios_lab.clear()
	_lab._acoes.clear()
	_lab._semana_acoes = -1
	_lab._ano_acoes = -1
	_lab._desafio_contexto = "amostragem"
	GameState.desafios_lab["amostragem"] = {
		"ano": GameState.ano, "semana": GameState.semana,
		"id": "amostra_aas_200", "recompensa": 20, "concluido": false,
	}
	var antes := GameState.moedas
	var ganhas_antes := GameState.moedas_ganhas_total
	_lab._metodo = "aas"
	_lab._n_alvo = 200
	_lab._nova_amostra()
	_lab._conferir_desafio()
	_ok(GameState.moedas == antes + 20, "desafio cumprido deveria pagar 20")
	_ok(GameState.moedas_ganhas_total == ganhas_antes + 20,
		"recompensa do LAB deveria contar para a nota")
	_ok(bool(GameState.desafios_lab["amostragem"].get("concluido", false)),
		"desafio deveria ficar marcado como concluido")
	var achou := false
	for t in Economy.extrato:
		if str(t.get("categoria", "")) == "desafio_lab":
			achou = true
	_ok(achou, "recompensa do LAB deveria aparecer no extrato")
	_lab._conferir_desafio()
	_ok(GameState.moedas == antes + 20, "o mesmo desafio nao pode pagar duas vezes")
	await get_tree().process_frame


func _testar_reset_semana() -> void:
	_lab._acoes = {"amostragem": 1}
	_lab._ultimo_grafico = {"tipo": 0, "x": "idade"}
	_lab._semana_acoes = GameState.semana
	_lab._ano_acoes = GameState.ano
	GameState.semana += 1
	_lab._sincronizar_semana_acoes()
	_ok(_lab._acoes.is_empty(), "acoes da semana anterior nao podem valer na nova SE")
	_ok(_lab._ultimo_grafico.is_empty(), "resultado da semana anterior nao pode valer na nova SE")
