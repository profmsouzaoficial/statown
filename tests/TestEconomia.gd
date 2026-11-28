extends Node
const SAVE_TESTE := "user://test_economia.json"

## Verifica as regras auditaveis das BioMoedas e o game over.
## Roda como cena porque usa os autoloads:
##   godot --headless res://tests/TestEconomia.tscn

var _falhas := 0
var _checks := 0
var _main: Control


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_falhas += 1
		print("  FALHA: ", msg)


func _ready() -> void:
	# Teste nao pode tocar na conta real se a maquina tiver sessao salva.
	Conta.cfg["habilitado"] = false
	Conta._autenticado = false
	Conta.access_token = ""
	GameState.caminho_save = SAVE_TESTE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TESTE))
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	for i in range(6):
		await get_tree().process_frame
	_main.fechar_modal()
	await get_tree().process_frame

	GameState.reiniciar_partida()
	_testar_obitos()
	_testar_surto()
	_testar_nota()
	await _testar_game_over()
	_testar_pausa_foco()
	_testar_carregamento()
	_testar_persistencia_e_conflito()
	_testar_semestre()

	GameState.reiniciar_partida()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TESTE))
	print("ECONOMIA: %d verificacoes, %d falhas" % [_checks, _falhas])
	get_tree().quit(1 if _falhas > 0 else 0)


func _testar_obitos() -> void:
	GameState.moedas = 1000
	GameState.moedas_ganhas_total = 0
	Economy.extrato.clear()
	var perda := Economy.aplicar_penalidade_obitos(10)
	_ok(perda == 100, "10 obitos com saldo 1000 deveriam custar 100 (1% cada)")
	_ok(GameState.moedas == 900, "saldo apos obitos deveria ser 900")
	_ok(not Economy.extrato.is_empty(), "obitos deveriam gerar linha no extrato")
	if not Economy.extrato.is_empty():
		var t: Dictionary = Economy.extrato[0]
		_ok(int(t.get("delta", 0)) == -100, "delta do extrato deveria ser -100")
		_ok(str(t.get("categoria", "")) == "obito", "categoria deveria ser obito")

	GameState.moedas = 10
	Economy.extrato.clear()
	var perda2 := Economy.aplicar_penalidade_obitos(100)
	_ok(perda2 == 2, "teto de 25% deveria limitar a perda a 2 de 10")
	_ok(GameState.moedas == 8, "saldo apos teto deveria ser 8")

	GameState.moedas = 1
	GameState.game_over = false
	Economy.aplicar_penalidade_obitos(1)
	_ok(GameState.game_over, "saldo zero deveria acionar game over")


func _testar_surto() -> void:
	GameState.reiniciar_partida()
	var antes := GameState.moedas
	Economy._ao_surto_iniciado(12, 50)
	Economy._ao_surto_encerrado(12)
	_ok(GameState.moedas == antes + 40,
		"surto de 1 semana sem obito deveria pagar 40 (20 base + 5 semana + 15 bonus)")
	var achou := false
	for t in Economy.extrato:
		if str(t.get("categoria", "")) == "surto":
			achou = true
	_ok(achou, "recompensa de surto deveria aparecer no extrato")


func _testar_nota() -> void:
	GameState.moedas_ganhas_total = 1000
	var n := Economy.nota_participacao()
	_ok(is_equal_approx(float(n["nota"]), 40.0), "1000 moedas deveriam gerar nota 40,0")
	_ok(is_equal_approx(float(n["nota_maxima"]), 40.0), "a nota maxima deveria ser 40,0")

	GameState.moedas_ganhas_total = 500
	n = Economy.nota_participacao()
	_ok(is_equal_approx(float(n["nota"]), 20.0), "500 moedas deveriam gerar nota 20,0")

	GameState.moedas_ganhas_total = 285
	n = Economy.nota_participacao()
	_ok(is_equal_approx(float(n["nota"]), 11.4),
		"285 moedas deveriam gerar 11,4 sem artefato de ponto flutuante")

	GameState.moedas_ganhas_total = 999
	n = Economy.nota_participacao()
	_ok(is_equal_approx(float(n["nota"]), 39.9),
		"999 moedas deveriam gerar 39,9 (truncado, sem arredondar para 40,0)")

	GameState.moedas_ganhas_total = 1390
	n = Economy.nota_participacao()
	_ok(is_equal_approx(float(n["nota"]), 40.0),
		"1390 moedas deveriam ficar no teto de 40,0")
	_ok(int(n["excedente_moedas"]) == 390,
		"o excedente acima de 1000 deveria ser 390 moedas")

	GameState.moedas_ganhas_total = 0
	n = Economy.nota_participacao()
	_ok(is_equal_approx(float(n["nota"]), 0.0), "zero moedas deveria gerar nota 0,0")


