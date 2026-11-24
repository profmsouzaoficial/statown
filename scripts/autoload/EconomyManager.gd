extends Node
## Economy - regras auditaveis das BioMoedas.
##
## A HUD mostra o saldo, mas toda moeda que entra ou sai passa por aqui e vira
## uma linha do extrato. Isso e proposital: a nota de participacao depende das
## moedas, entao o aluno (e o professor) precisa conseguir responder "por que
## meu saldo mudou?" sem confiar em um numero solto.
##
## Regras ficam em `data/economia.json` para o docente ajustar sem mexer no
## codigo. O servidor Supabase replica as mesmas regras nas RPCs; o cliente
## nunca deve ser a unica fonte de verdade da nota.

signal transacao_registrada(entrada: Dictionary)

const CAMINHO_CONFIG := "res://data/economia.json"
const LIMITE_EXTRATO := 240

var cfg: Dictionary = {}
var extrato: Array[Dictionary] = []
var _surtos: Dictionary = {}          # vila_id -> snapshot do inicio do surto
var _seq: int = 0
var _ultima_semana_processada: int = -1


func _ready() -> void:
	_carregar_config()
	_ultima_semana_processada = _chave_semana()
	GameState.semana_avancou.connect(_ao_avancar_semana)
	Epidemic.surto_iniciado.connect(_ao_surto_iniciado)
	Epidemic.surto_encerrado.connect(_ao_surto_encerrado)


func _carregar_config() -> void:
	cfg = {
		"moedas_iniciais": GameState.MOEDAS_INICIAIS,
		"penalidade_obitos": {
			"fracao_do_saldo_por_obito": 0.01,
			"teto_fracao_do_saldo_por_semana": 0.25,
			"minimo_por_semana_com_obito": 1,
		},
		"surto_controlado": {
			"base": 20, "por_semana_de_surto": 5,
			"bonus_sem_obitos": 15, "teto": 60,
		},
		"nota_participacao": {
			"moedas_por_ponto": 10, "nota_maxima": 100,
			"base": "moedas_ganhas",
		},
	}
	if not FileAccess.file_exists(CAMINHO_CONFIG):
		return
	var f := FileAccess.open(CAMINHO_CONFIG, FileAccess.READ)
	if f == null:
		return
	var lido = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(lido) != TYPE_DICTIONARY:
		push_warning("economia.json invalido; usando regras padrao")
		return
	for chave in cfg:
		if lido.has(chave) and typeof(lido[chave]) == TYPE_DICTIONARY and typeof(cfg[chave]) == TYPE_DICTIONARY:
			for sub in cfg[chave]:
				if (lido[chave] as Dictionary).has(sub):
					cfg[chave][sub] = lido[chave][sub]
		elif lido.has(chave):
			cfg[chave] = lido[chave]


# ---------------------------------------------------------------------------
# Extrato e transparencia
# ---------------------------------------------------------------------------

## Chamado por GameState depois de alterar o saldo. Nunca altera moedas por
## conta propria: assim existe um unico lugar que mexe no saldo e um unico
## lugar que registra o motivo.
func registrar_transacao(delta: int, motivo: String, categoria: String,
		referencia: String = "", saldo_apos: int = -1) -> Dictionary:
	_seq += 1
	var entrada := {
		"id": _seq,
		"delta": delta,
		"saldo_apos": GameState.moedas if saldo_apos < 0 else saldo_apos,
		"motivo": motivo if motivo != "" else "movimentacao",
		"categoria": categoria,
		"referencia": referencia,
		"semana": GameState.semana,
		"ano": GameState.ano,
		"quando": Time.get_datetime_string_from_system(false, true),
	}
	extrato.push_front(entrada)
	if extrato.size() > LIMITE_EXTRATO:
		extrato.resize(LIMITE_EXTRATO)
	transacao_registrada.emit(entrada)
	return entrada


func ultimas_transacoes(limite: int = 20) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(mini(limite, extrato.size())):
		out.append(extrato[i])
	return out


func total_por_categoria(categoria: String, somente_negativo: bool = false) -> int:
	var total := 0
	for t in extrato:
		if str(t.get("categoria", "")) != categoria:
			continue
		var d := int(t.get("delta", 0))
		if somente_negativo and d >= 0:
			continue
		total += d
	return total


# ---------------------------------------------------------------------------
# Obitos: perda proporcional ao saldo, com teto semanal
# ---------------------------------------------------------------------------

func _ao_avancar_semana(_se: int, _ano: int) -> void:
	if GameState.carregando or GameState.game_over:
		return
	var chave := _chave_semana()
	if chave == _ultima_semana_processada:
		return
	_ultima_semana_processada = chave
	var obitos := int(Epidemic.obitos_semana)
	if obitos > 0:
		aplicar_penalidade_obitos(obitos)


## Aplica a perda por obitos da semana. Retorna quantas moedas foram retiradas.
## Formula: saldo * 1% * obitos, limitada a 25% do saldo na semana e a pelo
## menos 1 moeda quando houve obito. O teto evita que uma semana catastrofica
## apague meses de aprendizado de uma vez.
func aplicar_penalidade_obitos(obitos: int, referencia: String = "") -> int:
	if obitos <= 0 or GameState.game_over:
		return 0
	var saldo := GameState.moedas
	if saldo <= 0:
		GameState.acionar_game_over()
		return 0
	var p: Dictionary = cfg.get("penalidade_obitos", {})
	var fracao := float(p.get("fracao_do_saldo_por_obito", 0.01))
	var teto_fracao := float(p.get("teto_fracao_do_saldo_por_semana", 0.25))
	var minimo := int(p.get("minimo_por_semana_com_obito", 1))
	var bruto := int(round(float(saldo) * fracao * float(obitos)))
	var teto := int(floor(float(saldo) * teto_fracao))
	var perda := clampi(bruto, minimo, maxi(teto, minimo))
	perda = mini(perda, saldo)
	if perda <= 0:
		return 0
	if referencia == "":
		referencia = "SE %d/%d" % [GameState.semana, GameState.ano]
	var motivo := ("Obitos: %d na %s. Perda de %d B (%.1f%% do saldo por obito, teto de %.0f%% na semana)."
		% [obitos, referencia, perda, fracao * 100.0, teto_fracao * 100.0])
	var retirado := GameState.descontar_moedas(perda, motivo, "obito", referencia)
	if retirado > 0:
		GameState.notificar("-%d BioMoedas por %d obito(s) na %s." % [retirado, obitos, referencia],
			"erro")
	return retirado


