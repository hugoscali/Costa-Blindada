# Test de sombras: cascadas del sol recortadas + soldado con sombra solo en la
# silueta (las mallas chicas del rig no proyectan).
# Verifica sobre el scene real (main.tscn) y sobre un soldado generado por
# _create_soldier_mesh().   godot --headless --path . --script res://test_shadows.gd
extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)

# Cuenta meshes con recorrido MANUAL: find_children() no es fiable en nodos que
# todavia no estan dentro de la SceneTree (lo mismo que hace main.gd con los barcos).
func count_meshes(from: Node) -> Array:
	var total := 0
	var casting := 0
	var stack: Array = [from]
	while stack.size() > 0:
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			var mi := nd as MeshInstance3D
			total += 1
			if mi.cast_shadow != 0:
				casting += 1
		for ch in nd.get_children():
			stack.append(ch)
	return [total, casting]

func count_visible_meshes(from: Node) -> Array:
	var total := 0
	var surfaces := 0
	var stack: Array = [from]
	while stack.size() > 0:
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			var mi := nd as MeshInstance3D
			if mi.visible and mi.mesh != null:
				total += 1
				surfaces += mi.mesh.get_surface_count()
		for ch in nd.get_children():
			stack.append(ch)
	return [total, surfaces]


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var sun: DirectionalLight3D = main.sun_light
	check(sun != null, "sun_light null")
	if sun != null:
		print("directional_shadow_mode = %d (esperado %d = PSSM 2 splits)" % [sun.directional_shadow_mode, main.SHADOW_MODE_PSSM_2])
		check(sun.directional_shadow_mode == main.SHADOW_MODE_PSSM_2, "la cascada del sol sigue en 4 splits")
		print("directional_shadow_max_distance = %.1f m, blend_splits = %s" % [sun.directional_shadow_max_distance, sun.directional_shadow_blend_splits])
		check(is_equal_approx(sun.directional_shadow_max_distance, main.SHADOW_MAX_DISTANCE_M), "max_distance de sombra no aplicado")
		check(sun.shadow_enabled, "el sol perdio su sombra")

	# Soldado generado por el propio juego: sombra ON en las mallas visibles
	var sol: Node3D = main._create_soldier_mesh()
	check(sol != null, "soldado null")
	if sol != null:
		var s_cnt: Array = count_meshes(sol)
		var s_vis: Array = count_visible_meshes(sol)
		print("soldado: %d MeshInstance3D (%d visibles, %d superficies dibujables), %d tiran sombra (SOLDIER_CAST_SHADOW=%s)" % [
			s_cnt[0], s_vis[0], s_vis[1], s_cnt[1], str(main.SOLDIER_CAST_SHADOW)])
		check(s_cnt[0] >= 4, "el soldado no tiene meshes (%d)" % s_cnt[0])
		if main.SOLDIER_CAST_SHADOW:
			check(s_cnt[1] >= 1, "SOLDIER_CAST_SHADOW=true pero el soldado no proyecta nada")
			check(s_cnt[1] == s_vis[0], "proyectan %d meshes y hay %d visibles" % [s_cnt[1], s_vis[0]])
		else:
			check(s_cnt[1] == 0, "hay %d meshes de soldado tirando sombra" % s_cnt[1])

		# El resto del mundo NO pierde sus sombras: lancha y tanque
		var boat: Node3D = main._create_boat_mesh(6)
		var b_cnt: Array = count_meshes(boat)
		print("lancha: %d meshes, %d tiran sombra (deben seguir tirando)" % [b_cnt[0], b_cnt[1]])
		check(b_cnt[0] > 0 and b_cnt[1] == b_cnt[0], "la lancha perdio sus sombras")
		var tank: Node3D = main._create_tank_mesh()
		var t_cnt: Array = count_meshes(tank)
		print("tanque: %d meshes, %d tiran sombra (deben seguir tirando)" % [t_cnt[0], t_cnt[1]])
		check(t_cnt[0] > 0 and t_cnt[1] == t_cnt[0], "el tanque perdio sus sombras")
		boat.free()
		tank.free()
		sol.free()

	if fails == 0:
		print("TEST OK: sombras")
		quit(0)
	else:
		print("FALLOS: %d" % fails)
		quit(1)
