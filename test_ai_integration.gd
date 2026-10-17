# Test de integracion: main.gd usando scripts/enemy_ai.gd (nodos reales).
# Llena main.enemies con soldados/tanque sobre nodos simples y corre el loop de
# enemigos varios frames. Verifica que la IA paralela se aplica (los soldados se
# mueven y se separan) y que no hay errores en tiempo de ejecucion.
#   godot --headless --path . --script res://test_ai_integration.gd
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
	if main == null:
		print("FALLO: main null")
		quit(1)
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var nodes: Array = []
	for i in 160:
		var nd := Node3D.new()
		nd.position = Vector3(rng.randf_range(-30.0, 30.0), 0.0, rng.randf_range(-30.0, 10.0))
		main.add_child(nd)
		nodes.append(nd)
		main.enemies.append({
			"id": 1000 + i, "node": nd, "type": "soldier", "health": 8.0,
			"speed": 3.0, "state": "running", "run_dir": Vector2(0.0, 1.0),
			"stop_t": 40.0, "shots_left": 0, "aim_t": 0.0, "shoot_timer": 1.0,
		})
	var tn := Node3D.new()
	tn.position = Vector3(0.0, 0.0, -14.0)
	main.add_child(tn)
	main.enemies.append({
		"id": 2000, "node": tn, "type": "tank", "health": 2.0, "armor": 2,
		"speed": 1.0, "shoot_timer": 9999.0,
	})

	var before: PackedFloat32Array = PackedFloat32Array()
	for nd in nodes:
		before.append(nd.position.x)
		before.append(nd.position.z)

	for k in 140:
		main._update_enemies(0.016)

	var moved := 0
	for i in nodes.size():
		var nd: Node3D = nodes[i]
		var dx: float = nd.position.x - before[i * 2]
		var dz: float = nd.position.z - before[i * 2 + 1]
		if Vector2(dx, dz).length() > 0.01:
			moved += 1
		check(is_finite(nd.position.x) and is_finite(nd.position.z), "posicion NaN en soldado %d" % i)
	check(moved > 100, "solo %d de %d soldados se movieron" % [moved, nodes.size()])

	# Separacion: con 160 soldados amontonados, nadie deberia quedar pegado a otro
	var min_d := 999.0
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var d: float = (nodes[i] as Node3D).global_position.distance_to((nodes[j] as Node3D).global_position)
			if d < min_d:
				min_d = d
	# La IA paralela tiene que estar alimentando el loop: con 160 soldados juntos,
	# muchos tienen vecinos dentro del radio de separacion.
	var with_sep := 0
	for i in main._ai._n:
		if main._ai.sep_at(i).length() > 0.01:
			with_sep += 1
	print("soldados con vector de separacion activo: %d / %d" % [with_sep, main._ai._n])
	check(with_sep > 50, "la separacion paralela no esta llegando al loop (%d)" % with_sep)

	print("distancia minima entre soldados tras 140 frames: %.2f m (informativo: la linea de contencion los junta a proposito)" % min_d)
	check(min_d > 0.2, "solapamiento total (%.2f m): la separacion no esta aplicando" % min_d)
	check(main.enemies.size() >= 160, "la lista de enemigos se rompio: %d" % main.enemies.size())

	if fails == 0:
		print("TEST OK: integracion main.gd + enemy_ai.gd")
		quit(0)
	else:
		print("FALLOS: %d" % fails)
		quit(1)
