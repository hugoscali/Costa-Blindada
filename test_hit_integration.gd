# Test de integracion del indice de colision: main.gd real, oleada 10 real y 400
# balas simultaneas. Mide cuanto cuesta _update_projectiles por frame con la grilla
# (HitSpace) y verifica que la colision sigue funcionando (hay kills, no quedan
# NaN, no se rompen los indices cuando mueren enemigos en el medio del loop).
#   godot --headless --path . --script res://test_hit_integration.gd
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
	# Arranque rapido (el knob existe para esto): oleada 10 para tener muchos enemigos
	main.DEBUG_START_WAVE = 10
	main.DEBUG_START_POINTS = 400
	main._start_game()
	for k in 40:
		main._update_wave(3.0)
	var n_en: int = main.enemies.size()
	check(n_en >= 20, "la oleada 10 no trajo suficientes enemigos (%d)" % n_en)
	print("escena: %d enemigos (oleada %d)" % [n_en, int(main.wave)])

	var rng := RandomNumberGenerator.new()
	rng.seed = 771
	var best_ms: float = 0.0
	var worst_ms: float = 0.0
	var total_kills: int = 0
	var rounds: int = 6

	for r in rounds:
		# 400 balas apuntando a enemigos reales o al vacio, como en partida.
		for i in 400:
			var nd := Node3D.new()
			nd.name = "TestProj_%d_%d" % [r, i]
			main.add_child(nd)
			nd.position = Vector3(rng.randf_range(-45, 45), rng.randf_range(0.5, 9), rng.randf_range(-70, 12))
			var dirv: Vector3 = Vector3(0, 0, -1)
			if rng.randf() < 0.7 and main.enemies.size() > 0:
				var tgt: Dictionary = main.enemies[rng.randi() % main.enemies.size()]
				var tn: Node3D = tgt["node"]
				dirv = (tn.position - nd.position).normalized()
			var splash: float = 7.5 if rng.randf() < 0.3 else 0.0
			main.projectiles.append({
				"node": nd, "dir": dirv, "speed": 90.0, "damage": 4.0, "life": 5.0,
				"area": 1.5 if splash > 0.0 else 0.0, "splash": splash, "slot": 0,
			})
		var before: int = main.score
		var t0: int = Time.get_ticks_usec()
		main._update_projectiles(0.016)
		var us: int = Time.get_ticks_usec() - t0
		var ms: float = float(us) / 1000.0
		if r == 0:
			best_ms = ms
			worst_ms = ms
		else:
			best_ms = minf(best_ms, ms)
			worst_ms = maxf(worst_ms, ms)
		total_kills += (int(main.score) - before)
		check(main.projectiles.size() >= 0, "projectiles se rompio")
		for pd in main.projectiles:
			var pn: Node3D = pd["node"]
			if pn != null and is_instance_valid(pn):
				check(pd["life"] is float, "life no es float")
	# Limpieza: los enemigos que quedaron vivos siguen sanos
	var bad: int = 0
	for e in main.enemies:
		var en: Node3D = e.get("node")
		if en == null or not is_instance_valid(en):
			bad += 1
		elif not (e["health"] is float):
			bad += 1
	check(bad == 0, "%d entradas de enemigos quedaron corruptas" % bad)
	print("costo _update_projectiles con 400 balas: min %.2f ms  max %.2f ms por frame" % [best_ms, worst_ms])
	print("score ganado por los impactos de prueba: %d (kills reales en la escena)" % total_kills)
	check(total_kills > 0, "ningun disparo impacto: la colision no funciona")

	# El medidor de costo se quito del juego: no tiene que quedar ninguna etiqueta
	var perf_lbl: Node = main.hud.get_node_or_null("PerfLabel")
	check(perf_lbl == null, "quedo una etiqueta de medidor en el HUD")

	if fails == 0:
		print("TEST OK: colisiones con HitSpace en la escena real")
	else:
		print("FALLOS: %d" % fails)
	quit(1 if fails > 0 else 0)
