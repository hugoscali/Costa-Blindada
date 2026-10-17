# Test: host LAN real (sin segundo peer). Cubre el FIX del bug mp_role (el host ahora
# obtiene rol 1 en _mp_host_start) y la Fase 3 (los @rpc/loops viven en el hijo Net).
# Crea una sala ENet de verdad (puerto 27016) pero SIN clientes: valida que el host
# arranca, el broadcast de estado corre sin errores, el game over va por la ruta MP
# (_mp_gameover_host) y el guardado del roster cierra en fase 2.
# La sincronía con un peer real la valida el usuario con 2 PCs.
extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.hud == null:
		print("FALLO: hud null")
		quit(1)
		return

	# 1) _setup_net: hijo "Net" con app enlazada y los @rpc movidos en Fase 3 presentes allá
	main._setup_net()
	check(main.net != null and main.net.name == "Net", "no se creó el hijo Net")
	check(main.net.app == main, "net.app no enlaza a main")
	for m in ["_net_start", "_net_input", "_net_state", "_net_gameover", "_net_my_initials",
		"_net_roster_done", "_send_net_state", "_net_host_loop", "_net_client_loop"]:
		check(main.net.has_method(m), "falta %s en Net" % m)
	# y ya NO existen en la raíz (garantía de la Fase 3)
	for m in ["_net_start", "_net_input", "_net_state", "_net_gameover", "_net_my_initials",
		"_net_roster_done", "_send_net_state", "_net_host_loop", "_net_client_loop"]:
		check(not main.has_method(m), "%s sigue en main.gd" % m)

	# 2) crear sala real (host solo, sin clientes)
	var ok: bool = main.net.create_room("TestRoom", 2, "")
	check(ok, "create_room falló (¿puerto 27016 ocupado?)")
	if not ok:
		quit(1)
		return

	# 3) _mp_host_start: FIX → el host debe quedar con mp_role == 1 y partida corriendo
	main._mp_host_start()
	check(main.mp_role == 1, "mp_role != 1 tras _mp_host_start (bug mp_role volvió)")
	check(main.phase == main.GamePhase.PLAYING, "fase != PLAYING tras _mp_host_start")
	check(main.slot_states.size() == 1, "slot_states != 1 (host sin clientes)")
	check(main.slot_by_pid.has(1), "slot_by_pid no incluye al host (pid 1)")

	# 4) loop de host: _net_host_loop → _send_net_state debe correr sin errores (0 peers → no-op)
	main.net._net_host_loop(0.1)
	check(main.mp_role == 1, "mp_role cambió tras _net_host_loop")

	# 5) game over del host: debe ir por _mp_gameover_host (rama mp_role == 1 de _gameover_gen)
	main._gameover_gen(main.game_generation)
	check(main.phase == main.GamePhase.GAMEOVER, "fase != GAMEOVER")
	check(main.entering_initials, "entering_initials != true (no fue por _mp_gameover_host)")
	check(main.mp_go_phase == 0, "mp_go_phase != 0")
	check(main.mp_roster.size() == 1, "mp_roster != 1")

	# 6) iniciales del host → roster completo → guardado en fase 2 (todo local, sin peers)
	main._submit_initials()  # initials vacío → "???" (ruta _is_mp_gameover → _mp_send_my_initials)
	check(main.mp_roster.size() == 1 and str(main.mp_roster[0]) == "???", "roster[0] != '???'")
	check(main.mp_go_phase == 2, "mp_go_phase != 2 (guardado del host no cerró)")

	# 7) limpieza: volver al menú deja el estado de red en cero
	main._mp_abort_cleanup()
	check(main.mp_role == 0, "mp_role != 0 tras _mp_abort_cleanup")
	check(main.phase == main.GamePhase.MENU, "fase != MENU tras cleanup")

	if fails == 0:
		print("== MP-HOST: OK ==")
	else:
		print("== MP-HOST: %d fallos ==" % fails)
	quit(0 if fails == 0 else 1)
