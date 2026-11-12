extends Node
## EpidemicManager - motor epidemiologico SEIR em nivel individual.
##
## A cada Semana Epidemiologica o motor:
##   1. calcula a forca de infeccao de cada vila (transmissao interna +
##      importada pela matriz de mobilidade pendular);
##   2. sorteia transicoes SARS-CoV-2 S->E->I->R->D pessoa a pessoa,
##      respeitando idade, doses de vacina, saneamento e capacidade de leitos;
##   3. atualiza contadores agregados, historico e indicadores (Rt, CFR).
##
## Como a transicao e individual, o aluno pode fazer perguntas reais aos
## dados: "quantos idosos nao vacinados adoeceram na Vila 17?".

signal atualizado()
signal surto_iniciado(vila_id: int, casos: int)
signal surto_encerrado(vila_id: int)
signal obito_registrado(vila_id: int)

var rng := RandomNumberGenerator.new()
var doencas: Dictionary = {}          # id -> parametros
var ativos := {}                      # vila_id -> {surtos, semanas_sem_caso}
var em_surto := {}                    # vila_id -> bool

# Historico global (uma entrada por SE)
var hist_se := PackedInt32Array()
var hist_casos := PackedInt32Array()
var hist_obitos := PackedInt32Array()
var hist_prevalencia := PackedFloat32Array()
var hist_recuperados := PackedInt32Array()
var hist_rt := PackedFloat32Array()
var hist_vacinados := PackedInt32Array()

var obitos_total := 0
var casos_total := 0
var obitos_semana := 0
var casos_semana := 0
var recuperados_total := 0
var _casos_anterior := 1


func _ready() -> void:
	rng.seed = 777_001
	_carregar_doencas()
	Vilas.carregar()
	_semear()


func _carregar_doencas() -> void:
	var f := FileAccess.open("res://data/doencas.json", FileAccess.READ)
	if f == null:
		push_error("EpidemicManager: data/doencas.json ausente")
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return
	for item in d.get("doencas", []):
		doencas[str(item["id"])] = item


# ============================================================================
# CONSULTAS BASICAS
# ============================================================================

func info_doenca(id: String = "") -> Dictionary:
	var k := id if id != "" else GameState.doenca_id
	return doencas.get(k, {})


func nome_doenca(id: String = "") -> String:
	return str(info_doenca(id).get("nome", "Agravo"))


func cor_doenca(id: String = "") -> Color:
	return Color(str(info_doenca(id).get("cor", "#e0574a")))


func ids_doencas() -> Array:
	return doencas.keys()


func infectados(vila_id: int) -> int:
	var c := Population.contar_por_estado(vila_id)
	return c[Population.ESTADO_INFECTADO] + c[Population.ESTADO_EXPOSTO]


func infectosos(vila_id: int) -> int:
	return Population.contar_por_estado(vila_id)[Population.ESTADO_INFECTADO]


## Obitos ATRIBUIDOS A DOENCA na vila. O estado "Obito" do PopulationManager
## tambem recebe as mortes naturais do ciclo de vida (Gompertz-Makeham); por isso
## descontamos `obitos_naturais`, que o registro da vila acumula por semana.
## Sem esse desconto a letalidade estourava 100% em vilas pequenas.
func obitos(vila_id: int) -> int:
	var c := Population.contar_por_estado(vila_id)
	var brutos := int(c[Population.ESTADO_OBITO])
	var naturais := int(Vilas.get_vila(vila_id).get("obitos_naturais", 0))
	return maxi(0, brutos - naturais)


func recuperados(vila_id: int) -> int:
	return Population.contar_por_estado(vila_id)[Population.ESTADO_RECUPERADO]


func suscetiveis(vila_id: int) -> int:
	return Population.contar_por_estado(vila_id)[Population.ESTADO_SUSCETIVEL]


