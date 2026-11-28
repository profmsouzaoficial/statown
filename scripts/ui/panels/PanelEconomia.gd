class_name PanelEconomia
extends Control
## Extrato das BioMoedas e explicacao da nota de participacao.
##
## A tela existe para o aluno conseguir reconstruir o saldo: cada linha mostra
## o motivo, a semana e o saldo depois da transacao. A nota usa as moedas
## GANHAS no semestre, nao o saldo, porque gastar em intervencoes e parte do
## jogo e nao pode punir o aluno duas vezes.

var main: Control
var _raiz: VBoxContainer


func _init(m: Control) -> void:
	main = m
	_build()


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

	# ---- coluna esquerda: resumo e regras ----
	var esq_scroll := UITheme.scroll()
	# A coluna esquerda sempre tem mais regras do que cabe em 900/720 px.
	# Mostrar a barra evita a impressao de que o cartao termina no meio.
	esq_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	esq_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	esq_scroll.size_flags_stretch_ratio = 0.85
	col.add_child(esq_scroll)
	var esq := UITheme.vbox(10)
	esq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	esq_scroll.add_child(esq)

	var p1 := UITheme.card("SALDO E NOTA", UITheme.ACENTO)
	esq.add_child(p1)
	var c1 := UITheme.conteudo(p1)
	c1.add_child(UITheme.campo("Saldo atual", "%d BioMoedas" % GameState.moedas))
	c1.add_child(UITheme.campo("Moedas ganhas no semestre", "%d" % GameState.moedas_ganhas_total))
	c1.add_child(UITheme.campo("Moedas gastas no semestre", "%d" % GameState.moedas_gastas_total))
	var n := Economy.nota_participacao()
	c1.add_child(UITheme.separador())
	c1.add_child(UITheme.campo("Nota projetada", "%.1f / %.1f" % [
		float(n["nota"]), float(n["nota_maxima"])]))
	c1.add_child(UITheme.barra(float(n["nota"]) / float(n["nota_maxima"]),
		float(n["nota_maxima"]), UITheme.SUCESSO))
	c1.add_child(UITheme.codigo(Economy.texto_regra_nota(), 14))
	c1.add_child(UITheme.paragrafo(
		"A nota usa as moedas GANHAS, nao o saldo: comprar uma intervencao reduz o saldo, "
		+ "mas nao apaga o aprendizado que gerou aquelas moedas. A regra e uma proporcao "
		+ "simples: %d moedas valem %.1f pontos; acima disso a nota fica no teto." % [
		int(n["moedas_para_nota_maxima"]), float(n["nota_maxima"])],
		12, UITheme.TEXTO_DIM))
	c1.add_child(UITheme.paragrafo(
		"O excedente continua no saldo e no extrato, mas nao aumenta a nota. "
		+ "Assim, repetir um minigame nao empurra a nota para cima do teto.",
		12, UITheme.TEXTO_FRACO))

	var p2 := UITheme.card("COMO GANHAR E PERDER", UITheme.INFO)
	esq.add_child(p2)
	var c2 := UITheme.conteudo(p2)
	c2.add_child(UITheme.paragrafo(
		"+ Minigames: recompensa proporcional aos acertos (10 a 70 BioMoedas por partida).",
		13, UITheme.SUCESSO))
	c2.add_child(UITheme.paragrafo(
		"+ Desafios do LAB: 20 a 30 BioMoedas, um por contexto por semana epidemiologica.",
		13, UITheme.SUCESSO))
	c2.add_child(UITheme.paragrafo(
		"+ Artigos auditados: 20 BioMoedas por artigo novo.", 13, UITheme.SUCESSO))
	c2.add_child(UITheme.paragrafo(
		"+ Surto controlado: 20 a 60 BioMoedas (base + semanas + bonus se nao houve obito).",
		13, UITheme.SUCESSO))
	c2.add_child(UITheme.separador())
	c2.add_child(UITheme.paragrafo(
		"- Intervencoes: saneamento 60, vacinacao 80, UBS 120, hospital 260 BioMoedas.",
		13, UITheme.ACENTO))
	c2.add_child(UITheme.paragrafo(
		"- Obitos: 1% do saldo por obito na semana, com teto de 25% do saldo. O detalhe "
		+ "de cada desconto aparece no extrato.", 13, UITheme.PERIGO))
	c2.add_child(UITheme.paragrafo(
		"Se o saldo chegar a zero, a partida termina. O botao de reinicio preserva as "
		+ "moedas ganhas e o extrato do semestre; apenas a partida recomeca.", 12,
		UITheme.TEXTO_DIM))

	var p3 := UITheme.card("ACOES", UITheme.ROXO)
	esq.add_child(p3)
	var c3 := UITheme.conteudo(p3)
	c3.add_child(UITheme.botao("Atualizar extrato", _atualizar, null, UITheme.SUCESSO))
	c3.add_child(UITheme.botao("Baixar extrato CSV", _baixar_csv, null, UITheme.ACENTO))
	c3.add_child(UITheme.botao("Abrir relatorio SIGA", func(): main._abrir_siga(), null, UITheme.INFO))

	# ---- coluna direita: extrato ----
	var dir := UITheme.vbox(8)
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir.size_flags_stretch_ratio = 1.45
	col.add_child(dir)
	var cab := UITheme.hbox(8)
	dir.add_child(cab)
	cab.add_child(UITheme.rotulo("EXTRATO (mais recente primeiro)", 12, UITheme.ACENTO))
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(esp)
	cab.add_child(UITheme.botao("Baixar CSV", _baixar_csv, null, UITheme.ACENTO))
	cab.add_child(UITheme.botao("Atualizar", _atualizar, null, UITheme.INFO))
	var p4 := UITheme.card("", UITheme.BORDA)
	p4.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dir.add_child(p4)
	var sc := UITheme.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p4.add_child(sc)
	_raiz = UITheme.vbox(6)
	_raiz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_raiz)
	_atualizar()


