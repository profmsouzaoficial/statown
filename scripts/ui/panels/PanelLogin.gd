class_name PanelLogin
extends PanelContainer
## Tela de conta do aluno. Pode ser aberta no inicio (obrigatoria) ou pelo
## botao CONTA da HUD. Sem Supabase configurado ela explica o que falta e
## oferece continuar localmente; nao finge que existe login.

signal concluido(modo: String)   # "conta", "local" ou "logout"
signal cancelado()

var main: Control
var obrigatorio := false
var _status: Label
var _status_ativo: Label
var _status_cor: Color = UITheme.TEXTO_DIM
var _email: LineEdit
var _senha: LineEdit
var _nome: LineEdit
var _matricula: LineEdit
var _campos_cadastro: VBoxContainer
var _botao_principal: Button
var _modo_cadastro := false


func _init(m: Control, obrig: bool = false) -> void:
	main = m
	obrigatorio = obrig
	_build()
	# Conecta uma unica vez: _build() pode ser refeito quando o download falha
	# depois de um login manual e a tela precisa virar o painel da conta ativa.
	Conta.login_concluido.connect(_ao_login)
	Conta.cadastro_pendente.connect(_ao_cadastro_pendente)
	Conta.sync_alterado.connect(_ao_sync)


func _build() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_PANEL
	sb.border_color = UITheme.ACENTO
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(560, 0)

	var v := UITheme.vbox(9)
	add_child(v)
	v.add_child(UITheme.rotulo("STATOWN - CONTA DO ALUNO", 12, UITheme.ACENTO))
	v.add_child(UITheme.titulo("Seu progresso, em qualquer navegador", 24,
		UITheme.TEXTO, true))
	v.add_child(UITheme.paragrafo(
		"A conta guarda a semana epidemiologica, o ano e as BioMoedas no servidor. "
		+ "Ao entrar em outro computador, a partida continua da semana em que parou.",
		13, UITheme.TEXTO_DIM))

	if Conta.autenticado():
		_build_conta_ativa(v)
	elif not Conta.configurado():
		_build_sem_config(v)
	else:
		_build_form(v)

	if not obrigatorio:
		v.add_child(UITheme.separador())
		v.add_child(UITheme.botao("VOLTAR AO JOGO", func(): cancelado.emit(),
			null, UITheme.BORDA_CLARA))


func _build_conta_ativa(v: VBoxContainer) -> void:
	v.add_child(UITheme.separador())
	v.add_child(UITheme.card_info("SESSAO ATIVA", Conta.nome_aluno(), UITheme.SUCESSO))
	v.add_child(UITheme.paragrafo("E-mail: " + Conta.email_aluno(), 13, UITheme.TEXTO))
	if Conta.matricula_aluno() != "":
		v.add_child(UITheme.paragrafo("Matricula: " + Conta.matricula_aluno(), 13, UITheme.TEXTO))
	_status_ativo = UITheme.paragrafo(
		"Baixando o progresso do servidor..." if not Conta.progresso_pronto()
		else Conta.status_curto(), 12,
		UITheme.INFO if not Conta.progresso_pronto() else UITheme.TEXTO_DIM)
	v.add_child(_status_ativo)
	if not Conta.progresso_pronto():
		v.add_child(UITheme.botao("TENTAR BAIXAR DE NOVO", func():
			Conta.baixar_progresso()
			_definir_status("Baixando o progresso...", UITheme.INFO), null, UITheme.INFO))
		v.add_child(UITheme.paragrafo(
			"Se o servidor nao responder, voce pode jogar agora, mas nada sera "
			+ "enviado ate o download terminar. O progresso feito sem sincronizar "
			+ "fica so neste navegador e pode ser substituido pelo save da nuvem "
			+ "quando a conexao voltar. Ao recuperar a conexao, use CONTA.", 11,
			UITheme.TEXTO_FRACO))
		v.add_child(UITheme.botao("JOGAR SEM SINCRONIZAR", func(): cancelado.emit(),
			null, UITheme.PERIGO))
	else:
		v.add_child(UITheme.botao("SINCRONIZAR AGORA", func():
			Conta.sincronizar_agora()
			_definir_status("Sincronizando...", UITheme.INFO), null, UITheme.INFO))
	v.add_child(UITheme.botao("SAIR DA CONTA", _sair, null, UITheme.PERIGO))


func _build_sem_config(v: VBoxContainer) -> void:
	v.add_child(UITheme.card_info("MODO LOCAL ATIVO",
		"O Supabase ainda nao foi configurado neste build.", UITheme.ACENTO))
	v.add_child(UITheme.paragrafo(
		"O jogo funciona e salva neste navegador, mas a semana/ano e as moedas NAO "
		+ "vao para o SIGA. Para ativar as contas, o professor precisa:", 13, UITheme.TEXTO))
	var passos := [
		"Criar um projeto gratuito em supabase.com.",
		"Rodar docs/SUPABASE.sql no SQL Editor do projeto.",
		"Preencher config/supabase.json com a URL e a anon key.",
		"Reexportar o jogo web e publicar de novo.",
	]
	for i in range(passos.size()):
		v.add_child(UITheme.paragrafo("%d. %s" % [i + 1, passos[i]], 13, UITheme.TEXTO_DIM))
	v.add_child(UITheme.paragrafo(
		"A anon key pode ser publica. Nunca coloque a service_role no cliente. "
		+ "O passo a passo completo esta em docs/SUPABASE.md.", 12, UITheme.PERIGO))
	v.add_child(UITheme.botao("CONTINUAR SEM CONTA", func(): concluido.emit("local"),
		null, UITheme.SUCESSO))


