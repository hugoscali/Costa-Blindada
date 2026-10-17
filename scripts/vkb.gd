class_name VirtualKeyboard
extends RefCounted
## Costa Blindada — teclado virtual A-Z (2 filas × 13) para las iniciales del high score.
##
## Dibuja sus nodos DIRECTAMENTE en el CanvasLayer del HUD y conserva los nombres
## de siempre — "VKB_%d", "VKBCursor", "VKBHint" en single; "SVKB_<s>_%d",
## "SVKBCursor<s>", "SVKBHint<s>" en split — porque el game over los busca por nombre.
##
## Es dueño del cursor y de si está visible. NO es dueño de las iniciales ni del
## guardado: eso sigue en main.gd y se invoca por callbacks (cb_*), que main.gd
## conecta en _build_vkb().
##
## player = -1 → single (una fila centrada en 960) · 0/1 → mitad izquierda/derecha del split.

const COLS := GameConfig.VKB_COLS
const ROWS := GameConfig.VKB_ROWS

var hud: CanvasLayer = null
var open: bool = false
var cursor: int = 0
var player: int = -1
var ui_select: AudioStreamPlayer = null  # beep al mover/seleccionar (solo split)

# Callbacks provistos por main.gd
var cb_label: Callable = Callable()        # (name, pos, texto, tamaño, color) -> Label
var cb_centered: Callable = Callable()     # (name, x, y, w, h, texto, tamaño, color) -> Label
var cb_tr: Callable = Callable()           # (clave) -> String
var cb_get_initials: Callable = Callable() # () -> String
var cb_set_initials: Callable = Callable() # (String) -> void (refresca el display del juego)
var cb_submit: Callable = Callable()       # () -> void
var cb_skip: Callable = Callable()         # () -> void
var ini_index: int = 0                     # de qué jugador son estas iniciales: 0 = single/P1, 1 = P2

# ─── NOMBRES DE NODOS Y GEOMETRÍA ───
func _suffix() -> String:
	return "0" if player == 0 else "1"

func _half_cx() -> float:
	return 480.0 if player == 0 else 1440.0

func _label_name(i: int) -> String:
	if player < 0:
		return "VKB_%d" % i
	return "SVKB_%s_%d" % [_suffix(), i]

func _cursor_name() -> String:
	if player < 0:
		return "VKBCursor"
	return "SVKBCursor%s" % _suffix()

func _hint_name() -> String:
	if player < 0:
		return "VKBHint"
	return "SVKBHint%s" % _suffix()

# Centro de la celda i (fila 0: A-M, fila 1: N-Z)
func cell(i: int) -> Vector2:
	var col := i % COLS
	# FIX: antes row era float(i)/COLS sin truncar → cada tecla quedaba unos px más baja
	# que la anterior (filas en rampa diagonal, el VKB nunca alineaba). Debe ser fila ENTERA
	# (0/1): misma división float que move() usa como int, sin "//" (GDScript no tiene).
	var row := int(float(i) / COLS)
	if player < 0:
		var x := 960.0 - (COLS * 70.0) / 2.0 + 35.0 + float(col) * 70.0
		return Vector2(x, 690.0 + float(row) * 66.0)
	var cw := 62.0
	var ch := 58.0
	var cx := _half_cx()
	var x2 := cx - (COLS * cw) / 2.0 + cw / 2.0 + float(col) * cw
	return Vector2(x2, 690.0 + float(row) * ch)

