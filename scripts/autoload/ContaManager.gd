extends Node
## Conta - login e sincronizacao do progresso com Supabase.
##
## Seguranca: o cliente guarda apenas o token de sessao, nunca a senha. A
## `anon key` e publica por desenho; a protecao real vem das policies RLS e
## das RPCs `statown_carregar` / `statown_salvar`, que usam `auth.uid()`.
## Nunca coloque a `service_role` neste arquivo nem no build web.
##
## Sem `config/supabase.json` preenchido o jogo funciona em modo local e esta
## camada fica inativa. A tela de login avisa isso em vez de fingir que salvou.

signal login_concluido(ok: bool, mensagem: String)
signal cadastro_pendente(mensagem: String)
signal sessao_alterada()
signal progresso_carregado(ok: bool, mensagem: String)
signal progresso_salvo(ok: bool, mensagem: String)
signal sync_alterado(texto: String, ok: bool)

const CAMINHO_CONFIG := "res://config/supabase.json"
const CAMINHO_SESSAO := "user://statown_sessao.json"
const INTERVALO_SYNC := 12.0

var cfg: Dictionary = {}
var usuario: Dictionary = {}
var access_token: String = ""
var refresh_token: String = ""
var expira_em: float = 0.0
var ultimo_sync: String = ""
var erro_sync: String = ""

var _http: HTTPRequest
var _timer: Timer
var _fila: Array = []
var _atual: Dictionary = {}
var _ocupado := false
var _sync_pendente := false
var _autenticado := false
var _bloquear_sync := false   # evita subir save local antes de baixar a nuvem
var _progresso_pronto := false # true somente apos carregar (ou confirmar conta nova)


func _ready() -> void:
	_carregar_config()
	_http = HTTPRequest.new()
	_http.timeout = 25.0
	# No navegador, o fetch ja descompacta respostas gzip. Se o HTTPRequest
	# tambem tentar descompactar, o Cloudflare/Supabase devolve gzip e o corpo
	# chega em texto: resultado 8 (RESULT_BODY_DECOMPRESS_FAILED) na leitura do
	# progresso. Pedir identidade evita a dupla descompactacao no build web.
	_http.accept_gzip = false
	add_child(_http)
	_http.request_completed.connect(_ao_http)
	_timer = Timer.new()
	_timer.wait_time = INTERVALO_SYNC
	_timer.one_shot = true
	_timer.timeout.connect(_ao_timer)
	add_child(_timer)
	GameState.semana_avancou.connect(func(_s, _a): agendar_sync())
	GameState.partida_reiniciada.connect(agendar_sync)
	Economy.transacao_registrada.connect(func(_t): agendar_sync())
	_carregar_sessao()


# ---------------------------------------------------------------------------
# Configuracao e estado
# ---------------------------------------------------------------------------

func _carregar_config() -> void:
	cfg = {"habilitado": false, "url": "", "anon_key": ""}
	if not FileAccess.file_exists(CAMINHO_CONFIG):
		return
	var f := FileAccess.open(CAMINHO_CONFIG, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) == TYPE_DICTIONARY:
		cfg = d
	var url := str(cfg.get("url", "")).strip_edges().trim_suffix("/")
	cfg["url"] = url
	cfg["habilitado"] = bool(cfg.get("habilitado", false)) and url.begins_with("http") \
		and str(cfg.get("anon_key", "")).length() > 20


func configurado() -> bool:
	return bool(cfg.get("habilitado", false))


func autenticado() -> bool:
	return _autenticado and access_token != ""


## Ha uma conta, mas o save da nuvem ainda nao foi baixado? Nesse estado o
## jogo nao pode avancar semanas nem enviar nada, para nao sobrescrever a nuvem.
func progresso_pronto() -> bool:
	return not autenticado() or _progresso_pronto


func nome_aluno() -> String:
	if usuario.is_empty():
		return "Aluno local"
	var meta: Dictionary = usuario.get("user_metadata", {}) if typeof(usuario.get("user_metadata", {})) == TYPE_DICTIONARY else {}
	return str(meta.get("nome", usuario.get("email", "Aluno")))


func email_aluno() -> String:
	return str(usuario.get("email", ""))


func matricula_aluno() -> String:
	if usuario.is_empty():
		return ""
	var meta: Dictionary = usuario.get("user_metadata", {}) if typeof(usuario.get("user_metadata", {})) == TYPE_DICTIONARY else {}
	return str(meta.get("matricula", ""))


