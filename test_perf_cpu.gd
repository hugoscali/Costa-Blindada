extends SceneTree
# test_perf_cpu.gd - banco de medicion de CPU (no toca el juego, solo lo llama).
#
# En headless no hay GPU: lo que se mide ahi es la logica de juego pura, o sea el
# trabajo de frame que despues se ve como tope de FPS en maquina lenta. Mide:
#   A) ms por frame con la oleada llena (1P y split 2P) + huerfanos por frame
#   B) us por llamada de cada subsistema, con la carga real del juego
#   C) churn: memoria y objetos creados por subsistema (causa de los pico)
#   D) costo de crear una bala / un soldado / un avion (costo de spawn)
#
#   godot --headless --path . --script test_perf_cpu.gd -- 14 400
#         (oleada, balas en vuelo)
#
# Detalles que importan para que el numero sea real:
#  - el informe se escribe solo, a user://perf_cpu.txt (stdout mezclado con stderr
#    del motor se pierde y desordena)
#  - entre bench y bench se espera un frame: si no, los queue_free del juego nunca
#    se procesan y la escena se llena de nodos zombie (los numeros suben solos)
#  - las balas de prueba se arman a mano con dir horizontal: si salen del canon,
#    con la playa llena de enemigos se comen todas en el primer frame y la medida
#    queda con 1 bala en vez de 400

var wave_target: int = 14
var want_bullets: int = 400
var want_enemies: int = 90
var failures: int = 0
var M: Node = null
var fp: FileAccess = null

const STEP: float = 0.0166


func say(s: String) -> void:
	print(s)
	if fp != null:
		fp.store_line(s)


func check(cond: bool, msg: String) -> void:
	if cond:
		say("  OK  " + msg)
	else:
		failures += 1
		say("  FAIL  " + msg)


func arg_int(i: int, dft: int) -> int:
	var ua: PackedStringArray = OS.get_cmdline_user_args()
	if i < ua.size():
		return int(ua[i])
	return dft


# Promedio de us por llamada + cuanto crea. Los huerfanos (RefCounted/Variants sin
# referencia) son lo que despues aparece como pico de CPU cuando se limpia memoria.
func bench(label: String, iters: int, fn: Callable) -> void:
	bench_n(label, iters, 1, fn)


# Igual que bench() pero dividiendo el tiempo entre las `per` llamadas que el cierre
# hace por iteracion: sirve para medir cosas de sub-micro (heightmap, get_node).
func bench_n(label: String, iters: int, per: int, fn: Callable) -> void:
	var n0: int = M.enemies.size()
	var b0: int = M.projectiles.size()
	var t0: int = Time.get_ticks_usec()
	var mem0: int = int(OS.get_static_memory_usage())
	var obj0: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var orph_max: int = 0
	var i: int = 0
	while i < iters:
		fn.call()
		var o: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		if o > orph_max:
			orph_max = o
		i += 1
	var dt_us: float = float(Time.get_ticks_usec() - t0) / (float(iters) * float(per))
	var dmem: int = int(OS.get_static_memory_usage()) - mem0
	var dobj: int = int(Performance.get_monitor(Performance.OBJECT_COUNT)) - obj0
	say("  %-26s %8.2f us  %6.1f%%frame  mem %+7.1f KB/lam  obj %+5d  huerf %6d  [%d->%d enm, %d->%d bal, %d espejos]" % [
		label, dt_us, dt_us / 16.6 * 100.0, float(dmem) / 1024.0 / float(iters), dobj,
		orph_max, n0, M.enemies.size(), b0, M.projectiles.size(), M._mirrors.size()])
	if fp != null:
		fp.flush()


func state_counts() -> String:
	var s: Dictionary = M._fx.stats()
	return "enemigos=%d  balas=%d  balas_enemigas=%d  vfx=%d  partes_fx=%d  nodos=%d  espejos=%d" % [
		M.enemies.size(), M.projectiles.size(), M.enemy_projectiles.size(),
		M._vfx_busy.size(), int(s.get("parts", -1)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), M._mirrors.size()]


