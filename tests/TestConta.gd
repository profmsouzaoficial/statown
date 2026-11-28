extends Node
## Regressao do login preso em "Carregando o progresso...".
##
## O handler HTTP precisa retirar a requisicao que terminou de `_atual` antes
## de emitir sinais. O sinal de progresso pode enfileirar um upload sincrono;
## se `_atual` for limpo depois, essa nova requisicao perde a tag e a resposta
## nunca chega ao painel. Este teste simula a resposta de `carregar` de uma
## conta nova, que dispara `salvar`, e verifica que o upload continua na fila.

const SAVE_TESTE := "user://test_conta_save.json"

var _falhas := 0
var _checks := 0
var _servidor: TCPServer


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_falhas += 1
		print("  FALHA: ", msg)


func _ready() -> void:
	# Servidor local que aceita a conexao e nao responde: mantem o request
	# pendente de forma deterministica, sem depender de internet.
	_servidor = TCPServer.new()
	var porta := _servidor.listen(0, "127.0.0.1")
	_ok(porta == OK, "nao foi possivel abrir o servidor local de teste")

	# Estado artificial: nao usa a sessao real nem grava credenciais.
	Conta._http.cancel_request()
	Conta._fila.clear()
	Conta._atual = {}
	Conta._ocupado = false
	Conta._autenticado = true
	Conta.access_token = "token-de-teste"
	Conta.refresh_token = ""
	Conta._bloquear_sync = false
	Conta._progresso_pronto = false
	Conta.cfg = {
		"habilitado": true,
		"url": "http://127.0.0.1:%d" % _servidor.get_local_port(),
		"anon_key": "chave-de-teste-sem-valor-real-000000000000",
	}
	GameState.caminho_save = SAVE_TESTE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TESTE))
	GameState.reiniciar_partida()

	# A resposta "conta nova" ([], sem linha) libera o progresso e agenda o
	# primeiro upload. Esse callback e sincrono e ocorre dentro de _ao_http.
	Conta._atual = {"tag": "carregar", "auth": true}
	Conta._ao_http(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		"[]".to_utf8_buffer())

	_ok(Conta.progresso_pronto(), "conta nova deve liberar o progresso")
	var tag := str(Conta._atual.get("tag", ""))
	_ok(tag == "salvar", "o upload disparado pelo callback deveria estar em _atual, veio '%s'" % tag)
	_ok(Conta._ocupado, "o upload deveria ter sido iniciado imediatamente")

	# --- envio da nota: salva primeiro e so entao chama a funcao Edge ---
	Conta._http.cancel_request()
	Conta._fila.clear()
	Conta._atual = {}
	Conta._ocupado = false
	Conta._bloquear_sync = false
	Conta._progresso_pronto = true
	Conta._sync_pendente = false
	Conta._enviando_nota_siga = false
	Conta._nota_siga_aguardando_save = false
	Conta.usuario = {
		"email": "teste@example.invalid",
		"user_metadata": {
			"nome": "Teste", "matricula": "000000000",
			"turma": "TESTE-A", "periodo_siga": "2026/3",
		},
	}
	var nota_resultado := {"ok": false, "msg": ""}
	var captura := func(ok: bool, msg: String, _dados: Dictionary) -> void:
		nota_resultado["ok"] = ok
		nota_resultado["msg"] = msg
	Conta.nota_siga_enviada.connect(captura)
	Conta.enviar_nota_siga()
	_ok(str(Conta._atual.get("tag", "")) == "salvar",
		"enviar_nota_siga deve sincronizar o save antes de tudo")
	Conta._http.cancel_request()
	Conta._fila.clear()
	Conta._ao_http(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		"{}".to_utf8_buffer())
	var req_nota: Dictionary = Conta._atual
	_ok(str(req_nota.get("caminho", "")) == "/functions/v1/enviar-nota-siga",
		"o save deve enfileirar a funcao Edge, veio '%s'" % str(req_nota.get("caminho", "")))
	_ok(str((req_nota.get("corpo", {}) as Dictionary).get("semestre", "")) != "",
		"a funcao Edge deve receber o semestre interno")
	Conta._http.cancel_request()
	Conta._fila.clear()
	Conta._ao_http(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		'{"ok":true,"mensagem":"Nota 13,3 enviada ao SIGA.","nota":13.3,"nota_maxima":40.0}'.to_utf8_buffer())
	_ok(bool(nota_resultado["ok"]) and str(nota_resultado["msg"]).contains("13,3")
		and not Conta._enviando_nota_siga,
		"o resultado da funcao Edge deve chegar ao painel")
	Conta.nota_siga_enviada.disconnect(captura)

	print("CONTA: fila pos-carregar=%s, %d verificacoes, %d falhas"
		% [tag if tag != "" else "vazia", _checks, _falhas])

	Conta._http.cancel_request()
	Conta._fila.clear()
	Conta._atual = {}
	Conta._ocupado = false
	Conta._autenticado = false
	Conta.access_token = ""
	Conta.usuario = {}
	Conta._progresso_pronto = false
	Conta._bloquear_sync = false
	Conta._enviando_nota_siga = false
	Conta._nota_siga_aguardando_save = false
	_servidor.stop()
	GameState.reiniciar_partida()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TESTE))
	get_tree().quit(1 if _falhas > 0 else 0)
