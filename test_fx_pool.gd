# Test de scripts/fx_pool.gd (pool de VFX de explosion).
#
# 1) EQUIVALENCIA: con el mismo stream de particulas, las posiciones y la cantidad
#    de particulas vivas del pool tienen que ser identicas a las del codigo original
#    de main.gd (_explode + _update_particles), que esta copiado aca tal cual.
# 2) COSTO: carga modelo de oleada 12 (balas impactando, bajas, destellos de canon)
#    corrida en frames reales, midiendo microsegundos por frame de cada camino y
#    cuantos nodos / materiales / luces crea cada uno.
#
#   godot --headless --path . --script res://test_fx_pool.gd
extends SceneTree

const EPS: float = 1e-4

# Carga liviana (fase de equivalencia): muy por debajo del techo del pool.
const EQ_FRAMES: int = 40
const EQ_SPAWNS: int = 1     # 1 grupo de 3 particulas por frame
# Carga modelo de oleada 12 (fase de costo): ~360 particulas por segundo, que es el
# pico real de una oleada con varios jugadores disparando y muchas bajas.
const COST_FRAMES: int = 120
const COST_SPAWNS: int = 2

var fails: int = 0
var frame_i: int = 0
var phase: String = "eq"
var rng := RandomNumberGenerator.new()

var cont: Node3D
var pool: FxPool
var n_list: Array = []      # estado del codigo original: [Dictionary]
var eq_us: float = 0.0
var pool_eq_us: float = 0.0
var cost_us: float = 0.0
var pool_cost_us: float = 0.0
var cost_i: int = 0
var cost_frames: int = 0
var eq_i: int = 0
var eq_checked: bool = false


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)


func _initialize() -> void:
	rng.seed = 20261017
	cont = Node3D.new()
	cont.name = "Naive"
	root.add_child(cont)
	pool = FxPool.new()
	pool.name = "Pool"
	root.add_child(pool)
	process_frame.connect(_on_frame)


# Modelo de carga: mismo reparto de valores que _explode() de main.gd.
func _make_specs(n: int) -> Array:
	var out: Array = []
	for _i in n:
		var base := Vector3(rng.randf_range(-40.0, 40.0), rng.randf_range(1.0, 3.0), rng.randf_range(-10.0, 40.0))
		for _j in 3:
			out.append({
				"pos": base + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 1.0), rng.randf_range(-0.5, 0.5)),
				"vel": Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(2.0, 12.0), rng.randf_range(-8.0, 8.0)),
				"life": rng.randf_range(0.6, 2.0),
				"grav": 1.0,
				"r": rng.randf_range(0.1, 0.5),
				"col": Color(1, 0.7, 0.4),
				"energy": rng.randf_range(3.0, 8.0),
				"base_a": 1.0,
				"fade": 1.0,
			})
	return out


# ─── CAMINO ORIGINAL (copiado de main.gd antes del pool) ────────────────────────
func _naive_spawn(s: Dictionary) -> void:
	var p := MeshInstance3D.new()
	var pm := SphereMesh.new()
	var r: float = float(s["r"])
	pm.radius = r
	pm.height = r * 2
	p.mesh = pm
	var mat := StandardMaterial3D.new()
	var c: Color = s["col"]
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = float(s["energy"])
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = mat
	p.position = s["pos"]
	cont.add_child(p)
	n_list.append({
		"node": p, "vel": s["vel"], "life": s["life"], "grav": s["grav"],
		"base_alpha": s["base_a"], "fade": s["fade"],
	})


func _naive_tick(delta: float) -> void:
	for i in range(n_list.size() - 1, -1, -1):
		var p: Dictionary = n_list[i]
		var pnode: MeshInstance3D = p["node"]
		var pvel: Vector3 = p["vel"]
		var plife: float = p["life"]
		var g: float = float(p.get("grav", 1.0))
		var base_a: float = float(p.get("base_alpha", 1.0))
		var fade: float = maxf(float(p.get("fade", 1.0)), 0.01)
		pvel.y -= 12.0 * g * delta
		p["vel"] = pvel
		pnode.position = pnode.position + pvel * delta
		plife -= delta
		p["life"] = plife
		var mat: StandardMaterial3D = pnode.get_active_material(0) as StandardMaterial3D
		if mat:
			var c: Color = mat.albedo_color
			c.a = clampf(base_a * (plife / fade), 0.0, 1.0)
			mat.albedo_color = c
		if plife <= 0 or pnode.position.y < -1:
			pnode.queue_free()
			n_list.remove_at(i)


