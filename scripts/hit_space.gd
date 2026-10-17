class_name HitSpace
extends RefCounted

## Indice espacial de enemigos para las colisiones de proyectiles.
##
## Lo usa main.gd en _update_projectiles / _cannon_splash / _cannon_will_kill_vehicle.
## El loop original comparaba cada bala contra TODOS los enemigos: con 475 balas y
## 60 enemigos son 28.500 iteraciones por frame, cada una con Dictionary.get +
## match de string + is_instance_valid. Medido en juego: 35 ms/frame, que es el
## cuello real del FPS desde la oleada 10 (GPU 18%, un solo core al 100%).
##
## LA REGLA DE COLISION NO CAMBIA: mismos radios, y entre los solapados gana el
## enemigo con indice mas alto en la lista, exactamente como el "for j in
## range(size-1, -1, -1)" de antes. Lo unico que cambia es COMO se encuentran los
## candidatos: grilla uniforme + arrays planos de floats, sin tocar nodos.
##
## main.gd reconstruye esto una vez por frame antes de mover las balas; durante el
## loop de proyectiles las posiciones enemigas no cambian, asi que la grilla vale
## todo el frame. Las entradas que mueren en el medio se resuelven por id.

const CELL: float = 16.0        # >= radio maximo (10 m) y >= splash (12.5 m): con la celda propia y las 8 vecinas alcanza
const GRID: int = 48            # 48 x 16 = 768 m de mundo cubiertos
const HALF: float = float(GRID) * CELL * 0.5
const CAP: int = 2048           # candidatos devueltos por candidates(): mas que sobra con 150 enemigos

# Codigo de tipo: el loop de colision no compara strings.
const K_OTHER := 0
const K_SOLDIER := 1
const K_BOAT := 2
const K_TANK := 3
const K_PLANE := 4

# Posiciones como floats separados: en el loop caliente leer un Vector3 de un
# PackedVector3Array cuesta bastante mas que leer tres floats.
var px: PackedFloat32Array = PackedFloat32Array()
var py: PackedFloat32Array = PackedFloat32Array()
var pz: PackedFloat32Array = PackedFloat32Array()
var rad: PackedFloat32Array = PackedFloat32Array()   # radio de hitbox (sin el parea del disparo)
var ord: PackedInt32Array = PackedInt32Array()       # indice que tenia en "enemies" al construir
var ids: PackedInt32Array = PackedInt32Array()       # id del enemigo (para resolverlo despues)
var kind: PackedInt32Array = PackedInt32Array()      # K_* de arriba
var ent: Array = []                                  # referencia directa a la entrada de main.enemies

var buf: PackedInt32Array = PackedInt32Array()       # salida de candidates()
var buf_n: int = 0

var _head: PackedInt32Array = PackedInt32Array()     # primer slot de cada celda (-1 = vacia)
var _next: PackedInt32Array = PackedInt32Array()     # lista enlazada dentro de la celda
var _touched: PackedInt32Array = PackedInt32Array()  # celdas usadas: un clear() limpia solo esas
var _cellmax: PackedFloat32Array = PackedFloat32Array()  # radio mas grande dentro de cada celda


func _init() -> void:
	_head.resize(GRID * GRID)
	_head.fill(-1)
	_cellmax.resize(GRID * GRID)
	_cellmax.fill(0.0)
	buf.resize(CAP)


func clear() -> void:
	for i in _touched.size():
		_head[_touched[i]] = -1
		_cellmax[_touched[i]] = 0.0
	_touched.resize(0)
	px.resize(0)
	py.resize(0)
	pz.resize(0)
	rad.resize(0)
	ord.resize(0)
	ids.resize(0)
	kind.resize(0)
	ent.clear()
	_next.resize(0)
	buf_n = 0


func count() -> int:
	return px.size()


func add(p: Vector3, r: float, id: int, order: int, k: int, e: Dictionary) -> void:
	var slot: int = px.size()
	px.append(p.x)
	py.append(p.y)
	pz.append(p.z)
	rad.append(r)
	ord.append(order)
	ids.append(id)
	kind.append(k)
	ent.append(e)
	var c: int = _cell(p.x, p.z)
	if c < 0:
		_next.append(-1)  # afuera de la grilla: candidates() nunca lo visita
		return
	_next.append(_head[c])
	_head[c] = slot
	_touched.append(c)
	if r > _cellmax[c]:
		_cellmax[c] = r  # sirve para descartar celdas enteras de una sola comparacion


func _cell(x: float, z: float) -> int:
	var cx: int = int(floor((x + HALF) / CELL))
	var cz: int = int(floor((z + HALF) / CELL))
	if cx < 0 or cz < 0 or cx >= GRID or cz >= GRID:
		return -1
	return cz * GRID + cx


