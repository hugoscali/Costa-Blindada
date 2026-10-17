# Test: estaciones y slots del multijugador LAN. Regresión de los 2 bugs reportados:
#   A) host y cliente arrancaban en el MISMO punto del mapa (la cámara principal estaba
#      hardcodeada al centro para todos los roles);
#   B) las balas del P2 salían por el lado izquierdo (el host usaba el index del listado
#      de get_peers() para dar slots, y en Godot 4.7 ese listado NO incluye al host id 1
#      → el primer cliente recibía slot 0, la estación del host).
# Cubre:
#   1) _player_station: layout simétrico y ordenado por cantidad de jugadores.
#   2) _mp_assign_slots: host = slot 0, clientes = 1..N-1 con contador propio.
#   3) _cam_anchor: cada rol mira desde SU estación, así el origen de disparo
#      (_player_station en _shoot_for) coincide con la mira.
# Es lógica pura sobre main.gd: no abre sockets ni construye el mundo.
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

	# ── 1) Layout de estaciones ──
	main.mp_players = 2
	var a0: Vector3 = main._player_station(0)
	var a1: Vector3 = main._player_station(1)
	check(a0.x < 0.0 and a1.x > 0.0, "2P: las estaciones no quedan a lados opuestos")
	check(absf(a0.x) == absf(a1.x), "2P: las estaciones no son simétricas")
	check(a0.y == 5.0 and a1.y == 5.0 and a0.z == 0.0, "2P: altura/frente de estación cambiado")
	main.mp_players = 4
	var xs: Array = []
	for s in 4:
		xs.append(float(main._player_station(s).x))
	check(xs[0] < xs[1] and xs[1] < xs[2] and xs[2] < xs[3], "4P: las estaciones no están ordenadas")
	check(main._player_station(9).x == xs[3], "4P: slot fuera de rango no se limita al último")
	# 3P (nuevo en esta sesión): simétrico respecto del centro y ordenado, igual que 2P/4P.
	# La geometría contra el mundo real (arena/rocas) la mide test_mp_4p.
	main.mp_players = 3
	var xs3: Array = []
	for s in 3:
		xs3.append(float(main._player_station(s).x))
	check(xs3[0] < xs3[1] and xs3[1] < xs3[2], "3P: las estaciones no están ordenadas")
	check(absf(xs3[0]) == absf(xs3[2]) and xs3[1] == 0.0, "3P: el layout no es simétrico respecto del centro")
	check(absf(xs3[1] - xs3[0]) == absf(xs3[2] - xs3[1]), "3P: el espaciado entre estaciones no es uniforme")

	# ── 2) Reparto de slots (bug B) ──
	main.mp_players = 2
	main._mp_assign_slots([2])
	check(int(main.slot_by_pid.get(1, -1)) == 0, "host no se queda el slot 0")
	check(int(main.slot_by_pid.get(2, -1)) == 1, "cliente 2 no recibe slot 1 (bug del index de get_peers)")
	main.mp_players = 4
	main._mp_assign_slots([3, 2, 5])  # orden de listado arbitrario
	check(int(main.slot_by_pid.get(1, -1)) == 0, "4P: host perdió el slot 0")
	check(int(main.slot_by_pid.get(3, -1)) == 1, "4P: primer peer del listado no obtuvo slot 1")
	check(int(main.slot_by_pid.get(2, -1)) == 2, "4P: segundo peer no obtuvo slot 2")
	check(int(main.slot_by_pid.get(5, -1)) == 3, "4P: tercer peer no obtuvo slot 3")
	main.mp_players = 2
	main._mp_assign_slots([2, 3, 4])  # más peers que jugadores: un solo cliente con estación
	check(main.slot_by_pid.size() == 2, "2P con 3 peers: se asignaron más estaciones que jugadores")
	main._mp_assign_slots([1, 2])  # un listado que SÍ incluye al host no roba slots
	check(int(main.slot_by_pid.get(1, -1)) == 0 and int(main.slot_by_pid.get(2, -1)) == 1, "listado con id 1 desordena los slots")
	main._mp_assign_slots([])  # host solo
	check(main.slot_by_pid.size() == 1 and int(main.slot_by_pid.get(1, -1)) == 0, "host solo: slot_by_pid != {1: 0}")

	# ── 3) Ancla de cámara por rol (bug A) ──
	main.mp_role = 1
	main.mp_players = 2
	main.my_slot = 0
	check(main._cam_anchor() == main._player_station(0), "host: la cámara no queda en su estación (slot 0)")
	main.mp_role = 2
	main.my_slot = 1
	check(main._cam_anchor() == main._player_station(1), "cliente: la cámara no queda en SU estación")
	main.mp_players = 4
	main.my_slot = 3
	check(main._cam_anchor() == main._player_station(3), "cliente slot 3: cámara fuera de su estación")
	# Cliente todavía sin slot asignado por el host (my_slot = 0): centro, sin teletransporte
	main.mp_players = 2
	main.my_slot = 0
	check(main._cam_anchor() == Vector3(0, 5, 0), "cliente pre-asignado no queda en el centro")
	# Slot inválido (slot >= mp_players): centro, no un índice fuera de tabla
	main.my_slot = 7
	check(main._cam_anchor() == Vector3(0, 5, 0), "slot inválido no cae al centro")
	# Split: J1 (cámara principal) en la estación 0, como el host LAN; J2 va a la estación 1
	# en el bloque split de _process (cam_b). Single player sigue en el centro.
	main.mp_role = 3
	main.my_slot = 0
	check(main._cam_anchor() == main._player_station(0), "split J1: no ancla en su estación (slot 0)")
	check(main._cam_anchor() != main._player_station(1), "split: J1 y J2 comparten estación")
	main.mp_role = 0
	check(main._cam_anchor() == Vector3(0, 5, 0), "single player: la ancla central cambió")

	if fails == 0:
		print("== MP-SLOTS: OK ==")
	else:
		print("== MP-SLOTS: %d fallos ==" % fails)
	quit(0 if fails == 0 else 1)
