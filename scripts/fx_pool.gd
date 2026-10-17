class_name FxPool
extends Node3D

# ─── POOL DE VFX DE EXPLOSION (chispas, humo, destellos, anillos, luces) ────────
# main.gd creaba por CADA particula de cada impacto: un MeshInstance3D nuevo +
# un SphereMesh nuevo + un StandardMaterial3D nuevo, y ademas escribia el
# albedo_color de ESA material en cada frame para hacer el fade. Con oleada 10+
# son miles de nodos y materiales creados y destruidos por segundo en el hilo
# principal, y cientos de materiales "sucios" por frame para el render thread:
# la GPU queda hambrienta (43% de uso) aunque el CPU total sea bajo.
#
# Acá: UNA SphereMesh compartida (cada instancia se escala a su tamano real),
# materiales compartidos indexados por (color, emision, paso de alpha) y nodos
# reciclados. Las formulas de movimiento, gravedad, velocidades, vidas y fade son
# las mismas de antes; solo cambia QUE se asigna, no COMO se mueve.
#
# main.gd -> _explode(), _smoke_burst(), _muzzle_flash(), _shockwave_ring(),
#            _flash_light(), _update_particles() delegan aca.

const MAX_PARTICLES: int = 420   # techo de particulas simultaneas (antes: sin techo)
const MAX_FLASHES: int = 48     # destellos de canon / anillos simultaneos
const MAX_LIGHTS: int = 6       # luces de destello simultaneas (antes: sin techo)
const ALPHA_STEPS: int = 10     # pasos de fade compartidos (1/10 de alpha: imperceptible)
const GRAV_Y: float = 12.0     # misma constante del _update_particles original
const SHADOW_OFF: int = 0       # MeshInstance3D.SHADOW_CASTING_SETTING_OFF

# Un objeto por SLOT del pool: se reutiliza, nunca se reasigna por frame.
class Part:
	var node: MeshInstance3D = null
	var vel: Vector3 = Vector3.ZERO
	var life: float = 0.0
	var grav: float = 1.0
	var base_a: float = 1.0
	var fade: float = 1.0
	var col: Color = Color.WHITE
	var ecol: Color = Color()
	var energy: int = 0
	var unsh: bool = false
	var step: int = -1

class Flash:
	var node: MeshInstance3D = null
	var t: float = 0.0
	var dur_s: float = 0.1
	var dur_a: float = 0.1
	var total: float = 0.1
	var s0: Vector3 = Vector3.ONE
	var s1: Vector3 = Vector3.ONE
	var a0: float = 1.0
	var col: Color = Color.WHITE
	var ecol: Color = Color()
	var energy: int = 0
	var unsh: bool = false
	var step: int = -1

class FlashLight:
	var node: OmniLight3D = null
	var t: float = 0.0
	var dur: float = 0.1
	var e0: float = 0.0

var _parts: Array = []
var _flashes: Array = []
var _lights: Array = []
var _free_nodes: Array = []
var _free_lights: Array = []
var _made_nodes: int = 0
var _made_lights: int = 0

var _sphere: SphereMesh = null
var _cyl: CylinderMesh = null
var _mats: Dictionary = {}


func _ready() -> void:
	_ensure_assets()


# Los recursos compartidos se crean apenas se usan: main.gd puede disparar antes
# de que este nodo entre al arbol.
func _ensure_assets() -> void:
	if _sphere != null:
		return
	# Geometria compartida. Los segmentos son los default (8 x 4), identicos a los
	# SphereMesh que se creaban uno por particula.
	_sphere = SphereMesh.new()
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_cyl = CylinderMesh.new()
	_cyl.top_radius = 0.7
	_cyl.bottom_radius = 0.7
	_cyl.height = 0.18


# ─── MATERIALES COMPARTIDOS ─────────────────────────────────────────────────────
func _col_key(c: Color) -> int:
	return int(clampf(c.r, 0.0, 1.0) * 255.0) \
		| (int(clampf(c.g, 0.0, 1.0) * 255.0) << 8) \
		| (int(clampf(c.b, 0.0, 1.0) * 255.0) << 16)


func _alpha_step(a: float) -> int:
	return clampi(int(round(clampf(a, 0.0, 1.0) * float(ALPHA_STEPS))), 0, ALPHA_STEPS)