func prevalencia(vila_id: int) -> float:
	var v := Vilas.get_vila(vila_id)
	var n := maxi(int(v.get("populacao", 1)), 1)
	# prevalencia e uma PROPORCAO: por definicao fica em [0,1]. O clamp e uma
	# rede de seguranca (vila recem-carregada, denominador defasado) para que a
	# interface nunca exiba "prevalencia 137%".
	return clampf(float(infectados(vila_id)) / float(n), 0.0, 1.0)


func incidencia_semana(vila_id: int) -> int:
	var hist := Vilas.historico(vila_id)
	if hist.is_empty():
		return 0
	return int(hist[hist.size() - 1].get("novos", 0))


func rt(vila_id: int) -> float:
	var h := Vilas.historico(vila_id)
	if h.size() < 3:
		return 0.0
	var a := int(h[h.size() - 1].get("novos", 0))
	var b := int(h[h.size() - 2].get("novos", 0))
	if b <= 0:
		return 0.0 if a <= 0 else 3.0
	var g := maxf(0.6, float(info_doenca().get("incubacao_se", 1.0)) + float(info_doenca().get("infeccioso_se", 1.5)))
	return clampf(pow(float(a) / float(b), 1.0 / g), 0.0, 6.0)


func estatisticas_globais() -> Dictionary:
	var pop := 0
	var inf := 0
	var rec := 0
	var ob := 0
	for v in Vilas.vilas:
		var id := int(v["id"])
		pop += int(v["populacao"])
		inf += infectados(id)
		rec += recuperados(id)
		ob += obitos(id)
	# numerador e denominador da letalidade vem do MESMO universo: obitos pela
	# doenca / casos diagnosticados. Sem o clamp, uma vila com mais obitos
	# acumulados do que casos da semana podia exibir letalidade > 100%.
	var let := 0.0
	if casos_total > 0:
		let = clampf(float(ob) / float(casos_total), 0.0, 1.0)
	return {
		"populacao_total": pop,
		"infectados_total": inf,
		"recuperados_total": rec,
		"obitos_total": ob,
		"obitos_naturais_total": _obitos_naturais_total(),
		"prevalencia": clampf(float(inf) / float(maxi(pop, 1)), 0.0, 1.0),
		"casos_total": casos_total,
		"incidencia_semana": casos_semana,
		"obitos_semana": obitos_semana,
		"letalidade": let,
	}


func _obitos_naturais_total() -> int:
	var n := 0
	for v in Vilas.vilas:
		n += int(v.get("obitos_naturais", 0))
	return n


# ============================================================================
# MOTOR
# ============================================================================

func _semear() -> void:
	# Caso indice: uma pessoa infectada na vila mais vulneravel ao agravo ativo.
	var alvo := _vila_indice(GameState.doenca_id)
	if alvo <= 0:
		return
	var ids := Population.indices_da_vila(alvo)
	if ids.is_empty():
		return
	var escolhido := ids[rng.randi_range(0, ids.size() - 1)]
	Population.set_estado(escolhido, Population.ESTADO_EXPOSTO)
	Population.set_tempo_no_estado(escolhido, 0.0)


func _vila_indice(doenca: String) -> int:
	var melhor := 0
	var score := -1.0
	for v in Vilas.vilas:
		var s := 1.0 - float(v["saneamento"])
		if doenca == "respiratoria":
			s = float(v["populacao"]) / 4000.0
		elif doenca == "cronica":
			s = 1.0 - float(v["renda_media_sm"]) / 5.2
		if s > score:
			score = s
			melhor = int(v["id"])
	return melhor


