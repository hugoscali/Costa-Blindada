# Test: multijugador LAN de 3 y 4 jugadores (headless, SIN sockets).
# Cubre lo que la suite de 2 jugadores no miraba:
#   1) Reparto de slots con 3 peers y listados desordenados (_mp_assign_slots).
#   2) Layout de estaciones 3P/4P medido contra el MUNDO REAL: simetría, orden, espaciado,
#      suelo por encima del agua y ninguna cámara dentro de la geometría de una roca/árbol.
#   3) _cam_anchor() para los slots 0..3 (host, clientes y split J1) y single en el centro.
#   4) Vida de la base y escala de oleada por cantidad de jugadores (_base_hp_for,
#      _spawn_scale, _start_wave): 1P y 2P NO cambian, 3P/4P reciben más enemigos.
#   5) Game over con 4 filas: ranking ordenado, las 4 filas + MVP + iniciales entran en
#      pantalla sin solaparse, y el cliente lee SU munición del snapshot ("pl" -> my_slot).
#   6) Roster de 4: no se guarda incompleto, un peer caído cierra su slot en "???" y el
#      guardado cierra sin esperar los 25 s, y la entrada queda en la categoría "4".
# Escribe user://highscores.json: el comando de validación restaura el backup antes y después.
extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   " + msg)
	else:
		fails += 1
		print("FALLO: " + msg)

