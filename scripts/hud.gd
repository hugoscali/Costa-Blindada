class_name HudUI
extends RefCounted
## Costa Blindada — HUD: crosshairs, barras de vida, score/oleada/munición/puntos,
## indicador de arma, barra de habilidades, botón de música, ícono de la base y
## las fábricas de nodos que usan también los menús y la pantalla de game over.
##
## Mantiene intactos los NOMBRES de nodos que el resto del juego busca por string
## ("HPBar", "ScoreLabel", "WeaponIndicatorP1", "CrosshairLayer", "GOHint", ...),
## y también el re-acomodo de clusters single/split (hud_cluster_solo/hud_cluster_split).
##
## Es una VISTA: dibuja en el CanvasLayer hud de main.gd. `app` es main.gd, que
## sigue siendo dueño de hud, crosshair_layer y de todo el estado que se muestra
## (vida, score, oleada, munición, slots del split). main.gd lo crea en _ready().

var app  # main.gd (acceso dinámico: main.gd es el dueño del estado)

# ─── HUD ───
# Construye una cruz de apunte (horizontal + vertical + punto) bajo CrosshairLayer.
# fx,fy = fracción del centro de pantalla (0.5,0.5 = centro; 0.25/0.75 = mitad split).
# Las posiciones reales se calculan en _layout_crosshairs() según la resolución actual.
func build_crosshair_root(root_name: String, fx: float, fy: float, is_split: bool) -> void:
	if app.crosshair_layer == null:
		return
	var xh_root := Control.new()
	xh_root.name = root_name
	xh_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	xh_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.crosshair_layer.add_child(xh_root)
	var grn := Color(0, 1, 0, 0.95)
	var xh_h := ColorRect.new()
	xh_h.color = grn
	xh_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var xh_v := ColorRect.new()
	xh_v.color = grn
	xh_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var xh_dot := ColorRect.new()
	xh_dot.color = Color(0, 1, 0, 1.0)
	xh_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xh_root.add_child(xh_h)
	xh_root.add_child(xh_v)
	xh_root.add_child(xh_dot)
	app.crosshairs.append({"root": xh_root, "h": xh_h, "v": xh_v, "dot": xh_dot, "fx": fx, "fy": fy, "split": is_split})

# Reposiciona/escala todas las cruces al centro real (single) o al centro de cada mitad
# (split) según la resolución actual de la ventana. Escala uniforme: 1.0 en 1920x1080.
func layout_crosshairs() -> void:
	if app.crosshairs.is_empty():
		return
	var vp = app.get_viewport().get_visible_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return
	var sc: float = minf(vp.x / 1920.0, vp.y / 1080.0)
	var arm_len := 20.0 * sc
	var arm_w := 3.0 * sc
	var dot_sz := 6.0 * sc
	for c in app.crosshairs:
		var cx: float = vp.x * float(c["fx"])
		var cy: float = vp.y * float(c["fy"])
		var h: ColorRect = c["h"]
		h.position = Vector2(cx - arm_len, cy - arm_w / 2.0)
		h.size = Vector2(arm_len * 2.0, arm_w)
		var v: ColorRect = c["v"]
		v.position = Vector2(cx - arm_w / 2.0, cy - arm_len)
		v.size = Vector2(arm_w, arm_len * 2.0)
		var d: ColorRect = c["dot"]
		d.position = Vector2(cx - dot_sz / 2.0, cy - dot_sz / 2.0)
		d.size = Vector2(dot_sz, dot_sz)

# Muestra la cruz de single (centro) o las dos de split (P1 izq. / P2 der.) y las reposiciona.
func set_crosshair_mode(split: bool) -> void:
	if app.crosshair_layer == null:
		return
	for c in app.crosshairs:
		(c["root"] as Control).visible = (bool(c["split"]) == split)
	layout_crosshairs()