## Avanca uma semana epidemiologica completa.
func avancar_semana() -> void:
	var info := info_doenca()
	var transmissivel := bool(info.get("transmissivel", true))
	var R0 := float(info.get("R0", 2.5))
	var incub := maxf(float(info.get("incubacao_se", 1.0)), 0.15)
	var infec := maxf(float(info.get("infeccioso_se", 1.5)), 0.15)
	var beta := R0 / infec
	var saz := float(info.get("sazonalidade", 0.0))
	var peso_san := float(info.get("peso_saneamento", 0.5))
	var efic := float(info.get("eficacia_vacina", 0.6))

	# sazonalidade senoidal (pico no verao chuvoso, SE 1..52)
	var fase := TAU * float(GameState.semana - 1) / 52.0
	var fator_saz := 1.0 + saz * sin(fase - PI * 0.5) * -1.0
	fator_saz = maxf(0.25, fator_saz)

	# 1. prevalencia efetiva por vila (com mobilidade)
	var prev := PackedFloat32Array()
	prev.resize(Vilas.vilas.size())
	var pop := PackedFloat32Array()
	pop.resize(Vilas.vilas.size())
	for i in range(Vilas.vilas.size()):
		var v := Vilas.vilas[i]
		var n := maxf(float(v["populacao"]), 1.0)
		pop[i] = n
		prev[i] = float(infectosos(int(v["id"]))) / n

	var expostas := PackedFloat32Array()
	expostas.resize(Vilas.vilas.size())
	for i in range(Vilas.vilas.size()):
		if not transmissivel:
			expostas[i] = 0.0
			continue
		var num := prev[i] * pop[i]
		var den := pop[i]
		for j in range(Vilas.vilas.size()):
			if i == j:
				continue
			var comut := float(Vilas.mobilidade[j][i]) * pop[j]
			num += comut * prev[j]
			den += comut
		expostas[i] = num / maxf(den, 1.0)

	# 2. transicoes individuais
	var novos_por_vila := {}
	var obitos_por_vila := {}
	casos_semana = 0
	obitos_semana = 0
	for vi in range(Vilas.vilas.size()):
		var v := Vilas.vilas[vi]
		var vid := int(v["id"])
		var n := maxf(float(v["populacao"]), 1.0)
		novos_por_vila[vid] = 0
		obitos_por_vila[vid] = 0
		var san := float(v["saneamento"])
		var leitos := maxf(float(v["leitos"]), 1.0)
		var ocup := clampf(float(infectosos(vid)) * 0.12 / leitos, 0.0, 2.0)
		var cfr_base := float(info.get("cfr", {}).get("adulto", 0.01))
		if ocup > 1.0:
			cfr_base = float(info.get("cfr_saturado", cfr_base * 2.0))

		# forca de infeccao da vila (por semana)
		var lam := 0.0
		if transmissivel:
			var mod_san := pow(clampf(1.15 - san, 0.08, 1.2), peso_san * 1.6)
			lam = beta * expostas[vi] * fator_saz * mod_san * 1.35
		for i in range(Population.total):
			if Population.vila_de(i) != vid:
				continue
			if not Population.vivo_de(i):
				continue
			var est := Population.estado_de(i)
			var t := Population.tempo_no_estado(i)
			match est:
				Population.ESTADO_SUSCETIVEL:
					if transmissivel:
						var susc := _suscetibilidade(i, efic)
						var p := 1.0 - exp(-lam * susc)
						if p > 0.0 and rng.randf() < p:
							Population.set_estado(i, Population.ESTADO_EXPOSTO)
							Population.set_tempo_no_estado(i, 0.0)
							Population.set_dias_sintomas(i, 0)
					elif rng.randf() < _incidencia_cronica(i, v):
						Population.set_estado(i, Population.ESTADO_INFECTADO)
						Population.set_tempo_no_estado(i, 0.0)
						Population.set_dias_sintomas(i, rng.randi_range(0, 4))
						novos_por_vila[vid] += 1
				Population.ESTADO_EXPOSTO:
					Population.set_tempo_no_estado(i, t + 1.0)
					if rng.randf() < 1.0 - exp(-1.0 / incub):
						Population.set_estado(i, Population.ESTADO_INFECTADO)
						Population.set_tempo_no_estado(i, 0.0)
						var dias := 0
						var lam_sint := 4.0 if str(info.get("id", "")) == "respiratoria" else 3.0
						# Poisson(3) aproximado
						var L := exp(-lam_sint)
						var k := 0
						var pp := 1.0
						while true:
							k += 1
							pp *= rng.randf()
							if pp <= L or k > 20:
								break
						dias = k - 1
						Population.set_dias_sintomas(i, dias)
						novos_por_vila[vid] += 1
						casos_semana += 1
				Population.ESTADO_INFECTADO:
					Population.set_tempo_no_estado(i, t + 1.0)
					# obito (CFR ajustado por idade, leitos e saneamento)
					var p_cfr := _cfr_individual(i, info, vid, cfr_base, san, ocup)
					if p_cfr > 0.0 and rng.randf() < p_cfr:
						Population.set_estado(i, Population.ESTADO_OBITO)
						obitos_por_vila[vid] += 1
						obitos_semana += 1
						obito_registrado.emit(vid)
						continue
					if rng.randf() < 1.0 - exp(-1.0 / infec):
						Population.set_estado(i, Population.ESTADO_RECUPERADO)
						Population.set_tempo_no_estado(i, 0.0)
				Population.ESTADO_RECUPERADO:
					Population.set_tempo_no_estado(i, t + 1.0)
				_:
					pass

	# 3. agregados e historico
	casos_total += casos_semana
	obitos_total += obitos_semana
	recuperados_total = 0
	for vi in range(Vilas.vilas.size()):
		var v := Vilas.vilas[vi]
		var vid := int(v["id"])
		var c := Population.contar_por_estado(vid)
		recuperados_total += c[Population.ESTADO_RECUPERADO]
		var novos := int(novos_por_vila[vid])
		var prev_v := float(c[Population.ESTADO_INFECTADO] + c[Population.ESTADO_EXPOSTO]) / maxf(float(v["populacao"]), 1.0)
		Vilas.registrar_historico(vid, {
			"se": GameState.semana,
			"novos": novos,
			"infectados": c[Population.ESTADO_INFECTADO] + c[Population.ESTADO_EXPOSTO],
			"obitos": obitos(vid),
			"prevalencia": prev_v,
			"vacinados": int(round(float(v["cobertura_vacinal"]) * float(v["populacao"]))),
		})
		_checar_surto(vid, prev_v, novos)

	hist_se.append(GameState.semana)
	hist_casos.append(casos_semana)
	hist_obitos.append(obitos_semana)
	hist_prevalencia.append(float(estatisticas_globais()["prevalencia"]))
	hist_recuperados.append(recuperados_total)
	var rt_g := 0.0
	if _casos_anterior > 0:
		var g := maxf(0.6, incub + infec)
		rt_g = clampf(pow(float(casos_semana) / float(_casos_anterior), 1.0 / g), 0.0, 6.0)
	hist_rt.append(rt_g)
	var vac := 0
	for v in Vilas.vilas:
		vac += int(round(float(v["cobertura_vacinal"]) * float(v["populacao"])))
	hist_vacinados.append(vac)
	_casos_anterior = maxi(casos_semana, 1)
	_limitar_historico()

	Population.reamostrar_biomarcadores()
	atualizado.emit()