func _testar_game_over() -> void:
	GameState.moedas_ganhas_total = 1390
	GameState.moedas = 0
	GameState.acionar_game_over()
	await get_tree().process_frame
	_ok(GameState.game_over, "acionar_game_over deveria marcar a partida")
	_ok(_main._game_over_layer.visible, "camada de game over deveria ficar visivel")
	var overlay_visivel: bool = bool(_main._game_over_layer.visible)
	_main._pausa_foco_layer.visible = true
	_main._reiniciar_game_over()
	await get_tree().process_frame
	_ok(not GameState.game_over, "reiniciar deveria limpar game over")
	_ok(not overlay_visivel or not _main._game_over_layer.visible,
		"overlay deveria sumir apos reiniciar")
	_ok(not _main._pausa_foco_layer.visible,
		"reiniciar deveria esconder a camada de pausa por foco")
	_ok(GameState.moedas == GameState.MOEDAS_INICIAIS, "reinicio deveria devolver o saldo inicial")
	_ok(GameState.moedas_ganhas_total == 1390, "reinicio deveria preservar as moedas ganhas")


func _testar_carregamento() -> void:
	GameState.reiniciar_partida()
	GameState.moedas = 500
	GameState.moedas_ganhas_total = 100
	Economy.extrato.clear()
	var d := GameState.serializar_partida()
	d["economia"] = {"seq": 0, "extrato": [], "surtos": {}}
	var ok := GameState.aplicar_save(d)
	_ok(ok, "save valido deveria ser aplicado")
	_ok(Economy.extrato.is_empty(),
		"carregar um save nao pode cobrar obitos da semana de novo")
	_ok(GameState.moedas == 500, "saldo do save deveria ser preservado no carregamento")