func build_hud() -> void:
	app.hud = CanvasLayer.new()
	app.hud.layer = 10
	app.add_child(app.hud)
	# El HUD está diseñado a 1920×1080: se escala a la ventana en _update_hud_scale()
	app.get_tree().root.size_changed.connect(app._update_hud_scale)
	# ── CRUZ DE APUNTAJE (crosshair) — verde brillante ──
	# Se construyen 3 cruces: una para single (centro 960) y dos para split (480 y 1440).
	# _set_crosshair_mode() muestra solo las del modo activo (ver _hud_cluster_split / _hud_cluster_solo).
	# CanvasLayer separado (layer 20) para asegurar que esté SOBRE todo
	var xh_layer := CanvasLayer.new()
	xh_layer.name = "CrosshairLayer"
	xh_layer.layer = 20
	app.add_child(xh_layer)
	app.crosshair_layer = xh_layer  # cache para el toggle por frame
	build_crosshair_root("CrosshairRoot", 0.5, 0.5, false)     # single player: centro
	build_crosshair_root("CrosshairRootP1", 0.25, 0.5, true)   # split: mitad izquierda
	build_crosshair_root("CrosshairRootP2", 0.75, 0.5, true)   # split: mitad derecha
	set_crosshair_mode(false)  # por defecto: solo la de single
	# Health bar
	var hp_bar := ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.position = Vector2(20, 985)
	hp_bar.size = Vector2(200, 20)
	hp_bar.show_percentage = false
	hp_bar.max_value = 150
	hp_bar.value = 150
	# StyleBox overrides (a theme StyleBox wins over a plain color override)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.15, 0.85, 0.25)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.05, 0.15, 0.05, 0.8)
	hp_bar.add_theme_stylebox_override("background", hp_bg)
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(hp_bar)
	# Score
	var score_label := Label.new()
	score_label.name = "ScoreLabel"
	score_label.position = Vector2(1600, 20)
	score_label.size = Vector2(300, 30)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 28)
	score_label.text = "0"
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(score_label)
	# Wave
	var wave_label := Label.new()
	wave_label.name = "WaveLabel"
	wave_label.position = Vector2(1600, 50)
	wave_label.size = Vector2(300, 30)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_label.add_theme_font_size_override("font_size", 28)
	wave_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	wave_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	wave_label.add_theme_constant_override("shadow_outline_size", 5)
	wave_label.text = "%s 1" % app._tr("wave_word")
	wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(wave_label)
	# (AmmoLabel kept as persistent name placeholder, but hidden — info is in WeaponIndicator)
	var ammo_label := Label.new()
	ammo_label.name = "AmmoLabel"
	ammo_label.visible = false
	ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(ammo_label)
	# Weapon indicator (box with name + ammo, bottom-right)
	var wpn_panel := PanelContainer.new()
	wpn_panel.name = "WeaponIndicator"
	wpn_panel.position = Vector2(1620, 950)
	var wpn_sb := StyleBoxFlat.new()
	wpn_sb.bg_color = Color(0.02, 0.04, 0.1, 0.85)
	wpn_sb.border_width_top = 3
	wpn_sb.border_width_bottom = 3
	wpn_sb.border_width_left = 3
	wpn_sb.border_width_right = 3
	wpn_sb.border_color = Color(0.85, 0.72, 0.3, 0.95)
	wpn_sb.corner_radius_top_left = 8
	wpn_sb.corner_radius_top_right = 8
	wpn_sb.corner_radius_bottom_left = 8
	wpn_sb.corner_radius_bottom_right = 8
	wpn_sb.content_margin_left = 20
	wpn_sb.content_margin_right = 20
	wpn_sb.content_margin_top = 8
	wpn_sb.content_margin_bottom = 8
	wpn_panel.add_theme_stylebox_override("panel", wpn_sb)
	var wpn_lbl := Label.new()
	wpn_lbl.name = "WeaponLabel"
	wpn_lbl.text = "  " + app._tr("wpn0") + "  "
	wpn_lbl.add_theme_font_size_override("font_size", 32)
	wpn_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	wpn_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	wpn_lbl.add_theme_constant_override("shadow_outline_size", 6)
	wpn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wpn_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn_panel.add_child(wpn_lbl)
	wpn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(wpn_panel)
	# Weapon indicator P1 (split 2P, abajo-izquierda; oculto fuera de split)
	var wpn1_panel := PanelContainer.new()
	wpn1_panel.name = "WeaponIndicatorP1"
	wpn1_panel.position = Vector2(640, 950)
	var wpn1_sb := StyleBoxFlat.new()
	wpn1_sb.bg_color = Color(0.02, 0.04, 0.1, 0.85)
	wpn1_sb.border_width_top = 3
	wpn1_sb.border_width_bottom = 3
	wpn1_sb.border_width_left = 3
	wpn1_sb.border_width_right = 3
	wpn1_sb.border_color = Color(0.85, 0.72, 0.3, 0.95)
	wpn1_sb.corner_radius_top_left = 8
	wpn1_sb.corner_radius_top_right = 8
	wpn1_sb.corner_radius_bottom_left = 8
	wpn1_sb.corner_radius_bottom_right = 8
	wpn1_sb.content_margin_left = 20
	wpn1_sb.content_margin_right = 20
	wpn1_sb.content_margin_top = 8
	wpn1_sb.content_margin_bottom = 8
	wpn1_panel.add_theme_stylebox_override("panel", wpn1_sb)
	var wpn1_lbl := Label.new()
	wpn1_lbl.name = "WeaponLabel"
	wpn1_lbl.text = "  " + app._tr("wpn0") + "  "
	wpn1_lbl.add_theme_font_size_override("font_size", 32)
	wpn1_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	wpn1_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	wpn1_lbl.add_theme_constant_override("shadow_outline_size", 6)
	wpn1_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wpn1_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn1_panel.add_child(wpn1_lbl)
	wpn1_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn1_panel.visible = false
	app.hud.add_child(wpn1_panel)
	# Points counter (top-right, below wave)
	var pts_label := Label.new()
	pts_label.name = "PtsLabel"
	pts_label.position = Vector2(1600, 80)
	pts_label.size = Vector2(300, 40)
	pts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pts_label.text = "● 0 PTS"
	pts_label.add_theme_font_size_override("font_size", 28)
	pts_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	pts_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	pts_label.add_theme_constant_override("shadow_outline_size", 5)
	pts_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(pts_label)
	# Ability button (abajo-izquierda, P1) — en solo queda a y=890; _hud_cluster_split lo mueve
	make_ability_bar("AbilityBar", "AbilityLabel", Vector2(20, 890), true)
	# Music toggle BUTTON (abajo-derecha) — margen x=1620 para no cortarse en el borde
	app.music_label = make_music_button("MusicLabel", Vector2(1620, 890), true)
	# Vida label (under the green bar)
	var vida_label := Label.new()
	vida_label.name = "VidaLabel"
	vida_label.position = Vector2(20, 1010)
	vida_label.text = "%s: 100%%" % app._tr("hud_vida")
	vida_label.add_theme_font_size_override("font_size", 34)
	vida_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.65, 0.95))
	vida_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	vida_label.add_theme_constant_override("shadow_outline_size", 4)
	vida_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(vida_label)
	# ── Base icon: casa junto a la barra de vida; las llamas muestran el nivel de fuego ──
	app.base_icon = add_base_icon("BaseIcon", Vector2(245, 968), app.base_icon_flames, true)
	# ── Nodos SÓLO split (simetría P1/P2): ocultos fuera de pantalla dividida ──
	app.music_label_p1 = make_music_button("MusicLabelP1", Vector2(640, 890), false)
	make_ability_bar("AbilityBarP2", "AbilityLabelP2", Vector2(1000, 890), false)
	# HPBar P2 (misma base que P1)
	var hp2 := ProgressBar.new()
	hp2.name = "HPBarP2"
	hp2.position = Vector2(1000, 985)
	hp2.size = Vector2(200, 20)
	hp2.show_percentage = false
	hp2.max_value = 150
	hp2.value = 150
	var hp2_fill := StyleBoxFlat.new()
	hp2_fill.bg_color = Color(0.15, 0.85, 0.25)
	hp2.add_theme_stylebox_override("fill", hp2_fill)
	var hp2_bg := StyleBoxFlat.new()
	hp2_bg.bg_color = Color(0.05, 0.15, 0.05, 0.8)
	hp2.add_theme_stylebox_override("background", hp2_bg)
	hp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp2.visible = false
	app.hud.add_child(hp2)
	# VidaLabel P2
	var vida2 := Label.new()
	vida2.name = "VidaLabelP2"
	vida2.position = Vector2(1000, 1010)
	vida2.text = "%s: 100%%" % app._tr("hud_vida")
	vida2.add_theme_font_size_override("font_size", 34)
	vida2.add_theme_color_override("font_color", Color(0.65, 1.0, 0.65, 0.95))
	vida2.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	vida2.add_theme_constant_override("shadow_outline_size", 4)
	vida2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vida2.visible = false
	app.hud.add_child(vida2)
	# Base icon P2 (casa + llamas)
	app.base_icon_p2 = add_base_icon("BaseIconP2", Vector2(1245, 968), app.base_icon_flames_p2, false)
	# ── Score/Oleada/PTS de P1 (split 2P: arriba de la mitad IZQUIERDA; ocultos fuera de split) ──
	var score1 := Label.new()
	score1.name = "ScoreLabelP1"
	score1.position = Vector2(640, 20)
	score1.size = Vector2(300, 30)
	score1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score1.add_theme_font_size_override("font_size", 28)
	score1.text = "0"
	score1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score1.visible = false
	app.hud.add_child(score1)
	var wave1 := Label.new()
	wave1.name = "WaveLabelP1"
	wave1.position = Vector2(640, 50)
	wave1.size = Vector2(300, 30)
	wave1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave1.add_theme_font_size_override("font_size", 28)
	wave1.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	wave1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	wave1.add_theme_constant_override("shadow_outline_size", 5)
	wave1.text = "%s 1" % app._tr("wave_word")
	wave1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave1.visible = false
	app.hud.add_child(wave1)
	var pts1 := Label.new()
	pts1.name = "PtsLabelP1"
	pts1.position = Vector2(640, 80)
	pts1.size = Vector2(300, 40)
	pts1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pts1.text = "● 0 PTS"
	pts1.add_theme_font_size_override("font_size", 28)
	pts1.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	pts1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	pts1.add_theme_constant_override("shadow_outline_size", 5)
	pts1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pts1.visible = false
	app.hud.add_child(pts1)