func status_curto() -> String:
	if not configurado():
		return "modo local (Supabase nao configurado)"
	if not autenticado():
		return "sem conta"
	if erro_sync != "":
		return "conta: %s (ultima sync falhou)" % email_aluno()
	if ultimo_sync == "":
		return "conta: %s" % email_aluno()
	return "conta: %s - sync %s" % [email_aluno(), ultimo_sync]


# ---------------------------------------------------------------------------
# Login / cadastro / sessao
# ---------------------------------------------------------------------------

func entrar(email: String, senha: String) -> void:
	if not configurado():
		login_concluido.emit(false, "Supabase nao configurado. Preencha config/supabase.json.")
		return
	if email.strip_edges() == "" or senha.length() < 6:
		login_concluido.emit(false, "Informe e-mail e senha (minimo 6 caracteres).")
		return
	_enfileirar("login", "/auth/v1/token?grant_type=password", HTTPClient.METHOD_POST,
		{"email": email.strip_edges(), "password": senha}, false)


func cadastrar(email: String, senha: String, nome: String, matricula: String) -> void:
	if not configurado():
		login_concluido.emit(false, "Supabase nao configurado. Preencha config/supabase.json.")
		return
	if email.strip_edges() == "" or senha.length() < 6:
		login_concluido.emit(false, "Informe e-mail e senha (minimo 6 caracteres).")
		return
	var corpo := {
		"email": email.strip_edges(), "password": senha,
		"data": {"nome": nome.strip_edges(), "matricula": matricula.strip_edges()},
	}
	_enfileirar("cadastro", "/auth/v1/signup", HTTPClient.METHOD_POST, corpo, false)


func sair() -> void:
	if autenticado() and configurado():
		_enfileirar("logout", "/auth/v1/logout", HTTPClient.METHOD_POST, {}, true)
	_limpar_sessao()
	_bloquear_sync = false
	_progresso_pronto = false
	# Troca o caminho ANTES de reiniciar/carregar: o cache da conta nao pode
	# ser sobrescrito por uma partida local no momento do logout.
	GameState.caminho_save = "user://statown_save.json"
	if FileAccess.file_exists(GameState.caminho_save):
		GameState.carregar_partida()
	else:
		GameState.reiniciar_partida()
	login_concluido.emit(false, "Sessao encerrada. O progresso local desta conta continua no servidor.")


func _carregar_sessao() -> void:
	if not configurado() or not FileAccess.file_exists(CAMINHO_SESSAO):
		return
	var f := FileAccess.open(CAMINHO_SESSAO, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return
	access_token = str(d.get("access_token", ""))
	refresh_token = str(d.get("refresh_token", ""))
	expira_em = float(d.get("expira_em", 0.0))
	usuario = d.get("usuario", {})
	if access_token == "":
		return
	_autenticado = true
	_bloquear_sync = true
	_progresso_pronto = false
	_preparar_caminho_local()
	if Time.get_unix_time_from_system() >= expira_em - 30.0:
		renovar_sessao()
	else:
		baixar_progresso()
	sessao_alterada.emit()


func _salvar_sessao() -> void:
	var f := FileAccess.open(CAMINHO_SESSAO, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"access_token": access_token, "refresh_token": refresh_token,
		"expira_em": expira_em, "usuario": usuario,
	}))
	f.close()


func _limpar_sessao() -> void:
	access_token = ""
	refresh_token = ""
	expira_em = 0.0
	usuario = {}
	_autenticado = false
	if FileAccess.file_exists(CAMINHO_SESSAO):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMINHO_SESSAO))
	sessao_alterada.emit()


func renovar_sessao() -> void:
	if refresh_token == "":
		_limpar_sessao()
		var msg := "Sessao expirada. Entre novamente."
		login_concluido.emit(false, msg)
		progresso_carregado.emit(false, msg)
		return
	_enfileirar("refresh", "/auth/v1/token?grant_type=refresh_token",
		HTTPClient.METHOD_POST, {"refresh_token": refresh_token}, false)