func _limitar_historico() -> void:
	var limite := 600
	if hist_se.size() > limite:
		var excesso := hist_se.size() - limite
		hist_se = hist_se.slice(excesso)
		hist_casos = hist_casos.slice(excesso)
		hist_obitos = hist_obitos.slice(excesso)
		hist_prevalencia = hist_prevalencia.slice(excesso)
		hist_recuperados = hist_recuperados.slice(excesso)
		hist_rt = hist_rt.slice(excesso)
		hist_vacinados = hist_vacinados.slice(excesso)


func _suscetibilidade(i: int, eficacia_vacina: float) -> float:
	var doses := Population.doses_de(i)
	var ef := 0.0
	if doses >= 2:
		ef = eficacia_vacina
	elif doses == 1:
		ef = eficacia_vacina * 0.45
	var idade := Population.idade_de(i)
	var fator_idade := 1.0
	if idade < 12.0:
		fator_idade = 1.15
	elif idade > 70.0:
		fator_idade = 1.05
	return maxf(0.05, (1.0 - ef) * fator_idade)


func _cfr_individual(i: int, info: Dictionary, vila_id: int, cfr_base: float,
		san: float, ocup: float) -> float:
	var idade := Population.idade_de(i)
	var cfr: Dictionary = info.get("cfr", {})
	var u := cfr_base
	if idade < 15.0:
		u = float(cfr.get("jovem", cfr_base))
	elif idade < 60.0:
		u = float(cfr.get("adulto", cfr_base))
	else:
		u = float(cfr.get("idoso", cfr_base * 3.0))
	# saneamento protege doencas hidricas; UBS/hospital protege todos
	u *= lerpf(1.6, 0.55, san)
	var v := Vilas.get_vila(vila_id)
	if int(v.get("ubs", 0)) > 0:
		u *= 0.62
	if int(v.get("hospital", 0)) > 0:
		u *= 0.55
	if ocup > 1.0:
		u *= lerpf(1.0, 2.6, clampf(ocup - 1.0, 0.0, 1.0))
	# comorbidade latente
	u *= lerpf(0.7, 2.2, Population.risco_de(i))
	# vacina protege contra morte (mesmo se infectar)
	var doses := Population.doses_de(i)
	if doses >= 2:
		u *= lerpf(1.0, 0.35, float(info.get("eficacia_vacina", 0.6)))
	elif doses == 1:
		u *= 0.7
	return clampf(u, 0.0, 0.9)