# Texture of the small house (64x56): roof, body, door, windows
func make_house_texture() -> Image:
	var img := Image.create_empty(64, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# roof (triangle)
	for r in range(0, 19):
		var y := 6 + r
		var half := int(2.0 + r * 1.55)
		if half > 28:
			half = 28
		img.fill_rect(Rect2i(32 - half, y, half * 2, 1), Color(0.52, 0.22, 0.13))
	# body
	img.fill_rect(Rect2i(10, 24, 44, 28), Color(0.62, 0.56, 0.46))
	# door
	img.fill_rect(Rect2i(27, 36, 10, 16), Color(0.3, 0.24, 0.16))
	# windows
	img.fill_rect(Rect2i(14, 30, 9, 9), Color(0.55, 0.72, 0.8))
	img.fill_rect(Rect2i(41, 30, 9, 9), Color(0.55, 0.72, 0.8))
	return img

# HUD: muestra las llamas de la casa según el nivel de fuego (P1 y P2)
func update_base_icon() -> void:
	var stage = app._base_stage()
	if app.base_destroying:
		stage = 3
	for flames in [app.base_icon_flames, app.base_icon_flames_p2]:
		for i in flames.size():
			var fr: Control = flames[i]
			fr.visible = (i < stage)

# Construye un icono de casa (base) con llamas progresivas; añade las llamas a p_flames
func add_base_icon(p_name: String, p_pos: Vector2, p_flames: Array, p_visible: bool = true) -> Control:
	var icon := Control.new()
	icon.name = p_name
	icon.position = p_pos
	icon.size = Vector2(72, 60)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = p_visible
	var house := TextureRect.new()
	house.texture = ImageTexture.create_from_image(make_house_texture())
	house.position = Vector2(3, 0)
	house.size = Vector2(64, 56)
	house.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(house)
	var flame_defs: Array = [
		[Vector2(42, 16), Vector2(10, 12), Color(1.0, 0.78, 0.25)],
		[Vector2(27, 9), Vector2(16, 18), Color(1.0, 0.55, 0.12)],
		[Vector2(12, 2), Vector2(34, 28), Color(0.95, 0.35, 0.08)]
	]
	for fd in flame_defs:
		var fr := ColorRect.new()
		fr.position = fd[0]
		fr.size = fd[1]
		fr.color = fd[2]
		fr.visible = false
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(fr)
		p_flames.append(fr)
	app.hud.add_child(icon)
	return icon

# Botón de música on/off (estilo AbilityBar). Conecta pressed → _toggle_music.
func make_music_button(p_name: String, p_pos: Vector2, p_visible: bool) -> Button:
	var b := Button.new()
	b.name = p_name
	b.position = p_pos
	b.text = app._music_lbl_text()
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.4))
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("shadow_outline_size", 4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.12, 0.8)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(0.85, 0.72, 0.3, 0.8)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.focus_mode = Control.FOCUS_NONE  # no robe foco/Enter a la navegación de menús
	b.pressed.connect(app._toggle_music)
	b.visible = p_visible
	app.hud.add_child(b)
	return b