func _aplicar_sessao(d: Dictionary) -> void:
	access_token = str(d.get("access_token", ""))
	refresh_token = str(d.get("refresh_token", refresh_token))
	expira_em = Time.get_unix_time_from_system() + float(d.get("expires_in", 3600)) - 60.0
	if typeof(d.get("user", {})) == TYPE_DICTIONARY:
		usuario = d["user"]
	_autenticado = access_token != ""
	_salvar_sessao()
	sessao_alterada.emit()


func _preparar_caminho_local() -> void:
	var uid := str(usuario.get("id", "sem_id"))
	var chave := str(abs(uid.hash()))
	GameState.caminho_save = "user://statown_save_%s.json" % chave
	# Se existe cache desta conta, ele e o melhor ponto de partida offline.
	# Se nao existe, NAO reinicie a partida: a nuvem ainda vai responder e o
	# save anonimo atual pode ser a primeira fotografia de uma conta nova.
	if FileAccess.file_exists(GameState.caminho_save):
		GameState.carregar_partida()


# ---------------------------------------------------------------------------
# Progresso remoto
# ---------------------------------------------------------------------------

func baixar_progresso() -> void:
	if not autenticado():
		return
	_progresso_pronto = false
	_enfileirar("carregar", "/rest/v1/rpc/statown_carregar", HTTPClient.METHOD_POST,
		{"p_semestre": GameState.semestre_atual()}, true)


func salvar_progresso(force: bool = false) -> void:
	if not autenticado() or not configurado() or _bloquear_sync or not _progresso_pronto:
		return
	if not force and not _sync_pendente:
		return
	_sync_pendente = false
	_enfileirar("salvar", "/rest/v1/rpc/statown_salvar", HTTPClient.METHOD_POST,
		{"p_semestre": GameState.semestre_atual(), "p_save": GameState.serializar_partida()}, true)


func sincronizar_agora() -> void:
	if not autenticado() or not _progresso_pronto:
		return
	_sync_pendente = true
	salvar_progresso(true)


func agendar_sync() -> void:
	if not autenticado() or _bloquear_sync or not _progresso_pronto:
		return
	_sync_pendente = true
	if _timer != null:
		_timer.start()


func _ao_timer() -> void:
	if _sync_pendente:
		salvar_progresso(true)


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

func _enfileirar(tag: String, caminho: String, metodo: int, corpo: Dictionary,
		com_auth: bool) -> void:
	if not configurado():
		return
	_fila.append({"tag": tag, "caminho": caminho, "metodo": metodo,
		"corpo": corpo, "auth": com_auth})
	_bombear()


func _bombear() -> void:
	if _ocupado or _fila.is_empty():
		return
	_atual = _fila.pop_front()
	_ocupado = true
	var headers := PackedStringArray(["apikey: %s" % str(cfg.get("anon_key", "")),
		"Content-Type: application/json"])
	if bool(_atual.get("auth", false)) and access_token != "":
		headers.append("Authorization: Bearer %s" % access_token)
	var corpo := "" if (_atual["metodo"] as int) == HTTPClient.METHOD_GET else JSON.stringify(_atual["corpo"])
	var url := "%s%s" % [str(cfg.get("url", "")), str(_atual["caminho"])]
	var err := _http.request(url, headers, int(_atual["metodo"]), corpo)
	if err != OK:
		_ocupado = false
		_erro_rede("Falha ao iniciar a conexao (%d)." % err)
		_bombear()


func _ao_http(result: int, codigo: int, _headers: PackedStringArray, corpo: PackedByteArray) -> void:
	_ocupado = false
	var txt := corpo.get_string_from_utf8()
	var dados = JSON.parse_string(txt) if txt != "" else {}
	var tag := str(_atual.get("tag", ""))
	if result != HTTPRequest.RESULT_SUCCESS:
		var msg_rede := "Sem conexao com o servidor (resultado %d)." % result
		if tag == "carregar":
			# Mantem o bloqueio: sem o save da nuvem, subir o local poderia
			# apagar a partida de outro computador.
			_progresso_pronto = false
			progresso_carregado.emit(false, msg_rede)
		else:
			_erro_rede(msg_rede)
		_bombear()
		return
	if codigo >= 200 and codigo < 300:
		_tratar(tag, dados)
	elif codigo == 401 and tag == "refresh":
		_limpar_sessao()
		var msg_exp := "Sessao expirada. Entre novamente."
		login_concluido.emit(false, msg_exp)
		progresso_carregado.emit(false, msg_exp)
	elif codigo == 401 and tag != "login":
		_autenticado = false
		if tag == "carregar":
			_progresso_pronto = false
			progresso_carregado.emit(false, "Sessao expirada. Entre novamente.")
		else:
			_erro_rede("Sessao expirada. Entre novamente.")
		sessao_alterada.emit()
	else:
		var msg := _mensagem_erro(dados)
		if tag == "login" or tag == "cadastro":
			login_concluido.emit(false, msg)
		elif tag == "salvar":
			_sync_pendente = true
			erro_sync = msg
			progresso_salvo.emit(false, msg)
			sync_alterado.emit("falha ao salvar: " + msg, false)
		elif tag == "carregar":
			progresso_carregado.emit(false, msg)
		else:
			push_warning("Conta/%s: HTTP %d %s" % [tag, codigo, msg])
	_bombear()