func _incidencia_cronica(i: int, v: Dictionary) -> float:
	var idade := Population.idade_de(i)
	var fator := 0.00035
	if idade > 40.0:
		fator *= 1.0 + (idade - 40.0) * 0.045
	var renda := float(v.get("renda_media_sm", 2.0))
	fator *= lerpf(1.5, 0.7, clampf(renda / 5.2, 0.0, 1.0))
	fator *= lerpf(1.0, 2.0, Population.risco_de(i))
	return clampf(fator, 0.0, 0.05)


func _checar_surto(vila_id: int, prev_v: float, novos: int) -> void:
	var estava := bool(em_surto.get(vila_id, false))
	if prev_v > 0.10 and not estava:
		em_surto[vila_id] = true
		surto_iniciado.emit(vila_id, novos)
	elif prev_v < 0.02 and estava:
		em_surto[vila_id] = false
		surto_encerrado.emit(vila_id)


# ============================================================================
# PREVISAO E SIMULACAO "E SE...?"
# ============================================================================

## Projeta a curva por `semanas` a frente mantendo tudo o mais constante
## (usado no painel de distribuicoes/leitos). Nao altera o estado real.
func projetar_leitos(vila_id: int, semanas: int = 8, reducao_rt: float = 0.0) -> Dictionary:
	var v := Vilas.get_vila(vila_id)
	var pop := float(v.get("populacao", 1))
	var s := float(suscetiveis(vila_id))
	var e := float(Population.contar_por_estado(vila_id)[Population.ESTADO_EXPOSTO])
	var i_ := float(infectosos(vila_id))
	var r := float(recuperados(vila_id))
	var info := info_doenca()
	var incub := maxf(float(info.get("incubacao_se", 1.0)), 0.15)
	var infec := maxf(float(info.get("infeccioso_se", 1.5)), 0.15)
	var rt0 := maxf(rt(vila_id) * (1.0 - reducao_rt), 0.0)
	if rt0 <= 0.0:
		rt0 = float(info.get("R0", 2.0)) * 0.9
	var out_s: Array = []
	var out_i: Array = []
	var out_n: Array = []
	var out_ocup: Array = []
	var leitos := maxf(float(v.get("leitos", 1)), 1.0)
	for k in range(semanas):
		var beta := rt0 / infec
		var novos := beta * (i_ / maxf(pop, 1.0)) * s
		novos = minf(novos, s)
		var s2e := e * (1.0 - exp(-1.0 / incub))
		var e2i := e * (1.0 - exp(-1.0 / incub))
		var i2r := i_ * (1.0 - exp(-1.0 / infec))
		s -= novos
		e += novos - e2i
		i_ += e2i - i2r
		r += i2r
		out_s.append(s)
		out_i.append(i_)
		out_n.append(maxf(novos, 0.0))
		out_ocup.append(clampf(i_ * 0.12 / leitos, 0.0, 3.0))
	return {"susceptiveis": out_s, "infectados": out_i, "novos": out_n,
		"ocupacao": out_ocup, "leitos": leitos}