# --- balas de prueba ---------------------------------------------------------
# Se meten directo en la lista de proyectiles del juego (misma forma que main usa
# en 6191), con direction horizontal y altura variada: asi vuelan de verdad y la
# medida del loop de proyectiles tiene con que trabajar.
func make_flight(n: int) -> void:
	for k in n:
		var is_cannon: bool = k % 8 == 0
		var proj: Node3D
		if is_cannon:
			proj = M._create_missile()
		else:
			proj = M._create_projectile(0.35, Color(1, 1, 0.3))
		proj.name = "BenchProj_%d" % M.projectiles.size()
		var x0: float = randf_range(-260.0, 260.0)
		var z0: float = randf_range(-160.0, 200.0)
		var y0: float = 6.0 if is_cannon else randf_range(1.0, 3.0)
		proj.position = Vector3(x0, y0, z0)
		M.add_child(proj)
		var dirv: Vector3 = Vector3(1.0, 0.0, 0.0) if k % 2 == 0 else Vector3(-0.6, 0.0, 0.8)
		M.projectiles.append({
			"node": proj, "dir": dirv.normalized(), "speed": 120.0 if is_cannon else 220.0,
			"damage": 40.0 if is_cannon else 12.0, "life": 4.0,
			"area": 1.5 if is_cannon else 0.0, "splash": 7.5 if is_cannon else 0.0,
			"missile": is_cannon, "slot": -1
		})


func topup_enemy_shots(n: int) -> void:
	for k in n:
		var p: Vector3 = Vector3(randf_range(-40, 40), 2.0, -20.0)
		M._enemy_shoot(p, Vector3(0.0, 2.0, 60.0))


func refill(target_b: int) -> void:
	var guard: int = 0
	while M.projectiles.size() < target_b and guard < 20:
		make_flight(maxi(20, target_b - M.projectiles.size()))
		guard += 1
	guard = 0
	while M.enemies.size() < want_enemies and guard < 20:
		M._update_wave(2.0)
		M._update_enemies(2.0)
		guard += 1
	while M.enemies.size() > want_enemies:
		var e: Dictionary = M.enemies.pop_back()
		var nd: Variant = e.get("node")
		if nd != null and nd is Node:
			(nd as Node).queue_free()


# Lanchas que llegan y descargan soldados/tanques, mas avioncitos: la composicion
# real de una oleada alta.
func fill_court(steps: int) -> void:
	for k in steps:
		M._update_wave(1.5)
		M._update_enemies(1.5)
		if M.enemies.size() > want_enemies * 2:
			break
	for k in 40:
		M._update_enemies(0.5)
		if M.enemies.size() > want_enemies * 2:
			break
	M._spawn_plane_from_warship()
	while M.enemies.size() > want_enemies:
		var e: Dictionary = M.enemies.pop_back()
		var nd: Variant = e.get("node")
		if nd != null and nd is Node:
			(nd as Node).queue_free()


func pump_frames(n: int, label: String) -> void:
	var t0: int = Time.get_ticks_msec()
	var orph_sum: int = 0
	var worst: int = 0
	var f: int = 0
	while f < n:
		var f0: int = Time.get_ticks_msec()
		await process_frame
		var fd: int = Time.get_ticks_msec() - f0
		if fd > worst:
			worst = fd
		orph_sum += int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		f += 1
		if Time.get_ticks_msec() - t0 > 60000:
			say("     (corte del pump a los 60 s)")
			break
	var cnt: int = maxi(1, f)
	var ms: float = float(Time.get_ticks_msec() - t0) / float(cnt)
	say("  %-26s %8.2f ms/frame  ~%7.1f fps  peor frame %4d ms  huerfanos/frame %6d" % [
		label, ms, 1000.0 / maxf(0.01, ms), worst, int(orph_sum / float(cnt))])
	say("     estado: " + state_counts())
	if fp != null:
		fp.flush()


# --- closures de bench (sin relleno adentro: rellena run_subsystems entre benches)
func c_rebuild() -> void:
	M._hit_rebuild()


func c_proj() -> void:
	M._update_projectiles(STEP)


func c_enem() -> void:
	M._update_enemies(STEP)


func c_part() -> void:
	M._update_particles(STEP)


func c_wave() -> void:
	M._update_wave(STEP)


func c_crates() -> void:
	M._update_crates(STEP)


func c_basefire() -> void:
	M._update_base_fire(STEP)


func c_abl() -> void:
	M._update_abilities(STEP)


func c_hud() -> void:
	M._hud.update_hud()


func c_fxtick() -> void:
	M._fx.tick_fx(STEP)


func c_vfxtick() -> void:
	M._vfx_tick(STEP)


func c_mirrors() -> void:
	M._update_split_mirrors()


func c_scan() -> void:
	M._split_scan_new_nodes()


# Solo el barrido de hijos + el lookup: es lo que el modo split paga cada frame por
# tener miles de nodos en la raiz de main.
func c_lookup() -> void:
	var chs: Array = M.get_children()
	for ch in chs:
		M._split_has_mirror(ch)


