class_name EnemyAI
extends RefCounted
## Costa Blindada — IA de evitación de soldados, repartida en los núcleos del CPU.
##
## main.gd entrega datos planos (posiciones en PackedFloat32Array, sin nodos) y
## recibe vectores ya calculados. Todo el trabajo O(N²) —separación entre
## soldados, esquiva de tanques, rocas y balas— se divide en tareas que
## WorkerThreadPool ejecuta en paralelo sobre los núcleos disponibles.
##
## Por qué es seguro desde otros hilos: ninguna tarea toca la escena de Godot
## (ni Node3D, ni AnimationPlayer, ni la SceneTree). Las tareas solo leen arrays
## compartidos de solo-lectura y escriben en SUS PROPIOS arrays de salida, uno por
## tarea; el hilo principal espera a que terminen y recién entonces aplica los
## resultados a los nodos.
##
## Uso (main.gd, una vez por frame):
##   _ai.solve(sold, tanks, rocks, bullets, delta)
##   var sep: Vector2 = _ai.sep_at(i)   # i = índice del soldado en "sold"

# ─── REJILLA ESPACIAL ───
# Con la rejilla, cada soldado solo mira a los vecinos de su celda y las 8
# contiguas: el trabajo deja de ser N² y pasa a ~N·vecinos.
const CELL: float = 8.0            # lado de celda (>= radio máximo de separación)
const GRID_MIN_X: float = -120.0
const GRID_MIN_Z: float = -120.0
const GRID_W: int = 30             # 30 * 8 m = 240 m: cubre de sobra la playa jugable
const GRID_H: int = 30

# ─── RADIOS (idénticos a los que usaba main.gd) ───
const SEP_R_SOLDIER: float = 7.0
const SEP_R_TANK: float = 5.5
const TANK_HULL: float = 2.5
const BULLET_R: float = 22.0

# ─── PARALELISMO ───
const MIN_PARALLEL: int = 64       # por debajo de N soldados, el threading cuesta más de lo que ahorra
const MAX_TASKS: int = 4           # techo de tareas simultáneas (más allá el reparto no ayuda)

# Entradas (solo lectura mientras corren las tareas)
var _sold: PackedFloat32Array = PackedFloat32Array()    # (x, z) por soldado
var _tanks: PackedFloat32Array = PackedFloat32Array()   # (x, z) por tanque
var _rocks: PackedFloat32Array = PackedFloat32Array()   # (x, z, radio)
var _bullets: PackedFloat32Array = PackedFloat32Array() # (x, z, dx, dz)
var _delta: float = 0.0
var _n: int = 0

# Rejilla en lista enlazada: _head por celda, _next por ocupante (solo arrays)
var _head: PackedInt32Array = PackedInt32Array()
var _next: PackedInt32Array = PackedInt32Array()
var _occ: PackedFloat32Array = PackedFloat32Array()     # (x, z, kind) kind 0=soldado 1=tanque

# Salidas (x, y) indexadas por el índice del soldado
var _sep: PackedFloat32Array = PackedFloat32Array()     # empuje de separación (pelotón)
var _soft: PackedFloat32Array = PackedFloat32Array()    # desvío suave contra rocas
var _evade: PackedFloat32Array = PackedFloat32Array()   # esquiva de balas del jugador
var _fixr: PackedFloat32Array = PackedFloat32Array()    # corrección dura: salió de la roca
var _fixt: PackedFloat32Array = PackedFloat32Array()    # corrección dura: salió del casco

# ─── API ───

