# Test: navegación del menú de habilidades de P2 (split, joystick).
# Verifica: apertura, descripción en el foco, navegación con D-PAD vía _input(), y activación con A.
extends SceneTree

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  ", msg)
	else:
		failures += 1
		print("  FAIL", msg)

func _joy_btn(dev: int, btn: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = dev
	e.button_index = btn
	e.pressed = true
	return e

func _init() -> void:
	print("== TEST P2 ABILITIES MENU ==")
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main: Node = ps.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	main._start_split_game()
	await process_frame
	await process_frame
	check(main.split_mode == true, "split activo")
	var p1dev: int = main._j1_joy_dev()
	var p2dev: int = main._p2_joy_dev()
	print("  P1 dev=%d  P2 dev=%d  (deben ser distintos)" % [p1dev, p2dev])
	check(p1dev != p2dev, "dispositivos P1/P2 distintos")
	main.combat_pts = 500  # que todas las habilidades sean alcanzables

	# ── Abrir menú de P2 ──
	main._toggle_abilities_menu(1)
	await process_frame
	check(main._abl1_open == true, "menú P2 abierto (_abl1_open)")
	var lbl: Label = main.hud.get_node_or_null("AbDescPanel1/AbDescLabel") as Label
	check(lbl != null, "AbDescPanel1/AbDescLabel existe")
	var focus_open = main._abl1_nav["focus"]
	print("  foco on-open = %s" % (focus_open.name if focus_open != null else "null"))
	check(focus_open != null, "foco inicial asignado (auto-foco)")
	if lbl:
		print("  desc on-open = '%s'" % lbl.text)
		check(lbl.text.find("Ráfaga") >= 0 or lbl.text.find("Rafaga") >= 0, "descripción inicial muestra la 1ª habilidad (no placeholder)")

	# ── Navegar con D-PAD DOWN (evento sintético del device de P2) vía _input() ──
	var before: Node = main._abl1_nav["focus"]
	main._input(_joy_btn(p2dev, JOY_BUTTON_DPAD_DOWN))
	await process_frame
	var after: Node = main._abl1_nav["focus"]
	print("  foco antes=%s  después=%s" % [before.name if before != null else "null", after.name if after != null else "null"])
	check(after != before, "D-PAD DOWN (device P2) movió el foco")
	if lbl:
		print("  desc tras nav = '%s'" % lbl.text)
		check(lbl.text.find("Escudo") >= 0, "descripción tras navegación muestra la habilidad enfocada")

	# ── Navegar con D-PAD UP de vuelta (debería volver al primer botón) ──
	var b2: Node = main._abl1_nav["focus"]
	main._input(_joy_btn(p2dev, JOY_BUTTON_DPAD_UP))
	await process_frame
	var a2: Node = main._abl1_nav["focus"]
	check(a2 != b2, "D-PAD UP (device P2) movió el foco (de vuelta)")
	if lbl:
		check(lbl.text.find("Ráfaga") >= 0 or lbl.text.find("Rafaga") >= 0, "descripción volvió a la 1ª habilidad (estable, sin placeholder)")

	# ── Que el device de P1 NO mueva el foco de P2 ──
	main._input(_joy_btn(p1dev, JOY_BUTTON_DPAD_DOWN))
	await process_frame
	check(main._abl1_nav["focus"] == a2, "device P1 no afecta la navegación de P2")

	# ── Cerrar el menú con SEL (abilities_menu) ──
	main._input(_joy_btn(p2dev, JOY_BUTTON_BACK))  # _jb("abilities_menu") = BACK por defecto
	await process_frame
	check(main._abl1_open == false, "SEL cierra el menú de P2")

	print("== RESULTADO: %d fallos ==" % failures)
	quit(0 if failures == 0 else 1)
