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
	GameState.moedas_ganhas_total = 1390
	var n := Economy.nota_participacao()
	_ok(int(n["pontos_brutos"]) == 139, "1390 moedas deveriam gerar 139 pontos brutos")
	_ok(int(n["nota"]) == 100, "nota deveria ser truncada no teto de 100")
	_ok(int(n["excedente"]) == 39, "excedente acima do teto deveria ser 39")

	GameState.moedas_ganhas_total = 99
	n = Economy.nota_participacao()
	_ok(int(n["nota"]) == 9, "99 moedas deveriam gerar nota 9 (divisao inteira por 10)")

	GameState.moedas_ganhas_total = 1000
	n = Economy.nota_participacao()
	_ok(int(n["nota"]) == 100, "1000 moedas deveriam gerar nota 100")


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