# ─── CREACIÓN / DIBUJO ───
func show() -> void:
	open = true
	cursor = 0
	var go_hint := "GOInitialsHint"
	if player == 0:
		go_hint = "GOHintP1"
	elif player == 1:
		go_hint = "GOHintP2"
	var nh: Node = hud.get_node_or_null(go_hint)
	if nh:
		nh.queue_free()
	for i in range(COLS * ROWS):
		var p := cell(i)
		# Cada letra es un Label CENTRADO dentro de su celda (rect fijo celda_a × celda_b):
		# así las columnas quedan perfectamente alineadas entre las 2 filas, sin importar el
		# ancho del glifo (antes un offset fijo -12/-11 desplazaba cada letra según su ancho
		# y "M"/"W" se salían de su columna).
		if player < 0:
			cb_centered.call(_label_name(i), p.x - 35.0, p.y, 70.0, 66.0, char(65 + i), 40, Color(0.7, 0.75, 0.82, 0.8))
		else:
			cb_centered.call(_label_name(i), p.x - 31.0, p.y, 62.0, 58.0, char(65 + i), 30, Color(0.7, 0.75, 0.82, 0.85))
	var box := ColorRect.new()
	box.name = _cursor_name()
	box.color = Color(1, 0.95, 0.5, 0.30)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(box)
	if player < 0:
		cb_label.call(_hint_name(), Vector2(640, 850), cb_tr.call("vkb_hint"), 18, Color(1, 1, 1, 0.75))
	else:
		cb_centered.call(_hint_name(), 960.0 * player, 830, 960, 30, cb_tr.call("vkb_hint"), 17, Color(1, 1, 1, 0.75))
	render()

func render() -> void:
	var hi := Color(1, 0.97, 0.6)
	var lo := Color(0.7, 0.75, 0.82, 0.8)
	if player >= 0:
		lo = Color(0.7, 0.75, 0.82, 0.85)
	for i in range(COLS * ROWS):
		var lbl: Label = hud.get_node_or_null(_label_name(i)) as Label
		if lbl == null:
			continue
		lbl.add_theme_color_override("font_color", hi if i == cursor else lo)
	var box: ColorRect = hud.get_node_or_null(_cursor_name()) as ColorRect
	if box:
		var p := cell(cursor)
		# Caja del cursor centrada en la celda (la letra también está centrada → siempre alineadas)
		if player < 0:
			box.position = Vector2(p.x - 33.0, p.y + 4.0)
			box.size = Vector2(66, 58)
		else:
			box.position = Vector2(p.x - 28.0, p.y + 4.0)
			box.size = Vector2(56, 50)

# ─── ENTRADA DEL MANDO (D-pad mueve · A elige · B borra · START guarda · Y salta) ───
func move(dr: int, dc: int) -> void:
	var row: int = int(float(cursor) / COLS)  # cociente entero (row se usa como int) sin aviso
	var col := cursor % COLS
	col = wrapi(col + dc, 0, COLS)
	row = clampi(row + dr, 0, ROWS - 1)
	cursor = row * COLS + col
	render()
	if ui_select != null:
		ui_select.play()

func select() -> void:
	var cur: String = str(cb_get_initials.call(ini_index))
	if cur.length() < 3:
		cur += char(65 + cursor)
		cb_set_initials.call(ini_index, cur)
	render()
	if ui_select != null:
		ui_select.play()

func backspace() -> void:
	var cur: String = str(cb_get_initials.call(ini_index))
	if cur.length() > 0:
		cb_set_initials.call(ini_index, cur.left(cur.length() - 1))

func submit() -> void:
	if player < 0:
		# Single: vacío → "???" (siempre deja iniciales al guardar)
		var cur: String = str(cb_get_initials.call(ini_index))
		if cur.length() == 0:
			cur = "???"
		cb_set_initials.call(ini_index, cur)
	cb_submit.call()

func skip() -> void:
	cb_skip.call()

# Quita todos sus nodos del HUD (quedan libres igual que antes: queue_free diferido)
func clear() -> void:
	open = false
	for i in range(COLS * ROWS):
		var nd: Node = hud.get_node_or_null(_label_name(i))
		if nd:
			nd.queue_free()
	for nm in [_cursor_name(), _hint_name()]:
		var nd2: Node = hud.get_node_or_null(nm)
		if nd2:
			nd2.queue_free()
