# Test: audio y efectos de explosión en el cliente LAN.
# El cliente NO corre _update_projectiles / _kill_enemy / _base_random_explosion: si el host
# no los reenvía, en la PC del jugador 2 no se escucha nada y no explota nada (bug reportado).
# Cubre:
#   1) HOST: cada evento genera su fx en el snapshot ("snd", "boom", "spark", "kill").
#   2) CLIENTE: _spawn_net_fx reproduce el audio atenuado por distancia y el visual.
#   3) CLIENTE: la muerte de un soldado se retira con su animación de caída, no de golpe.
#   4) Atenuación: base en la cámara, progresiva a media distancia, silenciada fuera de alcance.
# No abre sockets: usa la pipeline de FX directamente (lógica pura sobre main.gd).
extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)

func _has_fx(main: Node, kind: String) -> bool:
	for fx in main.net_fx:
		if str(fx[0]) == kind:
			return true
	return false

func _stop_all(main: Node) -> void:
	for ap in main.audio_players:
		(ap as AudioStreamPlayer).stop()

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.hud == null:
		print("FALLO: hud null")
		quit(1)
		return
	check(main.audio_players.size() >= 5, "faltan los SFX de armas/explosión (audio_players)")
	check(main.sfx_base_db.size() == main.audio_players.size(), "sfx_base_db no espeja a audio_players")

	# ── 1) HOST: los eventos viajan al snapshot ──
	main.mp_role = 1
	main.mp_players = 2
	main.my_slot = 0
	main.phase = main.GamePhase.PLAYING
	main.ammo = [999999, 300, 20]
	main.current_weapon = 0
	main.slot_states = [main._new_slot_state(), main._new_slot_state()]
	main.wave = 1

	main.net_fx = []
	main._shoot()
	check(_has_fx(main, "snd"), "el disparo del host no manda audio a los clientes")
	check(_has_fx(main, "flash"), "el disparo del host no manda destello a los clientes")

	main.net_fx = []
	main._big_boom(Vector3(0.0, 3.0, 20.0), 1.5, Color(1, 0.4, 0.1), true)
	check(_has_fx(main, "boom"), "_big_boom no se reenvía a los clientes (en LAN no explota nada)")

	main.net_fx = []
	main._hit_spark(Vector3(0.0, 3.0, 20.0), 4, Color(1, 0.7, 0))
	check(_has_fx(main, "spark"), "el impacto chico no se reenvía a los clientes")

	main.net_fx = []
	var fired: bool = main._shoot_for(1)
	check(fired, "_shoot_for(1) no disparó")
	check(_has_fx(main, "snd"), "el disparo de un cliente no llega como audio a los demás")
	_stop_all(main)
	main._play_net_sfx(0, main.camera.global_position)
	check(main.audio_players[0].playing, "el host no escucha los disparos de los otros jugadores")
	_stop_all(main)

	# Muerte de un enemigo: el cliente necesita saber CUÁL murió para retirarlo bien
	var en: Node3D = main._make_net_enemy("soldier")
	main.add_child(en)
	main.enemies.append({"id": 999, "type": "soldier", "node": en, "health": 1.0, "soldiers": 1})
	main.kill_credit_slot = 1
	main.net_fx = []
	main._kill_enemy(main.enemies.size() - 1)
	check(_has_fx(main, "kill"), "la muerte de un enemigo no se avisa a los clientes")

	# El cliente NO genera sus propios fx (evita ecos / duplicados)
	main.mp_role = 2
	main.net_fx = []
	main._big_boom(Vector3(0.0, 3.0, 20.0), 1.5, Color(1, 0.4, 0.1), true)
	check(main.net_fx.is_empty(), "el cliente re-envía fx (eco de explosiones)")
	main._base_random_explosion()
	check(main.net_fx.is_empty(), "el cliente genera sus propias explosiones de base (duplicadas)")
	main.mp_role = 1

	# ── 2) CLIENTE: reproduce audio + visual ──
	main.mp_role = 2
	main.my_slot = 1
	main.camera.position = Vector3(0.0, 5.0, 0.0)
	_stop_all(main)
	main._spawn_net_fx(["snd", 0, 0.0, 5.0, 0.0])
	check(main.audio_players[0].playing, "el cliente no reproduce el balazo que envía el host")
	check(float(main.audio_players[0].volume_db) > -8.0, "el balazo propio debería sonar al volumen base")
	_stop_all(main)
	main._spawn_net_fx(["snd", 0, 600.0, 5.0, 0.0])
	check(not main.audio_players[0].playing, "un SFX fuera de alcance no debería sonar")
	_stop_all(main)
	var parts0: int = main.particles_list.size()
	var vfx0: int = main._active_vfx.size()
	main._spawn_net_fx(["boom", 0.0, 5.0, 12.0, 1.5])
	check(main.audio_players[3].playing, "el cliente no reproduce el boom de una explosión")
	check(main.particles_list.size() > parts0 or main._active_vfx.size() > vfx0, "el cliente no genera el visual de la explosión")
	check(main.shake_amount > 0.0, "el cliente no siente la sacudida de la explosión")
	_stop_all(main)
	main._spawn_net_fx(["spark", 0.0, 5.0, 12.0, 4, 1.0, 0.7, 0.0, 3])
	check(main.audio_players[3].playing, "el cliente no reproduce el sonido del impacto chico")
	check(main.particles_list.size() > parts0, "el cliente no genera las chispas del impacto")
	_stop_all(main)

	# ── 3) CLIENTE: el soldado muerto cae animado ──
	var nd: Node3D = main._make_net_enemy("soldier")
	nd.name = "Enemy_999"
	nd.position = Vector3(0.0, 1.0, -10.0)
	main.add_child(nd)
	main.net_enemy_nodes[999] = {"node": nd, "target": nd.position, "state": 0}
	main._apply_net_state({
		"wave": 1, "score": 0, "hp": 100.0, "en": [], "pr": [], "ep": [], "cr": [],
		"pl": [[0, 300, 20], [0, 300, 20]], "fx": [["kill", 999, "soldier"]],
	})
	check(not main.net_enemy_nodes.has(999), "no se dejó de seguir al enemigo muerto")
	var ap: AnimationPlayer = nd.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null and ap.has_animation("default/fall"):
		check(is_instance_valid(nd) and not nd.is_queued_for_deletion(), "el soldado se borra de golpe, sin animación de caída")
		check(nd.get_children().size() > 0, "no se programó la liberación del soldado tras la caída")
	else:
		check(nd.is_queued_for_deletion(), "sin animación de caída el nodo debe liberarse igual")

	# ── 5) Varios jugadores tirando en el mismo snapshot: el lejano no corta al cercano ──
	# Cada arma tiene UN solo AudioStreamPlayer; con 3-4 jugadores llegan varios "snd" por
	# frame y el último reemplazaba al resto (microcortes / un compañero tapaba tu tiro).
	main.mp_role = 2
	main.my_slot = 1
	main.camera.position = Vector3(0.0, 5.0, 0.0)
	_stop_all(main)
	main._play_net_sfx(0, main.camera.global_position)  # el más cercano (mi disparo)
	var db_near: float = float(main.audio_players[0].volume_db)
	main._play_net_sfx(0, main.camera.global_position + Vector3(0.0, 0.0, -120.0))
	check(main.audio_players[0].playing, "un balazo lejano cortó el sonido más cercano")
	check(absf(float(main.audio_players[0].volume_db) - db_near) < 0.01, "el balazo lejano cambió el volumen del cercano")
	_stop_all(main)
	main._play_net_sfx(0, main.camera.global_position + Vector3(0.0, 0.0, -120.0))
	main._play_net_sfx(0, main.camera.global_position)
	check(main.audio_players[0].playing, "un balazo cercano no reemplaza a uno que estaba lejano")
	check(float(main.audio_players[0].volume_db) > -8.0, "el cercano debería sonar al volumen base")
	_stop_all(main)

	# ── 6) Atenuación ──
	var near: float = main._net_sfx_db(main.camera.global_position)
	check(absf(near) < 0.5, "un SFX en la cámara debe sonar al volumen base (recibió %.1f dB)" % near)
	var mid: float = main._net_sfx_db(main.camera.global_position + Vector3(0.0, 0.0, -85.0))
	check(mid < -1.0 and mid > -25.0, "la atenuación a media distancia no es progresiva (recibió %.1f dB)" % mid)
	var far: float = main._net_sfx_db(main.camera.global_position + Vector3(0.0, 0.0, -500.0))
	check(far < -900.0, "un SFX fuera de NET_SFX_RANGE debe silenciarse")

	if fails == 0:
		print("== MP-FX: OK ==")
	else:
		print("== MP-FX: %d fallos ==" % fails)
	quit(0 if fails == 0 else 1)