# Barra de habilidades (PanelContainer + Label), estética dorada.
func make_ability_bar(p_name: String, p_lbl_name: String, p_pos: Vector2, p_visible: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = p_name
	panel.position = p_pos
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.12, 0.8)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(0.85, 0.72, 0.3, 0.8)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.name = p_lbl_name
	lbl.text = app._tr("hud_ability") % app._dev_abl_key()
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_outline_size", 4)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = p_visible
	app.hud.add_child(panel)
	return panel

func set_hud_pos(p_name: String, p_pos: Vector2) -> void:
	var nd: Node = app.hud.get_node_or_null(p_name)
	if nd is Control:
		(nd as Control).position = p_pos

# Layout del HUD en SINGLE PLAYER: cluster P1 al borde izquierdo, cluster P2 al derecho.
func hud_cluster_solo() -> void:
	set_hud_pos("AbilityBar", Vector2(20, 890))
	set_hud_pos("HPBar", Vector2(20, 985))
	set_hud_pos("VidaLabel", Vector2(20, 1010))
	set_hud_pos("BaseIcon", Vector2(245, 968))
	# Cluster derecho con margen (x=1620) para que no se corte en el borde
	set_hud_pos("MusicLabel", Vector2(1620, 890))
	set_hud_pos("WeaponIndicator", Vector2(1620, 950))
	set_crosshair_mode(false)  # una sola cruz al centro (single)

