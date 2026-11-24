extends Node
## Valida a base offline da Revista Cientifica do Vale.
##
## A base e curada a partir do PubMed/NLM; este teste nao tenta provar que um
## artigo existe (isso exige rede), mas garante o contrato minimo que o painel
## usa: 50 registros, 10 por area, identificadores unicos, DOI/PMID, autores,
## periodo, resumo e metadados de fonte.

const CAMINHO := "res://data/revista_artigos.json"
const TEMAS := ["Bioestatistica", "Epidemiologia e surtos", "Farmacia",
	"Fisioterapia", "Odontologia"]
const ANO_MIN := 2021
const ANO_MAX := 2026

var falhas: Array[String] = []
var checks := 0


func _ready() -> void:
	var dados = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO))
	_ok(dados is Array, "base e um array JSON")
	if not (dados is Array):
		_fim()
		return
	var artigos: Array = dados
	_ok(artigos.size() == 50, "base tem 50 artigos (tem %d)" % artigos.size())

	var ids := {}
	var pmids := {}
	var dois := {}
	var titulos := {}
	var titulos_pt := {}
	var por_tema := {}
	for item in artigos:
		_ok(item is Dictionary, "registro e dicionario")
		if not (item is Dictionary):
			continue
		var a: Dictionary = item
		var id := str(a.get("id", ""))
		var pmid := str(a.get("pmid", ""))
		var doi := str(a.get("doi", ""))
		var titulo := str(a.get("titulo", ""))
		var tema := str(a.get("tema", ""))
		var ano := int(a.get("ano", 0))

		_ok(id == "pmid_" + pmid, "id bate com PMID: " + id)
		_ok(pmid.is_valid_int() and pmid.length() >= 7, "PMID plausivel: " + id)
		_ok(doi.begins_with("10."), "DOI com prefixo 10.: " + id)
		_ok(str(a.get("url", "")) == "https://doi.org/" + doi, "URL do DOI: " + id)
		_ok(not ids.has(id), "id unico: " + id)
		_ok(not pmids.has(pmid), "PMID unico: " + pmid)
		_ok(not dois.has(doi), "DOI unico: " + doi)
		_ok(not titulos.has(titulo), "titulo unico: " + id)
		ids[id] = true
		pmids[pmid] = true
		dois[doi] = true
		titulos[titulo] = true

		_ok(titulo.length() >= 20, "titulo preenchido: " + id)
		_ok(a.get("autores") is Array and (a.get("autores") as Array).size() >= 1,
			"autores preenchidos: " + id)
		_ok(str(a.get("autores_exibicao", "")) != "", "autores de exibicao: " + id)
		_ok(str(a.get("periodico", "")) != "", "periodico preenchido: " + id)
		_ok(ano >= ANO_MIN and ano <= ANO_MAX, "ano recente (%d): %s" % [ano, id])
		_ok(str(a.get("resumo", "")).length() >= 300, "resumo com corpo: " + id)
		_ok(a.get("secoes") is Array and not (a.get("secoes") as Array).is_empty(),
			"resumo estruturado: " + id)

		# Contrato da traducao: a Revista abre em PT-BR, mas o original
		# continua no JSON e e o unico texto usado na citacao/DOI.
		var titulo_pt := str(a.get("titulo_pt", ""))
		var resumo_pt := str(a.get("resumo_pt", ""))
		_ok(titulo_pt.length() >= 20, "titulo traduzido: " + id)
		_ok(titulo_pt != titulo, "titulo traduzido difere do original: " + id)
		_ok(not titulos_pt.has(titulo_pt), "titulo traduzido unico: " + id)
		titulos_pt[titulo_pt] = true
		_ok(resumo_pt.length() >= 300, "resumo traduzido com corpo: " + id)
		_ok(resumo_pt != str(a.get("resumo", "")), "resumo traduzido difere do original: " + id)
		var secoes_orig: Array = a.get("secoes", [])
		var secoes_pt: Array = a.get("secoes_pt", [])
		_ok(secoes_pt.size() == secoes_orig.size(),
			"secoes traduzidas mantem a estrutura: " + id)
		for si in range(mini(secoes_pt.size(), secoes_orig.size())):
			var sp: Dictionary = secoes_pt[si]
			var so: Dictionary = secoes_orig[si]
			var rot_pt := str(sp.get("rotulo_pt", ""))
			_ok(str(sp.get("texto_pt", "")).length() >= 20,
				"texto traduzido da secao %d: %s" % [si, id])
			_ok(rot_pt == "" or not _tem_acento(rot_pt),
				"rotulo traduzido sem acento: %s/%d" % [id, si])
			var rot_ok := (rot_pt == "") if str(so.get("rotulo", "")) == "" else (rot_pt != "")
			_ok(rot_ok, "rotulo traduzido presente: %s/%d" % [id, si])
		_ok(str(a.get("tipo", "")) != "" and str(a.get("desenho", "")) != "",
			"tipo/desenho: " + id)
		_ok(str(a.get("fonte", "")) == "PubMed / NLM", "fonte PubMed: " + id)
		_ok(str(a.get("consultado_em", "")).length() == 10, "data de consulta: " + id)
		_ok(tema in TEMAS, "tema conhecido: " + id)
		por_tema[tema] = int(por_tema.get(tema, 0)) + 1

	for tema in TEMAS:
		_ok(int(por_tema.get(tema, 0)) == 10, "10 artigos em " + tema)

	_fim()


func _tem_acento(t: String) -> bool:
	for i in range(t.length()):
		if t.unicode_at(i) > 127:
			return true
	return false


func _ok(cond: bool, nome: String) -> void:
	checks += 1
	if not cond:
		falhas.append(nome)


func _fim() -> void:
	print("\nREVISTA: %d verificacoes, %d falhas" % [checks, falhas.size()])
	for f in falhas:
		print("  FALHA: ", f)
	get_tree().quit(0 if falhas.is_empty() else 1)
