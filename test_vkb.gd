# Smoke test del teclado virtual (iniciales, joystick). NO invoca _vkb_submit
# (eso escribiria en el archivo real de highscores).
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
	main.local_input_mode = 1
	main.mp_role = 0
	main.phase = main.GamePhase.GAMEOVER
	main.entering_initials = true
	main.initials = ""
	if main.hud == null:
		print("FALLO: hud null")
		quit(1)
		return
	main._vkb.show()
	check(main._vkb.open == true, "vkb_open no true")
	check(main.hud.get_node_or_null("VKB_0") != null, "falta VKB_0")
	check(main.hud.get_node_or_null("VKB_25") != null, "falta VKB_25")
	check(main.hud.get_node_or_null("VKBCursor") != null, "falta VKBCursor")
	check(main._vkb.cursor == 0, "cursor inicial = %d" % main._vkb.cursor)

	# Alineación (regresión del VKB desalineado): cada tecla debe ser un Label de la celda
	# completa (70×66) con su centro EXACTO en cell(i) → columnas alineadas entre las 2 filas.
	var bad_align := 0
	for i in 26:
		var lbl: Label = main.hud.get_node_or_null("VKB_%d" % i) as Label
		var c: Vector2 = main._vkb.cell(i)
		var row0: Vector2 = main._vkb.cell(i - (i % 13))  # primera tecla de su fila: todas comparten Y
		if lbl == null or absf(lbl.position.x + lbl.size.x / 2.0 - c.x) > 0.5 \
				or absf(lbl.size.x - 70.0) > 0.5 or absf(lbl.size.y - 66.0) > 0.5 \
				or absf(lbl.position.y - row0.y) > 0.5:
			bad_align += 1
	check(bad_align == 0, "VKB single: %d/26 teclas desalineadas (x/tamaño/fila en rampa)" % bad_align)
	var col_bad := 0
	for col in 13:
		if absf(main._vkb.cell(col).x - main._vkb.cell(col + 13).x) > 0.01:
			col_bad += 1
	check(col_bad == 0, "VKB single: %d columnas no alinean entre filas" % col_bad)

	# navegación: derecha/izquierda/arriba/abajo + wrap de columna
	main._vkb.move(0, 1)   # → B (1)
	check(main._vkb.cursor == 1, "der %d != 1" % main._vkb.cursor)
	main._vkb.move(0, 1)   # → C (2)
	check(main._vkb.cursor == 2, "der %d != 2" % main._vkb.cursor)
	main._vkb.move(0, -1)  # → B (1)
	check(main._vkb.cursor == 1, "izq %d != 1" % main._vkb.cursor)
	main._vkb.move(1, 0)   # → fila 1, col 1 = O (14)
	check(main._vkb.cursor == 14, "abajo %d != 14" % main._vkb.cursor)
	main._vkb.move(-1, 0)  # → fila 0, col 1 = B (1)
	check(main._vkb.cursor == 1, "arriba %d != 1" % main._vkb.cursor)
	main._vkb.move(0, 11)  # → col 12 = M (12)
	check(main._vkb.cursor == 12, "a M %d != 12" % main._vkb.cursor)
	main._vkb.move(0, 1)   # → wrap col 0 = A (0)
	check(main._vkb.cursor == 0, "wrap %d != 0" % main._vkb.cursor)

	# selección + backspace + tope de 3
	main._vkb.select()     # A
	check(main.initials == "A", "select '%s' != A" % main.initials)
	main._vkb.move(0, 12)  # → M (12)
	main._vkb.select()     # AM
	check(main.initials == "AM", "select '%s' != AM" % main.initials)
	main._vkb.backspace()  # A
	check(main.initials == "A", "backspace '%s' != A" % main.initials)
	main._vkb.select(); main._vkb.select(); main._vkb.select()
	check(main.initials.length() == 3, "tope 3 -> '%s'" % main.initials)

	# clear (queue_free es diferido → esperar un frame)
	main._vkb.clear()
	check(main._vkb.open == false, "vkb_open tras clear")
	await process_frame
	check(main.hud.get_node_or_null("VKB_0") == null, "VKB_0 no liberada")
	check(main.hud.get_node_or_null("VKBCursor") == null, "VKBCursor no liberada")

	if fails == 0:
		print("== VKB: OK ==")
	else:
		print("== VKB: %d fallos ==" % fails)
	quit(0 if fails == 0 else 1)
