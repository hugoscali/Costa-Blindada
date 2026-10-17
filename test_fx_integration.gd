# Test de integracion: main.gd usando scripts/fx_pool.gd con el scene real.
# Dispara explosiones reales (_hit_spark, _big_boom, _muzzle_flash, _smoke_burst)
# y verifica que:
#  - el pool existe y recibe las particulas,
#  - la cantidad de nodos/materiales/luces queda ACOTADA aunque explote mucho,
#  - las instancias Binbun se reutilizan (no crecen con los booms),
#  - las particulas mueren y no dejan NaN ni nodos colgados,
#  - el reinicio (_vfx_release_all / _fx.release_all) deja todo listo para reusar.
#   godot --headless --path . --script res://test_fx_integration.gd
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

	check(main._fx != null, "main._fx no existe")
	if main._fx == null:
		quit(1)
		return
	check(main._fx.is_inside_tree(), "main._fx no esta en la SceneTree")
	main._load_binbun_vfx()
	print("VFX Binbun: ground=%s air=%s nuke=%s muzzle=%s" % [
		str(main._vfx_exp_ground != null), str(main._vfx_exp_air != null),
		str(main._vfx_exp_nuke != null), str(main._vfx_muzzle != null)])

	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	# Tormenta de oleada 12: impactos, bajas de vehiculo, destellos de canon, humo.
	for k in 120:
		main._hit_spark(Vector3(rng.randf_range(-25.0, 25.0), 1.5, rng.randf_range(-5.0, 35.0)), 9, Color(1.0, 0.8, 0.35))
		if k % 3 == 0:
			main._big_boom(Vector3(rng.randf_range(-25.0, 25.0), 1.5, rng.randf_range(0.0, 35.0)), 1.4, Color(1.0, 0.45, 0.12), false)
		if k % 2 == 0:
			main._muzzle_flash(Vector3(rng.randf_range(-6.0, 6.0), 2.2, 26.0), Vector3(0, -0.05, -1.0), false)
		if k % 5 == 0:
			main._smoke_burst(Vector3(rng.randf_range(-20.0, 20.0), 2.0, rng.randf_range(0.0, 30.0)), 9)
		main._update_particles(0.016)
		await process_frame

	var st: Dictionary = main._fx.stats()
	print("")
	print("pool tras 120 frames de explosiones: %s" % str(st))
	# Techo real del pool: MAX_PARTICLES(420) + MAX_FLASHES(48) nodos de malla.
	check(st["parts"] > 0, "el pool no recibio ninguna particula")
	check(st["nodes_created"] <= 468, "el pool creo %d nodos (techo 468)" % st["nodes_created"])
	check(st["lights_created"] <= 6, "el pool creo %d luces (techo 6)" % st["lights_created"])
	check(st["materials"] < 400, "se crearon %d materiales (deberian estar compartidos)" % st["materials"])

	# Las instancias Binbun: cantidad acotada y reutilizadas.
	var busy: int = main._vfx_busy.size()
	var pooled: int = 0
	for arrv in main._vfx_free.values():
		pooled += (arrv as Array).size()
	print("instancias Binbun: busy=%d reutilizables=%d" % [busy, pooled])
	var total_vfx: int = 0
	for c in main._fx.get_children():
		if c.name.begins_with("Vfx"):
			total_vfx += 1
	print("nodos VFX creados bajo el pool: %d" % total_vfx)
	check(total_vfx <= main.VFX_CAP_GROUND + main.VFX_CAP_AIR + main.VFX_CAP_NUKE + main.VFX_CAP_MUZZLE, "se crearon %d instancias VFX (sin techo)" % total_vfx)

	# Sigue la tormenta: el pool NO tiene que seguir creando nodos.
	var before_nodes: int = st["nodes_created"]
	for k in 120:
		main._hit_spark(Vector3(rng.randf_range(-25.0, 25.0), 1.5, rng.randf_range(-5.0, 35.0)), 9, Color(1.0, 0.6, 0.2))
		if k % 3 == 0:
			main._big_boom(Vector3(rng.randf_range(-25.0, 25.0), 1.5, rng.randf_range(0.0, 35.0)), 1.9, Color(1.0, 0.4, 0.1), false)
		main._update_particles(0.016)
		await process_frame
	var st2: Dictionary = main._fx.stats()
	print("pool tras la segunda tormenta: %s" % str(st2))
	check(st2["nodes_created"] <= before_nodes + 12, "el pool siguio asignando nodos: %d -> %d" % [before_nodes, st2["nodes_created"]])

	# Muerte de particulas: despues de dejarlas vivir, no pueden quedar colgadas.
	for k in 260:
		main._update_particles(0.016)
		await process_frame
	var st3: Dictionary = main._fx.stats()
	print("pool tras dejar expirar todo: %s" % str(st3))
	check(st3["parts"] == 0, "quedaron %d particulas colgadas" % st3["parts"])
	check(st3["lights"] == 0, "quedaron %d luces encendidas" % st3["lights"])
	check(st3["flashes"] == 0, "quedaron %d destellos colgados" % st3["flashes"])

	# NaN y nodos validos
	var bad: int = 0
	var hidden: int = 0
	for c in main._fx.get_children():
		if c is MeshInstance3D:
			if not c.visible:
				hidden += 1
			elif not is_finite(c.position.x) or not is_finite(c.position.y) or not is_finite(c.position.z):
				bad += 1
	check(bad == 0, "%d particulas con posicion NaN" % bad)
	print("nodos del pool ocultos y listos para reusar: %d" % hidden)
	check(hidden > 50, "el pool no esta reciclando nodos (%d ocultos)" % hidden)

	# Reinicio de partida: limpia y deja el pool reutilizable
	main._fx.release_all()
	main._vfx_release_all()
	var st4: Dictionary = main._fx.stats()
	check(st4["parts"] == 0, "release_all dejo %d particulas" % st4["parts"])
	check(main._vfx_busy.size() == 0, "release_all dejo %d instancias VFX ocupadas" % main._vfx_busy.size())
	main._hit_spark(Vector3(0, 2, 10), 6, Color(1, 1, 0.5))
	check(main._fx.stats()["parts"] > 0, "despues del reinicio el pool no vuelve a funcionar")
	var st5: Dictionary = main._fx.stats()
	check(st5["nodes_created"] == st4["nodes_created"], "el reinicio volvio a crear nodos (%d -> %d)" % [st4["nodes_created"], st5["nodes_created"]])

	# Medidor de costo: se quito del juego (cumplio su trabajo). El pool tiene que
	# seguir dejando todos sus nodos ocultos y listos para reusar.
	if fails == 0:
		print("TEST OK: integracion main.gd + fx_pool.gd")
		quit(0)
	else:
		print("FALLOS: %d" % fails)
		quit(1)
