# Test del arranque rapido (DEBUG_START_WAVE / DEBUG_START_POINTS).
# Verifica que por defecto el juego arranca NORMAL (oleada 1, 0 puntos) y que con
# los valores puestos arranca en la oleada pedida con sus puntos y su cantidad de
# lanchas, sin romperse al reiniciar.
#   godot --headless --path . --script res://test_start_wave10.gd
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

	# 1) Por defecto: arranque normal
	check(int(main.DEBUG_START_WAVE) == 1, "DEBUG_START_WAVE deberia estar en 1")
	check(int(main.DEBUG_START_POINTS) == 0, "DEBUG_START_POINTS deberia estar en 0")
	main._start_game()
	check(int(main.wave) == 1, "arranca en oleada %d en vez de 1" % int(main.wave))
	check(int(main.combat_pts) == 0, "arranca con %d puntos" % int(main.combat_pts))
	check(int(main.ammo[1]) == 300 and int(main.ammo[2]) == 20, "cargamento inicial cambiado: %s" % str(main.ammo))
	check(int(main.phase) == 1, "phase no es PLAYING")
	var sc1: float = float(main._spawn_scale())
	var esp1: int = maxi(1, int(float(3 + 1 * 2) * sc1))
	check(int(main.enemies_to_spawn) == esp1, "oleada 1 deberia traer %d lanchas (%d)" % [esp1, int(main.enemies_to_spawn)])
	print("arranque normal OK: oleada 1, %d lanchas, 0 puntos" % esp1)

	# 2) Con el arranque rapido puesto: oleada 10 con puntos
	main.DEBUG_START_WAVE = 10
	main.DEBUG_START_POINTS = 400
	main._start_game()
	check(int(main.wave) == 10, "con debug puesto arranca en oleada %d" % int(main.wave))
	check(int(main.combat_pts) == 400, "con debug puesto arranca con %d puntos" % int(main.combat_pts))
	check(int(main.ammo[1]) == 400 and int(main.ammo[2]) == 50, "cargamento de oleada alta no aplicado: %s" % str(main.ammo))
	var sc: float = float(main._spawn_scale())
	var esperado: int = maxi(1, int(float(3 + 10 * 2) * sc))
	print("spawn_scale=%.2f  lanchas de la oleada=%d  (pendientes %d)" % [sc, esperado, int(main.enemies_to_spawn)])
	check(int(main.enemies_to_spawn) == esperado, "enemies_to_spawn no coincide con la formula de oleada 10")

	# Spawn real: el intervalo entre lanchas es de segundos, asi que se simula tiempo
	# de juego (no frames) para ver venir la oleada completa.
	var barcos: int = 0
	for k in 40:
		main._update_wave(3.0)
	for e in main.enemies:
		if str(e.get("type", "")) == "boat":
			barcos += 1
	check(main.enemies.size() >= 20, "no aparecieron las lanchas de la oleada (%d)" % main.enemies.size())
	print("enemies tras simular la oleada: total %d  lanchas %d  pendientes %d" % [
		main.enemies.size(), barcos, int(main.enemies_to_spawn)])

	# El bonus por completar oleada sigue sumando sobre el valor inicial (+25).
	main.enemies.clear()
	main.enemies_to_spawn = 0
	main._update_wave(0.05)
	check(int(main.wave) == 11, "no avanza a la oleada 11 (es %d)" % int(main.wave))
	check(int(main.combat_pts) == 425, "el bonus por oleada no sumo (quedo %d)" % int(main.combat_pts))

	# Apagarlo devuelve el comportamiento normal, incluso en la misma partida.
	main.DEBUG_START_WAVE = 1
	main.DEBUG_START_POINTS = 0
	main._start_game()
	check(int(main.wave) == 1, "apagado el debug no vuelve a la oleada 1 (es %d)" % int(main.wave))
	check(int(main.combat_pts) == 0, "apagado el debug quedan puntos (%d)" % int(main.combat_pts))

	if fails == 0:
		print("TEST OK: arranque normal por defecto y arranque rapido disponible")
	else:
		print("FALLOS: %d" % fails)
	quit(1 if fails > 0 else 0)
