extends Node
## AudioManager — trilha sonora hierarquica do StaTown.
##
## Camadas (da mais geral para a mais especifica):
##   1. TEMA      musica de fundo: mapa -> zona da vila -> minigame
##   2. AMBIENCIA loop diegetico (freesound): vento no mapa, mercado/rio/mata na vila
##   3. STING     assinatura de 4 s ao entrar numa vila (motivo unico + acento)
##   4. SFX       interface, semana, moeda, alerta, descoberta
##
## A musica e sintetizada toda em La menor (tools/audio/render_audio.py), entao
## qualquer combinacao de tema + sting + sfx e harmonica. Os sons organicos sao
## CC0 do freesound.org (ver docs/CREDITOS_AUDIO.md).

const DIR := "res://assets/audio/"
const BUS_MUS := "Music"
const BUS_AMB := "Ambient"
const BUS_SFX := "SFX"
const SILENCIO := -60.0
const POOL_SFX := 8

var _cfg: Dictionary = {}
var _cache: Dictionary = {}
var _mus: Array[AudioStreamPlayer] = []
var _mus_idx := 0
var _tema := ""
var _amb: Array[AudioStreamPlayer] = []
var _amb_idx := 0
var _amb_base: AudioStreamPlayer
var _amb_atual := ""
var _base_ligada := false
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_idx := 0
var _tw_mus: Tween
var _tw_amb: Tween
var _duck_db := 0.0
var _vila := 0
var _ultimo_sting := 0.0
var _sting_vila := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cfg = _ler_json("res://data/audio.json")
	_criar_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_MUS
		p.volume_db = SILENCIO
		add_child(p)
		_mus.append(p)
		var a := AudioStreamPlayer.new()
		a.bus = BUS_AMB
		a.volume_db = SILENCIO
		add_child(a)
		_amb.append(a)
	_amb_base = AudioStreamPlayer.new()
	_amb_base.bus = BUS_AMB
	_amb_base.volume_db = SILENCIO
	add_child(_amb_base)
	for i in POOL_SFX:
		var s := AudioStreamPlayer.new()
		s.bus = BUS_SFX
		add_child(s)
		_sfx.append(s)
	_aplicar_volumes()


# ---------------------------------------------------------------- infraestrutura

func _ler_json(caminho: String) -> Dictionary:
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		push_warning("AudioManager: nao abriu " + caminho)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _criar_buses() -> void:
	for nome in [BUS_MUS, BUS_AMB, BUS_SFX]:
		if AudioServer.get_bus_index(nome) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, nome)
			AudioServer.set_bus_send(idx, "Master")


func _bus(nome: String) -> int:
	return maxi(0, AudioServer.get_bus_index(nome))


func _stream(caminho: String, loop: bool) -> AudioStream:
	if _cache.has(caminho):
		return _cache[caminho]
	if not ResourceLoader.exists(caminho):
		push_warning("AudioManager: arquivo ausente " + caminho)
		return null
	var s := load(caminho) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	_cache[caminho] = s
	return s


func _db_linear(v: float) -> float:
	if v <= 0.001:
		return SILENCIO
	return linear_to_db(clampf(v, 0.0, 1.0))


func _aplicar_volumes() -> void:
	var mu := _db_linear(GameState.volume_musica) + _duck_db
	AudioServer.set_bus_volume_db(_bus(BUS_MUS), mu)
	AudioServer.set_bus_volume_db(_bus(BUS_AMB), _db_linear(GameState.volume_ambiente) + _duck_db * 0.5)
	AudioServer.set_bus_volume_db(_bus(BUS_SFX), _db_linear(GameState.volume_sfx))
	for nome in [BUS_MUS, BUS_AMB, BUS_SFX]:
		AudioServer.set_bus_mute(_bus(nome), GameState.mudo)


func aplicar_volumes() -> void:
	_aplicar_volumes()


# ---------------------------------------------------------------- camada 1: tema

func tocar_tema(id: String, fade: float = 1.8) -> void:
	if id == _tema:
		return
	var s := _stream(DIR + "mus/" + id + ".ogg", true)
	if s == null:
		return
	_tema = id
	var novo := _mus[_mus_idx ^ 1]
	var velho := _mus[_mus_idx]
	_mus_idx ^= 1
	novo.stream = s
	novo.volume_db = SILENCIO
	novo.play()
	if _tw_mus != null and _tw_mus.is_valid():
		_tw_mus.kill()
	_tw_mus = create_tween()
	_tw_mus.set_parallel(true)
	_tw_mus.tween_property(novo, "volume_db", 0.0, fade)
	_tw_mus.tween_property(velho, "volume_db", SILENCIO, fade * 0.8)
	_tw_mus.chain().tween_callback(velho.stop)


func tema_atual() -> String:
	return _tema


func parar_tema(fade: float = 1.2) -> void:
	_tema = ""
	if _tw_mus != null and _tw_mus.is_valid():
		_tw_mus.kill()
	_tw_mus = create_tween()
	_tw_mus.set_parallel(true)
	for p in _mus:
		_tw_mus.tween_property(p, "volume_db", SILENCIO, fade)
	_tw_mus.chain().tween_callback(_parar_musicas)


func _parar_musicas() -> void:
	for p in _mus:
		p.stop()


# ---------------------------------------------------------- camada 2: ambiencia

func tocar_ambiente_base(id: String = "amb_parque_urbano", fade: float = 3.0) -> void:
	if _base_ligada:
		return
	var s := _stream(DIR + "amb/" + id + ".ogg", true)
	if s == null:
		return
	_base_ligada = true
	_amb_base.stream = s
	_amb_base.volume_db = SILENCIO
	_amb_base.play()
	var tw := create_tween()
	tw.tween_property(_amb_base, "volume_db", -3.0, fade)


