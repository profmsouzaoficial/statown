extends Node
## Audita o teto de moedas que contam para a nota.
##
## O jogo permite repetir minigames e semanas; por isso o saldo e as moedas
## ganhas podem crescer sem limite. A nota, porem, usa no maximo 1000 moedas.
## Este teste separa duas coisas:
##   1. conteudo unico de uma passagem (9 minigames, 50 artigos, 6 LAB, 8 Bayes);
##   2. repeticao infinita, que so aumenta saldo/extrato, nao a nota.

const SAVE_TESTE := "user://test_moedas.json"
const MOEDAS_TETO := 1000

var _falhas := 0
var _checks := 0


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_falhas += 1
		print("  FALHA: ", msg)


func _ready() -> void:
	Conta.cfg["habilitado"] = false
	Conta._autenticado = false
	Conta.access_token = ""
	GameState.caminho_save = SAVE_TESTE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TESTE))
	GameState.reiniciar_partida()

	var artigos: Array = _ler_json("res://data/revista_artigos.json")
	var lab: Dictionary = _ler_json("res://data/desafios_lab.json")
	_ok(artigos.size() == 50, "o acervo deveria ter 50 artigos unicos")
	_ok(PanelMinigames.JOGOS.size() == 9, "o hub deveria ter 9 minigames")
	_ok(lab.get("contextos", []).size() == 6, "o LAB deveria ter 6 contextos")

	# 1. Conteudo unico de uma passagem, sem repetir semana nem partida.
	var recompensa_minigame := 10 + int(round(60.0 * 1.0))
	_ok(recompensa_minigame == 70, "minigame perfeito deveria pagar 70")
	for j in PanelMinigames.JOGOS:
		GameState.registrar_minigame(str(j["id"]), 1, 1, recompensa_minigame)
	_ok(GameState.moedas_ganhas_total == 630, "9 minigames perfeitos deveriam pagar 630")

	var ids_artigos := {}
	for a in artigos:
		ids_artigos[str(a.get("id", ""))] = true
	_ok(ids_artigos.size() == 50, "os IDs dos artigos deveriam ser unicos")
	for id in ids_artigos:
		GameState.registrar_artigo(id)
	_ok(GameState.moedas_ganhas_total == 1630, "os 50 artigos deveriam pagar 1000")

	var max_lab := 0
	for ctx in lab.get("contextos", []):
		var maior := 0
		for d in ctx.get("desafios", []):
			maior = maxi(maior, int(d.get("recompensa", 0)))
		max_lab += maior
		GameState.ganhar_moedas(maior, "auditoria do teto do LAB", "desafio_lab")
	_ok(max_lab == 160, "o melhor desafio de cada contexto deveria somar 160")

	for i in range(8):
		GameState.ganhar_moedas(12, "auditoria de IA", "auditoria")
	_ok(GameState.moedas_ganhas_total == 1886,
		"conteudo unico deveria somar 1886 moedas, nao %d" % GameState.moedas_ganhas_total)
	var n := Economy.nota_participacao()
	_ok(is_equal_approx(float(n["nota"]), 40.0),
		"1886 moedas unicas ja deveriam saturar a nota em 40,0")
	_ok(int(n["excedente_moedas"]) == 886, "o excedente deveria ser 886 moedas")

	# 2. Repeticao: o saldo cresce, a nota nao.
	for i in range(20):
		GameState.registrar_minigame("delineamentos", 1, 1, recompensa_minigame)
	_ok(GameState.moedas_ganhas_total == 3286,
		"20 repeticoes deveriam somar 1400 moedas ao total ganho")
	n = Economy.nota_participacao()
	_ok(is_equal_approx(float(n["nota"]), 40.0),
		"repetir minigame nao pode ultrapassar a nota 40,0")
	_ok(int(n["excedente_moedas"]) == 2286,
		"o excedente deveria registrar as moedas acima do teto")
	_ok(GameState.moedas == GameState.MOEDAS_INICIAIS + GameState.moedas_ganhas_total,
		"o saldo deveria refletir todas as moedas ganhas, inclusive as excedentes")

	print("MOEDAS: conteudo unico=%d, teto da nota=%d, saldo apos repeticoes=%d"
		% [1886, MOEDAS_TETO, GameState.moedas])
	print("MOEDAS: %d verificacoes, %d falhas" % [_checks, _falhas])

	GameState.reiniciar_partida()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TESTE))
	get_tree().quit(1 if _falhas > 0 else 0)


func _ler_json(caminho: String) -> Variant:
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		_falhas += 1
		print("  FALHA: nao abriu ", caminho)
		return []
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d == null:
		_falhas += 1
		print("  FALHA: JSON invalido em ", caminho)
		return []
	return d
