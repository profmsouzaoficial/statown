extends Node
## GameState - estado global da partida, relogio epidemiologico e economia.
##
## Autoload. Concentra tudo o que precisa sobreviver a troca de telas:
## semana epidemiologica, BioMoedas, doenca ativa, configuracoes de
## acessibilidade e o registro de conquistas. Emite sinais que a HUD e o
## mapa escutam, evitando acoplamento direto entre paineis.

signal semana_avancou(se: int, ano: int)
signal moedas_alteradas(valor: int, delta: int)
signal velocidade_alterada(v: float)
signal pausa_alterada(pausada: bool)
signal doenca_alterada(id: String)
signal notificacao(texto: String, tipo: String)
signal partida_reiniciada()
signal conquista_desbloqueada(id: String, titulo: String)
signal game_over_acionado()

const SEGUNDOS_POR_SE := 6.0
const MOEDAS_INICIAIS := 150
const SE_POR_ANO := 52
const VERSAO_SAVE := 6   # v5: extrato, game over e desafios do LAB

# --- Relogio ---------------------------------------------------------------
var semana: int = 1
var ano: int = 1
var velocidade: float = 1.0
var pausado: bool = false
var _pausa_foco_ativa: bool = false
var _pausado_antes_foco: bool = false
var _velocidade_antes_foco: float = 1.0
var _acumulado: float = 0.0
var tempo_jogo: float = 0.0

# --- Economia --------------------------------------------------------------
var moedas: int = MOEDAS_INICIAIS
var moedas_ganhas_total: int = 0     # producao do semestre; base da nota
var moedas_gastas_total: int = 0
var game_over: bool = false
var carregando: bool = false
var desafios_lab: Dictionary = {}     # contexto -> registro do desafio
var caminho_save: String = "user://statown_save.json"   # trocado por conta

# --- Cenario ---------------------------------------------------------------
var doenca_id: String = "arbovirose"
var dificuldade: String = "normal"

# --- Progresso -------------------------------------------------------------
var minigames_concluidos: Dictionary = {}     # id -> {vezes, melhor, moedas}
var artigos_lidos: Array[String] = []
var auditorias_ia: int = 0
var amostras_coletadas: int = 0

# --- Configuracoes ---------------------------------------------------------
var fonte_grande: bool = false
var dicas_ativas: bool = true
var auto_pausa_lab: bool = true
var mostrar_rotulos: bool = true
var volume_musica: float = 0.55
var volume_ambiente: float = 0.45
var volume_sfx: float = 0.7
var mudo: bool = false
var overlay_ativo: String = "prevalencia"   # prevalencia | incidencia | vacinacao | saneamento | nenhum

# --- Controle de UI --------------------------------------------------------
var modal_aberto: bool = false
var _conquistas: Dictionary = {}

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 20261104
	set_process(true)


func _process(delta: float) -> void:
	if game_over or pausado or _pausa_foco_ativa or velocidade <= 0.0:
		return
	if modal_aberto and auto_pausa_lab:
		return
	tempo_jogo += delta
	_acumulado += delta * velocidade
	var passo := SEGUNDOS_POR_SE
	var guard := 0
	while _acumulado >= passo and guard < 16:
		_acumulado -= passo
		guard += 1
		avancar_semana()


func avancar_semana() -> void:
	if game_over:
		return
	semana += 1
	if semana > SE_POR_ANO:
		semana = 1
		ano += 1
	Epidemic.avancar_semana()
	Population.avancar_semana()
	semana_avancou.emit(semana, ano)
	_checar_marcos()
	_salvar()


## Forca o avanco de varias semanas (usado por "avancar rapido" e testes).
func avancar_semanas(n: int) -> void:
	for _i in range(n):
		avancar_semana()


## Semestre letivo real (nao confundir com o ano epidemiologico do jogo).
## Serve para agrupar a nota no SIGA; o professor pode sobrescrever no painel.
func semestre_atual() -> String:
	var d := Time.get_date_dict_from_system()
	return "%d/%d" % [int(d.get("year", 0)), 2 if int(d.get("month", 1)) >= 7 else 1]


# --- Economia --------------------------------------------------------------

## Toda entrada de moeda passa aqui. `categoria` separa minigame, artigo,
## desafio do LAB e surto no extrato; `referencia` guarda o id do desafio ou
## da vila para auditoria.
func ganhar_moedas(v: int, motivo: String = "", categoria: String = "ganho",
		referencia: String = "") -> void:
	if v <= 0 or game_over:
		return
	moedas += v
	moedas_ganhas_total += v
	moedas_alteradas.emit(moedas, v)
	Economy.registrar_transacao(v, motivo if motivo != "" else "ganho de BioMoedas",
		categoria, referencia, moedas)
	if motivo != "":
		notificar("+%d BioMoedas - %s" % [v, motivo], "sucesso")
	# Grava o disco imediatamente: fechar a aba logo apos um ganho nao pode
	# depender do proximo avanco de semana nem do upload assincrono.
	_salvar()