# Layout del HUD en SPLIT 2P: cada mitad se ve como el single player.
#  base-estado (Habilidades/Barra vida/% Vida/casita) a la IZQ · arma+música a la DER
func hud_cluster_split() -> void:
	# P1 (mitad izq., x 0-960)
	set_hud_pos("AbilityBar", Vector2(20, 890))
	set_hud_pos("HPBar", Vector2(20, 985))
	set_hud_pos("VidaLabel", Vector2(20, 1010))
	set_hud_pos("BaseIcon", Vector2(245, 968))
	set_hud_pos("MusicLabelP1", Vector2(640, 890))
	set_hud_pos("WeaponIndicatorP1", Vector2(640, 950))
	# Score/Oleada/PTS propios de P1 (espejo de los de P2, alineados al borde de su mitad)
	set_hud_pos("ScoreLabelP1", Vector2(640, 20))
	set_hud_pos("WaveLabelP1", Vector2(640, 50))
	set_hud_pos("PtsLabelP1", Vector2(640, 80))
	# P2 (mitad der., x 960-1920)
	set_hud_pos("AbilityBarP2", Vector2(1000, 890))
	set_hud_pos("HPBarP2", Vector2(1000, 985))
	set_hud_pos("VidaLabelP2", Vector2(1000, 1010))
	set_hud_pos("BaseIconP2", Vector2(1245, 968))
	set_hud_pos("MusicLabel", Vector2(1620, 890))
	set_hud_pos("WeaponIndicator", Vector2(1620, 950))
	set_crosshair_mode(true)  # cruz propia por mitad (P1 izq. / P2 der.)

