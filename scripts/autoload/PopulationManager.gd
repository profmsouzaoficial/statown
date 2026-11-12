extends Node
## PopulationManager - microdados sinteticos das 41.650 pessoas do Vale.
##
## Cada individuo e um indice em arrays paralelos (estrutura "array of
## structs" achatada), o que mantem ~2 MB de memoria e permite varrer a
## populacao inteira em ~10 ms por semana epidemiologica.
##
## Alem de alimentar a simulacao, este e o "banco de dados" que o aluno
## amostra no Laboratorio de Bioestatistica: todas as variaveis descritas na
## secao 3.2 da especificacao existem aqui.

signal populacao_alterada()

const ESTADO_SUSCETIVEL := 0
const ESTADO_EXPOSTO := 1
const ESTADO_INFECTADO := 2
const ESTADO_RECUPERADO := 3
const ESTADO_OBITO := 4

const ESTADO_NOMES := ["Suscetivel", "Exposto", "Infectado", "Recuperado", "Obito"]

# --- Microdados (arrays paralelos) -----------------------------------------
var _vila := PackedByteArray()
var _idade := PackedFloat32Array()
var _renda := PackedFloat32Array()
var _sexo := PackedByteArray()          # 0 = Feminino, 1 = Masculino
var _escolaridade := PackedByteArray()  # 0 Fundamental, 1 Medio, 2 Superior
var _saneamento := PackedByteArray()    # 0/1
var _doses := PackedByteArray()         # 0/1/2
var _estado := PackedByteArray()
var _tempo_estado := PackedFloat32Array()
var _biomarcador := PackedFloat32Array()
var _dias_sintomas := PackedInt32Array()
var _risco := PackedFloat32Array()      # risco latente de hospitalizacao 0..1
var _vivo := PackedByteArray()

var total: int = 0
var rng := RandomNumberGenerator.new()
var _seed_base: int = 20261104
var gerado := false

# Faixas usadas em toda a interface
const VARIAVEIS := [
	{"id": "idade", "rotulo": "Idade (anos)", "tipo": "quantitativa_continua", "unidade": "anos"},
	{"id": "renda_familiar_sm", "rotulo": "Renda familiar (SM)", "tipo": "quantitativa_continua", "unidade": "SM"},
	{"id": "biomarcador_clinico", "rotulo": "Biomarcador clinico", "tipo": "quantitativa_continua", "unidade": ""},
	{"id": "dias_sintomas", "rotulo": "Dias com sintomas", "tipo": "quantitativa_discreta", "unidade": "dias"},
	{"id": "doses_vacina", "rotulo": "Doses de vacina", "tipo": "quantitativa_discreta", "unidade": "doses"},
	{"id": "faixa_etaria", "rotulo": "Faixa etaria", "tipo": "qualitativa_ordinal", "unidade": ""},
	{"id": "genero", "rotulo": "Genero", "tipo": "qualitativa_nominal", "unidade": ""},
	{"id": "escolaridade", "rotulo": "Escolaridade", "tipo": "qualitativa_ordinal", "unidade": ""},
	{"id": "estrato_renda", "rotulo": "Estrato de renda", "tipo": "qualitativa_ordinal", "unidade": ""},
	{"id": "status_vacinal", "rotulo": "Status vacinal", "tipo": "qualitativa_ordinal", "unidade": ""},
	{"id": "estado_epidemiologico", "rotulo": "Estado epidemiologico", "tipo": "qualitativa_nominal", "unidade": ""},
	{"id": "saneamento_domiciliar", "rotulo": "Saneamento domiciliar", "tipo": "qualitativa_nominal", "unidade": ""},
	{"id": "vila_nome", "rotulo": "Vila", "tipo": "qualitativa_nominal", "unidade": ""},
]


func _ready() -> void:
	Vilas.carregar()
	gerar()


# ============================================================================
# GERACAO DOS MICRODADOS
# ============================================================================

