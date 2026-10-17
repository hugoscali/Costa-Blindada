# Test: game over split — teclado virtual por jugador (mando) + caso teclado de PC.
extends SceneTree

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  ", msg)
	else:
		failures += 1
		print("  FAIL", msg)

func _jb_ev(dev: int, btn: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = dev
	e.button_index = btn
	e.pressed = true
	return e

func _init() -> void:
	print("== TEST GAME OVER SPLIT VKB ==")
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main: Node = ps.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# ── Caso A: P1 y P2 ambos con joystick ──
	main._start_split_game()
	await process_frame
	await process_frame
	main.local_input_mode = 1   # P1 con joystick
	main.score = 500
	main._split_gameover()
	await process_frame
	check(main.phase == main.GamePhase.GAMEOVER, "fase GAMEOVER")
	var p1dev: int = main._j1_joy_dev()
	var p2dev: int = main._p2_joy_dev()
	print("  P1 dev=%d  P2 dev=%d" % [p1dev, p2dev])
	check(p1dev != p2dev, "dispositivos P1/P2 distintos")

	check(main.hud.get_node_or_null("SVKB_0_0") != null, "VKB P1 visible (SVKB_0_0)")
	check(main.hud.get_node_or_null("SVKB_1_0") != null, "VKB P2 visible (SVKB_1_0)")
	check(main._svkb[0].open and main._svkb[1].open, "split_vkb_open [P1,P2] = true")

	# Alineación (regresión del VKB desalineado): en AMBAS mitades cada tecla debe ser un Label
	# de la celda completa (62×58) con su centro EXACTO en cell(i) → columnas alineadas entre filas.
	for half in [0, 1]:
		var bad_align := 0
		for i in 26:
			var lbl: Label = main.hud.get_node_or_null("SVKB_%d_%d" % [half, i]) as Label
			var c: Vector2 = main._svkb[half].cell(i)
			var row0: Vector2 = main._svkb[half].cell(i - (i % 13))  # primera tecla de su fila: todas comparten Y
			if lbl == null or absf(lbl.position.x + lbl.size.x / 2.0 - c.x) > 0.5 \
					or absf(lbl.size.x - 62.0) > 0.5 or absf(lbl.size.y - 58.0) > 0.5 \
					or absf(lbl.position.y - row0.y) > 0.5:
				bad_align += 1
		check(bad_align == 0, "VKB P%d: %d/26 teclas desalineadas (x/tamaño/fila en rampa)" % [half + 1, bad_align])
		var col_bad := 0
		for col in 13:
			if absf(main._svkb[half].cell(col).x - main._svkb[half].cell(col + 13).x) > 0.01:
				col_bad += 1
		check(col_bad == 0, "VKB P%d: %d columnas no alinean entre filas" % [half + 1, col_bad])

	# P2 escribe "AAA" (cursor en A)
	main._split_input_joypad(_jb_ev(p2dev, JOY_BUTTON_A))
	main._split_input_joypad(_jb_ev(p2dev, JOY_BUTTON_A))
	main._split_input_joypad(_jb_ev(p2dev, JOY_BUTTON_A))
	await process_frame
	check(main.p2_initials == "AAA", "P2 VKB: iniciales = '%s'" % main.p2_initials)

	# P2 mueve cursor con D-pad (sigue funcionando tras seleccionar)
	main._split_input_joypad(_jb_ev(p2dev, JOY_BUTTON_DPAD_RIGHT))
	check(main._svkb[1].cursor == 1, "P2 VKB: cursor movió a 1")

	# P1 escribe "AAA"
	main._split_input_joypad(_jb_ev(p1dev, JOY_BUTTON_A))
	main._split_input_joypad(_jb_ev(p1dev, JOY_BUTTON_A))
	main._split_input_joypad(_jb_ev(p1dev, JOY_BUTTON_A))
	await process_frame
	check(main.initials == "AAA", "P1 VKB: iniciales = '%s'" % main.initials)

	# El device de P2 NO debe tocar el buffer de P1 (y viceversa)
	check(main.p2_initials == "AAA" and main.initials == "AAA", "buffers P1/P2 independientes")

	# Enviar P2 (START)
	main._split_input_joypad(_jb_ev(p2dev, JOY_BUTTON_START))
	await process_frame
	check(main.mp_roster.size() >= 2 and str(main.mp_roster[1]) == "AAA", "P2 envió: roster[1]='%s'" % str(main.mp_roster[1]))
	check(main._svkb[1].open == false, "VKB P2 liberado tras enviar")
	check(main.hud.get_node_or_null("SVKB_1_0") == null, "VKB P2 destruido tras enviar")

	# Enviar P1 (START)
	main._split_input_joypad(_jb_ev(p1dev, JOY_BUTTON_START))
	await process_frame
	await process_frame
	check(main.mp_go_phase >= 2, "guardado completo (phase=%d)" % main.mp_go_phase)
	check(main.hud.get_node_or_null("SVKB_0_0") == null, "VKB P1 destruido tras enviar")

	# ── Caso B: P1 con teclado/mouse → sin VKB P1, pero sí hint de teclado; P2 con VKB ──
	var ps2: PackedScene = load("res://scenes/main.tscn")
	var m2: Node = ps2.instantiate()
	root.add_child(m2)
	await process_frame
	await process_frame
	m2._start_split_game()
	await process_frame
	await process_frame
	m2.local_input_mode = 0   # P1 con teclado/mouse
	m2.score = 300
	m2._split_gameover()
	await process_frame
	check(m2.hud.get_node_or_null("SVKB_0_0") == null, "P1-teclado: SIN VKB (SVKB_0_0 ausente)")
	check(m2.hud.get_node_or_null("GOHintP1") != null, "P1-teclado: hint de teclado visible")
	check(m2.hud.get_node_or_null("SVKB_1_0") != null, "P2: VKB visible (siempre mando)")
	check(m2._svkb[0].open == false and m2._svkb[1].open == true, "split_vkb_open [P1=false, P2=true]")

	print("== RESULTADO: %d fallos ==" % failures)
	quit(0 if failures == 0 else 1)
