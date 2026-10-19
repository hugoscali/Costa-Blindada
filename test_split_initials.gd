# Test: ingreso de iniciales en el game over de PANTALLA DIVIDIDA.
# Reporte del usuario: "no puedo completar las iniciales con joystick al terminar el 2P local".
# Escenario A recorre el camino REAL del usuario: menu -> "joystick" -> asignacion de mandos
# -> partida -> game over. Escenario B: J1 con teclado/mouse y un solo mando (el de J2).
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

	# ── ESCENARIO A: el camino real, J1 con joystick y dos mandos ──
	main._menu.show_input_choice("split")
	await process_frame
	main._menu.on_io_joy()  # J1 elige joystick -> pantalla de asignacion de mandos
	await process_frame
	check(main.current_menu == "split_assign", "pantalla de asignacion de mandos activa")
	main._input(joy(0, 0))  # J1 reclama su pad
	main._input(joy(1, 0))  # J2 reclama el suyo
	await process_frame
	check(main.split_j1_dev == 0 and main.split_j2_dev == 1, "los dos mandos quedan asignados (J1=0, J2=1)")
	main._menu.on_split_assign_start()
	await process_frame
	await process_frame
	check(main.split_mode == true and main.mp_role == 3, "partida 2P local iniciada desde la asignacion con mandos")
	check(main.current_menu == "", "al empezar la partida no queda un menu abierto que se coma el input del mando")
	check(main.phase == main.GamePhase.PLAYING, "fase PLAYING")

	main.score = 142250
	main._split_gameover()
	await process_frame
	check(main.phase == main.GamePhase.GAMEOVER, "game over split activo")
	check(main._svkb[0].open and main._svkb[1].open, "los 2 teclados virtuales estan abiertos")
	check(main.mp_go_phase == 0, "fase 0 (esperando iniciales)")

	# J1 con su mando: D-pad mueve, A agrega (antes no llegaban: se perdian en "split_assign")
	var c0: int = main._svkb[0].cursor
	main._input(joy(0, JOY_BUTTON_DPAD_DOWN))
	await process_frame
	check(main._svkb[0].cursor != c0, "J1: D-pad mueve el cursor de su mitad")
	main._input(joy(0, int(main._jb("confirm"))))
	await process_frame
	check(main.initials.length() == 1, "J1: A agrega una letra (initials='%s')" % main.initials)
	main._input(joy(0, JOY_BUTTON_DPAD_RIGHT))
	main._input(joy(0, int(main._jb("confirm"))))
	await process_frame
	check(main.initials.length() == 2, "J1 completa una segunda letra (initials='%s')" % main.initials)

	# J2 con su mando
	var c1: int = main._svkb[1].cursor
	main._input(joy(1, JOY_BUTTON_DPAD_RIGHT))
	await process_frame
	check(main._svkb[1].cursor != c1, "J2: D-pad mueve el cursor de su mitad")
	main._input(joy(1, int(main._jb("confirm"))))
	await process_frame
	check(main.p2_initials.length() == 1, "J2: A agrega una letra (p2_initials='%s')" % main.p2_initials)
	main._input(joy(1, JOY_BUTTON_DPAD_DOWN))
	main._input(joy(1, int(main._jb("confirm"))))
	await process_frame
	check(main.p2_initials.length() == 2, "J2 completa una segunda letra (p2_initials='%s')" % main.p2_initials)

	# B borra la ultima letra en la mitad de J1
	main._input(joy(0, int(main._jb("back"))))
	await process_frame
	check(main.initials.length() == 1, "B borra una letra en la mitad de J1 (initials='%s')" % main.initials)

	# Teclado de PC con J1 en joystick (antes estaba bloqueado)
	var ini_before: String = main.initials
	main._input(key(KEY_Q, 113))
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

	# ── ESCENARIO B: J1 con teclado/mouse y un solo mando (el de J2) ──
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
