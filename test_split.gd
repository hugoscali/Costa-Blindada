# Test split-screen 2P: arranque, disparo J2, espejos, game over 2P, teardown.
extends SceneTree

var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  ", msg)
	else:
		failures += 1
		print("  FAIL", msg)

func _init() -> void:
	print("== TEST SPLIT 2P ==")
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main: Node = ps.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# ── Arranque de split ──
	main._start_split_game()
	await process_frame
	await process_frame
	check(main.split_mode == true, "split_mode activo")
	check(main.mp_role == 3, "mp_role == 3 (split)")
	check(main.mp_players == 2, "mp_players == 2")
	check(main.vp_a != null and main.vp_b != null, "viewports A/B creados")
	check(main.slot_states.size() == 2, "2 slots de estado")
	check(main.base_hp_max == 150.0, "base 150 HP (regla LAN 2P)")
	check(main.vp_a.get_node_or_null("CamA") != null, "cam_a dentro de vp_a")
	check(main.vp_b.get_node_or_null("CamB") != null, "cam_b dentro de vp_b")
	check(main.gun_a != null and main.gun_b != null, "viewmodels de arma J1/J2")
	check(main.vp_a.own_world_3d == true and main.vp_b.own_world_3d == true, "own_world_3d en A/B (sin arma original fantasma)")
	# El cañón izquierdo de arma 2 debe existir y con scale positiva intacta en el clone del split
	var sl_o: Node3D = main.camera.get_node_or_null("Gun/W_SMG/SMG_Left") as Node3D
	var sl_c: Node3D = main.gun_a.get_node_or_null("W_SMG/SMG_Left") as Node3D
	check(sl_o != null and sl_c != null, "arma2 izquierda existe en original y clone")
	if sl_o != null and sl_c != null:
		check(absf(sl_c.scale.x - 0.72) < 0.01 and absf(sl_c.scale.y - 0.72) < 0.01 and absf(sl_c.scale.z - 0.72) < 0.01, "scale intacta en clone split (scale=%s)" % str(sl_c.scale))
	check(main.world.visible == false, "mundo original oculto (renderiza en viewports)")
	check(main.camera.current == false, "camara principal no-current (render en viewports)")

	# ── Terrain3D fresco por viewport (fix: duplicate(true) no trae el atlas de texturas) ──
	var terr_a: Node = main.vp_a.get_node_or_null("World/Terrain3D")
	var terr_b: Node = main.vp_b.get_node_or_null("World/Terrain3D")
	check(terr_a != null, "Terrain3D presente en vp_a")
	check(terr_b != null, "Terrain3D presente en vp_b")
	if terr_a != null:
		check(terr_a.get("material") != null, "Terrain3D(vp_a).material creado (evita error world_background)")
	if terr_b != null:
		check(terr_b.get("material") != null, "Terrain3D(vp_b).material creado (evita error world_background)")

	# ── Espejos: spawn de barco ──
	var n_before: int = main._mirrors.size()
	main._spawn_boat()
	await process_frame
	await process_frame
	check(main._mirrors.size() == n_before + 1, "barco nuevo registrado en espejos (%d -> %d)" % [n_before, main._mirrors.size()])
	var mi: Dictionary = main._mirrors[main._mirrors.size() - 1]
	var c1: Node = mi["c1"]
	var c2: Node = mi["c2"]
	check(c1 != null and is_instance_valid(c1), "copia en vp_a existe")
	check(c2 != null and is_instance_valid(c2), "copia en vp_b existe")
	if c1 != null:
		check(c1.get_parent() == main.vp_a, "copia A padre == vp_a")
	if c2 != null:
		check(c2.get_parent() == main.vp_b, "copia B padre == vp_b")

	# ── VFX en las dos mitades (fix: en split no explotaba nada) ──
	check(main._fx_a != null and main._fx_b != null, "pools de VFX creados para cada mitad")
	check(main._fx.mirror_count() == 2, "_fx tiene 2 pools espejo")
	if main._fx_a != null and main._fx_b != null:
		check(main._fx_a.get_parent() == main.vp_a, "pool A vive dentro de vp_a")
		check(main._fx_b.get_parent() == main.vp_b, "pool B vive dentro de vp_b")
	main._explode(Vector3(0.0, 2.0, -30.0), 14, Color(1.0, 0.6, 0.2))
	main._shockwave_ring(Vector3(0.0, 2.0, -30.0), Color(1.0, 0.6, 0.2), 1.0)
	main._flash_light(Vector3(0.0, 2.0, -30.0), Color(1.0, 0.8, 0.4), 10.0, 12.0, 0.3)
	await process_frame
	var pa: Array = main._fx_a.debug_positions()
	var pb: Array = main._fx_b.debug_positions()
	check(pa.size() > 0 and pa.size() == pb.size(), "las particulas existen en AMBAS mitades (A=%d B=%d)" % [pa.size(), pb.size()])
	check(int(main._fx.stats().get("parts", -1)) == 0, "el arbol principal no crea VFX extra en split (sin triple costo)")
	var la: Array = main._fx_a.debug_light_energies()
	var lb: Array = main._fx_b.debug_light_energies()
	check(la.size() == 1 and lb.size() == 1, "luz de destello en ambas mitades (A=%d B=%d)" % [la.size(), lb.size()])
	var moved := false
	if pa.size() > 0:
		await process_frame
		var pa2: Array = main._fx_a.debug_positions()
		if pa2.size() == pa.size():
			for i in pa2.size():
				if pa2[i] != pa[i]:
					moved = true
					break
	check(moved, "las particulas espejadas se integran (tick cascadea a las mitades)")

	# ── Explosiones Binbun: instancia propia en cada mitad ──
	main._big_boom(Vector3(10.0, 1.0, -25.0), 1.0, Color(1.0, 0.7, 0.3), false)
	await process_frame
	var busy_bb: int = main._vfx_busy.size()
	var cps: int = 0
	var vis_copies: int = 0
	for k in main._vfx_copies:
		for c in main._vfx_copies[k]:
			cps += 1
			if c != null and is_instance_valid(c) and (c as Node3D).visible:
				vis_copies += 1
	check(busy_bb >= 1, "explosion Binbun en juego (%d)" % busy_bb)
	check(cps == 2 * busy_bb, "cada explosion Binbun tiene copia en cada mitad (%d copias / %d efectos)" % [cps, busy_bb])
	check(vis_copies == cps and cps > 0, "las copias estan visibles")
	var in_vp: int = 0
	for k in main._vfx_copies:
		for c in main._vfx_copies[k]:
			if c != null and is_instance_valid(c) and c.get_parent() in [main._fx_a, main._fx_b]:
				in_vp += 1
	check(in_vp == cps, "cada copia cuelga del pool de su mitad (dentro del viewport), no del arbol principal")

	# ── Helice del helicoptero en las dos mitades ──
	main._spawn_plane_from_warship()
	await process_frame
	await process_frame
	var heli_mi: Dictionary = main._mirrors[main._mirrors.size() - 1]
	var spins: Array = heli_mi.get("spins", [])
	check(spins.size() == 2, "las 2 helices quedan registradas como nodos a espejar (%d)" % spins.size())
	if spins.size() == 2:
		var r_o: Node3D = spins[0]["o"]
		var r_a: Node3D = spins[0]["c1"]
		var r_b: Node3D = spins[0]["c2"]
		var r0: float = r_a.rotation.y
		await process_frame
		await process_frame
		check(absf(r_o.rotation.y - r0) > 0.01, "la helice original gira (%.3f -> %.3f)" % [r0, r_o.rotation.y])
		check(absf(r_a.rotation.y - r0) > 0.01, "la helice gira en la mitad A (%.3f -> %.3f)" % [r0, r_a.rotation.y])
		check(absf(r_b.rotation.y - r_o.rotation.y) < 0.05, "la helice de la mitad B sincronizada con la original")

	# ── Disparo J2 (slot 1, estacion +22) ──
	main.slot_states[1].aim = [0.0, 0.0]
	main.slot_states[1].weapon = 1
	main._shoot_for(1)
	await process_frame
	var found_p2 := false
	var origin_ok := false
	for p in main.projectiles:
		if int(p.get("slot", -1)) == 1:
			found_p2 = true
			var n: Node3D = p["node"]
			origin_ok = absf(n.position.x - 22.0) < 3.0
	check(found_p2, "proyectil de J2 con slot 1")
	check(origin_ok, "origen disparo J2 ~ (+22, 5, 0)")
	# municion J2 descontada
	var st1: Dictionary = main.slot_states[1]
	check(int(st1.ammo[1]) == 299, "municion J2 arma2 = 299")

	# ── Disparo J1 (slot 0, via _shoot local) ──
	main.current_weapon = 1
	main.last_shot_time = 0.0
	main._shoot()
	await process_frame
	var found_p1 := false
	for p in main.projectiles:
		if int(p.get("slot", -1)) == 0:
			found_p1 = true
	check(found_p1, "proyectil de J1 con slot 0")

	# ── Cambio de arma J2 (gamepad logic) ──
	main._split_switch_weapon(2)
	check(main.p2_weapon == 2, "p2_weapon == 2")
	check(int(main.slot_states[1].weapon) == 2, "slot1.weapon == 2")
	var w2v: Node = main.gun_b.get_node_or_null("W_Cannon")
	check(w2v != null and w2v.visible == true, "gun_b muestra W_Cannon")
	var w0v: Node = main.gun_b.get_node_or_null("W_Pistol")
	check(w0v != null and w0v.visible == false, "gun_b oculta W_Pistol")

	# ── HUD split ──
	main._hud.update_hud()  # el HUD ahora está en scripts/hud.gd (HudUI)
	var wpn1: Label = main.hud.get_node_or_null("WeaponIndicatorP1/WeaponLabel") as Label
	check(wpn1 != null, "WeaponIndicatorP1 existe")
	var wpn2: Label = main.hud.get_node_or_null("WeaponIndicator/WeaponLabel") as Label
	check(wpn2 != null and wpn2.text.find("Cañón") >= 0, "indicador derecha muestra Cañón (J2): '%s'" % wpn2.text)

	# ── Game over 2P + iniciales + guardado ──
	main.score = 1234  # simular puntuacion acumulada (con score 0 no se guarda, por diseño)
	main._split_gameover()
	await process_frame
	check(main.phase == main.GamePhase.GAMEOVER, "fase GAMEOVER")
	check(main.mp_go_phase == 0, "mp_go_phase 0 (esperando iniciales)")
	check(main.mp_roster.size() == 2 and main.mp_roster[0] == "", "roster 2P vacio inicial")
	# J1 (teclado)
	main._mp_send_my_initials("abc")
	check(str(main.mp_roster[0]) == "ABC", "roster[0] = ABC (J1)")
	# J2 (gamepad): teclado virtual por mando (D-pad mueve el cursor, A elige, START guarda)
	main._svkb[1].move(0, 1)   # cursor 0 -> 1 ('B')
	main._svkb[1].select()       # agrega letra en el cursor
	main._svkb[1].move(1, 0)   # baja a la segunda fila
	main._svkb[1].move(0, 1)   # mueve a la derecha
	main._svkb[1].select()       # agrega letra
	main._svkb[1].select()       # agrega letra
	main._svkb[1].submit()
	check(main.mp_go_phase == 2, "mp_go_phase 2 (guardado)")
	# la puntuacion de equipo debio guardarse en la categoria "2"
	var hs: Array = main._hs_load_cat("2") if main.has_method("_hs_load_cat") else []
	if main.has_method("_hs_cat_rows"):
		pass
	print("  info hs_mp[2] size =", main.hs_mp.get("2", []).size())
	check((main.hs_mp.get("2", []) as Array).size() >= 1, "puntuacion guardada en categoria 2P")

	# ── Teardown ──
	main._teardown_split()
	await process_frame
	check(main.split_mode == false, "split_mode desactivado")
	check(main.vp_a == null and main.vp_b == null, "viewports liberados")
	check(main._fx_a == null and main._fx_b == null, "pools de VFX del split liberados")
	check(main._fx.mirror_count() == 0, "espejos de VFX cortados al salir de split")
	check(main._vfx_free_m.is_empty() and main._vfx_copies.is_empty(), "sin instancias espejadas colgando")
	main._explode(Vector3(0.0, 2.0, -30.0), 10, Color(1.0, 1.0, 1.0))
	check(int(main._fx.stats().get("parts", 0)) > 0, "de vuelta en single, el pool principal vuelve a crear su propio VFX")
	check(main.world.visible == true, "mundo restaurado visible")
	check(main.camera.current == true, "camara principal restaurada")
	check((main.hud.get_node_or_null("WeaponIndicatorP1") as Node).visible == false, "WeaponIndicatorP1 oculta")

	print("== RESULTADO: %d fallos ==" % failures)
	quit(0 if failures == 0 else 1)
