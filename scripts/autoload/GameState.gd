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

const SEGUNDOS_POR_SE := 6.0
const MOEDAS_INICIAIS := 150
const SE_POR_ANO := 52
const VERSAO_SAVE := 4   # v4: obitos naturais por vila + obitos da doenca separados

# --- Relogio ---------------------------------------------------------------
var semana: int = 1
var ano: int = 1
var velocidade: float = 1.0
var pausado: bool = false
var _acumulado: float = 0.0
var tempo_jogo: float = 0.0

# --- Economia --------------------------------------------------------------
var moedas: int = MOEDAS_INICIAIS
var moedas_ganhas_total: int = 0
var moedas_gastas_total: int = 0

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
	if pausado or velocidade <= 0.0:
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
	semana += 1
	if semana > SE_POR_ANO:
		semana = 1
		ano += 1
	Epidemic.avancar_semana()
	Population.avancar_semana()
	semana_avancou.emit(semana, ano)
	_checar_marcos()


## Forca o avanco de varias semanas (usado por "avancar rapido" e testes).
func avancar_semanas(n: int) -> void:
	for _i in range(n):
		avancar_semana()


# --- Economia --------------------------------------------------------------

func ganhar_moedas(v: int, motivo: String = "") -> void:
	if v <= 0:
		return
	moedas += v
	moedas_ganhas_total += v
	moedas_alteradas.emit(moedas, v)
	if motivo != "":
		notificar("+%d BioMoedas - %s" % [v, motivo], "sucesso")


func gastar_moedas(v: int) -> bool:
	if v > moedas:
		notificar("BioMoedas insuficientes: faltam %d." % (v - moedas), "erro")
		return false
	moedas -= v
	moedas_gastas_total += v
	moedas_alteradas.emit(moedas, -v)
	return true


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
	velocidade = v
	pausado = v <= 0.0
	velocidade_alterada.emit(velocidade)
	pausa_alterada.emit(pausado)


func alternar_pausa() -> void:
	pausado = not pausado
	velocidade = 0.0 if pausado else (velocidade if velocidade > 0.0 else 1.0)
	velocidade_alterada.emit(velocidade)
	pausa_alterada.emit(pausado)


func notificar(texto: String, tipo: String = "info") -> void:
	notificacao.emit(texto, tipo)


func registrar_minigame(id: String, acertos: int, total: int, moedas_recebidas: int) -> void:
	var reg: Dictionary = minigames_concluidos.get(id, {"vezes": 0, "melhor": 0.0, "moedas": 0})
	reg["vezes"] = int(reg["vezes"]) + 1
	reg["moedas"] = int(reg["moedas"]) + moedas_recebidas
	if total > 0:
		reg["melhor"] = maxf(float(reg["melhor"]), float(acertos) / float(total))
	minigames_concluidos[id] = reg
	ganhar_moedas(moedas_recebidas, "desafio concluido")
	_salvar()


func registrar_artigo(id: String) -> void:
	if not artigos_lidos.has(id):
		artigos_lidos.append(id)
		ganhar_moedas(20, "artigo lido")


func conquistar(id: String, titulo: String) -> void:
	if _conquistas.has(id):
		return
	_conquistas[id] = true
	conquista_desbloqueada.emit(id, titulo)
	notificar("Conquista: %s" % titulo, "conquista")


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
	var d := {
		"versao": VERSAO_SAVE,
		"semana": semana, "ano": ano, "moedas": moedas,
		"doenca": doenca_id, "moedas_ganhas": moedas_ganhas_total,
		"moedas_gastas": moedas_gastas_total,
		"minigames": minigames_concluidos, "artigos": artigos_lidos,
		"auditorias_ia": auditorias_ia, "amostras": amostras_coletadas,
		"conquistas": _conquistas,
		"config": {"fonte_grande": fonte_grande, "dicas": dicas_ativas,
			"auto_pausa": auto_pausa_lab, "rotulos": mostrar_rotulos,
			"vol_musica": volume_musica, "vol_ambiente": volume_ambiente,
			"vol_sfx": volume_sfx, "mudo": mudo},
		"vilas": Vilas.serializar(),
		"epidemia": Epidemic.serializar(),
		"populacao": Population.serializar(),
	}
	var f := FileAccess.open("user://statown_save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()


func carregar_partida() -> bool:
	if not FileAccess.file_exists("user://statown_save.json"):
		return false
	var f := FileAccess.open("user://statown_save.json", FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	if int(d.get("versao", 0)) != VERSAO_SAVE:
		return false
	semana = int(d.get("semana", 1))
	ano = int(d.get("ano", 1))
	moedas = int(d.get("moedas", MOEDAS_INICIAIS))
	doenca_id = str(d.get("doenca", "arbovirose"))
	moedas_ganhas_total = int(d.get("moedas_ganhas", 0))
	moedas_gastas_total = int(d.get("moedas_gastas", 0))
	minigames_concluidos = d.get("minigames", {})
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
	moedas_alteradas.emit(moedas, 0)
	doenca_alterada.emit(doenca_id)
	semana_avancou.emit(semana, ano)
	return true


func reiniciar_partida() -> void:
	semana = 1
	ano = 1
	moedas = MOEDAS_INICIAIS
	moedas_ganhas_total = 0
	moedas_gastas_total = 0
	minigames_concluidos.clear()
	artigos_lidos.clear()
	auditorias_ia = 0
	amostras_coletadas = 0
	_conquistas.clear()
	_acumulado = 0.0
	tempo_jogo = 0.0
	Vilas.reiniciar()
	Population.reiniciar()
	Epidemic.reiniciar()
	partida_reiniciada.emit()
	moedas_alteradas.emit(moedas, 0)
	semana_avancou.emit(semana, ano)
