# Test de HitSpace (scripts/hit_space.gd): la seleccion de objetivo tiene que ser
# IDENTICA al loop original (for j descendente sobre todos los enemigos), y tiene
# que ser mucho mas barata con muchas balas.
#   godot --headless --path . --script res://test_hit_space.gd
extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)


# Copia del loop original de _update_projectiles (solo la eleccion de objetivo).
func old_pick(enemies: Array, bpos: Vector3, parea: float) -> int:
	for j in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[j]
		var enode: Node3D = e["node"]
		var edist: float = bpos.distance_to(enode.position)
		var eradius: float
		match e["type"]:
			"boat": eradius = 6.0
			"tank": eradius = 10.0
			"plane": eradius = 10.0
			_: eradius = 3.5
		if edist < eradius + parea:
			return j
	return -1


func new_pick(hs: HitSpace, bpos: Vector3, parea: float) -> int:
	var slot: int = hs.best_hit(bpos, 10.0 + parea, parea)
	if slot < 0:
		return -1
	return hs.ord[slot]


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261017

	# 60 enemigos: lanchas en el mar, soldados agrupados en la playa, tanques y aviones.
	var enemies: Array = []
	var kinds: PackedInt32Array = PackedInt32Array()
	for i in 14:
		var p := Vector3(rng.randf_range(-60, 60), -0.1, rng.randf_range(-80, -40))
		enemies.append({"id": i, "type": "boat", "node": Node3D.new(), "pos": p})
		(enemies[i]["node"] as Node3D).position = p
		kinds.append(HitSpace.K_BOAT)
	for i in range(14, 48):
		var p2 := Vector3(rng.randf_range(-22, 22), 0.9, rng.randf_range(-34, 6))
		var idx: int = enemies.size()
		enemies.append({"id": idx, "type": "soldier", "node": Node3D.new(), "pos": p2})
		(enemies[idx]["node"] as Node3D).position = p2
		kinds.append(HitSpace.K_SOLDIER)
	for i in 3:
		var p3 := Vector3(rng.randf_range(-30, 30), 0.6, rng.randf_range(-40, -10))
		var idx2: int = enemies.size()
		enemies.append({"id": idx2, "type": "tank", "node": Node3D.new(), "pos": p3})
		(enemies[idx2]["node"] as Node3D).position = p3
		kinds.append(HitSpace.K_TANK)
	for i in 5:
		var p4 := Vector3(rng.randf_range(-40, 40), rng.randf_range(14, 22), rng.randf_range(-50, 0))
		var idx3: int = enemies.size()
		enemies.append({"id": idx3, "type": "plane", "node": Node3D.new(), "pos": p4})
		(enemies[idx3]["node"] as Node3D).position = p4
		kinds.append(HitSpace.K_PLANE)

	var hs := HitSpace.new()

	# 400 balas repartidas: algunas apuntan a un enemigo, otras al vacío (lo más común).
	var bullets: Array = []
	for b in 400:
		var t: Vector3 = (enemies[rng.randi() % enemies.size()] as Dictionary)["pos"]
		var bp: Vector3 = t + Vector3(rng.randf_range(-14, 14), rng.randf_range(-3, 4), rng.randf_range(-14, 14))
		if rng.randf() < 0.35:
			bp = Vector3(rng.randf_range(-90, 90), rng.randf_range(0, 25), rng.randf_range(-90, 20))
		bullets.append([bp, [0.0, 0.4, 1.0][rng.randi() % 3]])

	# 1) Equivalencia exacta de la seleccion, con varios parea.
	var hits_old: int = 0
	var hits_new: int = 0
	for parea in [0.0, 0.6, 1.5]:
		hs.clear()
		for j in enemies.size():
			var e: Dictionary = enemies[j]
			var et: String = str(e["type"])
			var r: float = 3.5
			match et:
				"boat": r = 6.0
				"tank", "plane": r = 10.0
			hs.add(e["pos"], r, int(e["id"]), j, kinds[j], e)
		for bp2 in bullets:
			var a: int = old_pick(enemies, bp2[0], parea)
			var b: int = new_pick(hs, bp2[0], parea)
			if a != b:
				fails += 1
				print("FALLO: seleccion distinta parea=%.1f bala=%s viejo=%d nuevo=%d" % [parea, str(bp2[0]), a, b])
				if fails > 6:
					quit(1)
					return
			if a >= 0:
				hits_old += 1
			if b >= 0:
				hits_new += 1
	check(hits_old == hits_new and hits_old > 40, "no hay suficientes impactos de prueba (%d vs %d)" % [hits_old, hits_new])
	print("seleccion identica en %d balas x 3 radios de area: %d impactos" % [bullets.size() * 3, hits_old])

	# Cuantos candidatos visita realmente cada bala (define el costo del loop).
	var visited: int = 0
	for bp0 in bullets:
		visited += hs.candidates(bp0[0], 10.0 + 0.6)
	print("candidatos visitados por bala: %.1f (grilla CELL %.0f m)" % [float(visited) / float(bullets.size()), HitSpace.CELL])

	# 2) Costo: loop viejo vs grilla, misma escena, 40 frames.
	var frames: int = 40
	var t0: int = Time.get_ticks_usec()
	for f in frames:
		for bp3 in bullets:
			old_pick(enemies, bp3[0], 0.6)
	var t_old: int = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for f in frames:
		hs.clear()
		for j in enemies.size():
			var e2: Dictionary = enemies[j]
			hs.add(e2["pos"], hs_rad(str(e2["type"])), int(e2["id"]), j, kinds[j], e2)
	var t_mid: int = Time.get_ticks_usec()
	for f in frames:
		for bp4 in bullets:
			new_pick(hs, bp4[0], 0.6)
	var t_build: int = t_mid - t0
	var t_query: int = Time.get_ticks_usec() - t_mid
	var t_new: int = t_build + t_query
	print("loop viejo: %.1f us/frame   grilla: %.1f us/frame (build %.1f + consultas %.1f)   (%.1fx menos)" % [
		float(t_old) / float(frames), float(t_new) / float(frames),
		float(t_build) / float(frames), float(t_query) / float(frames),
		float(t_old) / maxf(float(t_new), 1.0)])
	check(float(t_new) < float(t_old) * 0.4, "la grilla no es claramente mas barata")

	# 3) Splash: los candidatos dentro del radio son los mismos que el barrido completo.
	var center: Vector3 = (enemies[20] as Dictionary)["pos"]
	hs.clear()
	for j in enemies.size():
		var e3: Dictionary = enemies[j]
		hs.add(e3["pos"], hs_rad(str(e3["type"])), int(e3["id"]), j, kinds[j], e3)
	var rad_query: float = 7.5 + 5.0
	var cn: int = hs.candidates(center, rad_query)
	var got: Array = []
	for ci in cn:
		var s: int = hs.buf[ci]
		var dx: float = center.x - hs.px[s]
		var dy: float = center.y - hs.py[s]
		var dz: float = center.z - hs.pz[s]
		if dx * dx + dy * dy + dz * dz <= rad_query * rad_query:
			got.append(hs.ord[s])
	var want: Array = []
	for j in enemies.size():
		if center.distance_to((enemies[j] as Dictionary)["pos"]) <= rad_query:
			want.append(j)
	got.sort()
	want.sort()
	check(got == want, "splash: candidatos distintos (%s vs %s)" % [str(got), str(want)])
	print("splash sobre %d enemigos: %d candidatos reales, %d visitados" % [enemies.size(), got.size(), cn])

	if fails == 0:
		print("TEST OK: HitSpace da la misma seleccion que el loop original y cuesta menos")
	else:
		print("FALLOS: %d" % fails)
	quit(1 if fails > 0 else 0)


func hs_rad(t: String) -> float:
	match t:
		"boat": return 6.0
		"tank", "plane": return 10.0
	return 3.5