# AABB de un nodo del mundo en ESPACIO DE MUNDO. main._world_aabb recorre los hijos con sus
# transformadas locales pero NO aplica la transform del propio root -> la aplicamos acá.
func world_bb(main: Node, n: Node3D) -> AABB:
	var local: AABB = main._world_aabb(n)
	if local.size == Vector3.ZERO:
		return AABB()
	var t: Transform3D = n.global_transform
	var res := AABB()
	var first := true
	for cx in [local.position.x, local.position.x + local.size.x]:
		for cy in [local.position.y, local.position.y + local.size.y]:
			for cz in [local.position.z, local.position.z + local.size.z]:
				var p: Vector3 = t * Vector3(cx, cy, cz)
				var one := AABB(p, Vector3.ZERO)
				if first:
					res = one
					first = false
				else:
					res = res.merge(one)
	return res

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.hud == null:
		print("FALLO: hud null")
		quit(1)
		return
	# El hijo Net se crea para que _process (mp_role 1/2) no llame métodos sobre un null
	# (sin sala: los loops no hacen nada). Mantiene la salida del test limpia.
	main._setup_net()

	# ── 1) Reparto de slots con 3 peers (4 jugadores) y listados desordenados ──
	main.mp_players = 4
	main._mp_assign_slots([4, 2, 3])  # Godot 4.7: get_peers() no incluye al host (id 1)
	check(int(main.slot_by_pid.get(1, -1)) == 0, "4P: el host no se quedó con el slot 0")
	check(int(main.slot_by_pid.get(4, -1)) == 1, "4P: el primer peer del listado no obtuvo slot 1")
	check(int(main.slot_by_pid.get(2, -1)) == 2, "4P: el segundo peer no obtuvo slot 2")
	check(int(main.slot_by_pid.get(3, -1)) == 3, "4P: el tercer peer no obtuvo slot 3")
	main.mp_players = 3
	main._mp_assign_slots([9, 7])
	check(main.slot_by_pid.size() == 3, "3P: slot_by_pid no tiene host + 2 clientes")
	check(int(main.slot_by_pid.get(9, -1)) == 1 and int(main.slot_by_pid.get(7, -1)) == 2, "3P: slots de clientes mal asignados")
	main._mp_assign_slots([2, 3, 4, 5])  # más peers que jugadores: nadie repite estación
	check(main.slot_by_pid.size() == 3, "3P con 4 peers: se dieron más estaciones que jugadores")
	check(not main.slot_by_pid.has(5), "3P con 4 peers: un peer quedó con estación fuera de rango")
	main._mp_assign_slots([1, 3, 2])  # un listado que SÍ incluye al host no desordena los slots
	check(int(main.slot_by_pid.get(1, -1)) == 0 and int(main.slot_by_pid.get(3, -1)) == 1 and int(main.slot_by_pid.get(2, -1)) == 2, "listado con id 1 desordena los slots 3P")

	# ── 2) Layout de estaciones 3P/4P contra el mundo real ──
	var geo: Array = []  # [[n, xs...]]
	for n in [2, 3, 4]:
		main.mp_players = n
		var xs: Array = []
		for s in n:
			var st: Vector3 = main._player_station(s)
			xs.append(st.x)
			check(st.y == 5.0 and st.z == 0.0, "%dP: la estación %d cambió altura/frente" % [n, s])
		var ok_order := true
		for i in range(1, xs.size()):
			if float(xs[i]) <= float(xs[i - 1]):
				ok_order = false
		check(ok_order, "%dP: las estaciones no están ordenadas de izquierda a derecha" % n)
		var sym := true
		for i in xs.size():
			if absf(float(xs[i])) != absf(float(xs[xs.size() - 1 - i])):
				sym = false
		check(sym, "%dP: el layout no es simétrico respecto del centro" % n)
		if n >= 3:
			var gap := absf(float(xs[1]) - float(xs[0]))
			var uniform := true
			for i in range(1, xs.size()):
				if absf(absf(float(xs[i]) - float(xs[i - 1])) - gap) > 0.01:
					uniform = false
			check(uniform, "%dP: el espaciado entre estaciones no es uniforme" % n)
			check(gap >= 14.0, "%dP: estaciones demasiado juntas (%.1f m) para tener frente propio" % [n, gap])
			var outer: float = absf(float(xs[0]))
			check(outer >= 30.0 and outer <= 50.0, "%dP: la estación exterior (%.1f) no cubre el flanco o se sale de la playa" % [n, outer])
		# Suelo: la estación tiene que estar en arena seca (el mar está a y=-0.35) y la cámara
		# a 5 m debe quedar claramente por encima del terreno.
		for xi in xs:
			var h: float = main._terrain_height(float(xi), 0.0)
			check(h > -0.34, "%dP: la estación x=%.1f queda bajo el nivel del agua (h=%.2f)" % [n, float(xi), h])
			check(5.0 - h >= 2.0, "%dP: la cámara x=%.1f queda a menos de 2 m del suelo" % [n, float(xi)])
		geo.append([n, xs])
	# Ninguna cámara (x,5,0) dentro de la geometría de un decorado (rocas, árboles, base).
	# Se mide contra los nodos YA construidos por _ready (las rocas y los árboles tienen
	# posiciones fijas; solo cambian su escala/rotación).
	var obst: Array = []
	for ch in main.world.get_children():
		var nd: Node = ch as Node
		if nd == null or not (ch is Node3D) or nd.name == "Terrain3D" or nd is Camera3D:
			continue
		var bb: AABB = world_bb(main, ch as Node3D)
		if bb.size != Vector3.ZERO:
			obst.append([str(nd.name), bb])
	check(obst.size() > 20, "el mundo no tiene decorados medibles (%d)" % obst.size())
	for g in geo:
		var n2: int = int(g[0])
		for xs2 in (g[1] as Array):
			var p := Vector3(float(xs2), 5.0, 0.0)
			var hits: Array = []
			for o in obst:
				if (o[1] as AABB).has_point(p):
					hits.append(str(o[0]))
			check(hits.is_empty(), "%dP: la cámara x=%.1f quedó dentro de %s" % [n2, float(xs2), str(hits)])

	# ── 3) Ancla de cámara por rol y por slot 0..3 ──
	main.mp_players = 4
	main.mp_role = 1
	main.my_slot = 0
	check(main._cam_anchor() == main._player_station(0), "host: la cámara no está en su estación (slot 0)")
	for s in range(1, 4):
		main.mp_role = 2
		main.my_slot = s
		check(main._cam_anchor() == main._player_station(s), "cliente slot %d: la cámara no está en SU estación" % s)
	main.mp_role = 2
	main.my_slot = 0
	check(main._cam_anchor() == Vector3(0, 5, 0), "cliente aún sin slot asignado no queda en el centro")
	main.my_slot = 9
	check(main._cam_anchor() == Vector3(0, 5, 0), "slot inválido no cae al centro")
	main.mp_role = 3
	main.my_slot = 0
	check(main._cam_anchor() == main._player_station(0), "split J1 no ancla en su estación (slot 0)")
	main.mp_role = 0
	check(main._cam_anchor() == Vector3(0, 5, 0), "single player cambió de ancla")
	main.mp_role = 1
	main.my_slot = 0

	# ── 4) Vida de la base y escala de oleada por cantidad de jugadores ──
	check(main._base_hp_for(1) == 100.0, "1P base_hp_max != 100")
	check(main._base_hp_for(2) == 150.0, "2P base_hp_max != 150 (igual que single/split)")
	check(main._base_hp_for(3) == 200.0, "3P base_hp_max != 200")
	check(main._base_hp_for(4) == 250.0, "4P base_hp_max != 250")
	check(main._base_hp_for(0) == 100.0, "mp_players 0 no se limita a 1 jugador")
	main.mp_players = 1
	check(main._spawn_scale() == 1.0, "single: la escala de enemigos cambió")
	main.mp_players = 2
	check(main._spawn_scale() == 1.0, "2P (LAN o split): la escala de enemigos cambió")
	main.mp_players = 3
	check(absf(main._spawn_scale() - 1.8) < 0.001, "3P: la escala de enemigos no es x1.8")
	main.mp_players = 4
	check(absf(main._spawn_scale() - 2.2) < 0.001, "4P: la escala de enemigos no es x2.2")
	# _start_wave: 1P/2P exactos como antes, 3P/4P con más lanchas y el mismo durado de oleada
	main.wave = 1
	main.mp_players = 2
	main._start_wave()
	check(main.enemies_to_spawn == 5, "2P oleada 1: enemies_to_spawn != 5 (cambió lo validado)")
	var gap2: float = main._spawn_gap()
	check(absf(gap2 - 3.3) < 0.001, "2P: el intervalo entre lanchas cambió (%.2f)" % gap2)
	main.mp_players = 4
	main._start_wave()
	check(main.enemies_to_spawn == 11, "4P oleada 1: enemies_to_spawn != 11 (5 x2.2)")
	var gap4: float = main._spawn_gap()
	check(gap4 < gap2 and gap4 >= 0.45, "4P: el intervalo entre lanchas no se acorta con la escala (%.2f vs %.2f)" % [gap4, gap2])
	main.wave = 8
	main.mp_players = 2
	main._start_wave()
	var c2: int = main.enemies_to_spawn
	main.mp_players = 4
	main._start_wave()
	check(main.enemies_to_spawn > c2, "oleada 8: 4P no genera más enemigos que 2P")

	# ── 5) Game over con 4 filas: ranking + MVP + iniciales sin solaparse ──
	main.phase = main.GamePhase.PLAYING
	main.mp_role = 1
	main.mp_players = 4
	main.local_input_mode = 0  # mouse/teclado: iniciales más abajo del ranking
	main.split_mode = false
	var sts: Array = []
	var scores: Array = [1200, 5000, 300, 2600]
	for s in 4:
		var stt: Dictionary = main._new_slot_state()
		stt.score = int(scores[s])
		stt.kills = 10 + s
		sts.append(stt)
	main.slot_states = sts
	main.mp_roster = ["AAA", "BBB", "CCC", "DDD"]
	main.score = 9300
	main.wave = 7
	var rows: Array = main._mp_rank_rows()
	check(rows.size() == 4, "el ranking no devuelve 4 filas (%d)" % rows.size())
	var desc := true
	for i in range(1, rows.size()):
		if int(rows[i][1]) > int(rows[i - 1][1]):
			desc = false
	check(desc, "las filas del ranking no están ordenadas por puntaje")
	check(str(rows[0][0]) == "BBB" and int(rows[0][1]) == 5000, "el ranking no pone primero al de mayor puntaje")
	main._mp_show_gameover_screen()
	await process_frame
	var rank: Label = main.hud.get_node_or_null("GORank") as Label
	var mvp: Label = main.hud.get_node_or_null("GOMvp") as Label
	var ini_prompt: Label = main.hud.get_node_or_null("GOInitialsPrompt") as Label
	var ini_boxes: Label = main.hud.get_node_or_null("GOInitialsBoxes") as Label
	var title: Label = main.hud.get_node_or_null("GOTitle") as Label
	var team: Label = main.hud.get_node_or_null("GOTeam") as Label
	if rank == null or mvp == null or ini_prompt == null or ini_boxes == null or title == null or team == null:
		check(false, "falta alguna label del game over MP")
	else:
		var rank_lines: int = rank.text.strip_edges().split("\n").size()
		check(rank_lines == 4, "GORank no muestra 4 filas (%d)" % rank_lines)
		check(rank.size.y > 100.0, "GORank no midió las 4 filas (alto %.1f)" % rank.size.y)
		# Orden vertical: título -> equipo -> ranking -> iniciales (el MVP va al costado de la
		# tabla, ver _mp_rebuild_ranking). Todo adentro del lienzo de diseño 1920x1080 (el HUD
		# se escala parejo con hud_scale).
		check(title.position.y + title.size.y <= rank.position.y, "GOTitle se solapa con el ranking")
		check(team.position.y + team.size.y <= rank.position.y, "GOTeam se solapa con el ranking")
		check(rank.position.x + rank.size.x <= mvp.position.x, "el ranking de 4 filas se solapa con el MVP")
		check(mvp.position.y + mvp.size.y <= ini_prompt.position.y, "el MVP se solapa con el pedido de iniciales")
		check(rank.position.y + rank.size.y <= ini_prompt.position.y, "las 4 filas del ranking se solapan con el pedido de iniciales")
		check(ini_prompt.position.y + ini_prompt.size.y <= ini_boxes.position.y, "el pedido de iniciales se solapa con las cajas")
		check(ini_boxes.position.y + ini_boxes.size.y < 1080.0, "las cajas de iniciales se salen de pantalla")
		check(rank.position.y + rank.size.y < 1080.0, "el ranking de 4 filas se sale de pantalla")
		check(mvp.position.x + mvp.size.x <= 1920.0, "el MVP se sale de pantalla por la derecha")
		check(str(mvp.text).contains("BBB"), "el MVP no corresponde al mejor puntaje")
	# Mismo game over con mando (local_input_mode 1): las iniciales y el teclado virtual van
	# más arriba (debajo del ranking) → es el camino más apretado con 4 filas.
	main._vkb.clear()
	main.local_input_mode = 1
	main._mp_show_gameover_screen()
	await process_frame
	var rank2: Label = main.hud.get_node_or_null("GORank") as Label
	var mvp2: Label = main.hud.get_node_or_null("GOMvp") as Label
	var prompt2: Label = main.hud.get_node_or_null("GOInitialsPrompt") as Label
	var boxes2: Label = main.hud.get_node_or_null("GOInitialsBoxes") as Label
	if rank2 == null or mvp2 == null or prompt2 == null or boxes2 == null:
		check(false, "falta alguna label del game over MP con mando")
	else:
		check(rank2.position.y + rank2.size.y <= prompt2.position.y, "mando: las 4 filas del ranking se solapan con el pedido de iniciales")
		check(rank2.position.x + rank2.size.x <= mvp2.position.x, "mando: el ranking se solapa con el MVP")
		check(prompt2.position.y + prompt2.size.y <= boxes2.position.y, "mando: el pedido de iniciales se solapa con las cajas")
		check(boxes2.position.y + boxes2.size.y <= 690.0, "mando: las cajas de iniciales invaden el teclado virtual (y=%.1f)" % (boxes2.position.y + boxes2.size.y))
	main._vkb.clear()
	main.local_input_mode = 0
	# El cliente construye sus 4 filas con la estadística que le mandó el host (mp_slot_stats)
	main.mp_role = 2
	main.slot_states = []
	main.mp_slot_stats = [[1200, 11], [5000, 22], [300, 33], [2600, 44]]
	main.mp_roster = ["AAA", "BBB", "CCC", "DDD"]
	var crows: Array = main._mp_rank_rows()
	check(crows.size() == 4, "cliente: el ranking no devuelve 4 filas")
	check(str(crows[0][0]) == "BBB" and int(crows[0][1]) == 5000, "cliente: el ranking no usa la estadística del host")
	# Munición: el cliente toma la de SU slot del snapshot ("pl" -> my_slot)
	main.mp_players = 4
	main.my_slot = 3
	main.ammo = [999999, 1, 1]
	main._apply_net_state({
		"wave": 7, "score": 9300, "hp": 100.0, "en": [], "pr": [], "ep": [], "cr": [],
		"pl": [[0, 300, 20], [0, 222, 14], [0, 111, 7], [0, 177, 9]], "fx": [],
	})
	check(int(main.ammo[1]) == 177 and int(main.ammo[2]) == 9, "el cliente slot 3 no lee SU munición del snapshot")
	main.mp_role = 1

	# ── 6) Roster de 4: incompleto no se guarda, un peer caído cierra su slot ──
	main.phase = main.GamePhase.GAMEOVER
	main.mp_go_phase = 0
	main.mp_roster = ["AAA", "", "CCC", ""]
	main._mp_assign_slots([2, 3, 4])  # pid 2 -> slot 1, pid 3 -> slot 2, pid 4 -> slot 3
	main._mp_host_check_roster()
	check(main.mp_go_phase == 0, "el roster incompleto se guardó igual (fase %d)" % main.mp_go_phase)
	check(main._mp_match_running(), "_mp_match_running debe ser true en game over (fase < 2)")
	main._mp_peer_gone(2)  # el peer del slot 1 se cayó: su lugar se cierra en "???"
	check(str(main.mp_roster[1]) == "???", "el slot del peer caído no se cerró en '???'")
	check(not main.slot_by_pid.has(2), "el peer caído sigue con estación asignada")
	check(main.mp_go_phase == 0, "el guardado cerró con un slot todavía sin iniciales")
	main._mp_peer_gone(4)  # falta solo el slot 3 → con esto el roster queda completo
	check(str(main.mp_roster[3]) == "???", "el segundo peer caído no se cerró en '???'")
	check(main.mp_go_phase == 2, "el guardado no cerró al completar el roster (esperaría los 25 s)")
	var cat4: Array = main.hs_mp.get("4", [])
	var mine: Dictionary = {}
	for e in cat4:
		if int(e.get("score", 0)) == 9300 and int(e.get("wave", 0)) == 7:
			mine = e as Dictionary
			break
	check(not mine.is_empty(), "no se guardó la partida de 4 en la categoría 4P (%d entradas)" % cat4.size())
	if not mine.is_empty():
		var pl: Array = mine.get("players", [])
		check(pl.size() == 4, "el highscore 4P no guarda las 4 iniciales (%d)" % pl.size())
		check(str(pl[0]) == "AAA" and str(pl[1]) == "???" and str(pl[2]) == "CCC" and str(pl[3]) == "???", "las iniciales del highscore 4P están mal ordenadas")
	# y quedó escrito en el archivo (las categorías 3P y 4P existen en el formato v2)
	var disk: Dictionary = SaveData.load_highscores()
	var disk4: Array = disk["mp"].get("4", [])
	var disk_mine := false
	for e in disk4:
		if int(e.get("score", 0)) == 9300:
			disk_mine = true
	check(disk_mine, "la categoría 4P no quedó escrita en highscores.json")
	# Con el guardado cerrado la sala vuelve a aceptar jugadores (usable para la próxima partida)
	check(not main._mp_match_running(), "cerrado el guardado la sala sigue rechazando ingresos")

	if fails == 0:
		print("== MP-4P: OK ==")
	print("RESULTADO: %d fallos" % fails)
	quit(0 if fails == 0 else 1)