func tocar_ambiente(id: String, fade: float = 2.4) -> void:
	if id == _amb_atual:
		return
	_amb_atual = id
	if _tw_amb != null and _tw_amb.is_valid():
		_tw_amb.kill()
	if id == "":
		_tw_amb = create_tween()
		_tw_amb.set_parallel(true)
		for p in _amb:
			_tw_amb.tween_property(p, "volume_db", SILENCIO, fade)
		_tw_amb.chain().tween_callback(_parar_ambientes)
		return
	var s := _stream(DIR + "amb/" + id + ".ogg", true)
	if s == null:
		return
	# Nivel proprio por arquivo: os loops vem de gravacoes diferentes e sem esse
	# ajuste o de passaros ficava 6 dB acima da musica (medido em LUFS).
	var alvo := float((_cfg.get("ambiente_ganho_db", {}) as Dictionary).get(id, 0.0))
	var novo := _amb[_amb_idx ^ 1]
	var velho := _amb[_amb_idx]
	_amb_idx ^= 1
	novo.stream = s
	novo.volume_db = SILENCIO
	novo.play()
	if _tw_amb != null and _tw_amb.is_valid():
		_tw_amb.kill()
	_tw_amb = create_tween()
	_tw_amb.set_parallel(true)
	_tw_amb.tween_property(novo, "volume_db", alvo, fade)
	_tw_amb.tween_property(velho, "volume_db", SILENCIO, fade)
	_tw_amb.chain().tween_callback(velho.stop)


func _parar_ambientes() -> void:
	for p in _amb:
		p.stop()


func ambiente_atual() -> String:
	return _amb_atual


# ------------------------------------------------------------- camada 3: vila

func tocar_vila(vila_id: int) -> void:
	var mesma := vila_id == _vila
	_vila = vila_id
	var conf = _cfg.get("vilas", {}).get(str(vila_id), {})
	var zona := str(conf.get("zona", "urbana"))
	var amb := str(conf.get("ambiente", "amb_parque_urbano"))
	tocar_tema("zona_" + zona, 2.2)
	tocar_ambiente(amb, 2.4)
	# Sem esta guarda, cada clique/zoom na mesma vila dispara outro sting de
	# 4,2 s; em sequencia eles se sobrepoem e parecem um loop travado.
	if not mesma:
		tocar_sting(vila_id)


func tocar_sting(vila_id: int) -> void:
	var agora := Time.get_ticks_msec() / 1000.0
	if agora - _ultimo_sting < 3.0:
		return
	if vila_id == _sting_vila and agora - _ultimo_sting < 10.0:
		return
	_ultimo_sting = agora
	_sting_vila = vila_id
	var caminho := DIR + "vila/vila_%02d.ogg" % vila_id
	var s := _stream(caminho, false)
	if s != null:
		_sfx_tocar(s, -3.0)


func vila_atual() -> int:
	return _vila


func modo_mapa() -> void:
	_vila = 0
	tocar_tema("mapa", 2.6)
	tocar_ambiente("", 2.4)


## Volta ao tema da exploracao depois de fechar um painel, sem repetir o sting.
func restaurar_exploracao(vila_id: int) -> void:
	if vila_id <= 0:
		modo_mapa()
		return
	var conf = _cfg.get("vilas", {}).get(str(vila_id), {})
	_vila = vila_id
	tocar_tema("zona_" + str(conf.get("zona", "urbana")), 2.0)
	tocar_ambiente(str(conf.get("ambiente", "amb_parque_urbano")), 2.0)


# ---------------------------------------------------------------- camada 4: sfx

func _sfx_tocar(s: AudioStream, db: float = 0.0, pitch: float = 1.0) -> void:
	if s == null:
		return
	# Prefere um player livre: o round-robin puro cortava o som anterior no
	# meio quando havia varios cliques juntos, o que soa como "travar".
	var p: AudioStreamPlayer = null
	for cand in _sfx:
		if not cand.playing:
			p = cand
			break
	if p == null:
		p = _sfx[_sfx_idx]
		_sfx_idx = (_sfx_idx + 1) % _sfx.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func sfx(id: String, db: float = 0.0, pitch: float = 1.0) -> void:
	_sfx_tocar(_stream(DIR + "sfx/" + id + ".ogg", false), db, pitch)


func ui(id: String = "clique") -> void:
	# -6 dB: audivel sem competir com a musica (medido no teste de audio)
	sfx(id, -6.0)


func tema_minigame(id: String) -> void:
	var tema := str(_cfg.get("minigames", {}).get(id, ""))
	if tema != "":
		tocar_tema(tema, 1.2)


func duck(db: float) -> void:
	_duck_db = db
	_aplicar_volumes()


# ------------------------------------------------------------------ utilidades

func ids_temas() -> Array:
	var out := []
	for z in _cfg.get("zonas", []):
		out.append(str(z))
	for k in _cfg.get("minigames", {}).keys():
		out.append(str(_cfg["minigames"][k]))
	return out


func possui(id: String) -> bool:
	return ResourceLoader.exists(DIR + "mus/" + id + ".ogg")


func parar_tudo() -> void:
	for p in _mus:
		p.stop()
	for p in _amb:
		p.stop()
	_amb_base.stop()
	for p in _sfx:
		p.stop()
	_tema = ""
	_amb_atual = ""
	_base_ligada = false
