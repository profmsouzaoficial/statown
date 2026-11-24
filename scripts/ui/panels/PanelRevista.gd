class_name PanelRevista
extends Control
## Revista Cientifica do Vale - leitura de artigos reais indexados no PubMed.
##
## A base fica em data/revista_artigos.json e tambem e replicada no Supabase.
## A cada semana o jogo sorteia 6 artigos. O painel exibe titulo, autores,
## periodico, DOI, PMID, tipo de estudo e o resumo da fonte; nenhum resultado
## e inventado pelo jogo. O botao de leitura paga 20 BioMoedas uma unica vez
## por artigo (GameState.artigos_lidos).

const CAMINHO_ARTIGOS := "res://data/revista_artigos.json"
const ARTIGOS_POR_RODADA := 6

var main: Control
var ARTIGOS: Array = []          # os 6 artigos sorteados para a semana
var _todos: Array = []           # acervo completo (50)
var _lista: VBoxContainer
var _leitor: VBoxContainer
var _artigo_atual := -1
var _lbl_contagem: Label
var _erro := ""

const ROTULOS_SECAO := {
	"BACKGROUND": "Contexto",
	"BACKGROUND AND OBJECTIVES": "Contexto e objetivos",
	"INTRODUCTION": "Introducao",
	"OBJECTIVE": "Objetivo",
	"OBJECTIVES": "Objetivos",
	"AIM": "Objetivo",
	"AIMS": "Objetivos",
	"METHODS": "Metodos",
	"METHOD": "Metodo",
	"MATERIALS AND METHODS": "Materiais e metodos",
	"PATIENTS AND METHODS": "Pacientes e metodos",
	"METHODS AND RESULTS": "Metodos e resultados",
	"STUDY DESIGN": "Desenho do estudo",
	"DESIGN": "Desenho",
	"SETTING": "Cenario",
	"PARTICIPANTS": "Participantes",
	"MAIN OUTCOME MEASURES": "Desfechos principais",
	"SUMMARY OF BACKGROUND DATA": "Contexto",
	"RESULTS": "Resultados",
	"DISCUSSION": "Discussao",
	"CONCLUSION": "Conclusao",
	"CONCLUSIONS": "Conclusoes",
	"LIMITATIONS": "Limitacoes",
	"CLINICAL TRIAL REGISTRATION": "Registro do ensaio",
}


func _init(m: Control) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_carregar_base()
	_sortear_artigos()
	_build()


# ============================================================================
# BASE E SORTEIO
# ============================================================================

func _carregar_base() -> void:
	_todos.clear()
	_erro = ""
	if not FileAccess.file_exists(CAMINHO_ARTIGOS):
		_erro = "Base de artigos ausente: " + CAMINHO_ARTIGOS
		return
	var dados = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO_ARTIGOS))
	if not (dados is Array):
		_erro = "Nao foi possivel ler a base de artigos."
		return
	var vistos := {}
	for item in dados:
		if not (item is Dictionary):
			continue
		var a: Dictionary = item
		var id := str(a.get("id", ""))
		var doi := str(a.get("doi", ""))
		if id == "" or str(a.get("titulo", "")) == "" or not doi.begins_with("10."):
			continue
		if vistos.has(id):
			continue
		vistos[id] = true
		_todos.append(a)
	if _todos.is_empty():
		_erro = "A base de artigos esta vazia ou invalida."


## Sorteio deterministico por semana/ano: o aluno ve os mesmos 6 durante a
## semana e recebe outro lote quando a semana epidemiologica avanca.
func _sortear_artigos() -> void:
	ARTIGOS.clear()
	if _todos.is_empty():
		return
	var baralho := _todos.duplicate()
	var semente := int(GameState.ano) * 100003 + int(GameState.semana) * 1009
	semente += abs(hash(GameState.semestre_atual()))
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(semente, 1)
	var limite := mini(ARTIGOS_POR_RODADA, baralho.size())
	for i in range(limite):
		var j := rng.randi_range(i, baralho.size() - 1)
		var tmp = baralho[i]
		baralho[i] = baralho[j]
		baralho[j] = tmp
		ARTIGOS.append(baralho[i])


# ============================================================================
# INTERFACE
# ============================================================================