func _tratar(tag: String, dados) -> void:
	match tag:
		"login":
			if typeof(dados) != TYPE_DICTIONARY or str(dados.get("access_token", "")) == "":
				login_concluido.emit(false, "Resposta de login sem token. Verifique a confirmacao de e-mail.")
				return
			_aplicar_sessao(dados)
			_bloquear_sync = true
			_progresso_pronto = false
			_preparar_caminho_local()
			login_concluido.emit(true, "Login realizado. Carregando o progresso...")
			baixar_progresso()
		"cadastro":
			if typeof(dados) == TYPE_DICTIONARY and str(dados.get("access_token", "")) != "":
				_aplicar_sessao(dados)
				_bloquear_sync = true
				_progresso_pronto = false
				_preparar_caminho_local()
				login_concluido.emit(true, "Conta criada e sessao iniciada.")
				baixar_progresso()
			else:
				cadastro_pendente.emit("Conta criada. Confirme o e-mail antes de entrar.")
		"refresh":
			if typeof(dados) == TYPE_DICTIONARY and str(dados.get("access_token", "")) != "":
				_aplicar_sessao(dados)
				baixar_progresso()
			else:
				_limpar_sessao()
				var msg := "Sessao expirada. Entre novamente."
				login_concluido.emit(false, msg)
				progresso_carregado.emit(false, msg)
		"logout":
			pass
		"carregar":
			_tratar_carregar(dados)
		"salvar":
			ultimo_sync = Time.get_datetime_string_from_system(false, true)
			erro_sync = ""
			progresso_salvo.emit(true, "Progresso salvo no servidor.")
			sync_alterado.emit("sincronizado " + ultimo_sync, true)
		_:
			pass


func _tratar_carregar(dados) -> void:
	var linha = null
	if typeof(dados) == TYPE_ARRAY and not (dados as Array).is_empty():
		linha = dados[0]
	elif typeof(dados) == TYPE_DICTIONARY and dados.has("save_data"):
		linha = dados
	if typeof(linha) != TYPE_DICTIONARY:
		# Conta nova: preserva a partida local e sobe a primeira fotografia.
		_progresso_pronto = true
		_bloquear_sync = false
		progresso_carregado.emit(true, "Conta nova: progresso local sera enviado ao servidor.")
		sincronizar_agora()
		return
	var save = linha.get("save_data", null)
	if typeof(save) == TYPE_STRING:
		save = JSON.parse_string(str(save))
	if typeof(save) != TYPE_DICTIONARY:
		_progresso_pronto = false
		progresso_carregado.emit(false, "O servidor respondeu sem um save valido.")
		return
	if GameState.aplicar_save(save):
		ultimo_sync = str(linha.get("atualizado_em", ""))
		_progresso_pronto = true
		_bloquear_sync = false
		progresso_carregado.emit(true, "Progresso carregado: SE %d, ano %d." % [
			GameState.semana, GameState.ano])
	else:
		_progresso_pronto = false
		progresso_carregado.emit(false, "Save do servidor incompativel com esta versao.")


func _erro_rede(msg: String) -> void:
	erro_sync = msg
	sync_alterado.emit(msg, false)
	progresso_salvo.emit(false, msg)


func _mensagem_erro(dados) -> String:
	if typeof(dados) == TYPE_DICTIONARY:
		for chave in ["error_description", "msg", "message", "error", "hint"]:
			if dados.has(chave):
				return str(dados[chave])
	return "Falha de comunicacao com o Supabase."