## Resuelve toda la evitación. Con pocos enemigos lo hace en el hilo principal
## (menos overhead); con muchos, reparte el trabajo entre los núcleos.
func solve(sold: PackedFloat32Array, tanks: PackedFloat32Array, rocks: PackedFloat32Array, bullets: PackedFloat32Array, delta: float) -> void:
	_sold = sold
	_tanks = tanks
	_rocks = rocks
	_bullets = bullets
	_delta = delta
	_n = int(_sold.size()) >> 1
	if _n == 0:
		return
	# resize/fill sobre los miembros DIRECTOS (si se pasaran como argumento, la
	# semantica copy-on-write de GDScript dejaria el miembro sin actualizar)
	_sep.resize(_n * 2)
	_sep.fill(0.0)
	_soft.resize(_n * 2)
	_soft.fill(0.0)
	_evade.resize(_n * 2)
	_evade.fill(0.0)
	_fixr.resize(_n * 2)
	_fixr.fill(0.0)
	_fixt.resize(_n * 2)
	_fixt.fill(0.0)
	_build_grid()
	var tasks: int = _task_count()
	if tasks <= 1:
		var job0 := Chunk.new()
		job0.ai = self
		job0.i0 = 0
		job0.i1 = _n
		job0.run()
		_merge(job0)
		return
	var jobs: Array = []
	var ids: Array = []
	var per: int = int(ceil(float(_n) / float(tasks)))
	for c in tasks:
		var i0: int = c * per
		if i0 >= _n:
			break
		var job := Chunk.new()
		job.ai = self
		job.i0 = i0
		job.i1 = mini(_n, i0 + per)
		jobs.append(job)
		ids.append(WorkerThreadPool.add_task(job.run, true, "cb_enemy_ai"))
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(int(id))
	for job2 in jobs:
		_merge(job2)

func clear() -> void:
	_sep.resize(0)
	_soft.resize(0)
	_evade.resize(0)
	_fixr.resize(0)
	_fixt.resize(0)
	_occ.resize(0)
	_n = 0

func sep_at(i: int) -> Vector2:
	return _at(_sep, i)

func soft_at(i: int) -> Vector2:
	return _at(_soft, i)

func evade_at(i: int) -> Vector2:
	return _at(_evade, i)

## Devuelve el desplazamiento SIN escalar: main.gd aplica el factor de frame
## (delta * 5.0 o delta * 6.0) exactamente como antes.
func fixr_at(i: int) -> Vector2:
	return _at(_fixr, i)

func fixt_at(i: int) -> Vector2:
	return _at(_fixt, i)

# ─── INTERNO ───

func _at(arr: PackedFloat32Array, i: int) -> Vector2:
	if i < 0 or i * 2 + 1 >= arr.size():
		return Vector2.ZERO
	return Vector2(arr[i * 2], arr[i * 2 + 1])

func _task_count() -> int:
	if _n < MIN_PARALLEL:
		return 1
	var cores: int = OS.get_processor_count()
	return clampi(cores - 2, 1, MAX_TASKS)

func _cell_x(x: float) -> int:
	return clampi(int((x - GRID_MIN_X) / CELL), 0, GRID_W - 1)

func _cell_z(z: float) -> int:
	return clampi(int((z - GRID_MIN_Z) / CELL), 0, GRID_H - 1)

func _cell_index(x: float, z: float) -> int:
	return _cell_z(z) * GRID_W + _cell_x(x)

func _build_grid() -> void:
	_occ.resize(0)
	var total: int = _n + (int(_tanks.size()) >> 1)
	_next.resize(total)
	_head.resize(GRID_W * GRID_H)
	_head.fill(-1)
	var k: int = 0
	var idx: int = 0
	while k < _sold.size():
		var sx: float = _sold[k]
		var sz: float = _sold[k + 1]
		_occ.append(sx)
		_occ.append(sz)
		_occ.append(0.0)
		var c: int = _cell_index(sx, sz)
		_next[idx] = _head[c]
		_head[c] = idx
		idx += 1
		k += 2
	var t: int = 0
	while t < _tanks.size():
		var tx: float = _tanks[t]
		var tz: float = _tanks[t + 1]
		_occ.append(tx)
		_occ.append(tz)
		_occ.append(1.0)
		var c2: int = _cell_index(tx, tz)
		_next[idx] = _head[c2]
		_head[c2] = idx
		idx += 1
		t += 2

func _merge(job: Chunk) -> void:
	var n: int = job.i1 - job.i0
	for i in n:
		var src: int = i * 2
		var dst: int = (job.i0 + i) * 2
		_sep[dst] = job.sep[src]
		_sep[dst + 1] = job.sep[src + 1]
		_soft[dst] = job.soft[src]
		_soft[dst + 1] = job.soft[src + 1]
		_evade[dst] = job.evade[src]
		_evade[dst + 1] = job.evade[src + 1]
		_fixr[dst] = job.fixr[src]
		_fixr[dst + 1] = job.fixr[src + 1]
		_fixt[dst] = job.fixt[src]
		_fixt[dst + 1] = job.fixt[src + 1]

