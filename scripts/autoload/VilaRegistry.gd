extends Node
## VilaRegistry - as 20 vilas do Vale, sua geometria, economia e matriz de mobilidade.
##
## Combina dois arquivos de dados:
##   data/vilas.json  -> parametros socioeconomicos (renda, saneamento, populacao)
##   data/map_data.json -> geometria (ancoras, centroides, ruas, rota fluvial, grid RLE)
##
## Alem dos dados estaticos, guarda o estado mutavel de cada vila durante a
## partida (saneamento investido, cobertura vacinal, leitos, UBS construida).

signal vila_atualizada(id: int)
signal intervencao_aplicada(id: int, tipo: String)

const GRID_W := 240
const GRID_H := 180
const TILE := 16

var vilas: Array[Dictionary] = []
var mobilidade: Array = []            # 20x20, fração de moradores de i que vão a j
var zone_grid := PackedByteArray()    # 240*180, 0=fora, id da vila
var water_grid := PackedByteArray()
var roads: Array = []
var boat_route: PackedVector2Array = PackedVector2Array()
var carregado := false

var _by_id: Dictionary = {}
var _by_anchor: Dictionary = {}


func _ready() -> void:
	carregar()


func carregar() -> void:
	if carregado:
		return
	var base := _ler_json("res://data/vilas.json")
	var mapa := _ler_json("res://data/map_data.json")
	if base.is_empty() or mapa.is_empty():
		push_error("VilaRegistry: falha ao ler os arquivos de dados.")
		return
	var geo: Dictionary = {}
	for z in mapa.get("zones", []):
		geo[int(z["id"])] = z
	vilas.clear()
	for v in base.get("vilas", []):
		var id := int(v["id"])
		var g: Dictionary = geo.get(id, {})
		var leitos := int(round(float(v["populacao_inicial"]) * float(v["leitos_por_mil"]) / 1000.0))
		var d := {
			"id": id,
			"nome": str(v["nome"]),
			"perfil": str(v["perfil"]),
			"regiao": str(v["regiao"]),
			"descricao": str(v["descricao"]),
			"cor": Color(str(v["cor"])),
			"renda_media_sm": float(v["renda_media_sm"]),
			"saneamento": float(v["saneamento"]),
			"saneamento_base": float(v["saneamento"]),
			"populacao_inicial": int(v["populacao_inicial"]),
			"populacao": int(v["populacao_inicial"]),
			"leitos": leitos,
			"leitos_base": leitos,
			"ubs": 0,
			"hospital": 0,
			"cobertura_vacinal": float(v["cobertura_vacinal_inicial"]),
			"cobertura_base": float(v["cobertura_vacinal_inicial"]),
			"nascimentos": 0,
			"obitos_naturais": 0,
			"anchor": Vector2(g.get("anchor", [0, 0])[0], g.get("anchor", [0, 0])[1]),
			"centroid": Vector2(g.get("centroid", [0, 0])[0], g.get("centroid", [0, 0])[1]),
			"bbox": g.get("bbox", [0, 0, 0, 0]),
			"area_tiles": int(g.get("area_tiles", 1)),
			"historico": [],
		}
		vilas.append(d)
		_by_id[id] = d
		_by_anchor[Vector2i(d["anchor"])] = id
	zone_grid = _rle_decode(mapa.get("zone_rle", []))
	water_grid = _rle_decode(mapa.get("water_rle", []))
	roads = mapa.get("roads", [])
	boat_route = PackedVector2Array()
	for p in mapa.get("boats", []):
		for pt in p:
			boat_route.append(Vector2(pt[0], pt[1]))
	_construir_mobilidade()
	carregado = true