## Probabilidade de superlotacao em `semanas` semanas (Binomial sobre leitos).
func prob_superlotacao(vila_id: int, semanas: int = 4) -> Dictionary:
	var proj := projetar_leitos(vila_id, semanas)
	var ocup: Array = proj["ocupacao"]
	var leitos := float(proj["leitos"])
	var i_fut := float(proj["infectados"][semanas - 1])
	var graves_esperados := i_fut * 0.12
	var p_grave := 0.12
	var n := maxi(int(round(i_fut)), 1)
	var k := int(ceil(leitos))
	# P(X > leitos) com X ~ Binomial(n, 0.12) aproximada por Poisson quando n grande
	var lam := graves_esperados
	var p_acum := 0.0
	if lam < 30.0:
		for x in range(0, k + 1):
			p_acum += StatCore.poisson_pmf(x, lam)
	else:
		p_acum = StatCore.normal_cdf(float(k), lam, sqrt(maxf(lam, 0.01)))
	return {
		"p": clampf(1.0 - p_acum, 0.0, 1.0),
		"graves_esperados": graves_esperados,
		"leitos": leitos,
		"ocupacao_atual": float(ocup[ocup.size() - 1]),
		"n": n, "p_grave": p_grave,
	}


# ============================================================================
# CENARIOS E PERSISTENCIA
# ============================================================================

func reiniciar() -> void:
	rng.seed = 777_001
	hist_se.clear()
	hist_casos.clear()
	hist_obitos.clear()
	hist_prevalencia.clear()
	hist_recuperados.clear()
	hist_rt.clear()
	hist_vacinados.clear()
	obitos_total = 0
	casos_total = 0
	obitos_semana = 0
	casos_semana = 0
	recuperados_total = 0
	_casos_anterior = 1
	em_surto.clear()
	Population.reiniciar()
	_semear()
	atualizado.emit()


func serializar() -> Dictionary:
	return {
		"obitos": obitos_total, "casos": casos_total, "recuperados": recuperados_total,
		"se": Array(hist_se), "casos_hist": Array(hist_casos), "obitos_hist": Array(hist_obitos),
		"prev_hist": Array(hist_prevalencia), "rt_hist": Array(hist_rt),
		"vac_hist": Array(hist_vacinados), "rec_hist": Array(hist_recuperados),
		"casos_anterior": _casos_anterior,
	}


func deserializar(d: Dictionary) -> void:
	if d.is_empty():
		return
	obitos_total = int(d.get("obitos", 0))
	casos_total = int(d.get("casos", 0))
	recuperados_total = int(d.get("recuperados", 0))
	_casos_anterior = int(d.get("casos_anterior", 1))
	hist_se = PackedInt32Array(d.get("se", []))
	hist_casos = PackedInt32Array(d.get("casos_hist", []))
	hist_obitos = PackedInt32Array(d.get("obitos_hist", []))
	hist_prevalencia = PackedFloat32Array(d.get("prev_hist", []))
	hist_rt = PackedFloat32Array(d.get("rt_hist", []))
	hist_vacinados = PackedInt32Array(d.get("vac_hist", []))
	hist_recuperados = PackedInt32Array(d.get("rec_hist", []))
	atualizado.emit()