func _build_form(v: VBoxContainer) -> void:
	v.add_child(UITheme.separador())
	_email = _campo(v, "E-mail institucional", "nome@instituicao.br", false)
	_senha = _campo(v, "Senha", "minimo 6 caracteres", true)
	_campos_cadastro = UITheme.vbox(6)
	_nome = _campo(_campos_cadastro, "Nome completo", "como aparece no SIGA", false)
	_matricula = _campo(_campos_cadastro, "Matricula", "opcional", false)
	_campos_cadastro.visible = false
	v.add_child(_campos_cadastro)
	_status = UITheme.paragrafo("", 12, UITheme.TEXTO_DIM)
	v.add_child(_status)
	_botao_principal = UITheme.botao("ENTRAR", _acao_principal, null, UITheme.SUCESSO)
	_botao_principal.custom_minimum_size = Vector2(0, 44)
	v.add_child(_botao_principal)
	var alternar := UITheme.botao("CRIAR CONTA", _alternar_modo, null, UITheme.BORDA_CLARA)
	v.add_child(alternar)
	v.add_child(UITheme.paragrafo(
		"A senha vai direto para o Supabase Auth; o jogo guarda apenas o token de sessao. "
		+ "Se o projeto exigir confirmacao, confirme o e-mail antes de entrar.", 11,
		UITheme.TEXTO_FRACO))


## Depois de um login manual que baixou a sessao mas falhou no download, troca
## o formulario pelo painel da conta ativa (com tentar de novo/offline/sair).
func mostrar_conta_ativa() -> void:
	if _status_ativo != null:
		return
	for filho in get_children():
		remove_child(filho)
		filho.queue_free()
	_status = null
	_status_ativo = null
	_email = null
	_senha = null
	_nome = null
	_matricula = null
	_campos_cadastro = null
	_botao_principal = null
	_modo_cadastro = false
	_build()


func _campo(destino: VBoxContainer, titulo_txt: String, dica: String,
		secreto: bool) -> LineEdit:
	destino.add_child(UITheme.rotulo(titulo_txt, 11, UITheme.TEXTO_DIM))
	var e := LineEdit.new()
	e.placeholder_text = dica
	e.secret = secreto
	e.custom_minimum_size = Vector2(0, 40)
	e.add_theme_font_size_override("font_size", 15)
	destino.add_child(e)
	return e


func _alternar_modo() -> void:
	_modo_cadastro = not _modo_cadastro
	_campos_cadastro.visible = _modo_cadastro
	_botao_principal.text = "CRIAR CONTA" if _modo_cadastro else "ENTRAR"
	_definir_status("Preencha nome e matricula para criar a conta." if _modo_cadastro
		else "Informe e-mail e senha.", UITheme.TEXTO_DIM)


func _acao_principal() -> void:
	if _modo_cadastro:
		Conta.cadastrar(_email.text, _senha.text,
			_nome.text if _nome != null else "", _matricula.text if _matricula != null else "")
		_definir_status("Criando conta...", UITheme.INFO)
	else:
		Conta.entrar(_email.text, _senha.text)
		_definir_status("Entrando...", UITheme.INFO)


func _ao_login(ok: bool, msg: String) -> void:
	_definir_status(msg, UITheme.SUCESSO if ok else UITheme.PERIGO)
	if ok:
		concluido.emit("conta")


func _ao_sync(msg: String, ok: bool) -> void:
	# "Sincronizando..." nao pode ficar para sempre: o painel ativo mostra o
	# resultado real do upload (ou o erro) assim que a requisicao termina.
	if _status_ativo != null:
		_status_ativo.text = msg
		_status_ativo.add_theme_color_override("font_color",
			UITheme.SUCESSO if ok else UITheme.PERIGO)


func _ao_cadastro_pendente(msg: String) -> void:
	_definir_status(msg, UITheme.ACENTO)
	_modo_cadastro = false
	_campos_cadastro.visible = false
	_botao_principal.text = "ENTRAR"


func _definir_status(msg: String, cor: Color) -> void:
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color", cor)
	if _status_ativo != null:
		_status_ativo.text = msg
		_status_ativo.add_theme_color_override("font_color", cor)


## Chamado pelo Main quando o download falha com a tela de conta ja aberta.
func definir_status(msg: String, cor: Color = UITheme.PERIGO) -> void:
	_definir_status(msg, cor)


func _sair() -> void:
	Conta.sair()
	concluido.emit("logout")