# ─── TAREA (se ejecuta en un hilo de WorkerThreadPool) ───
class Chunk:
	extends RefCounted
	var ai: EnemyAI
	var i0: int = 0
	var i1: int = 0
	var sep: PackedFloat32Array = PackedFloat32Array()
	var soft: PackedFloat32Array = PackedFloat32Array()
	var evade: PackedFloat32Array = PackedFloat32Array()
	var fixr: PackedFloat32Array = PackedFloat32Array()
	var fixt: PackedFloat32Array = PackedFloat32Array()

	func run() -> void:
		var count: int = i1 - i0
		sep.resize(count * 2)
		soft.resize(count * 2)
		evade.resize(count * 2)
		fixr.resize(count * 2)
		fixt.resize(count * 2)
		var sold: PackedFloat32Array = ai._sold
		var rocks: PackedFloat32Array = ai._rocks
		var bullets: PackedFloat32Array = ai._bullets
		var head: PackedInt32Array = ai._head
		var nxt: PackedInt32Array = ai._next
		var occ: PackedFloat32Array = ai._occ
		var delta: float = ai._delta
		for i in range(i0, i1):
			var li: int = i * 2
			var x: float = sold[li]
			var z: float = sold[li + 1]
			var sep_v := Vector2.ZERO
			var soft_v := Vector2.ZERO
			var evade_v := Vector2.ZERO
			var fixr_v := Vector2.ZERO
			var fixt_v := Vector2.ZERO

			# Vecinos: solo la celda propia y las 8 contiguas (antes: todos los enemigos)
			var cgx: int = ai._cell_x(x)
			var cgz: int = ai._cell_z(z)
			for dz in range(-1, 2):
				var gz: int = cgz + dz
				if gz < 0 or gz >= EnemyAI.GRID_H:
					continue
				for dx in range(-1, 2):
					var gx: int = cgx + dx
					if gx < 0 or gx >= EnemyAI.GRID_W:
						continue
					var k: int = head[gz * EnemyAI.GRID_W + gx]
					while k >= 0:
						if k != i:
							var away := Vector2(x - occ[k * 3], z - occ[k * 3 + 1])
							var d: float = away.length()
							var kind: int = int(occ[k * 3 + 2])
							if kind == 0:
								if d < EnemyAI.SEP_R_SOLDIER and d > 0.01:
									sep_v += (away / d) * (1.0 - d / EnemyAI.SEP_R_SOLDIER)
							else:
								if d < EnemyAI.SEP_R_TANK and d > 0.01:
									sep_v += (away / d) * (1.0 - d / EnemyAI.SEP_R_TANK)
								if d < EnemyAI.TANK_HULL:
									fixt_v += (away / maxf(0.01, d)) * (EnemyAI.TANK_HULL - d)
						k = nxt[k]

			# Rocas: empuje suave (para la dirección deseada) + corrección dura (salir del casco)
			var r: int = 0
			while r < rocks.size():
				var rrad: float = rocks[r + 2]
				var raway := Vector2(x - rocks[r], z - rocks[r + 1])
				var rd: float = raway.length()
				if rd < rrad:
					var rdir: Vector2 = raway / maxf(0.01, rd)
					soft_v += rdir * (1.0 - rd / rrad) * 4.0
					fixr_v += rdir * (rrad - rd)
				r += 3

			# Evasión de las balas del jugador
			var b: int = 0
			while b < bullets.size():
				var away2 := Vector2(x - bullets[b], z - bullets[b + 1])
				var bd: float = away2.length()
				if bd < EnemyAI.BULLET_R:
					var adir: Vector2 = away2 / maxf(0.01, bd)
					var bdir := Vector2(bullets[b + 2], bullets[b + 3])
					var wgt: float = (1.0 - bd / EnemyAI.BULLET_R) * maxf(0.25, bdir.dot(adir))
					evade_v += adir * wgt
				b += 4

			if sep_v.length() > 3.0:
				sep_v = sep_v.normalized() * 3.0
			if evade_v.length() > 3.0:
				evade_v = evade_v.normalized() * 3.0

			var oi: int = (i - i0) * 2
			sep[oi] = sep_v.x
			sep[oi + 1] = sep_v.y
			soft[oi] = soft_v.x
			soft[oi + 1] = soft_v.y
			evade[oi] = evade_v.x
			evade[oi + 1] = evade_v.y
			fixr[oi] = fixr_v.x
			fixr[oi + 1] = fixr_v.y
			fixt[oi] = fixt_v.x
			fixt[oi + 1] = fixt_v.y
