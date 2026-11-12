class_name SigaExporter
extends RefCounted
## SigaExporter - gera o relatorio semanal no formato SIGA/SINAN e calcula o
## resumo de integridade (SHA-256) do arquivo.
##
## O exercicio pedagogico e duplo: (1) o aluno aprende a estrutura de um arquivo
## de notificacao (campos, dominios, completude); (2) verifica que o hash muda
## quando qualquer registro e alterado — a base da auditoria de dados.

const SEP := ";"


static func _hex(bytes: PackedByteArray) -> String:
	const HEX := "0123456789abcdef"
	var out := ""
	for b in bytes:
		out += HEX[b >> 4]
		out += HEX[b & 0x0F]
	return out


static func sha256(texto: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(texto.to_utf8_buffer())
	return _hex(ctx.finish())


static func _fmt_num(v: float, casas: int = 1) -> String:
	return String.num(v, casas).replace(".", ",")


## Monta o relatorio. Retorna {corpo, cabecalho, csv, hash, registros, resumo}.
static func gerar(vila_id: int = 0) -> Dictionary:
	var doenca := GameState.info_doenca()
	var pop_total := Vilas.populacao_total()
	var stats := Epidemic.estatisticas_globais()

	# --- seleciona os individuos notificaveis -----------------------------
	var indices := PackedInt32Array()
	if vila_id > 0:
		indices = Population.indices_por_estado(vila_id, Population.ESTADO_INFECTADO)
	else:
		for v in Vilas.vilas:
			var iv := Population.indices_por_estado(int(v["id"]), Population.ESTADO_INFECTADO)
			for i in iv:
				indices.append(i)
	# amostra limitada para manter o arquivo utilizavel no navegador
	var limite := 400
	if indices.size() > limite:
		var passo := float(indices.size()) / float(limite)
		var sel := PackedInt32Array()
		for k in range(limite):
			sel.append(indices[int(k * passo)])
		indices = sel

	var cols := PackedStringArray(["id", "vila_nome", "idade", "faixa_etaria", "genero",
		"escolaridade", "saneamento_domiciliar", "doses_vacina", "estado_epidemiologico",
		"biomarcador_clinico", "dias_sintomas"])

	var linhas := PackedStringArray()
	linhas.append("ID;VILA;IDADE;FAIXA_ETARIA;SEXO;ESCOLARIDADE;SANEAMENTO;DOSES;" +
		"CLASSIFICACAO;BIOMARCADOR;DIAS_SINTOMAS")
	var completos := 0
	for i in indices:
		var idade := Population.idade_de(i)
		var idade_txt := _fmt_num(idade, 0)
		var faixa := Population.faixa_etaria(idade)
		var sexo := "M" if str(Population.valor(i, "genero")) == "Masculino" else "F"
		var escol := str(Population.valor(i, "escolaridade"))
		var san := str(Population.valor(i, "saneamento_domiciliar"))
		var doses := int(Population.doses_de(i))
		var estado := Population.nome_estado(Population.estado_de(i))
		var bio := _fmt_num(float(Population.valor(i, "biomarcador_clinico")), 1)
		var dias := Population.dias_sintomas_de(i)
		var campos_ok := 0
		for campo in [idade_txt, faixa, sexo, escol, san, bio]:
			if str(campo).strip_edges() != "":
				campos_ok += 1
		if campos_ok >= 5:
			completos += 1
		linhas.append("%d;%s;%s;%s;%s;%s;%s;%d;%s;%s;%d" % [
			i + 1, Population.valor(i, "vila_nome"), idade_txt, faixa, sexo, escol,
			san, doses, estado, bio, dias])

	var corpo := "\n".join(linhas)
	var hash := sha256(corpo)
	var agora := Time.get_datetime_string_from_system(false, true)

	var cab := PackedStringArray()
	cab.append("# RELATORIO SIGA / SINAN  -  StaTown (simulacao didatica)")
	cab.append("# Municipio: Vale do Rio Doce (ficticio) - MG")
	cab.append("# Semana epidemiologica: %d / ano %d" % [GameState.semana, GameState.ano])
	cab.append("# Data de geracao: " + agora)
	cab.append("# Agravo: %s (%s)" % [str(doenca.get("nome", "?")), GameState.doenca_id])
	cab.append("# Populacao do territorio: %d" % pop_total)
	cab.append("# Casos ativos notificados: %d de %d" % [linhas.size() - 1, indices.size()])
	cab.append("# Casos acumulados: %d   Obitos acumulados: %d" % [
		int(stats["casos_total"]), int(stats["obitos_total"])])
	cab.append("# Registros com >=5 campos preenchidos: %d (%.1f%%)" % [
		completos, 100.0 * float(completos) / float(maxi(linhas.size() - 1, 1))])
	cab.append("# SHA-256 do corpo: " + hash)
	cab.append("#")
	var cabecalho := "\n".join(cab)
	var csv := cabecalho + "\n" + corpo

	return {
		"csv": csv, "corpo": corpo, "cabecalho": cabecalho, "hash": hash,
		"registros": linhas.size() - 1, "completos": completos,
		"doenca": str(doenca.get("nome", "?")),
		"resumo": {
			"populacao": pop_total,
			"casos_ativos": int(stats["infectados_total"]),
			"obitos": int(stats["obitos_total"]),
			"prevalencia": float(stats["prevalencia"]),
			"semana": GameState.semana,
			"ano": GameState.ano,
		},
	}


## Grava no disco do jogador e, no navegador, dispara o download.
static func baixar(nome_arquivo: String, conteudo: String) -> Dictionary:
	var caminho := "user://" + nome_arquivo
	var f := FileAccess.open(caminho, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "msg": "Nao foi possivel abrir " + caminho}
	f.store_string(conteudo)
	f.close()
	var msg := "Arquivo salvo em " + ProjectSettings.globalize_path(caminho)
	if OS.has_feature("web"):
		var js := JavaScriptBridge.get_interface("window")
		if js != null:
			var b64 := Marshalls.utf8_to_base64(conteudo)
			var a = js.document.createElement("a")
			a.href = "data:text/csv;charset=utf-8;base64," + b64
			a.download = nome_arquivo
			js.document.body.appendChild(a)
			a.click()
			js.document.body.removeChild(a)
			msg = "Download iniciado no navegador: " + nome_arquivo
	return {"ok": true, "msg": msg, "caminho": caminho}
