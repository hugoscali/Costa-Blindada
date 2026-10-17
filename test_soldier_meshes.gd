# Diagnostico: mallas del rig de soldado (tamano real de cada una).
# Sirve para decidir cuales tienen que seguir proyectando sombra.
#   godot --headless --path . --script res://test_soldier_meshes.gd
extends SceneTree

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var sol: Node3D = main._create_soldier_mesh()
	if sol == null:
		print("soldado null")
		quit(1)
		return
	var rows: Array = []
	var stack: Array = [sol]
	var rig_height: float = 0.0
	while stack.size() > 0:
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			var mi: MeshInstance3D = nd as MeshInstance3D
			var ab: AABB = AABB()
			if mi.mesh != null:
				ab = mi.mesh.get_aabb()
			var vol: float = ab.size.x * ab.size.y * ab.size.z * absf(mi.scale.x * mi.scale.y * mi.scale.z)
			var surf: float = 2.0 * (ab.size.x * ab.size.y + ab.size.y * ab.size.z + ab.size.x * ab.size.z)
			rows.append([mi.name, ab.size, vol, surf, mi.visible, (mi.mesh.get_surface_count() if mi.mesh != null else 0)])
			rig_height = maxf(rig_height, absf(mi.global_transform.origin.y) + ab.size.y * 0.5)
		for ch in nd.get_children():
			stack.append(ch)
	rows.sort_custom(func(a, b): return float(a[3]) > float(b[3]))
	print("altura estimada del rig: %.2f m" % rig_height)
	print("%-22s %-22s %10s %10s %7s %s" % ["NOMBRE", "AABB x,y,z", "volumen", "superficie", "visible", "surfaces"])
	for r in rows:
		var sz: Vector3 = r[1]
		print("%-22s %-22s %10.4f %10.4f %7s %d" % [str(r[0]), "%.2f,%.2f,%.2f" % [sz.x, sz.y, sz.z], float(r[2]), float(r[3]), str(r[4]), int(r[5])])
	sol.free()
	quit(0)