func gerar(seed_val: int = 0) -> void:
	if seed_val != 0:
		_seed_base = seed_val
	rng.seed = _seed_base
	_vila = PackedByteArray()
	_idade = PackedFloat32Array()
	_renda = PackedFloat32Array()
	_sexo = PackedByteArray()
	_escolaridade = PackedByteArray()
	_saneamento = PackedByteArray()
	_doses = PackedByteArray()
	_estado = PackedByteArray()
	_tempo_estado = PackedFloat32Array()
	_biomarcador = PackedFloat32Array()
	_dias_sintomas = PackedInt32Array()
	_risco = PackedFloat32Array()
	_vivo = PackedByteArray()

	for v in Vilas.vilas:
		var vid := int(v["id"])
		var n := int(v["populacao_inicial"])
		var renda_media: float = float(v["renda_media_sm"])
		var san: float = float(v["saneamento_base"])
		var cob: float = float(v["cobertura_base"])
		# parametros da log-normal: media desejada = renda_media
		var sigma := 0.62
		var mu := log(maxf(renda_media, 0.2)) - sigma * sigma * 0.5
		var p_superior := clampf(0.04 + 0.12 * renda_media / 5.0, 0.02, 0.40)
		var p_medio := clampf(0.26 + 0.14 * renda_media / 5.0, 0.20, 0.55)
		for _k in range(n):
			var idade := _sortear_idade()
			_vila.append(vid)
			_idade.append(idade)
			_renda.append(clampf(exp(mu + sigma * _gauss()), 0.05, 30.0))
			_sexo.append(1 if rng.randf() < 0.495 else 0)
			# escolaridade: mais velhos com menos escolaridade formal
			var ajuste_idade := 1.0 if idade < 40.0 else (0.72 if idade < 60.0 else 0.45)
			var u := rng.randf()
			if u < p_superior * ajuste_idade:
				_escolaridade.append(2)
			elif u < p_superior * ajuste_idade + p_medio * ajuste_idade:
				_escolaridade.append(1)
			else:
				_escolaridade.append(0)
			_saneamento.append(1 if rng.randf() < san else 0)
			var ud := rng.randf()
			if ud < cob * 0.86:
				_doses.append(2)
			elif ud < cob:
				_doses.append(1)
			else:
				_doses.append(0)
			_estado.append(ESTADO_SUSCETIVEL)
			_tempo_estado.append(0.0)
			_biomarcador.append(0.0)
			_dias_sintomas.append(0)
			_risco.append(_calcular_risco(idade, san, renda_media))
			_vivo.append(1)
	total = _idade.size()
	gerado = true
	_atualizar_biomarcadores()
	populacao_alterada.emit()


func _gauss() -> float:
	# Box-Muller (o rng de Godot nao tem distribuicao normal nativa)
	var u1 := maxf(rng.randf(), 1e-9)
	var u2 := rng.randf()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)


## Piramide etaria realista: 22% jovens, 62% adultos, 16% idosos com cauda.
func _sortear_idade() -> float:
	var u := rng.randf()
	if u < 0.22:
		return 14.0 * (u / 0.22) + rng.randf() * 0.999
	elif u < 0.84:
		return 15.0 + 45.0 * ((u - 0.22) / 0.62) + rng.randf() * 0.999
	var t := (u - 0.84) / 0.16
	return 60.0 + minf(42.0, -11.0 * log(maxf(1.0 - t, 1e-6))) + rng.randf() * 0.999


## Risco latente de hospitalizacao - usado pelo modulo preditivo de IA.
## E gerado por um modelo logistico "verdadeiro" + ruido, de modo que o
## classificador treinado pelo aluno possa de fato aprender algo.
func _calcular_risco(idade: float, san: float, renda_media: float) -> float:
	var z := -3.4
	z += 0.075 * idade
	if idade > 60.0:
		z += 1.15
	z += 0.85 * (1.0 - san)
	z += 0.35 * (2.5 - renda_media) * 0.5
	z += _gauss() * 0.9
	return 1.0 / (1.0 + exp(-clampf(z, -20.0, 20.0)))


func _atualizar_biomarcadores() -> void:
	var info := GameState.info_doenca()
	var mu: Dictionary = info.get("bio_mu", {})
	var sd: Dictionary = info.get("bio_sd", {})
	for i in range(total):
		if _vivo[i] == 0:
			continue
		var est := _estado[i]
		var chave := "S"
		match est:
			ESTADO_EXPOSTO: chave = "E"
			ESTADO_INFECTADO: chave = "I"
			ESTADO_RECUPERADO: chave = "R"
		var m := float(mu.get(chave, 100.0))
		var s := float(sd.get(chave, 10.0))
		_biomarcador[i] = m + s * _gauss()


# ============================================================================
# ACESSO AS VARIAVEIS
# ============================================================================

func faixa_etaria(idade: float) -> String:
	if idade < 15.0:
		return "0-14 (Jovem)"
	elif idade < 60.0:
		return "15-59 (Adulto)"
	return "60+ (Idoso)"


