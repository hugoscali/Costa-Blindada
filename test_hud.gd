# Test del HUD perezoso (hud.gd): el HUD tiene que seguir mostrando lo mismo, pero
# sin rehecerse completo cada frame. Verifica que los textos cambian cuando cambia
# el valor y que el trabajo por frame baja.
#   godot --headless --path . --script res://test_hud.gd
extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)


func txt(main: Node, nm: String) -> String:
	var nd = main.hud.get_node_or_null(nm)
	if nd == null:
		return "<falta>"
	return str(nd.text)


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._start_game()
	main._switch_weapon(1)  # AM: es la que muestra un numero de municion (la pistola muestra inf)
	await process_frame
	main._hud.update_hud()
	await process_frame

	check(txt(main, "ScoreLabel") == str(int(main.score)), "score no se pinta: '%s'" % txt(main, "ScoreLabel"))
	check(txt(main, "WaveLabel").contains(str(int(main.wave))), "oleada no se pinta: '%s'" % txt(main, "WaveLabel"))
	check(txt(main, "VidaLabel").contains("%"), "vida no se pinta: '%s'" % txt(main, "VidaLabel"))
	check(txt(main, "AmmoLabel").contains("AM"), "municion no se pinta: '%s'" % txt(main, "AmmoLabel"))
	check(txt(main, "PtsLabel").contains(str(int(main.combat_pts))), "puntos no se pintan: '%s'" % txt(main, "PtsLabel"))
	var hp0 = main.hud.get_child(0) as ProgressBar
	check(hp0 != null and hp0.value > 0.0, "la barra de vida no se actualizo")

	# Cambiar valores -> el HUD tiene que reflejarlo en el mismo frame
	main.score = 12345
	main.combat_pts = 777
	main.health = 42.0
	main.wave = 9
	main.ammo[1] = 271
	main._hud.update_hud()
	check(txt(main, "ScoreLabel") == "12345", "score no se actualizo: '%s'" % txt(main, "ScoreLabel"))
	check(txt(main, "PtsLabel").contains("777"), "puntos no se actualizaron: '%s'" % txt(main, "PtsLabel"))
	check(txt(main, "WaveLabel").contains("9"), "oleada no se actualizo: '%s'" % txt(main, "WaveLabel"))
	check(txt(main, "AmmoLabel").contains("271"), "municion no se actualizo: '%s'" % txt(main, "AmmoLabel"))
	var vida_txt: String = txt(main, "VidaLabel")
	check(vida_txt.contains("%"), "vida perdida: '%s'" % vida_txt)

	# Con valores que no cambian, update_hud no tiene que tocar ningún Label
	var before: String = txt(main, "ScoreLabel") + txt(main, "WaveLabel") + txt(main, "AmmoLabel")
	var t0: int = Time.get_ticks_usec()
	for k in 400:
		main._hud.update_hud()
	var t_skip: int = Time.get_ticks_usec() - t0
	var after: String = txt(main, "ScoreLabel") + txt(main, "WaveLabel") + txt(main, "AmmoLabel")
	check(before == after, "el HUD cambio sin que cambie nada: '%s' -> '%s'" % [before, after])

	# Comparacion: rehacer el HUD completo cada frame (comportamiento anterior)
	main._hud._hud_reset_cache()
	var t1: int = Time.get_ticks_usec()
	for k2 in 400:
		main._hud._hud_reset_cache()
		main._hud.update_hud()
	var t_full: int = Time.get_ticks_usec() - t1
	print("400 frames sin cambios: saltado %.1f us total (%.2f us/frame) vs completo %.1f us total (%.2f us/frame) -> %.1fx menos" % [
		float(t_skip), float(t_skip) / 400.0, float(t_full), float(t_full) / 400.0,
		float(t_full) / maxf(float(t_skip), 1.0)])
	check(float(t_skip) < float(t_full) * 0.5, "no se ahorro trabajo cuando nada cambia")

	# Cambiando valores cada frame, el HUD sigue pintando (no se queda viejo)
	for k3 in 30:
		main.score += 100
		main._hud.update_hud()
	check(txt(main, "ScoreLabel") == str(int(main.score)), "con cambios constantes el HUD se quedo viejo: '%s'" % txt(main, "ScoreLabel"))

	if fails == 0:
		print("TEST OK: HUD perezoso pinta lo mismo y cuesta menos")
	else:
		print("FALLOS: %d" % fails)
	quit(1 if fails > 0 else 0)