# ---------------------------------------------------------------------------
# Surtos: recompensa por conter e evitar obitos
# ---------------------------------------------------------------------------

func _ao_surto_iniciado(vila_id: int, casos: int) -> void:
	_surtos[vila_id] = {
		"ano": GameState.ano,
		"semana": GameState.semana,
		"obitos": Epidemic.obitos(vila_id),
		"casos_inicio": casos,
		"semanas": 0,
	}


func _ao_surto_encerrado(vila_id: int) -> void:
	var r: Dictionary = _surtos.get(vila_id, {})
	var semanas := 1
	if not r.is_empty():
		semanas = maxi(1, _chave_semana() - _chave_abs(int(r.get("ano", 1)), int(r.get("semana", 1))) + 1)
	var obitos_inicio := int(r.get("obitos", 0))
	var obitos_surto := maxi(0, Epidemic.obitos(vila_id) - obitos_inicio)
	var s: Dictionary = cfg.get("surto_controlado", {})
	var base := int(s.get("base", 20))
	var por_semana := int(s.get("por_semana_de_surto", 5))
	var bonus := int(s.get("bonus_sem_obitos", 15)) if obitos_surto == 0 else 0
	var teto := int(s.get("teto", 60))
	var recompensa := mini(teto, base + por_semana * mini(semanas, 6) + bonus)
	var nome := str(Vilas.get_vila(vila_id).get("nome", "vila"))
	var detalhe := ("Surto controlado em %s: +%d B (base %d + %d por semana x %d + bonus %d)."
		% [nome, recompensa, base, por_semana, mini(semanas, 6), bonus])
	if obitos_surto > 0:
		detalhe += " O surto teve %d obito(s); o bonus de zero obitos nao foi pago." % obitos_surto
	GameState.ganhar_moedas(recompensa, detalhe, "surto", str(vila_id))
	_surtos.erase(vila_id)


# ---------------------------------------------------------------------------
# Nota de participacao
# ---------------------------------------------------------------------------

## Converte a producao do semestre em nota. A base padrao e o total de moedas
## GANHAS (nao o saldo): gastar em intervencoes nao pode punir o aluno duas
## vezes. O teto e aplicado depois da divisao, exatamente como pedido:
## 1390 moedas -> 139 pontos -> 100 (teto), e nao 139.
func nota_participacao() -> Dictionary:
	var n: Dictionary = cfg.get("nota_participacao", {})
	var por_ponto := maxi(1, int(n.get("moedas_por_ponto", 10)))
	var maxima := maxi(1, int(n.get("nota_maxima", 100)))
	var base_tipo := str(n.get("base", "moedas_ganhas"))
	var base := GameState.moedas_ganhas_total if base_tipo == "moedas_ganhas" else GameState.moedas
	var pontos_brutos := int(floor(float(base) / float(por_ponto)))
	var nota := mini(pontos_brutos, maxima)
	return {
		"base": base,
		"base_tipo": base_tipo,
		"moedas_por_ponto": por_ponto,
		"pontos_brutos": pontos_brutos,
		"nota": nota,
		"nota_maxima": maxima,
		"excedente": maxi(0, pontos_brutos - maxima),
	}


func texto_regra_nota() -> String:
	var n := nota_participacao()
	return "nota = min(%d, floor(%d / %d)) = %d" % [
		int(n["nota_maxima"]), int(n["base"]), int(n["moedas_por_ponto"]), int(n["nota"])]


# ---------------------------------------------------------------------------
# Serializacao / reinicio
# ---------------------------------------------------------------------------

func serializar() -> Dictionary:
	var surtos := {}
	for k in _surtos:
		surtos[str(k)] = _surtos[k].duplicate(true)
	return {
		"seq": _seq,
		"extrato": extrato.duplicate(true),
		"surtos": surtos,
	}


func deserializar(d: Dictionary) -> void:
	_seq = int(d.get("seq", 0))
	extrato.clear()
	for item in d.get("extrato", []):
		if typeof(item) == TYPE_DICTIONARY:
			extrato.append(item)
	if extrato.size() > LIMITE_EXTRATO:
		extrato.resize(LIMITE_EXTRATO)
	_surtos.clear()
	var ss: Dictionary = d.get("surtos", {})
	for k in ss:
		_surtos[int(k)] = ss[k]
	reiniciar_controle()


func reiniciar_controle() -> void:
	_ultima_semana_processada = _chave_semana()


func reiniciar_partida(manter_pontuacao: bool = false) -> void:
	_surtos.clear()
	if not manter_pontuacao:
		extrato.clear()
		_seq = 0
	reiniciar_controle()


# ---------------------------------------------------------------------------
# Utilitarios
# ---------------------------------------------------------------------------

func _chave_semana() -> int:
	return _chave_abs(GameState.ano, GameState.semana)


func _chave_abs(ano: int, semana: int) -> int:
	return ano * GameState.SE_POR_ANO + semana
