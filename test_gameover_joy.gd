# Test enfocado: GAME OVER + joystick (single player).
# Verifica el routing del branch GAMEOVER de _joy_menu_nav():
#   - D-pad mueve el cursor del teclado virtual
#   - A (confirm) elige letra  (NO va a menú)
#   - B (back)   borra letra   (NO reinicia mientras el vkb está abierto)
#   - Y (weapon_cycle) salta las iniciales → vkb cerrado, fase GAMEOVER
#   - A (confirm) luego → menú principal (fase MENU)
# NO presiona B tras saltar para no invocar _restart_game() (recarga escena /
# escribe highscores). En su lugar se aserciona la precondición que garantiza
# que ese B caiga en el último `elif back: _restart_game()`.
extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)

func jb_ev(idx: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = idx
	ev.pressed = true
	return ev

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if main.hud == null:
		print("FALLO: hud null")
		quit(1)
		return

	# Estado single player, joystick, GAME OVER pidiendo iniciales.
	main.split_mode = false
	main.mp_role = 0
	main.local_input_mode = 1
	main.score = 0  # defensivo: evita escribir highscore si algo lo dispara
	main.phase = main.GamePhase.GAMEOVER
	main.entering_initials = true
	main.initials = ""
	main.joy_binds = main.JOY_BINDS_DEFAULT.duplicate()  # mapping determinista A/B/Y/DPad
	main._vkb.show()
	check(main._vkb.open == true, "vkb no abrió")
	check(main._vkb.cursor == 0, "cursor inicial != 0 (%d)" % main._vkb.cursor)

	# 1) D-pad derecha mueve el cursor
	main._joy_menu_nav(jb_ev(JOY_BUTTON_DPAD_RIGHT))
	check(main._vkb.cursor == 1, "D-pad der: cursor %d != 1" % main._vkb.cursor)
	main._joy_menu_nav(jb_ev(JOY_BUTTON_DPAD_LEFT))
	check(main._vkb.cursor == 0, "D-pad izq: cursor %d != 0" % main._vkb.cursor)

	# 2) A (confirm) elige letra A — y NO cambia a menú
	main._joy_menu_nav(jb_ev(JOY_BUTTON_A))
	check(main.initials == "A", "A: initials '%s' != A" % main.initials)
	check(main.phase == main.GamePhase.GAMEOVER, "A: fase != GAMEOVER")

	# 3) B (back) borra la letra — y NO reinicia (sigue GAMEOVER)
	main._joy_menu_nav(jb_ev(JOY_BUTTON_B))
	check(main.initials == "", "B: initials '%s' != vacio" % main.initials)
	check(main._vkb.open == true, "B: vkb debería seguir abierto")
	check(main.phase == main.GamePhase.GAMEOVER, "B: fase != GAMEOVER (debería seguir en vkb)")

	# 4) Y (weapon_cycle) salta: cierra el vkb, mantiene GAMEOVER, no guarda
	main._joy_menu_nav(jb_ev(JOY_BUTTON_Y))
	check(main._vkb.open == false, "Y: vkb_open no false")
	check(main.entering_initials == false, "Y: entering_initials no false")
	check(main.phase == main.GamePhase.GAMEOVER, "Y: fase != GAMEOVER")
	await process_frame
	check(main.hud.get_node_or_null("VKB_0") == null, "Y: VKB_0 no liberada")

	# Precondición del branch B→restart (no lo invocamos por recargar escena):
	# con mp_role==0, vkb cerrado y fase GAMEOVER, el único camino para B es
	# el último `elif back: _restart_game()`.
	check(main.mp_role == 0, "precond: mp_role != 0")
	check(main._vkb.open == false and not main.entering_initials, "precond: vkb/entering no cerrados")

	# 5) A (confirm) ahora → menú principal
	main._joy_menu_nav(jb_ev(JOY_BUTTON_A))
	check(main.phase == main.GamePhase.MENU, "A tras saltar: fase != MENU")

	# START también → menú (mismo destino que A)
	main.phase = main.GamePhase.GAMEOVER
	main._joy_menu_nav(jb_ev(JOY_BUTTON_START))
	check(main.phase == main.GamePhase.MENU, "START tras saltar: fase != MENU")

	if fails == 0:
		print("== GAMEOVER-JOY: OK ==")
	else:
		print("== GAMEOVER-JOY: %d fallos ==" % fails)
	quit(0 if fails == 0 else 1)
