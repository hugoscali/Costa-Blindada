class_name WorldMath
extends RefCounted
## Costa Blindada — matemática de mundo.
##
## Heightmap del terreno (alturas + muestreo bilineal), colocación dispersa con
## separación mínima (rejection sampling), distancia mínima a una lista de puntos
## y AABBs de meshes/viewmodels (para centrar y escalar armas y decorados).
##
## main.gd tiene una instancia (`_wmath`): el heightmap vive acá y los wrappers
## _terrain_height / _scatter_place / _min_dist_to / _world_aabb ... de main.gd
## delegan sin cambiar el comportamiento.

const TERRAIN_SIZE := 512  # heightmap 512x512 (1 px = 1 m, mundo -256..256)

var terrain_h: PackedFloat32Array = PackedFloat32Array()

# Altura del terreno en mundo (m) muestreando el heightmap con bilineal.
# Píxel (i,j) -> mundo (x = -256+i, z = -256+j); valor = y en mundo.
func height(x: float, z: float) -> float:
	if terrain_h.is_empty():
		return 0.0
	var S := 512.0
	var fx := x + 256.0
	var fz := z + 256.0
	if fx < 0.0 or fz < 0.0 or fx >= S - 1.0 or fz >= S - 1.0:
		return 0.0
	var i0 := int(fx)
	var j0 := int(fz)
	var tx := fx - float(i0)
	var tz := fz - float(j0)
	var r0: int = j0 * 512 + i0
	var h00: float = terrain_h[r0]
	var h10: float = terrain_h[r0 + 1]
	var h01: float = terrain_h[r0 + 512]
	var h11: float = terrain_h[r0 + 513]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

# ─── ARCHIVOS BINARIOS DEL TERRENO (height / control / color) ───
static func load_terrain_bin(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Terrain3D: cannot open " + path + " (error " + str(FileAccess.get_open_error()) + ")")
		return PackedByteArray()
	var buf := f.get_buffer(f.get_length())
	f.close()
	return buf

# ─── COLOCACIÓN DISPERSA ───
# Posición aleatoria con separación mínima frente a las ya colocadas (rejection sampling).
# corridor: franja central |x|<corridor libre hasta z=corridor_z (visuales a las montañas).
static func scatter_place(placed: Array, xmin: float, xmax: float, zmin: float, zmax: float, min_sp: float, corridor: float, corridor_z: float) -> Vector2:
	for _t in 80:
		var px := randf_range(xmin, xmax)
		var pz := randf_range(zmin, zmax)
		if absf(px) < corridor and pz < corridor_z:
			continue
		var ok := true
		for pv in placed:
			if Vector2(px, pz).distance_to(pv) < min_sp:
				ok = false
				break
		if ok:
			placed.append(Vector2(px, pz))
			return Vector2(px, pz)
	# fallback: extremo lejano
	var pxf := randf_range(xmin, xmax)
	var pzf := zmax
	placed.append(Vector2(pxf, pzf))
	return Vector2(pxf, pzf)

# Distancia mínima a cualquier punto (9999 si la lista está vacía)
static func min_dist_to(positions: Array, p: Vector3) -> float:
	var d := 9999.0
	for q in positions:
		d = minf(d, p.distance_to(q))
	return d

# ─── AABB / VIEWMODEL FIT HELPERS ───
static func xform_aabb(bb: AABB, t: Transform3D) -> AABB:
	var mn: Vector3 = bb.position
	var mx: Vector3 = bb.position + bb.size
	var pts := [
		Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z),
		Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mx.z), mx,
	]
	var result := AABB()
	var first := true
	for p in pts:
		var q: Vector3 = t * p
		var one := AABB(q, Vector3.ZERO)
		if first:
			result = one
			first = false
		else:
			result = result.merge(one)
	return result

static func combined_aabb(root: Node3D, base: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	for child in root.get_children():
		var sub_bb := AABB()
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var local_bb: AABB = mi.mesh.get_aabb()
				sub_bb = xform_aabb(local_bb, base * mi.transform)
		elif child is Node3D:
			sub_bb = combined_aabb(child as Node3D, base * (child as Node3D).transform)
		if sub_bb.size != Vector3.ZERO:
			if first:
				result = sub_bb
				first = false
			else:
				result = result.merge(sub_bb)
	return result

# AABB robusto: incluye el root del GLB si es MeshInstance3D (los combined_aabb se lo pierden).
# Usa transformadas locales acumuladas (funciona con nodos fuera del tree).
static func world_aabb(root: Node3D) -> AABB:
	var pts := PackedVector3Array()
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while stack.size() > 0:
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var t: Transform3D = item[1]
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var local: AABB = mi.mesh.get_aabb()
				var mn: Vector3 = local.position
				var mx: Vector3 = local.position + local.size
				for cx in [mn.x, mx.x]:
					for cy in [mn.y, mx.y]:
						for cz in [mn.z, mx.z]:
							pts.append(t * Vector3(cx, cy, cz))
		for ch in n.get_children():
			if ch is Node3D:
				stack.append([ch, t * (ch as Node3D).transform])
	if pts.is_empty():
		return AABB()
	var bb := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		bb = bb.merge(AABB(p, Vector3.ZERO))
	return bb