# Color + emision + sombreado + paso de alpha -> UN material compartido.
# ecol opcional: color de emision distinto del albedo (destello del canon).
func _mat(col: Color, energy: int, unsh: bool, step: int, ecol: Color = Color()) -> StandardMaterial3D:
	var ec: Color = ecol if (energy > 0 and ecol.a > 0.0) else col
	var key: int = _col_key(col) | (_col_key(ec) << 24) | (energy << 48) | ((1 if unsh else 0) << 54) | (step << 55)
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, float(step) / float(ALPHA_STEPS))
	if energy > 0:
		m.emission_enabled = true
		m.emission = Color(ec.r, ec.g, ec.b)
		m.emission_energy_multiplier = float(energy)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unsh:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


# Misma curva que Tween TRANS_QUAD + EASE_OUT: quad(ease_out(p))
func _quad_out(p: float) -> float:
	var q: float = 1.0 - (1.0 - p) * (1.0 - p)
	return q * q


# ─── NODOS DEL POOL ─────────────────────────────────────────────────────────────
func _acquire_node() -> MeshInstance3D:
	if not _free_nodes.is_empty():
		var mi: MeshInstance3D = _free_nodes.pop_back()
		mi.visible = true
		return mi
	var nn := MeshInstance3D.new()
	# Esferas transparentes de 0.1-0.5 m no tienen que proyectar sombra del sol:
	# antes lo hacian por default y se dibujaban de nuevo en cada split de cascada.
	nn.cast_shadow = SHADOW_OFF
	add_child(nn)
	_made_nodes += 1
	nn.visible = true
	return nn


# ─── PARTICULAS (chispas de impacto, humo, escombros) ──────────────────────────
func add_particle(pos: Vector3, vel: Vector3, life: float, grav: float, radius: float, height: float, col: Color, energy: float, unsh: bool, base_alpha: float, fade: float, ecol: Color = Color()) -> void:
	_ensure_assets()
	var p: Part
	if _parts.size() < MAX_PARTICLES:
		p = Part.new()
		p.node = _acquire_node()
		_parts.append(p)
	else:
		# Pool lleno: se DESCARTA la nueva (no se pisa una viva). Pisar vivias hacfa
		# que ninguna terminara de morir y quedaba una niebla permanente de esferas.
		return
	var en: int = clampi(int(round(energy)), 0, 63)
	var fd: float = maxf(fade, 0.01)
	p.vel = vel
	p.life = life
	p.grav = grav
	p.base_a = clampf(base_alpha, 0.0, 1.0)
	p.fade = fd
	p.col = col
	p.ecol = ecol
	p.energy = en
	p.unsh = unsh
	if p.node.mesh != _sphere:
		p.node.mesh = _sphere
	p.node.scale = Vector3(radius, maxf(height * 0.5, 0.001), radius)
	p.node.position = pos
	p.step = _alpha_step(p.base_a * clampf(life / fd, 0.0, 1.0))
	p.node.material_override = _mat(col, en, unsh, p.step, ecol)


# Idéntico al _update_particles original: gravedad, integracion, fade y muerte.
func tick_particles(delta: float) -> void:
	for i in range(_parts.size() - 1, -1, -1):
		var p: Part = _parts[i]
		p.vel.y -= GRAV_Y * p.grav * delta
		var np: Vector3 = p.node.position + p.vel * delta
		p.node.position = np
		p.life -= delta
		var st: int = _alpha_step(p.base_a * (p.life / p.fade))
		if st != p.step:
			p.step = st
			p.node.material_override = _mat(p.col, p.energy, p.unsh, st, p.ecol)
		if p.life <= 0.0 or np.y < -1.0:
			_free_part(i)


func _free_part(i: int) -> void:
	var p: Part = _parts[i]
	p.node.visible = false
	_free_nodes.append(p.node)
	var last: int = _parts.size() - 1
	_parts[i] = _parts[last]
	_parts.remove_at(last)


