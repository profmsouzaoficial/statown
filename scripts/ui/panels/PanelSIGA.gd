class_name PanelSIGA
extends Control
## Gerador e auditor do relatorio semanal SIGA/SINAN.
##
## O aluno gera o arquivo, confere a completude dos campos, copia o CSV e
## verifica o SHA-256 — o mesmo raciocinio de auditoria usado em vigilancia.

var main: Control
var _ultimo: Dictionary = {}
var _preview: VBoxContainer
var _resumo: VBoxContainer
var _lbl_hash: Label


func _init(m: Control) -> void:
	main = m
	_build()
	_gerar()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margem.add_theme_constant_override(lado, 16)
	add_child(margem)

	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margem.add_child(col)

	# -------- esquerda: preview monoespaçado --------
	var esq := VBoxContainer.new()
	esq.add_theme_constant_override("separation", 8)
	esq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	esq.size_flags_stretch_ratio = 1.9
	col.add_child(esq)
	esq.add_child(UITheme.rotulo("PREVIA DO ARQUIVO (CSV, SEPARADOR ';')", 12, UITheme.ACENTO))

	var pv := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.09)
	sb.border_color = UITheme.BORDA
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	pv.add_theme_stylebox_override("panel", sb)
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	esq.add_child(pv)
	var sc := UITheme.scroll()
	pv.add_child(sc)
	_preview = UITheme.vbox(0)
	sc.add_child(_preview)

	# -------- direita: resumo e acoes (com rolagem: o conteudo passa da altura) --------
	var scd := UITheme.scroll()
	scd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scd.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scd)
	var dir := UITheme.vbox(12)
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scd.add_child(dir)

	var p1 := UITheme.card("RESUMO DA SEMANA", UITheme.SUCESSO)
	dir.add_child(p1)
	_resumo = UITheme.conteudo(p1)

	var p2 := UITheme.card("INTEGRIDADE", UITheme.ACENTO)
	dir.add_child(p2)
	var c2 := UITheme.conteudo(p2)
	c2.add_child(UITheme.paragrafo(
		"O SHA-256 e uma impressao digital do arquivo: qualquer alteracao em um unico "
		+ "campo muda o hash por completo. E assim que se prova que um dado nao foi "
		+ "adulterado depois de publicado.", 13, UITheme.TEXTO_DIM))
	_lbl_hash = UITheme.codigo("", 14)
	_lbl_hash.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	c2.add_child(_lbl_hash)

	var p3 := UITheme.card("ACOES", UITheme.INFO)
	dir.add_child(p3)
	var c3 := UITheme.conteudo(p3)
	c3.add_child(UITheme.botao("Gerar novamente", _gerar, null, UITheme.SUCESSO))
	c3.add_child(UITheme.botao("Copiar CSV", _copiar, null, UITheme.INFO))
	c3.add_child(UITheme.botao("Baixar CSV", _baixar, null, UITheme.ACENTO))
	c3.add_child(UITheme.botao("Baixar JSON de resumo", _baixar_json, null, UITheme.ROXO))
	c3.add_child(UITheme.separador())
	c3.add_child(UITheme.paragrafo(
		"Dica de aula: peca a dois colegas que gerem o relatorio na mesma semana e comparem "
		+ "os hashes. Se forem iguais, os dados sao identicos; se diferirem, algo mudou "
		+ "entre as geracoes (uma semana avancou, uma intervencao foi aplicada).",
		12, UITheme.TEXTO_DIM))


func _gerar() -> void:
	_ultimo = SigaExporter.gerar()
	for c in _preview.get_children():
		c.queue_free()
	var linhas := str(_ultimo["csv"]).split("\n")
	var limite := mini(linhas.size(), 120)
	for k in range(limite):
		var l := UITheme.codigo(linhas[k], 13)
		l.add_theme_color_override("font_color",
			UITheme.TEXTO_DIM if linhas[k].begins_with("#") else UITheme.TEXTO)
		_preview.add_child(l)
	if linhas.size() > limite:
		_preview.add_child(UITheme.rotulo("... %d linhas omitidas" % (linhas.size() - limite),
			11, UITheme.TEXTO_FRACO))

	for c in _resumo.get_children():
		c.queue_free()
	var r: Dictionary = _ultimo["resumo"]
	_resumo.add_child(UITheme.campo("Semana epidemiologica", "SE %d / ano %d" % [int(r["semana"]), int(r["ano"])]))
	_resumo.add_child(UITheme.campo("Agravo", str(_ultimo["doenca"])))
	_resumo.add_child(UITheme.campo("Populacao", _mil(int(r["populacao"]))))
	_resumo.add_child(UITheme.campo("Casos ativos", _mil(int(r["casos_ativos"]))))
	_resumo.add_child(UITheme.campo("Obitos acumulados", _mil(int(r["obitos"]))))
	_resumo.add_child(UITheme.campo("Prevalencia", "%.2f%%" % (float(r["prevalencia"]) * 100.0)))
	_resumo.add_child(UITheme.separador())
	_resumo.add_child(UITheme.campo("Registros no arquivo", _mil(int(_ultimo["registros"]))))
	var comp := 100.0 * float(_ultimo["completos"]) / float(maxi(int(_ultimo["registros"]), 1))
	_resumo.add_child(UITheme.campo("Completude dos campos", "%.1f%%" % comp))
	_resumo.add_child(UITheme.barra(comp / 100.0, 1.0,
		UITheme.SUCESSO if comp > 95.0 else UITheme.ACENTO))
	_lbl_hash.text = str(_ultimo["hash"])


func _copiar() -> void:
	DisplayServer.clipboard_set(str(_ultimo["csv"]))
	main.mostrar_toast("CSV copiado para a area de transferencia", "sucesso")


func _baixar() -> void:
	var nome := "siga_statown_SE%02d_%s.csv" % [GameState.semana, GameState.doenca_id]
	var r := SigaExporter.baixar(nome, str(_ultimo["csv"]))
	main.mostrar_toast(str(r["msg"]), "sucesso" if bool(r["ok"]) else "erro")


func _baixar_json() -> void:
	var d := {
		"versao": 1, "semana": GameState.semana, "ano": GameState.ano,
		"doenca": GameState.doenca_id, "hash_csv": _ultimo["hash"],
		"resumo": _ultimo["resumo"], "populacao_total": Vilas.populacao_total(),
		"vilas": [],
	}
	for v in Vilas.vilas:
		(d["vilas"] as Array).append({
			"id": int(v["id"]), "nome": str(v["nome"]),
			"populacao": int(v["populacao"]),
			"prevalencia": Epidemic.prevalencia(int(v["id"])),
			"rt": Epidemic.rt(int(v["id"])),
			"leitos": int(v["leitos"]), "ubs": int(v["ubs"]),
			"hospital": int(v["hospital"]),
			"saneamento": float(v["saneamento"]),
			"cobertura_vacinal": float(v["cobertura_vacinal"]),
		})
	var nome := "statown_resumo_SE%02d.json" % GameState.semana
	var r := SigaExporter.baixar(nome, JSON.stringify(d, "  "))
	main.mostrar_toast(str(r["msg"]), "sucesso" if bool(r["ok"]) else "erro")


func _mil(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return out