# Replica del codigo viejo (barrido de _mirrors por cada hijo) para comparar contra
# el lookup O(1) actual sobre los MISMOS datos. Se miden solo 300 hijos: con miles
# de espejos, una pasada completa del codigo viejo tardaba segundos.
func c_lookup_old() -> void:
	var ms: Array = M._mirrors
	var chs: Array = M.get_children()
	var lim: int = mini(300, chs.size())
	for k in lim:
		var ch: Node = chs[k]
		for mi in ms:
			if mi["orig"] == ch:
				break


# Costo de espejar un nodo que recien nace (duplicate x2 + limpiar audio): lo paga
# cada bala, enemigo o efecto que aparece en modo split.
func c_register() -> void:
	var n: Node3D = Node3D.new()
	n.name = "BenchReg_%d" % n.get_instance_id()
	M.add_child(n)
	M._register_split_mirror(n)
	M.remove_child(n)
	n.free()


func c_mkbullet() -> void:
	var m: MeshInstance3D = M._create_projectile(0.35, Color(1, 1, 0.3))
	M.add_child(m)
	m.free()


func c_mksoldier() -> void:
	var s: Node3D = M._create_soldier_mesh()
	M.add_child(s)
	s.free()


func c_mkplane() -> void:
	var s: Node3D = M._create_plane_mesh()
	M.add_child(s)
	s.free()


# --- micro del loop de soldados ---------------------------------------------
# _update_enemies es lo mas caro de la simulacion; aca se rompe en piezas para ver
# cuanto vale cada cosa dentro del loop (el cierre mismo cuesta ~0,3 us).
var SOLD: Node = null
var AP: AnimationPlayer = null
var SKEL: Skeleton3D = null
var hsum: float = 0.0
var junk: Variant = null


func c_aisolve() -> void:
	M._ai_solve(STEP)


func c_terrain100() -> void:
	for k in 100:
		hsum += M._terrain_height(float(k) * 1.3, float(k) * 0.7)


func c_aplookup() -> void:
	junk = SOLD.get_node_or_null("AnimationPlayer")


func c_skellookup() -> void:
	junk = SOLD.get_node_or_null("Rig/Skeleton3D")


func c_gear() -> void:
	M._sync_gear(SOLD)


func c_gear_cached() -> void:
	M._sync_gear(SOLD, SKEL)


func c_gunpose() -> void:
	M._set_soldier_gun_pose(SOLD, true)


func c_poswrite() -> void:
	SOLD.position.x += 0.0001
	SOLD.position.y = 1.0
	SOLD.position.z += 0.0001
	SOLD.rotation.y = 0.5


func c_poswrite1() -> void:
	var p: Vector3 = SOLD.position
	p.x += 0.0001
	p.y = 1.0
	p.z += 0.0001
	SOLD.position = p
	SOLD.rotation.y = 0.5


func c_animstate() -> void:
	if AP != null:
		var cur: String = AP.current_animation
		if cur != "default/run":
			AP.play("default/run")


func c_aicalls() -> void:
	var ai: int = int(SOLD_E.get("ai_i", -1))
	junk = M._ai.sep_at(ai)
	junk = M._ai.soft_at(ai)
	junk = M._ai.evade_at(ai)
	junk = M._ai.fixr_at(ai)
	junk = M._ai.fixt_at(ai)


var SOLD_E: Dictionary = {}


func run_soldier_micro() -> void:
	for e in M.enemies:
		if str(e.get("type", "")) == "soldier":
			SOLD_E = e
			SOLD = e.get("node") as Node
			break
	if SOLD == null:
		say("\n-- E) micro del loop de soldados: no habia soldados, se saltea --")
		return
	AP = SOLD.get_node_or_null("AnimationPlayer") as AnimationPlayer
	SKEL = SOLD.get_node_or_null("Rig/Skeleton3D") as Skeleton3D
	say("\n-- E) micro del loop de soldados (por llamada; el cierre suma ~0,3 us) --")
	bench_n("_ai_solve (armar buffers + paralelo)", 200, 1, c_aisolve)
	bench_n("_terrain_height", 500, 100, c_terrain100)
	bench_n("get_node AnimationPlayer", 2000, 1, c_aplookup)
	bench_n("get_node Rig/Skeleton3D", 2000, 1, c_skellookup)
	bench_n("_sync_gear (busca skeleton)", 500, 1, c_gear)
	bench_n("_sync_gear (skeleton dado)", 500, 1, c_gear_cached)
	bench_n("_set_soldier_gun_pose", 500, 1, c_gunpose)
	bench_n("escribir position 3 veces", 2000, 1, c_poswrite)
	bench_n("escribir position en bloque", 2000, 1, c_poswrite1)
	bench_n("leer/poner animacion", 2000, 1, c_animstate)
	bench_n("5 lecturas de _ai.*_at", 2000, 5, c_aicalls)


