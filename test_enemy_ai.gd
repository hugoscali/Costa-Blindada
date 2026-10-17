# Test de scripts/enemy_ai.gd (IA de evitacion en paralelo).
# Verifica que los vectores que devuelve EnemyAI son los MISMO que calculaba el
# codigo original de main.gd (separacion de peloton, esquiva de tanques, rocas
# suaves/duras y evasion de balas), y compara el tiempo del camino secuencial
# contra el paralelo con muchos enemigos.
#   godot --headless --path . --script res://test_enemy_ai.gd
extends SceneTree

const EPS: float = 1e-3

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)

# â”€â”€â”€ Referencia: las formulas originales de main.gd, sin optimizar â”€â”€â”€
func ref_sep(i: int, sold: PackedFloat32Array, tanks: PackedFloat32Array) -> Vector2:
	var x: float = sold[i * 2]
	var z: float = sold[i * 2 + 1]
	var out := Vector2.ZERO
	for o in range(sold.size() >> 1):
		if o == i:
			continue
		var away := Vector2(x - sold[o * 2], z - sold[o * 2 + 1])
		var d: float = away.length()
		if d < 7.0 and d > 0.01:
			out += (away / d) * (1.0 - d / 7.0)
	for t in range(tanks.size() >> 1):
		var away2 := Vector2(x - tanks[t * 2], z - tanks[t * 2 + 1])
		var d2: float = away2.length()
		if d2 < 5.5 and d2 > 0.01:
			out += (away2 / d2) * (1.0 - d2 / 5.5)
	if out.length() > 3.0:
		out = out.normalized() * 3.0
	return out

func ref_soft(i: int, sold: PackedFloat32Array, rocks: PackedFloat32Array) -> Vector2:
	var x: float = sold[i * 2]
	var z: float = sold[i * 2 + 1]
	var out := Vector2.ZERO
	for r in range(rocks.size() / 3):
		var rrad: float = rocks[r * 3 + 2]
		var away := Vector2(x - rocks[r * 3], z - rocks[r * 3 + 1])
		var d: float = away.length()
		if d < rrad:
			out += (away / maxf(0.01, d)) * (1.0 - d / rrad) * 4.0
	return out

func ref_fixr(i: int, sold: PackedFloat32Array, rocks: PackedFloat32Array) -> Vector2:
	var x: float = sold[i * 2]
	var z: float = sold[i * 2 + 1]
	var out := Vector2.ZERO
	for r in range(rocks.size() / 3):
		var rrad: float = rocks[r * 3 + 2]
		var away := Vector2(x - rocks[r * 3], z - rocks[r * 3 + 1])
		var d: float = away.length()
		if d < rrad:
			out += (away / maxf(0.01, d)) * (rrad - d)
	return out

func ref_fixt(i: int, sold: PackedFloat32Array, tanks: PackedFloat32Array) -> Vector2:
	var x: float = sold[i * 2]
	var z: float = sold[i * 2 + 1]
	var out := Vector2.ZERO
	for t in range(tanks.size() >> 1):
		var away := Vector2(x - tanks[t * 2], z - tanks[t * 2 + 1])
		var d: float = away.length()
		if d < 2.5:
			out += (away / maxf(0.01, d)) * (2.5 - d)
	return out

func ref_evade(i: int, sold: PackedFloat32Array, bullets: PackedFloat32Array) -> Vector2:
	var x: float = sold[i * 2]
	var z: float = sold[i * 2 + 1]
	var out := Vector2.ZERO
	for b in range(bullets.size() / 4):
		var away := Vector2(x - bullets[b * 4], z - bullets[b * 4 + 1])
		var d: float = away.length()
		if d < 22.0:
			var adir: Vector2 = away / maxf(0.01, d)
			var bdir := Vector2(bullets[b * 4 + 2], bullets[b * 4 + 3])
			out += adir * ((1.0 - d / 22.0) * maxf(0.25, bdir.dot(adir)))
	if out.length() > 3.0:
		out = out.normalized() * 3.0
	return out

func near(a: Vector2, b: Vector2, what: String, i: int) -> void:
	check(a.distance_to(b) < EPS, "%s[%d] %s vs %s" % [what, i, a, b])

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261017

	# Mundo de prueba: 4 pilas de rocas, 2 tanques, 6 balas, N soldados
	var rocks := PackedFloat32Array([
		-10.0, -20.0, 4.0,
		6.0, -18.0, 3.0,
		0.0, -12.0, 5.0,
		14.0, -25.0, 3.5,
	])
	var bullets := PackedFloat32Array([
		-5.0, -22.0, 0.0, 1.0,
		3.0, -15.0, 0.6, 0.8,
		12.0, -24.0, -1.0, 0.0,
		-14.0, -19.0, 0.2, -0.9,
		8.0, -11.0, 0.0, -1.0,
		-2.0, -30.0, 0.0, 1.0,
	])

	for n in [17, 40, 200]:
		var sold := PackedFloat32Array()
		for i in n:
			# Soldados amontonados en la franja donde realmente pelean
			sold.append(rng.randf_range(-20.0, 20.0))
			sold.append(rng.randf_range(-28.0, 20.0))
		var tanks := PackedFloat32Array([
			sold[0] + 1.2, sold[1] + 0.7,   # tanque encima de un soldado (fixt)
			rng.randf_range(-15.0, 15.0), rng.randf_range(-25.0, 5.0),
		])
		var delta := 0.016

		var ai := EnemyAI.new()
		ai.solve(sold, tanks, rocks, bullets, delta)
		var n_sold: int = sold.size() >> 1
		for i in n_sold:
			near(ai.sep_at(i), ref_sep(i, sold, tanks), "sep", i)
			near(ai.soft_at(i), ref_soft(i, sold, rocks), "soft", i)
			near(ai.fixr_at(i), ref_fixr(i, sold, rocks), "fixr", i)
			near(ai.fixt_at(i), ref_fixt(i, sold, tanks), "fixt", i)
			near(ai.evade_at(i), ref_evade(i, sold, bullets), "evade", i)
		print("ok N=%d (paralelo=%s)" % [n, ai._task_count() > 1])

	# Medicion: mismo trabajo, secuencial vs paralelo
	var big := PackedFloat32Array()
	for i in 220:
		big.append(rng.randf_range(-25.0, 25.0))
		big.append(rng.randf_range(-30.0, 25.0))
	var big_tanks := PackedFloat32Array([0.0, -20.0, 8.0, -14.0, -9.0, -24.0])
	var ai2 := EnemyAI.new()
	# warm-up
	ai2.solve(big, big_tanks, rocks, bullets, 0.016)
	var t_par := Time.get_ticks_usec()
	for k in 30:
		ai2.solve(big, big_tanks, rocks, bullets, 0.016)
	var t_par_all := Time.get_ticks_usec() - t_par
	var t_seq := Time.get_ticks_usec()
	for k in 30:
		var n_big: int = big.size() >> 1
		for i in n_big:
			ref_sep(i, big, big_tanks)
			ref_soft(i, big, rocks)
			ref_fixr(i, big, rocks)
			ref_fixt(i, big, big_tanks)
			ref_evade(i, big, bullets)
	var t_seq_all := Time.get_ticks_usec() - t_seq
	print("220 soldados x 30 frames -> EnemyAI: %.1f ms | referencia ingenua: %.1f ms" % [t_par_all / 1000.0, t_seq_all / 1000.0])

	if fails == 0:
		print("TEST OK: enemy_ai.gd")
		quit(0)
	else:
		print("FALLOS: %d" % fails)
		quit(1)