func estrato_renda(renda: float) -> String:
	if renda < 2.0:
		return "Baixa (< 2 SM)"
	elif renda <= 5.0:
		return "Media (2 a 5 SM)"
	return "Alta (> 5 SM)"


func escolaridade_nome(e: int) -> String:
	match e:
		0: return "Fundamental"
		1: return "Medio"
	return "Superior"


func status_vacinal(d: int) -> String:
	match d:
		0: return "Nao Vacinado"
		1: return "Parcial"
	return "Imunizado"


func nome_estado(e: int) -> String:
	return ESTADO_NOMES[clampi(e, 0, 4)]


## Retorna o valor da variavel `nome` para o individuo `i`.
func valor(i: int, nome: String):
	if i < 0 or i >= total:
		return null
	match nome:
		"idade": return _idade[i]
		"renda_familiar_sm": return _renda[i]
		"biomarcador_clinico": return _biomarcador[i]
		"dias_sintomas": return _dias_sintomas[i]
		"doses_vacina": return _doses[i]
		"faixa_etaria": return faixa_etaria(_idade[i])
		"genero": return "Masculino" if _sexo[i] == 1 else "Feminino"
		"escolaridade": return escolaridade_nome(_escolaridade[i])
		"estrato_renda": return estrato_renda(_renda[i])
		"status_vacinal": return status_vacinal(_doses[i])
		"estado_epidemiologico": return nome_estado(_estado[i])
		"saneamento_domiciliar": return "Sim" if _saneamento[i] == 1 else "Nao"
		"vila_nome": return str(Vilas.get_vila(_vila[i]).get("nome", "?"))
	return null


func vila_de(i: int) -> int:
	return int(_vila[i]) if i >= 0 and i < total else 0


func estado_de(i: int) -> int:
	return int(_estado[i]) if i >= 0 and i < total else ESTADO_OBITO


func idade_de(i: int) -> float:
	return _idade[i] if i >= 0 and i < total else 0.0


func risco_de(i: int) -> float:
	return _risco[i] if i >= 0 and i < total else 0.0


func doses_de(i: int) -> int:
	return int(_doses[i]) if i >= 0 and i < total else 0


func vivo_de(i: int) -> bool:
	return _vivo[i] == 1 if i >= 0 and i < total else false


func indice_de(i: int) -> int:
	return i


# --- Escrita controlada (usada pelo EpidemicManager) -----------------------

func set_estado(i: int, e: int) -> void:
	if i >= 0 and i < total:
		_estado[i] = e
		if e == ESTADO_OBITO:
			_vivo[i] = 0


func tempo_no_estado(i: int) -> float:
	return _tempo_estado[i] if i >= 0 and i < total else 0.0


func set_tempo_no_estado(i: int, t: float) -> void:
	if i >= 0 and i < total:
		_tempo_estado[i] = t


func dias_sintomas_de(i: int) -> int:
	return _dias_sintomas[i] if i >= 0 and i < total else 0


func set_dias_sintomas(i: int, d: int) -> void:
	if i >= 0 and i < total:
		_dias_sintomas[i] = d


func set_biomarcador(i: int, v: float) -> void:
	if i >= 0 and i < total:
		_biomarcador[i] = v


func reamostrar_biomarcadores() -> void:
	_atualizar_biomarcadores()


func gauss() -> float:
	return _gauss()


# ============================================================================
# CONTAGENS AGREGADAS
# ============================================================================

func contar_por_estado(vila_id: int) -> PackedInt32Array:
	var c := PackedInt32Array([0, 0, 0, 0, 0])
	for i in range(total):
		if _vila[i] != vila_id:
			continue
		c[_estado[i]] += 1
	return c


func vivos_em(vila_id: int) -> int:
	var n := 0
	for i in range(total):
		if _vila[i] == vila_id and _vivo[i] == 1:
			n += 1
	return n