func _build() -> void:
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margem.add_theme_constant_override(lado, 16)
	add_child(margem)

	var raiz := HBoxContainer.new()
	raiz.add_theme_constant_override("separation", 16)
	margem.add_child(raiz)

	# ---- coluna esquerda: fonte, contagem e lista da semana ----
	var esq := VBoxContainer.new()
	esq.custom_minimum_size.x = 340
	esq.add_theme_constant_override("separation", 10)
	raiz.add_child(esq)

	var fonte := UITheme.card("ACERVO CIENTIFICO", UITheme.INFO)
	esq.add_child(fonte)
	var cf := UITheme.conteudo(fonte)
	cf.add_child(UITheme.paragrafo(
		"%d artigos reais indexados no PubMed/NLM. A cada semana o jogo sorteia "
		% _todos.size()
		+ "6. Os resumos sao traduzidos para o portugues e marcados como TRADUZIDO; "
		+ "o texto original abre pelo DOI. Cada ficha mostra autores, periodico, "
		+ "DOI e PMID. Confira o DOI antes de citar.", 12, UITheme.TEXTO_DIM))
	cf.add_child(UITheme.paragrafo(
		"Consulta: %s · recorte dos ultimos cinco anos." % _data_consulta(), 11, UITheme.TEXTO_FRACO))

	_lbl_contagem = UITheme.rotulo("", 11, UITheme.ACENTO)
	esq.add_child(_lbl_contagem)
	_atualizar_contagem()

	if _erro != "":
		esq.add_child(UITheme.card_info("BASE INDISPONIVEL", _erro, UITheme.PERIGO, 12))
	else:
		var sc := UITheme.scroll()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		esq.add_child(sc)
		_lista = UITheme.vbox(8)
		sc.add_child(_lista)
		_preencher_lista()

	# ---- coluna direita: leitor ----
	var dir := VBoxContainer.new()
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir.add_theme_constant_override("separation", 8)
	raiz.add_child(dir)
	var sc2 := UITheme.scroll()
	sc2.name = "LeitorScroll"
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dir.add_child(sc2)
	_leitor = UITheme.vbox(12)
	sc2.add_child(_leitor)

	if _erro != "":
		_leitor.add_child(UITheme.card_info("SEM ARTIGOS", _erro, UITheme.PERIGO, 14))
	elif not ARTIGOS.is_empty():
		_abrir_artigo(0)


func _atualizar_contagem() -> void:
	if _lbl_contagem == null:
		return
	_lbl_contagem.text = "%d ARTIGOS DA SEMANA  ·  SE %d / ANO %d" % [
		ARTIGOS.size(), int(GameState.semana), int(GameState.ano)]


func _preencher_lista() -> void:
	if _lista == null:
		return
	for c in _lista.get_children():
		c.queue_free()
	for i in range(ARTIGOS.size()):
		_lista.add_child(_botao_artigo(i))


func _botao_artigo(i: int) -> Button:
	var a: Dictionary = ARTIGOS[i]
	var lido := GameState.artigos_lidos.has(str(a["id"]))
	var b := UITheme.botao(("* " if lido else "") + "%d. %s" % [i + 1, _titulo_lista(a)],
		_abrir_artigo.bind(i), null, UITheme.SUCESSO if lido else UITheme.BORDA)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 78)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = _titulo(a) + "\n" + str(a["autores_exibicao"]) + "\nDOI: " + str(a["doi"])
	if _tem_traducao(a):
		b.tooltip_text += "\nTraducao PT-BR; texto original no DOI."
	return b


func _titulo(a: Dictionary) -> String:
	# A Revista mostra a traducao por padrao. O titulo original continua
	# disponivel na citacao e no artigo aberto pelo DOI.
	if _tem_traducao(a) and str(a.get("titulo_pt", "")).strip_edges() != "":
		return str(a["titulo_pt"])
	return str(a.get("titulo", ""))


func _tem_traducao(a: Dictionary) -> bool:
	return str(a.get("titulo_pt", "")).strip_edges() != "" \
		and str(a.get("resumo_pt", "")).strip_edges() != ""


func _titulo_lista(a: Dictionary) -> String:
	var t := _titulo(a)
	if t.length() > 88:
		t = t.substr(0, 85).strip_edges() + "..."
	return t