func _atualizar() -> void:
	for c in _raiz.get_children():
		c.queue_free()
	var trans := Economy.ultimas_transacoes(120)
	if trans.is_empty():
		_raiz.add_child(UITheme.paragrafo(
			"Nenhuma movimentacao ainda. Jogue um minigame, cumpra um desafio do LAB ou "
			+ "compre uma intervencao para o extrato comecar.", 14, UITheme.TEXTO_DIM))
		return
	var cab := UITheme.linha_tabela(["SE", "TIPO", "MOTIVO", "DELTA", "SALDO"],
		[0.55, 0.9, 3.2, 0.75, 0.75],
		[UITheme.TEXTO_FRACO, UITheme.TEXTO_FRACO, UITheme.TEXTO_FRACO,
		UITheme.TEXTO_FRACO, UITheme.TEXTO_FRACO], 11)
	_raiz.add_child(cab)
	for t in trans:
		var d := int(t.get("delta", 0))
		var cor := UITheme.SUCESSO if d > 0 else (UITheme.PERIGO if d < 0 else UITheme.TEXTO_DIM)
		var motivo := str(t.get("motivo", ""))
		var linha := UITheme.linha_tabela([
			"%d/%d" % [int(t.get("semana", 0)), int(t.get("ano", 0))],
			str(t.get("categoria", "")),
			motivo,
			"%+d" % d,
			str(int(t.get("saldo_apos", 0)))],
			[0.55, 0.9, 3.2, 0.75, 0.75],
			[UITheme.TEXTO_DIM, UITheme.INFO, UITheme.TEXTO, cor, UITheme.TEXTO], 12)
		_raiz.add_child(linha)


func _baixar_csv() -> void:
	var linhas := PackedStringArray()
	linhas.append("semana;ano;categoria;delta;saldo_apos;motivo;referencia;quando")
	for t in Economy.extrato:
		linhas.append("%d;%d;%s;%d;%d;%s;%s;%s" % [
			int(t.get("semana", 0)), int(t.get("ano", 0)),
			str(t.get("categoria", "")), int(t.get("delta", 0)),
			int(t.get("saldo_apos", 0)),
			str(t.get("motivo", "")).replace(";", ","),
			str(t.get("referencia", "")), str(t.get("quando", ""))])
	var nome := "statown_extrato_SE%02d.csv" % GameState.semana
	var r := SigaExporter.baixar(nome, "\n".join(linhas))
	main.mostrar_toast(str(r["msg"]), "sucesso" if bool(r["ok"]) else "erro")