func indices_da_vila(vila_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(total):
		if _vila[i] == vila_id:
			out.append(i)
	return out


func indices_por_estado(vila_id: int, estado: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(total):
		if _vila[i] == vila_id and _estado[i] == estado:
			out.append(i)
	return out


## Todas as pessoas vivas (para amostragem global).
func indices_vivos() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(total):
		if _vivo[i] == 1:
			out.append(i)
	return out


# ============================================================================
# AMOSTRAGEM
# ============================================================================

## Amostragem aleatoria simples (AAS) dentro de uma vila ou global (vila_id=0).
func amostrar(n: int, vila_id: int = 0, seed_val: int = 0) -> PackedInt32Array:
	var pool := indices_da_vila(vila_id) if vila_id > 0 else indices_vivos()
	return StatCore.sample_simple_random(pool, n, seed_val)


func amostrar_sistematica(n: int, vila_id: int = 0, seed_val: int = 0) -> PackedInt32Array:
	var pool := indices_da_vila(vila_id) if vila_id > 0 else indices_vivos()
	return StatCore.sample_systematic(pool, n, seed_val)


## Amostragem estratificada por faixa etaria.
func amostrar_estratificada(n: int, vila_id: int = 0, seed_val: int = 0) -> Dictionary:
	var estratos := {}
	for faixa in ["0-14 (Jovem)", "15-59 (Adulto)", "60+ (Idoso)"]:
		var ids := PackedInt32Array()
		for i in range(total):
			if vila_id > 0 and _vila[i] != vila_id:
				continue
			if _vivo[i] == 0:
				continue
			if faixa_etaria(_idade[i]) == faixa:
				ids.append(i)
		estratos[faixa] = ids
	return StatCore.sample_stratified(estratos, n, seed_val)


## Amostragem por conglomerados: sorteia vilas e depois individuos nelas.
func amostrar_conglomerados(n_vilas: int, n_por_vila: int, seed_val: int = 0) -> Dictionary:
	var ids_vilas := PackedInt32Array()
	for v in Vilas.vilas:
		ids_vilas.append(int(v["id"]))
	var sorteadas := StatCore.sample_simple_random(ids_vilas, n_vilas, seed_val)
	var out := PackedInt32Array()
	var detalhe := {}
	for vid in sorteadas:
		var s := amostrar(n_por_vila, vid, seed_val + vid)
		for i in s:
			out.append(i)
		detalhe[str(vid)] = s.size()
	return {"indices": out, "vilas": sorteadas, "detalhe": detalhe}


# ============================================================================
# TABELAS PARA A INTERFACE / CSV
# ============================================================================

func tabela(indices: PackedInt32Array, colunas: PackedStringArray = PackedStringArray()) -> Array:
	var cols := colunas
	if cols.is_empty():
		cols = PackedStringArray(["id", "vila_nome", "idade", "faixa_etaria", "genero",
			"renda_familiar_sm", "estrato_renda", "escolaridade", "saneamento_domiciliar",
			"status_vacinal", "estado_epidemiologico", "biomarcador_clinico", "dias_sintomas"])
	var rows: Array = []
	for i in indices:
		var row := {}
		for c in cols:
			if c == "id":
				row[c] = i + 1
			else:
				row[c] = valor(i, c)
		rows.append(row)
	return rows


func gerar_csv(indices: PackedInt32Array, colunas: PackedStringArray = PackedStringArray()) -> String:
	var cols := colunas
	if cols.is_empty():
		cols = PackedStringArray(["id", "vila_nome", "idade", "faixa_etaria", "genero",
			"renda_familiar_sm", "estrato_renda", "escolaridade", "saneamento_domiciliar",
			"status_vacinal", "estado_epidemiologico", "biomarcador_clinico", "dias_sintomas"])
	var linhas := PackedStringArray()
	linhas.append(",".join(cols))
	for row in tabela(indices, cols):
		var campos := PackedStringArray()
		for c in cols:
			var v = row[c]
			if typeof(v) == TYPE_FLOAT:
				campos.append("%.4f" % float(v))
			else:
				campos.append(str(v))
		linhas.append(",".join(campos))
	return "\n".join(linhas)


## Extrai um vetor numerico (usado pelo laboratorio e pelos testes).
func vetor_numerico(indices: PackedInt32Array, nome: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(indices.size())
	for k in range(indices.size()):
		var v = valor(indices[k], nome)
		out[k] = float(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else 0.0
	return out


func vetor_categorico(indices: PackedInt32Array, nome: String) -> PackedStringArray:
	var out := PackedStringArray()
	for i in indices:
		out.append(str(valor(i, nome)))
	return out


# ============================================================================
# CICLO DE VIDA
# ============================================================================

## Nascimentos, envelhecimento e mortalidade natural (secao 3.3 da especificacao).
func avancar_semana() -> void:
	var nascidos := 0
	var mortos_por_vila := {}
	for i in range(total):
		if _vivo[i] == 0:
			continue
		_idade[i] += 1.0 / 52.0
		# mortalidade de Gompertz-Makeham simplificada
		var a := _idade[i]
		var p_morte := 1.0 - exp(-(0.0007 + 0.000028 * exp(0.084 * a)) / 52.0)
		var vid := int(_vila[i])
		var v := Vilas.get_vila(vid)
		if int(v.get("ubs", 0)) > 0:
			p_morte *= 0.82
		if float(v.get("saneamento", 0.5)) > 0.8:
			p_morte *= 0.92
		if rng.randf() < p_morte:
			_vivo[i] = 0
			_estado[i] = ESTADO_OBITO
			# mortes naturais sao contabilizadas por vila (nunca o total global
			# em todas as vilas): o painel separa obito natural de obito pela doenca
			mortos_por_vila[vid] = int(mortos_por_vila.get(vid, 0)) + 1
	var mortos := 0
	for v in Vilas.vilas:
		var vid := int(v["id"])
		var n := 0
		for i in range(total):
			if _vila[i] == vid and _vivo[i] == 1:
				n += 1
		# natalidade inversamente modulada pela renda (0.011 a 0.022 ao ano)
		var nu := 0.022 - 0.011 * clampf(float(v["renda_media_sm"]) / 5.0, 0.0, 1.0)
		var esperado := float(n) * nu / 52.0
		var k := _poisson(esperado)
		for _b in range(k):
			_nascer(vid)
			nascidos += 1
		v["populacao"] = n + k
		v["nascimentos"] = int(v["nascimentos"]) + k
		var mortos_v := int(mortos_por_vila.get(vid, 0))
		mortos += mortos_v
		v["obitos_naturais"] = int(v["obitos_naturais"]) + mortos_v
	if nascidos > 0 or mortos > 0:
		populacao_alterada.emit()


func _nascer(vila_id: int) -> void:
	var v := Vilas.get_vila(vila_id)
	_vila.append(vila_id)
	_idade.append(0.0)
	var renda_media: float = float(v.get("renda_media_sm", 2.0))
	var sigma := 0.62
	var mu := log(maxf(renda_media, 0.2)) - sigma * sigma * 0.5
	_renda.append(clampf(exp(mu + sigma * _gauss()), 0.05, 30.0))
	_sexo.append(1 if rng.randf() < 0.495 else 0)
	_escolaridade.append(0)
	_saneamento.append(1 if rng.randf() < float(v.get("saneamento", 0.5)) else 0)
	_doses.append(0)
	_estado.append(ESTADO_SUSCETIVEL)
	_tempo_estado.append(0.0)
	_biomarcador.append(0.0)
	_dias_sintomas.append(0)
	_risco.append(_calcular_risco(0.0, float(v.get("saneamento", 0.5)), renda_media))
	_vivo.append(1)
	total += 1


func _poisson(lam: float) -> int:
	if lam <= 0.0:
		return 0
	if lam > 30.0:
		return int(round(lam + sqrt(lam) * _gauss()))
	var L := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		k += 1
		p *= rng.randf()
		if p <= L:
			break
	return k - 1


# ============================================================================
# PERSISTENCIA
# ============================================================================

## Salva apenas os agregados (estado por vila) e a semente; ao carregar, os
## estados individuais sao reconstruidos de forma deterministica.
func serializar() -> Dictionary:
	var agg := {}
	for v in Vilas.vilas:
		var c := contar_por_estado(int(v["id"]))
		agg[str(v["id"])] = [c[0], c[1], c[2], c[3], c[4]]
	return {"seed": _seed_base, "total": total, "estados": agg}


func deserializar(d: Dictionary) -> void:
	if d.is_empty():
		return
	var seed_val := int(d.get("seed", _seed_base))
	gerar(seed_val)
	var estados: Dictionary = d.get("estados", {})
	for vid in estados:
		var c: Array = estados[vid]
		var precisa := 0
		for est in range(c.size()):
			precisa += int(c[est])
		# o save guarda nascimentos: recria os individuos que nasceram depois da
		# geracao inicial, senao o denominador (populacao) ficaria maior que o
		# numero de agentes e a prevalencia sairia subestimada apos carregar.
		var ids := indices_da_vila(int(vid))
		while ids.size() < precisa:
			_nascer(int(vid))
			ids = indices_da_vila(int(vid))
		var pos := 0
		for est in range(5):
			var qtd := int(c[est]) if est < c.size() else 0
			for _k in range(qtd):
				if pos < ids.size():
					_estado[ids[pos]] = est
					_vivo[ids[pos]] = 0 if est == ESTADO_OBITO else 1
					pos += 1
	populacao_alterada.emit()


func reiniciar() -> void:
	gerar(_seed_base)