## Compra de uma intervencao. O motivo deve ser explicito para o extrato.
func gastar_moedas(v: int, motivo: String = "", categoria: String = "intervencao",
		referencia: String = "") -> bool:
	if game_over:
		notificar("A partida terminou. Reinicie para voltar a jogar.", "erro")
		return false
	if v <= 0:
		return true
	if v > moedas:
		notificar("BioMoedas insuficientes: faltam %d." % (v - moedas), "erro")
		return false
	moedas -= v
	moedas_gastas_total += v
	moedas_alteradas.emit(moedas, -v)
	Economy.registrar_transacao(-v, motivo if motivo != "" else "gasto de BioMoedas",
		categoria, referencia, moedas)
	if motivo != "":
		notificar("-%d BioMoedas - %s" % [v, motivo], "info")
	if moedas <= 0:
		acionar_game_over()
	_salvar()
	return true


## Perda que nao e compra (obitos, evento). Retorna o valor efetivamente
## descontado, que nunca ultrapassa o saldo disponivel.
func descontar_moedas(v: int, motivo: String, categoria: String = "obito",
		referencia: String = "") -> int:
	if v <= 0 or game_over:
		return 0
	var real := mini(v, maxi(moedas, 0))
	if real <= 0:
		return 0
	moedas -= real
	moedas_alteradas.emit(moedas, -real)
	Economy.registrar_transacao(-real, motivo if motivo != "" else "perda de BioMoedas",
		categoria, referencia, moedas)
	if moedas <= 0:
		acionar_game_over()
	_salvar()
	return real


## Chame quando o saldo chega a zero. Idempotente de proposito: varias
## transacoes podem tentar acionar o fim da partida no mesmo frame.
func acionar_game_over() -> void:
	if game_over:
		return
	game_over = true
	pausado = true
	velocidade = 0.0
	pausa_alterada.emit(true)
	velocidade_alterada.emit(0.0)
	notificar("GAME OVER: suas BioMoedas chegaram a zero. Reinicie a partida.", "erro")
	game_over_acionado.emit()


# --- Cenario ---------------------------------------------------------------

func definir_doenca(id: String) -> void:
	if id == doenca_id:
		return
	doenca_id = id
	doenca_alterada.emit(id)
	notificar("Cenario ativo: %s" % Epidemic.nome_doenca(id), "info")


func info_doenca() -> Dictionary:
	return Epidemic.info_doenca(doenca_id)


# --- Controles -------------------------------------------------------------

func definir_velocidade(v: float) -> void:
	if game_over:
		return
	velocidade = v
	pausado = v <= 0.0
	velocidade_alterada.emit(velocidade)
	pausa_alterada.emit(pausado)


func alternar_pausa() -> void:
	if game_over:
		return
	pausado = not pausado
	_pausado_antes_foco = pausado
	velocidade = 0.0 if pausado else (velocidade if velocidade > 0.0 else 1.0)
	velocidade_alterada.emit(velocidade)
	pausa_alterada.emit(pausado)


## Pausa obrigatoria quando a janela/aba perde foco. Guarda a velocidade
## anterior e o estado manual para que retomar nao "despause" quem ja estava
## pausado de proposito.
func pausar_por_foco() -> void:
	if _pausa_foco_ativa:
		return
	_pausa_foco_ativa = true
	_pausado_antes_foco = pausado
	_velocidade_antes_foco = velocidade
	pausado = true
	velocidade = 0.0
	pausa_alterada.emit(true)
	_salvar()


## Volta do foco. Se o jogador ja estava pausado antes, continua pausado.
func retomar_por_foco() -> void:
	if not _pausa_foco_ativa:
		return
	_pausa_foco_ativa = false
	if not _pausado_antes_foco:
		pausado = false
		velocidade = _velocidade_antes_foco if _velocidade_antes_foco > 0.0 else 1.0
	pausa_alterada.emit(pausado)
	velocidade_alterada.emit(velocidade)


func pausado_por_foco() -> bool:
	return _pausa_foco_ativa


func notificar(texto: String, tipo: String = "info") -> void:
	notificacao.emit(texto, tipo)


func registrar_minigame(id: String, acertos: int, total: int, moedas_recebidas: int) -> void:
	var reg: Dictionary = minigames_concluidos.get(id, {"vezes": 0, "melhor": 0.0, "moedas": 0})
	reg["vezes"] = int(reg["vezes"]) + 1
	reg["moedas"] = int(reg["moedas"]) + moedas_recebidas
	if total > 0:
		reg["melhor"] = maxf(float(reg["melhor"]), float(acertos) / float(total))
	minigames_concluidos[id] = reg
	ganhar_moedas(moedas_recebidas, "desafio concluido", "minigame", id)
	_salvar()


