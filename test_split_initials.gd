# Test: ingreso de iniciales en el game over de PANTALLA DIVIDIDA.
# Reporte del usuario: "al finalizar la partida no nos permite seleccionar las letras".
# Cubre: mando de J1, mando de J2, teclado de PC (con J1 en joystick y con J1 en teclado),
# clic con el mouse sobre una letra, y que al guardar no quede ningun VKB "open".
extends SceneTree

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  ", msg)
	else:
		failures += 1
		print("  FAIL  ", msg)

func joy(dev: int, btn: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = dev
	ev.button_index = btn
	ev.pressed = true
	return ev

func key(kc: int, uni: int = 0) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = kc
	ev.unicode = uni if uni > 0 else kc
	ev.pressed = true
	return ev

func click(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev

func _init() -> void:
	print("== TEST INICIALES SPLIT ==")
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main: Node = ps.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# ── Escenario 1: J1 con joystick (el del reporte: dos mitades con teclado virtual) ──
	main.local_input_mode = 1
	main.split_j1_dev = 0
	main.split_j2_dev = 1
	main._start_split_game()
	await process_frame
	main.score = 1000
	main._split_gameover()
	await process_frame
	check(main.phase == main.GamePhase.GAMEOVER, "game over split activo")
	check(main._svkb[0].open and main._svkb[1].open, "los 2 teclados virtuales estan abiertos")
	check(main.mp_go_phase == 0, "fase 0 (esperando iniciales)")

	# J1 con su mando (device 0)
	var c0: int = main._svkb[0].cursor
	main._input(joy(0, JOY_BUTTON_DPAD_DOWN))
	await process_frame
	check(main._svkb[0].cursor != c0, "J1: D-pad mueve el cursor de su mitad")
	main._input(joy(0, int(main._jb("confirm"))))
	await process_frame
	check(main.initials.length() == 1, "J1: A agrega una letra (initials='%s')" % main.initials)

	# J2 con su mando (device 1)
	var c1: int = main._svkb[1].cursor
	main._input(joy(1, JOY_BUTTON_DPAD_RIGHT))
	await process_frame
	check(main._svkb[1].cursor != c1, "J2: D-pad mueve el cursor de su mitad")
	main._input(joy(1, int(main._jb("confirm"))))
	await process_frame
	check(main.p2_initials.length() == 1, "J2: A agrega una letra (p2_initials='%s')" % main.p2_initials)

	# Teclado de PC con J1 en joystick: antes estaba bloqueado (el bug reportado)
	var ini_before: String = main.initials
	main._input(key(KEY_Q, 113))  # 'q' minuscula -> debe entrar como Q
	await process_frame
	check(main.initials.length() > ini_before.length(), "J1 puede tipear con el teclado de PC aunque haya elegido joystick ('%s' -> '%s')" % [ini_before, main.initials])

	# Clic con el mouse sobre una letra de la mitad DERECHA (la de J2)
	var lbl: Label = main.hud.get_node_or_null("SVKB_1_5") as Label  # letra 'F' de J2
	check(lbl != null, "la letra 'F' de J2 existe en el HUD")
	if lbl != null:
		var r: Rect2 = lbl.get_global_rect()
		check(r.size.x > 1.0, "la tecla tiene un rect util para hit-test (%s)" % str(r.size))
		var p2b: String = main.p2_initials
		main._input(click(r.get_center()))
		await process_frame
		check(main.p2_initials.length() > p2b.length(), "clic en una letra la agrega a las iniciales de esa mitad ('%s' -> '%s')" % [p2b, main.p2_initials])

	# ENTER (J1) y START (J2) cierran el guardado
	main._input(key(KEY_ENTER))
	await process_frame
	check(main.mp_go_phase >= 1, "ENTER envia las iniciales de J1 al equipo")
	main._input(joy(1, int(main._jb("pause"))))  # START
	await process_frame
	check(main.mp_go_phase >= 2, "START guarda las de J2 y cierra el guardado")
	check((main.hs_mp.get("2", []) as Array).size() >= 1, "puntuacion de equipo guardada en la categoria 2P")
	await process_frame
	check(not main._svkb[0].open and not main._svkb[1].open, "tras guardar, ningun teclado virtual queda abierto")

	# ── Escenario 2: J1 con teclado/mouse (el otro camino, no debe haberse roto) ──
	main._teardown_split()
	await process_frame
	main.local_input_mode = 0
	main.split_j1_dev = 0
	main.split_j2_dev = 0
	main._start_split_game()
	await process_frame
	main.score = 2000
	main._split_gameover()
	await process_frame
	check(not main._svkb[0].open, "con J1 en teclado no se muestra el VKB de la mitad izquierda")
	main._input(key(KEY_B, 98))
	await process_frame
	check(main.initials.length() == 1, "J1 tipea sus iniciales con el teclado de PC (initials='%s')" % main.initials)
	main._input(joy(0, int(main._jb("confirm"))))  # el pad unico es de J2
	await process_frame
	check(main.p2_initials.length() == 1, "el pad unico es de J2 y agrega una letra (p2_initials='%s')" % main.p2_initials)
	main._input(key(KEY_ENTER))
	await process_frame
	check(main.mp_go_phase >= 1, "ENTER envia las de J1 (J1 en teclado)")

	main._teardown_split()
	await process_frame
	print("== RESULTADO: %d fallos ==" % failures)
	quit(0 if failures == 0 else 1)
