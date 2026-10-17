# Test de configuración de upscale/Frame Generation por modo (single / LAN / split).
# Single y LAN usan el viewport raiz con la camara principal: tienen DLSS + FG.
# Split usa dos SubViewport: ellos llevan el DLSS, el raiz NO (no renderiza 3D) y por
# eso tampoco FG (el motor solo genera frames para una vista 3D a la vez).
#   godot --headless --path . --script res://test_scaling_modes.gd
extends SceneTree

var fails := 0

const DLSS := 6      # Viewport.SCALING_3D_MODE_DLSS en el fork rtx-godot
const BILINEAR := 0  # Viewport.SCALING_3D_MODE_BILINEAR

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)


func mode_of(nd: Node) -> int:
	return int(nd.get("scaling_3d_mode"))


func fg_of(nd: Node) -> bool:
	return bool(nd.get("frame_generation"))


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# Config fija, sin depender del settings.json de quien corre el test. OJO: este script
	# corre sobre el proyecto real y el juego guarda sus ajustes en user://, asi que se
	# guardan los valores originales y se devuelven al terminar (no queremos pisar los
	# ajustes de quien esta jugando).
	var cfg_orig: Dictionary = {
		"upscaler": int(main.upscaler), "fg": bool(main.fg_enabled), "fsr": int(main.fsr_mode),
	}
	main.upscaler = 1
	main.fg_enabled = true
	main.fsr_mode = 1
	main._apply_fsr()

	check(main._engine_has_dlss(), "el engine no expone DLSS (no es un build rtx-godot)")
	check(mode_of(root) == DLSS, "single: el raiz no quedo en DLSS (es %d)" % mode_of(root))
	check(fg_of(root), "single: el raiz no tiene Frame Generation")
	check(absf(float(root.get("scaling_3d_scale")) - 0.67) < 0.01, "single: la escala no es la de CALIDAD")
	print("single OK: raiz DLSS escala %.2f + FG" % float(root.get("scaling_3d_scale")))

	# ── LAN: host y clientes renderizan con el viewport raiz (no hay SubViewport) ──
	main._setup_net()  # el loop de red vive en el hijo Net: sin eso _process llama a Nil
	main.mp_role = 1
	main.mp_players = 2
	main._start_game_mp()
	await process_frame
	check(mode_of(root) == DLSS, "LAN host: el raiz perdio el DLSS (es %d)" % mode_of(root))
	check(fg_of(root), "LAN host: el raiz perdio el Frame Generation")
	check(main.camera.current, "LAN host: la camara principal no esta activa")
	print("LAN OK: raiz DLSS + FG, camara principal activa")

	# ── Split: el DLSS vive en las mitades, el raiz queda sin upscale 3D ──
	main._menu.on_btn_back_to_menu()
	await process_frame
	main._start_split_game()
	await process_frame
	await process_frame
	var vpa: Node = main.get_node_or_null("SplitVPA")
	var vpb: Node = main.get_node_or_null("SplitVPB")
	check(vpa != null and vpb != null, "no se crearon los SubViewport de split")
	if vpa != null and vpb != null:
		check(mode_of(vpa) == DLSS and mode_of(vpb) == DLSS,
			"split: las mitades no tienen DLSS (%d / %d)" % [mode_of(vpa), mode_of(vpb)])
		check(absf(float(vpa.get("scaling_3d_scale")) - 0.67) < 0.01, "split: las mitades no heredaron la escala")
		check(not fg_of(vpa) and not fg_of(vpb), "split: las mitades pidieron Frame Generation")
	check(mode_of(root) == BILINEAR, "split: el raiz sigue con upscale 3D (%d)" % mode_of(root))
	check(not fg_of(root), "split: el raiz sigue con Frame Generation")
	check(not main.camera.current, "split: la camara principal sigue activa")
	print("split OK: mitades DLSS escala %.2f, raiz sin upscale ni FG" % float(vpa.get("scaling_3d_scale")))

	# Cambiar las opciones de upscale a mitad de split: las mitades la reciben, el raiz no
	main.fsr_mode = 0
	main._apply_fsr()
	if vpa != null and vpb != null:
		check(absf(float(vpa.get("scaling_3d_scale")) - 0.5) < 0.01,
			"split: cambiar el preset no llego a las mitades (%.2f)" % float(vpa.get("scaling_3d_scale")))
		check(mode_of(vpa) == DLSS, "split: las mitades perdieron DLSS al cambiar el preset")
	check(mode_of(root) == BILINEAR, "split: el raiz recupero upscale 3D al cambiar el preset")

	# Volver a single/LAN: el raiz recupera el upscale y el FG configurados
	main._teardown_split()
	await process_frame
	check(mode_of(root) == DLSS, "tras salir de split el raiz no volvio a DLSS (es %d)" % mode_of(root))
	check(fg_of(root), "tras salir de split el raiz no volvio a tener Frame Generation")
	check(main.camera.current, "tras salir de split la camara principal no se reactiva")

	# Upscale OFF: ni el raiz ni las mitades deben pedir scaling
	main.upscaler = 2
	main._apply_fsr()
	check(mode_of(root) == BILINEAR, "upscaler OFF: el raiz no quedo sin scaling (es %d)" % mode_of(root))
	check(not fg_of(root), "upscaler OFF: el raiz conserva Frame Generation")

	# Devolver los ajustes del usuario: este test escribe settings.json al aplicar
	main.upscaler = int(cfg_orig["upscaler"])
	main.fg_enabled = bool(cfg_orig["fg"])
	main.fsr_mode = int(cfg_orig["fsr"])
	main._apply_fsr()

	if fails == 0:
		print("TEST OK: DLSS/FG correctos en single, LAN y split")
	else:
		print("FALLOS: %d" % fails)
	quit(1 if fails > 0 else 0)