func registrar_artigo(id: String) -> void:
	if not artigos_lidos.has(id):
		artigos_lidos.append(id)
		ganhar_moedas(20, "artigo lido", "artigo", id)


func conquistar(id: String, titulo: String) -> void:
	if _conquistas.has(id):
		return
	_conquistas[id] = true
	conquista_desbloqueada.emit(id, titulo)
	notificar("Conquista: %s" % titulo, "conquista")
	_salvar()


func conquistas() -> Dictionary:
	return _conquistas.duplicate()


func _checar_marcos() -> void:
	var stats := Epidemic.estatisticas_globais()
	if int(stats["obitos_total"]) == 0 and semana >= 12:
		conquistar("12_semanas_sem_obito", "12 semanas sem obito")
	if int(stats["recuperados_total"]) >= 500:
		conquistar("500_recuperados", "500 recuperados")
	if minigames_concluidos.size() >= 5:
		conquistar("5_desafios", "5 desafios concluidos")
	if amostras_coletadas >= 10:
		conquistar("amostrador", "10 amostras coletadas")
	if artigos_lidos.size() >= 3:
		conquistar("leitor_critico", "3 artigos auditados")


# --- Escore global ---------------------------------------------------------

## Indice de Saude do Vale (0-100) - sintese usada no relatorio SIGA.
func escore_global() -> Dictionary:
	var s := Epidemic.estatisticas_globais()
	var prev: float = float(s["prevalencia"])          # 0..1
	var obitos: int = int(s["obitos_total"])
	var pop: int = maxi(int(s["populacao_total"]), 1)
	var cobertura: float = Vilas.cobertura_media()
	var sane: float = Vilas.saneamento_medio()
	var mortalidade := float(obitos) / float(pop) * 1000.0
	var indice := 100.0
	indice -= clampf(prev * 100.0 * 1.6, 0.0, 35.0)
	indice -= clampf(mortalidade * 9.0, 0.0, 30.0)
	indice += cobertura * 12.0
	indice += sane * 10.0
	indice = clampf(indice, 0.0, 100.0)
	return {
		"indice": indice,
		"prevalencia": prev,
		"mortalidade_1000": mortalidade,
		"cobertura_vacinal": cobertura,
		"saneamento": sane,
		"obitos": obitos,
		"populacao": pop,
		"semana": semana,
		"ano": ano,
	}


# --- Persistencia ----------------------------------------------------------

func salvar_partida() -> void:
	_salvar()