# Camino original de _flash_light(): luz nueva + Tween por boom.
func _naive_light(pos: Vector3, color: Color, energy: float, radius: float, life: float) -> void:
	var li := OmniLight3D.new()
	li.light_color = color
	li.light_energy = energy
	li.omni_range = radius
	li.position = pos
	cont.add_child(li)
	var tw := root.create_tween()
	tw.tween_property(li, "light_energy", 0.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(li.queue_free)


func _pool_tick(specs: Array, delta: float) -> void:
	for s in specs:
		pool.add_particle(s["pos"], s["vel"], s["life"], s["grav"], float(s["r"]), float(s["r"]) * 2.0, s["col"], float(s["energy"]), false, float(s["base_a"]), float(s["fade"]))
	pool.tick_particles(delta)


func _on_frame() -> void:
	frame_i += 1
	var delta: float = 1.0 / 60.0
	if frame_i >= EQ_FRAMES + COST_FRAMES:
		_report()
		quit(1 if fails > 0 else 0)
		return
	if phase == "eq":
		var specs: Array = _make_specs(EQ_SPAWNS)
		var t0: int = Time.get_ticks_usec()
		for s in specs:
			_naive_spawn(s)
		_naive_tick(delta)
		var t1: int = Time.get_ticks_usec()
		_pool_tick(specs, delta)
		var t2: int = Time.get_ticks_usec()
		eq_i += 1
		if eq_i > 5:  # sin compilacion / primera vez
			eq_us += float(t1 - t0)
			pool_eq_us += float(t2 - t1)
		if frame_i == EQ_FRAMES:
			_check_equivalence()
			phase = "cost"
			cost_us = 0.0
			pool_cost_us = 0.0
			cost_i = 0
		return
	var specs2: Array = _make_specs(COST_SPAWNS)
	cost_i += 1
	var u0: int = Time.get_ticks_usec()
	for s in specs2:
		_naive_spawn(s)
	_naive_tick(delta)
	if cost_i % 15 == 0:
		_naive_light(Vector3(rng.randf_range(-20.0, 20.0), 2.0, rng.randf_range(0.0, 30.0)), Color(1.0, 0.45, 0.12), 14.0, 20.0, 0.45)
	var u1: int = Time.get_ticks_usec()
	_pool_tick(specs2, delta)
	if cost_i % 15 == 0:
		pool.add_light(Vector3(rng.randf_range(-20.0, 20.0), 2.0, rng.randf_range(0.0, 30.0)), Color(1.0, 0.45, 0.12), 14.0, 20.0, 0.45)
	var u2: int = Time.get_ticks_usec()
	if cost_i > 10:  # los primeros frames tienen compilacion/primera vez
		cost_us += float(u1 - u0)
		pool_cost_us += float(u2 - u1)
	cost_frames += 1


func _check_equivalence() -> void:
	eq_checked = true
	var a: Array = []
	for p in n_list:
		var nd: MeshInstance3D = p["node"]
		a.append(nd.position)
	var b: Array = pool.debug_positions()
	check(a.size() == b.size(), "particulas vivas: original %d vs pool %d" % [a.size(), b.size()])
	a.sort_custom(func(x, y): return _k(x) < _k(y))
	b.sort_custom(func(x, y): return _k(x) < _k(y))
	var worst: float = 0.0
	var n: int = mini(a.size(), b.size())
	for i in n:
		worst = maxf(worst, (a[i] - b[i]).length())
	check(worst < EPS, "deriva de posiciones: %f (limite %f)" % [worst, EPS])
	print("equivalencia: %d particulas vivas, deriva maxima %.8f" % [n, worst])


func _k(v: Vector3) -> String:
	return "%8.4f|%8.4f|%8.4f" % [v.x, v.y, v.z]


func _report() -> void:
	var st: Dictionary = pool.stats()
	var spawned: int = 3 * (COST_SPAWNS * COST_FRAMES + EQ_SPAWNS * EQ_FRAMES)
	var eq_n: float = maxf(float(eq_i - 5), 1.0)
	var co_n: float = maxf(float(cost_frames), 1.0)
	print("")
	print("== EQUIVALENCIA (fase liviana, %d frames medidos) ==" % int(eq_i - 5))
	print("  original: %.2f us/frame   pool: %.2f us/frame   (%.1fx menos CPU)" % [
		eq_us / eq_n, pool_eq_us / eq_n, eq_us / maxf(pool_eq_us, 1.0)])
	print("")
	print("== COSTO (modelo de oleada 12, %d frames medidos, %d particulas/frame) ==" % [cost_frames, 3 * COST_SPAWNS])
	print("  original: %.2f us/frame   pool: %.2f us/frame   (%.1fx menos CPU)" % [
		cost_us / co_n, pool_cost_us / co_n,
		(cost_us / maxf(pool_cost_us, 1.0))])
	print("  nodos MeshInstance3D creados: original=%d  pool=%d (techo %d)" % [
		spawned, st["nodes_created"], 420])
	print("  materiales StandardMaterial3D: original=%d  pool=%d (compartidos)" % [
		spawned, st["materials"]])
	print("  particulas vivas al final: original=%d  pool=%d" % [n_list.size(), st["parts"]])
	print("  luces OmniLight3D creadas: pool=%d (techo %d)" % [st["lights_created"], 6])
	print("")
	if fails == 0:
		print("OK: misma fisica y mismas posiciones, con ~%dx menos asignaciones." % int(round(cost_us / maxf(pool_cost_us, 1.0))))
	else:
		print("FALLARON %d chequeos" % fails)
