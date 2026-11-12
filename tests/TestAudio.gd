extends Node
## Verifica o AudioManager: buses, arquivos, mapeamento vila -> zona/ambiente,
## volumes persistidos e troca de tema. Roda como cena (precisa dos autoloads):
##   godot --headless res://tests/TestAudio.tscn

var _falhas := 0
var _passos := 0


func _ready() -> void:
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in range(3):
		await get_tree().process_frame
	main.fechar_modal()

	_teste_buses()
	_teste_arquivos()
	_teste_mapa_de_vilas()
	_teste_tema()
	_teste_vila()
	_teste_minigames()
	_teste_volumes()
	_teste_sfx()

	print("TESTE AUDIO: %d passos, %d falhas" % [_passos, _falhas])
	get_tree().quit(1 if _falhas > 0 else 0)


func _ok(cond: bool, nome: String) -> void:
	_passos += 1
	if not cond:
		_falhas += 1
		print("  FALHOU: ", nome)


func _teste_buses() -> void:
	for nome in ["Music", "Ambient", "SFX"]:
		_ok(AudioServer.get_bus_index(nome) >= 0, "bus " + nome)
	_ok(AudioServer.get_bus_index("Music") != 0, "Music nao e o Master")


func _teste_arquivos() -> void:
	for id in ["mapa", "zona_urbana", "zona_rural", "zona_rio", "zona_mata",
			"zona_industrial"]:
		_ok(ResourceLoader.exists("res://assets/audio/mus/%s.ogg" % id), "tema " + id)
	var reais := 0
	for i in range(1, 21):
		if ResourceLoader.exists("res://assets/audio/vila/vila_%02d.ogg" % i):
			reais += 1
	_ok(reais == 20, "20 stings de vila (achei %d)" % reais)
	for id in ["clique", "abrir", "fechar", "sucesso", "erro", "moeda", "semana",
			"alerta", "pagina", "descoberta"]:
		_ok(ResourceLoader.exists("res://assets/audio/sfx/%s.ogg" % id), "sfx " + id)
	var ganhos: Dictionary = Audio._cfg.get("ambiente_ganho_db", {})
	for id in ["amb_parque_urbano", "amb_passaros", "amb_rio", "amb_mercado", "amb_multidao",
			"amb_porto"]:
		_ok(ResourceLoader.exists("res://assets/audio/amb/%s.ogg" % id), "ambiente " + id)
		_ok(ganhos.has(id), "nivel calibrado de " + id)


func _teste_mapa_de_vilas() -> void:
	var cfg: Dictionary = Audio._cfg
	_ok(cfg.has("vilas"), "audio.json tem vilas")
	_ok(cfg.get("vilas", {}).size() == 20, "20 vilas mapeadas")
	var zonas: Array = cfg.get("zonas", [])
	for k in cfg.get("vilas", {}).keys():
		var conf: Dictionary = cfg["vilas"][k]
		var zona := "zona_" + str(conf.get("zona", ""))
		_ok(zonas.has("zona_" + str(conf.get("zona", ""))), "zona valida para vila " + str(k))
		_ok(ResourceLoader.exists("res://assets/audio/mus/%s.ogg" % zona),
			"trilha da zona de " + str(k))
		_ok(ResourceLoader.exists("res://assets/audio/amb/%s.ogg" % str(conf.get("ambiente", ""))),
			"ambiente de " + str(k))


func _teste_tema() -> void:
	Audio.modo_mapa()
	_ok(Audio.tema_atual() == "mapa", "tema inicial do mapa")
	Audio.tocar_tema("zona_rural", 0.01)
	_ok(Audio.tema_atual() == "zona_rural", "troca para zona rural")
	Audio.tocar_tema("zona_rural", 0.01)
	_ok(Audio.tema_atual() == "zona_rural", "troca idempotente")


func _teste_vila() -> void:
	Audio.tocar_vila(10)
	_ok(Audio.tema_atual() == "zona_rural", "vila 10 usa zona rural")
	_ok(Audio.ambiente_atual() == "amb_passaros", "vila 10 usa passaros")
	_ok(Audio.vila_atual() == 10, "vila atual = 10")
	Audio.tocar_vila(16)
	_ok(Audio.tema_atual() == "zona_industrial", "vila 16 usa zona industrial")
	Audio.restaurar_exploracao(16)
	_ok(Audio.vila_atual() == 16, "restaura exploracao na vila 16")
	Audio.modo_mapa()
	_ok(Audio.tema_atual() == "mapa" and Audio.vila_atual() == 0, "volta ao mapa")


func _teste_minigames() -> void:
	var ids := ["delineamentos", "banco_dados", "assimetria", "grafico", "amostragem",
		"distribuicoes", "hipoteses", "tendencias", "auditoria"]
	for id in ids:
		var tema := str(Audio._cfg.get("minigames", {}).get(id, ""))
		_ok(tema != "", "minigame mapeado: " + id)
		_ok(ResourceLoader.exists("res://assets/audio/mus/%s.ogg" % tema), "tema de " + id)
	Audio.tema_minigame("auditoria")
	_ok(Audio.tema_atual() == "mg_auditoria", "tema do minigame de auditoria")


func _teste_volumes() -> void:
	var antes := GameState.volume_musica
	GameState.volume_musica = 0.5
	Audio.aplicar_volumes()
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	_ok(absf(db - linear_to_db(0.5)) < 0.6, "volume da musica aplicado (%.1f dB)" % db)
	GameState.mudo = true
	Audio.aplicar_volumes()
	_ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "mudo silencia a musica")
	GameState.mudo = false
	GameState.volume_musica = antes
	Audio.aplicar_volumes()
	_ok(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "desmuta")


func _teste_sfx() -> void:
	for id in ["clique", "sucesso", "erro", "moeda", "descoberta"]:
		Audio.sfx(id, -6.0)
	_ok(true, "sfx tocados sem erro")
	Audio.ui("clique")
	_ok(true, "ui sem erro")
	Audio.parar_tudo()
	_ok(Audio.tema_atual() == "", "parar_tudo limpa o tema")