func _abrir_artigo(i: int) -> void:
	if i < 0 or i >= ARTIGOS.size():
		return
	_artigo_atual = i
	for c in _leitor.get_children():
		c.queue_free()
	var a: Dictionary = ARTIGOS[i]
	var lido := GameState.artigos_lidos.has(str(a["id"]))
	var traduzido := _tem_traducao(a)

	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 10)
	topo.add_child(UITheme.rotulo(str(a.get("tema", "")).to_upper(), 11, UITheme.ACENTO))
	topo.add_child(UITheme.rotulo(str(int(a.get("ano", 0))), 11, UITheme.TEXTO_DIM))
	if lido:
		topo.add_child(UITheme.rotulo("LIDO", 11, UITheme.SUCESSO))
	if traduzido:
		var selo := UITheme.badge("TRADUZIDO", UITheme.INFO, 10)
		selo.tooltip_text = "Traducao PT-BR. O artigo original abre pelo DOI."
		topo.add_child(selo)
	_leitor.add_child(topo)

	var tit := UITheme.paragrafo(str(a["titulo_pt"]) if traduzido else str(a.get("titulo", "")),
		24, UITheme.TEXTO)
	tit.add_theme_font_override("font", UITheme.corpo(700))
	tit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_leitor.add_child(tit)

	var autores := UITheme.paragrafo("Autores: " + str(a.get("autores_exibicao", "")),
		13, UITheme.TEXTO_DIM)
	_leitor.add_child(autores)

	var local := UITheme.paragrafo("Periodico: " + _publicacao(a), 13, UITheme.TEXTO_FRACO)
	_leitor.add_child(local)

	var doi := UITheme.paragrafo("DOI: " + str(a.get("doi", "")), 13, UITheme.INFO)
	_leitor.add_child(doi)

	var acoes := HFlowContainer.new()
	acoes.add_theme_constant_override("h_separation", 10)
	acoes.add_theme_constant_override("v_separation", 8)
	_leitor.add_child(acoes)
	acoes.add_child(UITheme.botao("Abrir original no DOI", _abrir_doi, null, UITheme.INFO))
	acoes.add_child(UITheme.botao("Copiar citacao", _copiar_citacao, null, UITheme.BORDA))
	acoes.add_child(UITheme.botao("Marcar como lido (+20)", _marcar_lido, null, UITheme.SUCESSO))

	var resumo := UITheme.card(
		"RESUMO TRADUZIDO (FONTE: PUBMED)" if traduzido else "RESUMO DO ARTIGO (FONTE: PUBMED)",
		UITheme.INFO)
	_leitor.add_child(resumo)
	var cr := UITheme.conteudo(resumo)
	var secoes_pt: Array = a.get("secoes_pt", [])
	var usar_pt := traduzido and not secoes_pt.is_empty()
	var secoes: Array = secoes_pt if usar_pt else a.get("secoes", [])
	var tem_rotulo := false
	for s in secoes:
		var chave_rot := "rotulo_pt" if usar_pt else "rotulo"
		if str((s as Dictionary).get(chave_rot, "")) != "":
			tem_rotulo = true
	if tem_rotulo:
		for s in secoes:
			var chave_rot := "rotulo_pt" if usar_pt else "rotulo"
			var rot := str((s as Dictionary).get(chave_rot, ""))
			if not usar_pt:
				rot = _rotulo_secao(rot)
			if rot != "":
				cr.add_child(UITheme.rotulo(rot.to_upper(), 11, UITheme.ACENTO_2))
			var chave_txt := "texto_pt" if usar_pt else "texto"
			cr.add_child(_texto(str((s as Dictionary).get(chave_txt, ""))))
	else:
		cr.add_child(_texto(str(a.get("resumo_pt", "")) if traduzido else str(a.get("resumo", ""))))

	var metadados := UITheme.card("FONTE E METADADOS", UITheme.ACENTO_2)
	_leitor.add_child(metadados)
	var cm := UITheme.conteudo(metadados)
	cm.add_child(_linha_fonte("Base", "PubMed / NLM"))
	cm.add_child(_linha_fonte("PMID", str(a.get("pmid", ""))))
	cm.add_child(_linha_fonte("DOI", str(a.get("doi", "")), UITheme.INFO))
	cm.add_child(_linha_fonte("Tipo", str(a.get("desenho", "Artigo"))))
	if traduzido:
		cm.add_child(_linha_fonte("Idioma", "Traduzido do ingles; original no DOI",
			UITheme.INFO))

	var guia := UITheme.card("ROTEIRO DE LEITURA CRITICA", UITheme.ROXO)
	_leitor.add_child(guia)
	var cg := UITheme.conteudo(guia)
	cg.add_child(UITheme.paragrafo(
		"Leia o resumo com estas perguntas em mente. O texto completo esta no DOI.",
		12, UITheme.TEXTO_FRACO))
	for pergunta in [
		"Qual e a pergunta e o desenho do estudo?",
		"Quem foi incluido e como foi selecionado?",
		"Qual medida de efeito e qual incerteza foram reportadas?",
		"Quais limitacoes os autores reconhecem?",
	]:
		cg.add_child(UITheme.paragrafo("- " + str(pergunta), 13, UITheme.TEXTO))