func _testar_persistencia_e_conflito() -> void:
	# Reproduz o relato: ganhar 25 e fechar a aba antes do upload. O save local
	# precisa conter o ganho e a nuvem velha nao pode apaga-lo ao reabrir.
	GameState.caminho_save = SAVE_TESTE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TESTE))
	GameState.reiniciar_partida()
	var antes := GameState.moedas
	GameState.ganhar_moedas(25, "teste de persistencia", "desafio_lab", "teste_persistencia")
	_ok(GameState.moedas == antes + 25,
		"ganho deveria entrar no saldo antes de qualquer sync")

	var arquivo := FileAccess.open(SAVE_TESTE, FileAccess.READ)
	var texto := ""
	if arquivo != null:
		texto = arquivo.get_as_text()
		arquivo.close()
	var lido = JSON.parse_string(texto)
	var d: Dictionary = lido if typeof(lido) == TYPE_DICTIONARY else {}
	_ok(FileAccess.file_exists(SAVE_TESTE),
		"ganhar moedas deveria gravar o save local na hora")
	_ok(not d.is_empty(), "save local deveria ser um JSON valido")
	_ok(int(d.get("moedas", 0)) == antes + 25,
		"save local deveria guardar o saldo com o ganho")
	_ok(int(d.get("moedas_ganhas", 0)) == 25,
		"save local deveria guardar a producao do semestre")
	var achou := false
	var extrato: Array = (d.get("economia", {}) as Dictionary).get("extrato", [])
	for t in extrato:
		if typeof(t) == TYPE_DICTIONARY and str(t.get("categoria", "")) == "desafio_lab" \
				and int(t.get("delta", 0)) == 25:
			achou = true
	_ok(achou, "extrato salvo deveria conter a transacao do ganho")

	var antigo: Dictionary = d.duplicate(true)
	antigo["moedas"] = antes
	antigo["moedas_ganhas"] = 0
	antigo["semana"] = 1
	antigo["ano"] = 1
	_ok(GameState.progresso_local_maior(antigo),
		"cache local com 25 ganhas deveria vencer a nuvem com 0")
	var novo: Dictionary = d.duplicate(true)
	novo["moedas_ganhas"] = 25
	novo["semana"] = GameState.semana + 1
	_ok(not GameState.progresso_local_maior(novo),
		"nuvem com a mesma producao e semana posterior deveria vencer")

	# Simula fechar/reabrir: o estado em memoria some e so o arquivo fica.
	GameState.moedas = 0
	GameState.moedas_ganhas_total = 0
	_ok(GameState.carregar_partida(), "save local recem-gravado deveria carregar")
	_ok(GameState.moedas == antes + 25 and GameState.moedas_ganhas_total == 25,
		"reabrir deveria recuperar as 25 BioMoedas e a producao")

	# O download antigo da nuvem nao pode substituir esse cache.
	Conta._autenticado = false
	Conta._bloquear_sync = true
	Conta._progresso_pronto = false
	Conta._cache_local_conta = true
	Conta._tratar_carregar([{"save_data": antigo, "atualizado_em": "2026-11-24T22:11:56+00:00"}])
	_ok(GameState.moedas == antes + 25,
		"aplicar a nuvem velha nao pode apagar as 25 moedas locais")
	_ok(Conta._progresso_pronto,
		"depois de preservar o local, o progresso deveria ser considerado pronto")

	# Sem cache comprovado desta conta, a nuvem continua sendo a referencia:
	# um save anonimo/default nao pode sobrescrever a conta.
	Conta._progresso_pronto = false
	Conta._cache_local_conta = false
	Conta._tratar_carregar([{"save_data": antigo, "atualizado_em": "2026-11-24T22:11:56+00:00"}])
	_ok(GameState.moedas == antes,
		"sem cache da conta, a nuvem deveria prevalecer")

	# E, quando a nuvem realmente tem mais producao, ela continua vencendo.
	Conta._progresso_pronto = false
	novo["moedas"] = 200
	novo["moedas_ganhas"] = 50
	novo["semana"] = GameState.semana + 2
	Conta._tratar_carregar([{"save_data": novo, "atualizado_em": "2026-11-25T10:00:00+00:00"}])
	_ok(GameState.moedas == 200,
		"nuvem com mais producao deveria ser aplicada")

	Conta._bloquear_sync = false
	Conta._progresso_pronto = false
	GameState.caminho_save = SAVE_TESTE
	GameState.reiniciar_partida()


func _testar_semestre() -> void:
	var d := GameState.serializar_partida()
	d["semestre"] = "1999/1"
	_ok(not GameState.aplicar_save(d), "save de outro semestre nao pode ser aplicado")
	GameState.caminho_save = "user://test_semestre.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.caminho_save))
	var f := FileAccess.open(GameState.caminho_save, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	_ok(GameState.carregar_partida(), "save antigo deveria ser reconhecido e reiniciado")
	_ok(GameState.semana == 1 and GameState.moedas_ganhas_total == 0,
		"semestre novo deveria comecar em SE 1 sem moedas do semestre anterior")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.caminho_save))
	GameState.caminho_save = SAVE_TESTE
	GameState.reiniciar_partida()


func _testar_pausa_foco() -> void:
	GameState.pausado = false
	GameState.velocidade = 1.0
	GameState.pausar_por_foco()
	_ok(GameState.pausado, "pausa por foco deveria pausar")
	_ok(GameState.pausado_por_foco(), "estado de pausa por foco deveria ficar ativo")
	GameState.retomar_por_foco()
	_ok(not GameState.pausado, "retomar por foco deveria despausar")
	_ok(not GameState.pausado_por_foco(), "estado de pausa por foco deveria ser limpo")

	GameState.pausado = true
	GameState.velocidade = 0.0
	GameState.pausar_por_foco()
	GameState.retomar_por_foco()
	_ok(GameState.pausado, "quem ja estava pausado deveria continuar pausado")
	GameState.pausado = false
	GameState.velocidade = 1.0