# ─── HUD OVERLAY HELPERS ───
func clear_overlay_nodes() -> void:
	app._menu_nav_reset()
	app._abl_menu_nodes = []
	app._abl1_nodes = []
	app._abl1_nav = {"btns": [], "focus": null, "idx": 0}
	app._abilities_menu_open = false
	app._abl1_open = false
	var to_free: Array = []
	for child in app.hud.get_children():
		if not child.name in GameConfig.PERSISTENT_HUD:
			to_free.append(child)
	for node in to_free:
		app.hud.remove_child(node)
		node.queue_free()  # deferred: si se llama desde una señal (botón), el objeto está locked y free() falla
	app.initials_label = null
	app.options_music_btn = null

func make_overlay(p_name: String, p_color: Color) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.name = p_name
	overlay.color = p_color
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(1920, 1080)
	app.hud.add_child(overlay)
	return overlay

func make_label(p_name: String, p_pos: Vector2, p_text: String, p_size: int, p_color: Color = Color(1, 1, 1, 0.95)) -> Label:
	var lbl := Label.new()
	lbl.name = p_name
	lbl.position = p_pos
	lbl.text = p_text
	lbl.add_theme_font_size_override("font_size", p_size)
	lbl.add_theme_color_override("font_color", p_color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	lbl.add_theme_constant_override("shadow_outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(lbl)
	return lbl

# Label CENTRADO dentro de un rectángulo (menu de iniciales por mitad).
func make_centered_label(p_name: String, p_x: float, p_y: float, p_w: float, p_h: float, p_text: String, p_size: int, p_color: Color = Color(1, 1, 1, 0.95)) -> Label:
	var lbl := Label.new()
	lbl.name = p_name
	lbl.position = Vector2(p_x, p_y)
	lbl.size = Vector2(p_w, p_h)
	lbl.text = p_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", p_size)
	lbl.add_theme_color_override("font_color", p_color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(lbl)
	return lbl

func make_button(p_name: String, p_pos: Vector2, p_text: String, p_cb: Callable, p_nav: bool = true) -> Button:
	var btn := Button.new()
	btn.name = p_name
	btn.position = p_pos
	btn.size = Vector2(480, 62)
	btn.text = p_text
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.4))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.8, 0.3))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.07, 0.1, 0.16, 0.88)
	normal.border_color = Color(0.35, 0.6, 0.95, 0.9)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.22, 0.38, 0.95)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.2, 0.32, 0.55, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.pressed.connect(p_cb)
	app.hud.add_child(btn)
	if p_nav:
		app.menu_nav_buttons.append(btn)
	return btn