func _data_consulta() -> String:
	if _todos.is_empty():
		return "PubMed/NLM"
	var iso := str(_todos[0].get("consultado_em", ""))
	var partes := iso.split("-")
	if partes.size() == 3:
		return "%s/%s/%s" % [partes[2], partes[1], partes[0]]
	return iso


func _publicacao(a: Dictionary) -> String:
	var s := "%s. %d" % [str(a.get("periodico", "")), int(a.get("ano", 0))]
	var vol := str(a.get("volume", ""))
	var num := str(a.get("numero", ""))
	var pag := str(a.get("paginas", ""))
	if vol != "":
		s += ";%s" % vol
	if num != "":
		s += "(%s)" % num
	if pag != "":
		s += ":%s" % pag
	return s + "."


func _rotulo_secao(rotulo: String) -> String:
	var r := rotulo.strip_edges().to_upper()
	if ROTULOS_SECAO.has(r):
		return str(ROTULOS_SECAO[r])
	if r == "":
		return ""
	return rotulo.strip_edges().capitalize()


func _texto(t: String) -> Label:
	var l := UITheme.paragrafo(t, 15, UITheme.TEXTO)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _linha_fonte(rotulo_txt: String, valor: String, cor: Color = UITheme.TEXTO) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(UITheme.rotulo(rotulo_txt.to_upper(), 11, UITheme.TEXTO_FRACO))
	var v := UITheme.paragrafo(valor, 13, cor)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(v)
	return h


# ============================================================================
# ACOES
# ============================================================================

func _abrir_doi() -> void:
	if _artigo_atual < 0:
		return
	var doi := str(ARTIGOS[_artigo_atual].get("doi", ""))
	if not doi.begins_with("10."):
		main.mostrar_toast("DOI indisponivel para este artigo", "info")
		return
	OS.shell_open("https://doi.org/" + doi)
	main.mostrar_toast("Abrindo o artigo original no navegador", "info")


func _marcar_lido() -> void:
	if _artigo_atual < 0:
		return
	var a: Dictionary = ARTIGOS[_artigo_atual]
	var id := str(a.get("id", ""))
	if GameState.artigos_lidos.has(id):
		main.mostrar_toast("Este artigo ja foi contabilizado", "info")
		return
	GameState.registrar_artigo(id)
	main.mostrar_toast("Artigo lido: +20 BioMoedas", "sucesso")
	_preencher_lista()
	_abrir_artigo(_artigo_atual)


func _copiar_citacao() -> void:
	if _artigo_atual < 0:
		return
	var a: Dictionary = ARTIGOS[_artigo_atual]
	var autores: Array = a.get("autores", [])
	var autores_txt := str(a.get("autores_exibicao", ""))
	if not autores.is_empty():
		autores_txt = ", ".join(autores)
	var cit := "%s. %s. %s DOI: %s. PMID: %s." % [
		autores_txt, str(a.get("titulo", "")), _publicacao(a),
		str(a.get("doi", "")), str(a.get("pmid", ""))]
	DisplayServer.clipboard_set(cit)
	main.mostrar_toast("Citacao copiada com DOI e PMID", "info")