# ─── DESTELLOS Y ANILLOS (antes: Tween + nodo + mesh + material por efecto) ─────
func add_flash(pos: Vector3, cyl: bool, s0: Vector3, s1: Vector3, col: Color, energy: float, unsh: bool, a0: float, dur_s: float, dur_a: float, ecol: Color = Color()) -> void:
	_ensure_assets()
	var f: Flash
	if _flashes.size() < MAX_FLASHES:
		f = Flash.new()
		f.node = _acquire_node()
		_flashes.append(f)
	else:
		var bi: int = 0
		var best: float = -1.0
		for i in _flashes.size():
			var q: Flash = _flashes[i]
			var prog: float = q.t / q.total
			if prog > best:
				best = prog
				bi = i
		f = _flashes[bi]
	var want: Mesh = _cyl if cyl else _sphere
	if f.node.mesh != want:
		f.node.mesh = want
	var en: int = clampi(int(round(energy)), 0, 63)
	f.t = 0.0
	f.dur_s = maxf(dur_s, 0.001)
	f.dur_a = maxf(dur_a, 0.001)
	f.total = maxf(f.dur_s, f.dur_a)
	f.s0 = s0
	f.s1 = s1
	f.a0 = clampf(a0, 0.0, 1.0)
	f.col = col
	f.ecol = ecol
	f.energy = en
	f.unsh = unsh
	f.step = _alpha_step(f.a0)
	f.node.position = pos
	f.node.scale = s0
	f.node.material_override = _mat(col, en, unsh, f.step, ecol)


# ─── LUCES DE DESTELLO ──────────────────────────────────────────────────────────
func add_light(pos: Vector3, col: Color, energy: float, radius: float, life: float) -> void:
	var fl: FlashLight
	if _lights.size() < MAX_LIGHTS:
		var li: OmniLight3D
		if _free_lights.is_empty():
			li = OmniLight3D.new()
			add_child(li)
			_made_lights += 1
		else:
			li = _free_lights.pop_back()
		fl = FlashLight.new()
		fl.node = li
		_lights.append(fl)
	else:
		# Lleno: re-targetea la que menos le queda (la mas barata de robar).
		var bi: int = 0
		var best: float = 1e20
		for i in _lights.size():
			var rem: float = _lights[i].dur - _lights[i].t
			if rem < best:
				best = rem
				bi = i
		fl = _lights[bi]
	fl.t = 0.0
	fl.dur = maxf(life, 0.01)
	fl.e0 = energy
	fl.node.visible = true
	fl.node.light_color = col
	fl.node.light_energy = energy
	fl.node.omni_range = radius
	fl.node.position = pos


# Destellos, anillos y luces: se integran siempre (tambien en game over / pausa,
# como los Tween de antes). Las particulas van en tick_particles().
func tick_fx(delta: float) -> void:
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Flash = _flashes[i]
		f.t += delta
		if f.t >= f.total:
			f.node.visible = false
			_free_nodes.append(f.node)
			_flashes.remove_at(i)
			continue
		f.node.scale = f.s0.lerp(f.s1, _quad_out(clampf(f.t / f.dur_s, 0.0, 1.0)))
		var st: int = _alpha_step(f.a0 * (1.0 - clampf(f.t / f.dur_a, 0.0, 1.0)))
		if st != f.step:
			f.step = st
			f.node.material_override = _mat(f.col, f.energy, f.unsh, st, f.ecol)
	for i in range(_lights.size() - 1, -1, -1):
		var l: FlashLight = _lights[i]
		l.t += delta
		if l.t >= l.dur:
			l.node.visible = false
			l.node.light_energy = 0.0
			_free_lights.append(l.node)
			_lights.remove_at(i)
			continue
		l.node.light_energy = l.e0 * (1.0 - _quad_out(clampf(l.t / l.dur, 0.0, 1.0)))


# ─── LIMPIEZA (reinicio de partida / cambio de mapa) ────────────────────────────
func release_all() -> void:
	for _i in _parts.size():
		_free_part(0)
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Flash = _flashes[i]
		f.node.visible = false
		_free_nodes.append(f.node)
	_flashes.clear()
	for i in range(_lights.size() - 1, -1, -1):
		var l: FlashLight = _lights[i]
		l.node.visible = false
		l.node.light_energy = 0.0
		_free_lights.append(l.node)
	_lights.clear()


# Solo para tests: posiciones actuales de las particulas vivas.
func debug_positions() -> Array:
	var out: Array = []
	for pp in _parts:
		out.append(pp.node.position)
	return out


func debug_light_energies() -> Array:
	var out: Array = []
	for ll in _lights:
		out.append(ll.node.light_energy)
	return out


func stats() -> Dictionary:
	return {
		"parts": _parts.size(),
		"flashes": _flashes.size(),
		"lights": _lights.size(),
		"nodes_created": _made_nodes,
		"lights_created": _made_lights,
		"materials": _mats.size(),
	}