# Slot del enemigo al que este disparo le gana, o -1 si no le gana a ninguno.
# Misma regla que el loop viejo: entre todos los que solapan, el de indice mas alto.
# Como se busca el indice mas alto, un candidato con ord menor que el mejor actual
# ni se mide.
func best_hit(p: Vector3, reach: float, parea: float) -> int:
	var c: int = _cell(p.x, p.z)
	if c < 0:
		return -1
	# Los arrays se enlazan una sola vez por llamada: leer px[s] como miembro del
	# objeto construye un Variant en cada acceso y eso domina el costo del loop.
	var lx: PackedFloat32Array = px
	var ly: PackedFloat32Array = py
	var lz: PackedFloat32Array = pz
	var lr: PackedFloat32Array = rad
	var lo: PackedInt32Array = ord
	var lh: PackedInt32Array = _head
	var ln: PackedInt32Array = _next
	var bx: float = p.x
	var by: float = p.y
	var bz: float = p.z
	var span: int = int(ceil(reach / CELL))
	var cz0: int = int(c / GRID)
	var cx0: int = c - cz0 * GRID
	var x0: int = maxi(0, cx0 - span)
	var x1: int = mini(GRID - 1, cx0 + span)
	var z0: int = maxi(0, cz0 - span)
	var z1: int = mini(GRID - 1, cz0 + span)
	var best_slot: int = -1
	var best_ord: int = -1000000
	var z: int = z0
	while z <= z1:
		var row: int = z * GRID
		var zmin: float = float(z) * CELL - HALF
		var zmax: float = zmin + CELL
		var cz_clamp: float = bz
		if cz_clamp < zmin:
			cz_clamp = zmin
		elif cz_clamp > zmax:
			cz_clamp = zmax
		var x: int = x0
		while x <= x1:
			var cidx: int = row + x
			# Filtro de celda: si la caja de la celda esta mas lejos que el radio mas
			# grande que hay adentro, ningun enemigo de esa celda puede tocar el disparo.
			# (La altura no se mira aca: es conservador, la prueba fina viene abajo.)
			var lim: float = _cellmax[cidx] + parea
			var xmin: float = float(x) * CELL - HALF
			var cx_clamp: float = bx
			if cx_clamp < xmin:
				cx_clamp = xmin
			elif cx_clamp > xmin + CELL:
				cx_clamp = xmin + CELL
			var ddx: float = bx - cx_clamp
			var ddz: float = bz - cz_clamp
			var s: int = -1
			if ddx * ddx + ddz * ddz <= lim * lim:
				s = lh[cidx]
			while s >= 0:
				var o: int = lo[s]
				if o > best_ord:
					var dx: float = bx - lx[s]
					var dy: float = by - ly[s]
					var dz: float = bz - lz[s]
					var rr: float = lr[s] + parea
					if dx * dx + dy * dy + dz * dz < rr * rr:
						best_ord = o
						best_slot = s
				s = ln[s]
			x += 1
		z += 1
	return best_slot


# Llena `buf` (buf[0..buf_n-1]) con los slots cuya celda puede caer dentro de
# `reach` desde p y devuelve cuantos hay. Es una sobreseleccion: el que consulta
# comprueba la distancia real contra el radio de cada candidato.
func candidates(p: Vector3, reach: float) -> int:
	buf_n = 0
	var c: int = _cell(p.x, p.z)
	if c < 0:
		return 0
	var span: int = int(ceil(reach / CELL))
	var cz0: int = int(c / GRID)
	var cx0: int = c - cz0 * GRID
	var x0: int = maxi(0, cx0 - span)
	var x1: int = mini(GRID - 1, cx0 + span)
	var z0: int = maxi(0, cz0 - span)
	var z1: int = mini(GRID - 1, cz0 + span)
	var z: int = z0
	while z <= z1:
		var row: int = z * GRID
		var zmin: float = float(z) * CELL - HALF
		var zmax: float = zmin + CELL
		var cz_clamp: float = p.z
		if cz_clamp < zmin:
			cz_clamp = zmin
		elif cz_clamp > zmax:
			cz_clamp = zmax
		var x: int = x0
		while x <= x1:
			var xmin: float = float(x) * CELL - HALF
			var cx_clamp: float = p.x
			if cx_clamp < xmin:
				cx_clamp = xmin
			elif cx_clamp > xmin + CELL:
				cx_clamp = xmin + CELL
			var ddx: float = p.x - cx_clamp
			var ddz: float = p.z - cz_clamp
			var s: int = -1
			# Misma idea: la caja de la celda esta mas lejos que reach -> adentro no
			# puede haber ningun candidato aceptable.
			if ddx * ddx + ddz * ddz <= reach * reach:
				s = _head[row + x]
			while s >= 0:
				if buf_n < CAP:
					buf[buf_n] = s
					buf_n += 1
				s = _next[s]
			x += 1
		z += 1
	return buf_n