func run_subsystems(tag: String) -> void:
	say("\n-- B/C) subsistemas %s  (%%frame sobre 16,6 ms) --" % tag)
	var specs: Array = [
		["_hit_rebuild (grilla)", 200, c_rebuild],
		["_update_projectiles", 100, c_proj],
		["_update_enemies", 100, c_enem],
		["_update_particles", 200, c_part],
		["_update_wave", 300, c_wave],
		["_update_crates", 300, c_crates],
		["_update_base_fire", 300, c_basefire],
		["_update_abilities", 300, c_abl],
		["_hud.update_hud", 300, c_hud],
		["_fx.tick_fx", 300, c_fxtick],
		["_vfx_tick", 300, c_vfxtick],
	]
	for sp in specs:
		await process_frame
		refill(want_bullets)
		bench(String(sp[0]), int(sp[1]), sp[2])


func _init() -> void:
	wave_target = arg_int(0, 14)
	want_bullets = arg_int(1, 400)
	fp = FileAccess.open("user://perf_cpu.txt", FileAccess.WRITE)
	say("== BANCO DE CPU ==  oleada=%d  balas~%d" % [wave_target, want_bullets])

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	M = main
	await process_frame
	await process_frame

	# ---------- ESCENARIO 1: un jugador ----------
	main.DEBUG_START_WAVE = wave_target
	main.DEBUG_START_POINTS = 4000
	main._start_game()
	main.base_hp_max = 99999.0
	main.health = 99999.0
	await process_frame
	fill_court(60)
	make_flight(want_bullets)
	topup_enemy_shots(60)
	await process_frame
	say("\n-- estado 1P -- " + state_counts())
	check(main.enemies.size() >= 15, "poblacion de enemigos suficiente (%d)" % main.enemies.size())
	check(main.projectiles.size() >= want_bullets * 0.5, "balas en vuelo (%d de %d)" % [main.projectiles.size(), want_bullets])

	say("\n-- A) frame completo 1P --")
	await pump_frames(240, "1P oleada %d" % wave_target)

	await run_subsystems("1P")

	await run_soldier_micro()

	say("\n-- D) costo de creacion (spawn) --")
	bench("crear bala (Mesh+Sph+Mat)", 300, c_mkbullet)
	bench("crear misil (glb)", 60, c_mkmissile)
	bench("crear soldado (glb)", 50, c_mksoldier)
	bench("crear avion (mesh)", 120, c_mkplane)

	# ---------- ESCENARIO 2: split 2P ----------
	say("\n\n== ESCENARIO SPLIT 2P ==")
	await main._start_split_game()
	await process_frame
	await process_frame
	main.base_hp_max = 99999.0
	main.health = 99999.0
	fill_court(60)
	make_flight(want_bullets)
	topup_enemy_shots(60)
	await process_frame
	say("-- estado split -- " + state_counts())
	check(bool(main.split_mode), "split activo")

	say("\n-- A) frame completo split --")
	await pump_frames(240, "split oleada %d" % wave_target)

	say("\n-- espejos de split --")
	await process_frame
	refill(want_bullets)
	# Primera pasada al margen: registra todo lo que hay en cancha (duplica cada nodo
	# en los 2 viewports). Lo que importa es cuanto cuesta YA con los espejos hechos.
	M._split_scan_new_nodes()
	await process_frame
	bench("_split_scan_new_nodes", 300, c_scan)
	bench("  solo el lookup por hijo", 300, c_lookup)
	bench("  lookup como antes (lineal)", 30, c_lookup_old)
	await process_frame
	refill(want_bullets)
	M._split_scan_new_nodes()
	bench("_update_split_mirrors", 100, c_mirrors)
	bench("registrar 1 espejo nuevo", 200, c_register)

	await run_subsystems("split")

	main._teardown_split()
	await process_frame
	say("\n== RESULTADO: %d fallos ==" % failures)
	if fp != null:
		fp.flush()
	quit(0 if failures == 0 else 1)


func c_mkmissile() -> void:
	var s: Node3D = M._create_missile()
	M.add_child(s)
	s.free()