func _ler_json(caminho: String) -> Dictionary:
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _rle_decode(rle: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(GRID_W * GRID_H)
	var pos := 0
	for par in rle:
		var v := int(par[0])
		var n := int(par[1])
		for _i in range(n):
			if pos < out.size():
				out[pos] = v
			pos += 1
	return out


## Matriz gravitacional: fluxo diario de i para j proporcional a populacao e
## renda de j e inversamente proporcional a distancia entre as ancoras.
func _construir_mobilidade() -> void:
	var n := vilas.size()
	mobilidade = []
	for i in range(n):
		var linha := PackedFloat32Array()
		linha.resize(n)
		mobilidade.append(linha)
	for i in range(n):
		var vi: Dictionary = vilas[i]
		var soma := 0.0
		for j in range(n):
			if i == j:
				continue
			var vj: Dictionary = vilas[j]
			var d: float = (vi["anchor"] as Vector2).distance_to(vj["anchor"] as Vector2)
			d = maxf(d, 3.0)
			var atrat := sqrt(float(vj["populacao_inicial"])) * (0.6 + 0.4 * float(vj["renda_media_sm"]) / 5.0)
			var f := atrat / pow(d, 1.35)
			mobilidade[i][j] = f
			soma += f
		if soma > 0.0:
			for j in range(n):
				if i != j:
					mobilidade[i][j] = mobilidade[i][j] / soma
		mobilidade[i][i] = 0.0


# --- Consultas -------------------------------------------------------------

func get_vila(id: int) -> Dictionary:
	return _by_id.get(id, {})


func total_vilas() -> int:
	return vilas.size()


func populacao_total() -> int:
	var s := 0
	for v in vilas:
		s += int(v["populacao"])
	return s


func saneamento_medio() -> float:
	var s := 0.0
	var w := 0.0
	for v in vilas:
		s += float(v["saneamento"]) * float(v["populacao"])
		w += float(v["populacao"])
	return s / maxf(w, 1.0)


func cobertura_media() -> float:
	var s := 0.0
	var w := 0.0
	for v in vilas:
		s += float(v["cobertura_vacinal"]) * float(v["populacao"])
		w += float(v["populacao"])
	return s / maxf(w, 1.0)


func leitos_totais() -> int:
	var s := 0
	for v in vilas:
		s += int(v["leitos"])
	return s


## ID da vila na posicao em tiles do mundo (amostra o grid do zoneamento).
func vila_em(x_tile: float, y_tile: float) -> int:
	var gx := int(x_tile)
	var gy := int(y_tile)
	if gx < 0 or gy < 0 or gx >= GRID_W or gy >= GRID_H:
		return 0
	var id := int(zone_grid[gy * GRID_W + gx])
	if id > 0:
		return id
	# Clicar no rio nao deve selecionar a vila da margem.
	if int(water_grid[gy * GRID_W + gx]) != 0:
		return 0
	var p := Vector2(x_tile, y_tile)
	# A mascara de zona cobre so o miolo urbanizado. O bbox de cada vila e o
	# território administrativo: se o clique cai dentro dele, ja e dela. Em
	# sobreposicao, vence a ancora mais proxima.
	var melhor := 0
	var dist := INF
	for v in vilas:
		var b: Array = v["bbox"]
		if b.size() < 4:
			continue
		if x_tile < float(b[0]) or x_tile > float(b[2]) \
				or y_tile < float(b[1]) or y_tile > float(b[3]):
			continue
		var d: float = (v["anchor"] as Vector2).distance_to(p)
		if d < dist:
			dist = d
			melhor = int(v["id"])
	if melhor > 0:
		return melhor
	# Ultimo recurso: ate 9 tiles (144 px) da ancora, para ruas/pracas fora do
	# bbox (poucas, mas existem nas bordas do mapa).
	dist = 9.0
	for v in vilas:
		var d: float = (v["anchor"] as Vector2).distance_to(p)
		if d < dist:
			dist = d
			melhor = int(v["id"])
	return melhor


func e_agua(x_tile: float, y_tile: float) -> bool:
	var gx := int(x_tile)
	var gy := int(y_tile)
	if gx < 0 or gy < 0 or gx >= GRID_W or gy >= GRID_H:
		return false
	return int(water_grid[gy * GRID_W + gx]) != 0


## Vila mais proxima de um ponto (fallback quando o clique cai em area vazia).
func vila_mais_proxima(p_tile: Vector2) -> int:
	var melhor := 0
	var dist := INF
	for v in vilas:
		var d: float = (v["anchor"] as Vector2).distance_to(p_tile)
		if d < dist:
			dist = d
			melhor = int(v["id"])
	return melhor


## Peso de mobilidade que chega em `j` vindo de todas as vilas.
func pressao_de_entrada(j: int) -> float:
	var s := 0.0
	for i in range(vilas.size()):
		s += float(mobilidade[i][j]) * float(vilas[i]["populacao"])
	return s


# --- Intervencoes ----------------------------------------------------------

func aplicar_saneamento(id: int, delta: float = 0.20) -> void:
	var v := get_vila(id)
	if v.is_empty():
		return
	v["saneamento"] = clampf(float(v["saneamento"]) + delta, 0.0, 1.0)
	vila_atualizada.emit(id)
	intervencao_aplicada.emit(id, "saneamento")


func aplicar_vacina(id: int, delta: float = 0.25) -> void:
	var v := get_vila(id)
	if v.is_empty():
		return
	v["cobertura_vacinal"] = clampf(float(v["cobertura_vacinal"]) + delta, 0.0, 1.0)
	vila_atualizada.emit(id)
	intervencao_aplicada.emit(id, "vacinacao")


func construir_ubs(id: int) -> void:
	var v := get_vila(id)
	if v.is_empty():
		return
	v["ubs"] = int(v["ubs"]) + 1
	v["leitos"] = int(v["leitos"]) + 12
	vila_atualizada.emit(id)
	intervencao_aplicada.emit(id, "ubs")


func construir_hospital(id: int) -> void:
	var v := get_vila(id)
	if v.is_empty():
		return
	v["hospital"] = int(v["hospital"]) + 1
	v["leitos"] = int(v["leitos"]) + 45
	vila_atualizada.emit(id)
	intervencao_aplicada.emit(id, "hospital")


## Capacidade de atendimento: leitos disponiveis por infectado grave estimado.
func ocupacao_leitos(id: int) -> float:
	var v := get_vila(id)
	var leitos := float(v.get("leitos", 1))
	var graves := float(Epidemic.infectados(id)) * 0.12
	if leitos <= 0.0:
		return 1.0
	# pode passar de 1,0 (demanda maior que a capacidade instalada). O teto de 9
	# evita numeros absurdos sem esconder a crise: 900% ja e colapso total.
	return clampf(graves / leitos, 0.0, 9.0)


# --- Ciclo de vida ---------------------------------------------------------

func registrar_historico(id: int, dados: Dictionary) -> void:
	var v := get_vila(id)
	if v.is_empty():
		return
	var h: Array = v["historico"]
	h.append(dados)
	if h.size() > 520:
		h.pop_front()


func historico(id: int) -> Array:
	return get_vila(id).get("historico", [])


func reiniciar() -> void:
	for v in vilas:
		v["populacao"] = int(v["populacao_inicial"])
		v["saneamento"] = float(v["saneamento_base"])
		v["cobertura_vacinal"] = float(v["cobertura_base"])
		v["leitos"] = int(v["leitos_base"])
		v["ubs"] = 0
		v["hospital"] = 0
		v["nascimentos"] = 0
		v["obitos_naturais"] = 0
		v["historico"] = []
	for i in range(vilas.size()):
		vila_atualizada.emit(int(vilas[i]["id"]))


func serializar() -> Dictionary:
	var out: Array = []
	for v in vilas:
		out.append({
			"id": v["id"], "populacao": v["populacao"], "saneamento": v["saneamento"],
			"cobertura": v["cobertura_vacinal"], "leitos": v["leitos"],
			"ubs": v["ubs"], "hospital": v["hospital"],
			"nasc": v["nascimentos"], "obn": v["obitos_naturais"],
		})
	return {"vilas": out}


func deserializar(d: Dictionary) -> void:
	var arr: Array = d.get("vilas", [])
	for item in arr:
		var v := get_vila(int(item.get("id", 0)))
		if v.is_empty():
			continue
		v["populacao"] = int(item.get("populacao", v["populacao"]))
		v["saneamento"] = float(item.get("saneamento", v["saneamento"]))
		v["cobertura_vacinal"] = float(item.get("cobertura", v["cobertura_vacinal"]))
		v["leitos"] = int(item.get("leitos", v["leitos"]))
		v["ubs"] = int(item.get("ubs", 0))
		v["hospital"] = int(item.get("hospital", 0))
		v["nascimentos"] = int(item.get("nasc", 0))
		v["obitos_naturais"] = int(item.get("obn", 0))
		vila_atualizada.emit(int(v["id"]))