# ─── HUD UPDATE ───
func update_hud() -> void:
	var hp_bar: ProgressBar = app.hud.get_child(0) as ProgressBar
	if hp_bar:
		hp_bar.value = maxf(0, app.health)
	var vida_label: Label = app.hud.get_node_or_null("VidaLabel") as Label
	if vida_label:
		vida_label.text = "%s: %d%%" % [app._tr("hud_vida"), int(ceilf(clampf(app.health / app.base_hp_max, 0.0, 1.0) * 100.0))]
	# Score: single = score global; split = puntuación individual de cada jugador
	# (slot 0 = mitad izq. / slot 1 = mitad der., acreditada por kill_credit_slot)
	var score_label: Label = app.hud.get_node_or_null("ScoreLabel") as Label
	var score1_label: Label = app.hud.get_node_or_null("ScoreLabelP1") as Label
	if app.split_mode and app.mp_role == 3 and app.slot_states.size() > 1:
		if score1_label:
			score1_label.text = "%d" % int(app.slot_states[0].get("score", 0))
		if score_label:
			score_label.text = "%d" % int(app.slot_states[1].get("score", 0))
	elif score_label:
		score_label.text = "%d" % app.score
	var wave_label: Label = app.hud.get_node_or_null("WaveLabel") as Label
	if wave_label:
		wave_label.text = "%s %d" % [app._tr("wave_word"), app.wave]
	var wave1_label: Label = app.hud.get_node_or_null("WaveLabelP1") as Label
	if wave1_label:
		wave1_label.text = "%s %d" % [app._tr("wave_word"), app.wave]
	var ammo_label: Label = app.hud.get_node_or_null("AmmoLabel") as Label
	if ammo_label:
		var wname: String = app._tr("wpn%d" % app.current_weapon)
		var wammo: String = "∞" if app.current_weapon == 0 else str(app.ammo[app.current_weapon])
		ammo_label.text = "%s: %s" % [wname, wammo]
	# Caja de arma visible (abajo-derecha): actualización en tiempo real cada frame
	# Split 2P: derecha = P2 (gamepad) · izquierda = P1 (mouse)
	var wpn_lbl: Label = app.hud.get_node_or_null("WeaponIndicator/WeaponLabel") as Label
	if wpn_lbl:
		if app.split_mode and app.mp_role == 3 and app.slot_states.size() > 1:
			var st1: Dictionary = app.slot_states[1]
			var pi: int = int(st1.get("weapon", 0))
			var pa: Array = st1.get("ammo", [999999, 300, 20])
			var wtext := "  %s: %s  " % [app._tr("wpn%d" % pi), "∞" if pi == 0 else str(int(pa[pi]))]
			if wpn_lbl.text != wtext:
				wpn_lbl.text = wtext
		else:
			var wname_v: String = app._tr("wpn%d" % app.current_weapon)
			var wammo_v: String = "∞" if app.current_weapon == 0 else str(app.ammo[app.current_weapon])
			var wtext := "  %s: %s  " % [wname_v, wammo_v]
			if wpn_lbl.text != wtext:
				wpn_lbl.text = wtext
	var wpn1_lbl: Label = app.hud.get_node_or_null("WeaponIndicatorP1/WeaponLabel") as Label
	if wpn1_lbl and app.split_mode and app.mp_role == 3:
		var w1name: String = app._tr("wpn%d" % app.current_weapon)
		var w1ammo: String = "∞" if app.current_weapon == 0 else str(app.ammo[app.current_weapon])
		var w1text := "  %s: %s  " % [w1name, w1ammo]
		if wpn1_lbl.text != w1text:
			wpn1_lbl.text = w1text
	var pts_label: Label = app.hud.get_node_or_null("PtsLabel") as Label
	if pts_label:
		pts_label.text = "● %d PTS" % app.combat_pts
	var pts1_label: Label = app.hud.get_node_or_null("PtsLabelP1") as Label
	if pts1_label:
		pts1_label.text = "● %d PTS" % app.combat_pts  # PTS de habilidades: pool compartido (igual en ambas mitades)
	# P2 (split): barra de vida + etiqueta Vida (misma base que P1)
	var hp2: ProgressBar = app.hud.get_node_or_null("HPBarP2") as ProgressBar
	if hp2:
		hp2.value = maxf(0, app.health)
	var vida2: Label = app.hud.get_node_or_null("VidaLabelP2") as Label
	if vida2:
		vida2.text = "%s: %d%%" % [app._tr("hud_vida"), int(ceilf(clampf(app.health / app.base_hp_max, 0.0, 1.0) * 100.0))]
	# Etiquetas estáticas del HUD: se refrescan por frame para reflejar el idioma activo
	if app.music_label:
		app.music_label.text = app._music_lbl_text()
	if app.music_label_p1:
		app.music_label_p1.text = app._music_lbl_text()
	var abl_lbl: Label = app.hud.get_node_or_null("AbilityLabel") as Label
	if abl_lbl:
		abl_lbl.text = app._tr("hud_ability") % app._dev_abl_key()
	var abl_lbl2: Label = app.hud.get_node_or_null("AbilityLabelP2") as Label
	if abl_lbl2:
		abl_lbl2.text = app._tr("hud_ability") % app._dev_abl_key()