func _salvar() -> void:
	var d := serializar_partida()
	var f := FileAccess.open(caminho_save, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()


## Separado de _salvar para o servidor conseguir montar o mesmo payload sem
## depender do caminho local do save.
func serializar_partida() -> Dictionary:
	return {
		"versao": VERSAO_SAVE,
		"semestre": semestre_atual(),
		"semana": semana, "ano": ano, "moedas": moedas,
		"doenca": doenca_id, "moedas_ganhas": moedas_ganhas_total,
		"moedas_gastas": moedas_gastas_total,
		"game_over": game_over,
		"minigames": minigames_concluidos, "artigos": artigos_lidos,
		"auditorias_ia": auditorias_ia, "amostras": amostras_coletadas,
		"conquistas": _conquistas,
		"desafios_lab": desafios_lab,
		"economia": Economy.serializar(),
		"config": {"fonte_grande": fonte_grande, "dicas": dicas_ativas,
			"auto_pausa": auto_pausa_lab, "rotulos": mostrar_rotulos,
			"vol_musica": volume_musica, "vol_ambiente": volume_ambiente,
			"vol_sfx": volume_sfx, "mudo": mudo},
		"vilas": Vilas.serializar(),
		"epidemia": Epidemic.serializar(),
		"populacao": Population.serializar(),
	}


## Compara o progresso em memoria com um save vindo da nuvem. `moedas_ganhas`
## e monotonico dentro do semestre (gastar ou perder saldo nao o reduz), entao
## ele funciona como relogio de progresso. A semana/ano desempata quando as
## duas fotos tem a mesma producao. Assim um ganho local que ainda nao subiu
## nao e apagado pelo download antigo ao reabrir o jogo.
func progresso_local_maior(save_remoto: Dictionary) -> bool:
	var remoto_ganhas := int(save_remoto.get("moedas_ganhas", 0))
	if moedas_ganhas_total != remoto_ganhas:
		return moedas_ganhas_total > remoto_ganhas
	var local_ord := ano * SE_POR_ANO + semana
	var remoto_ord := int(save_remoto.get("ano", 1)) * SE_POR_ANO \
		+ int(save_remoto.get("semana", 1))
	return local_ord > remoto_ord


func carregar_partida() -> bool:
	if not FileAccess.file_exists(caminho_save):
		return false
	var f := FileAccess.open(caminho_save, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	# Semestre novo = participacao nova. O save antigo fica para tras (na
	# nuvem ele continua na linha do semestre anterior).
	if d.has("semestre") and str(d.get("semestre", "")) != semestre_atual():
		reiniciar_partida(false)
		return true
	return aplicar_save(d)


## Aplica um save vindo do arquivo local ou do Supabase. Separar essa funcao
## permite que a nuvem use exatamente o mesmo caminho de validacao do disco.
func aplicar_save(d: Dictionary) -> bool:
	var versao := int(d.get("versao", 0))
	if versao < 4 or versao > VERSAO_SAVE:
		return false
	if d.has("semestre") and str(d.get("semestre", "")) != semestre_atual():
		return false
	carregando = true
	_pausa_foco_ativa = false
	semana = int(d.get("semana", 1))
	ano = int(d.get("ano", 1))
	moedas = int(d.get("moedas", MOEDAS_INICIAIS))
	doenca_id = str(d.get("doenca", "arbovirose"))
	moedas_ganhas_total = int(d.get("moedas_ganhas", 0))
	moedas_gastas_total = int(d.get("moedas_gastas", 0))
	game_over = bool(d.get("game_over", false))
	minigames_concluidos = d.get("minigames", {})
	desafios_lab = d.get("desafios_lab", {})
	var arts = d.get("artigos", [])
	artigos_lidos.clear()
	for a in arts:
		artigos_lidos.append(str(a))
	auditorias_ia = int(d.get("auditorias_ia", 0))
	amostras_coletadas = int(d.get("amostras", 0))
	_conquistas = d.get("conquistas", {})
	var cfg: Dictionary = d.get("config", {})
	fonte_grande = bool(cfg.get("fonte_grande", false))
	dicas_ativas = bool(cfg.get("dicas", true))
	auto_pausa_lab = bool(cfg.get("auto_pausa", true))
	mostrar_rotulos = bool(cfg.get("rotulos", true))
	volume_musica = clampf(float(cfg.get("vol_musica", 0.55)), 0.0, 1.0)
	volume_ambiente = clampf(float(cfg.get("vol_ambiente", 0.45)), 0.0, 1.0)
	volume_sfx = clampf(float(cfg.get("vol_sfx", 0.7)), 0.0, 1.0)
	mudo = bool(cfg.get("mudo", false))
	Vilas.deserializar(d.get("vilas", {}))
	Epidemic.deserializar(d.get("epidemia", {}))
	Population.deserializar(d.get("populacao", {}))
	if versao >= 5:
		Economy.deserializar(d.get("economia", {}))
	else:
		Economy.reiniciar_controle()
	pausado = game_over
	velocidade = 0.0 if game_over else 1.0
	moedas_alteradas.emit(moedas, 0)
	doenca_alterada.emit(doenca_id)
	pausa_alterada.emit(pausado)
	velocidade_alterada.emit(velocidade)
	semana_avancou.emit(semana, ano)
	carregando = false
	if game_over:
		game_over_acionado.emit()
	elif moedas <= 0:
		acionar_game_over()
	return true


## `manter_pontuacao` e usado no game over: a partida (semana, mapa, saldo)
## recomeca, mas a producao do semestre e o extrato continuam valendo para a
## nota. O menu "reiniciar tudo" usa o padrao false.
func reiniciar_partida(manter_pontuacao: bool = false) -> void:
	semana = 1
	ano = 1
	moedas = MOEDAS_INICIAIS
	if not manter_pontuacao:
		moedas_ganhas_total = 0
		moedas_gastas_total = 0
		desafios_lab.clear()
	minigames_concluidos.clear()
	artigos_lidos.clear()
	auditorias_ia = 0
	amostras_coletadas = 0
	_conquistas.clear()
	_acumulado = 0.0
	tempo_jogo = 0.0
	game_over = false
	pausado = false
	_pausa_foco_ativa = false
	_pausado_antes_foco = false
	velocidade = 1.0
	Vilas.reiniciar()
	Population.reiniciar()
	Epidemic.reiniciar()
	Economy.reiniciar_partida(manter_pontuacao)
	partida_reiniciada.emit()
	moedas_alteradas.emit(moedas, 0)
	pausa_alterada.emit(false)
	velocidade_alterada.emit(velocidade)
	semana_avancou.emit(semana, ano)
	_salvar()
