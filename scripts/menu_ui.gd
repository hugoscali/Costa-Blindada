class_name MenuUI
extends RefCounted
## Costa Blindada — pantallas de menú: inicio, pausa, opciones, gráficos,
## puntuaciones (single/2-3-4 jugadores), idioma, elección de dispositivo y
## asignación de mandos del split. Incluye sus botones y su navegación.
##
## Es una VISTA: dibuja en el CanvasLayer del HUD de main.gd usando sus fábricas
## (_make_button/_make_label/_clear_overlay_nodes) y registra los botones en la
## navegación con joystick de main.gd, que es la que sigue procesando el input.
## `app` es main.gd: dueño de phase, current_menu, ajustes, highscores y del flujo
## de juego. main.gd crea una instancia en _build_menu() y la llama app._menu.

var app  # main.gd (acceso dinámico: main.gd sigue siendo el dueño del estado)

# ─── MENÚS (inicio, pausa, puntuaciones, opciones) ───
func show_menu() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var _xh = app.get_node_or_null("CrosshairLayer")
	if _xh: _xh.visible = false
	app._hud.clear_overlay_nodes()
	app.current_menu = "menu"
	app._hud.make_overlay("MenuOverlay", Color(0.02, 0.04, 0.08, 0.45))
	# Título principal: grande, acero, con sombra fuerte
	var title = app._hud.make_label("MenuTitle", Vector2(550, 140), app._tr("menu_title"), 78, Color(0.75, 0.82, 0.95))
	title.add_theme_color_override("font_shadow_color", Color(0.1, 0.15, 0.3, 0.9))
	title.add_theme_constant_override("shadow_outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.15))
	title.add_theme_constant_override("outline_size", 4)
	# Subtítulo: línea de defensa
	app._hud.make_label("MenuSub", Vector2(570, 250), app._tr("menu_sub"), 24, Color(0.85, 0.72, 0.35))
	# Separador
	app._hud.make_label("MenuSep", Vector2(600, 300), "═══════════════════════════", 20, Color(0.4, 0.5, 0.65, 0.7))
	var bx := 720.0
	var by := 390.0
	app._hud.make_button("MenuBtnStart", Vector2(bx, by), app._tr("menu_start"), on_btn_start)
	app._hud.make_button("MenuBtnSplit", Vector2(bx, by + 80), app._tr("menu_split"), on_btn_split_choice)
	app._hud.make_button("MenuBtnMultiplayer", Vector2(bx, by + 160), app._tr("menu_mp"), on_btn_lan_choice)
	app._hud.make_button("MenuBtnScores", Vector2(bx, by + 240), app._tr("menu_scores"), on_btn_scores)
	app._hud.make_button("MenuBtnOptions", Vector2(bx, by + 320), app._tr("menu_options"), on_btn_options)
	app._hud.make_button("MenuBtnQuit", Vector2(bx, by + 400), app._tr("menu_quit"), on_btn_quit)
	# Botón de idioma (abajo-izquierda, naranja llamativo)
	var lang_btn = app._hud.make_button("MenuBtnLang", Vector2(40, 950), app._tr("menu_lang"), on_btn_lang)
	lang_btn.size = Vector2(230, 58)
	var lb_sb := StyleBoxFlat.new()
	lb_sb.bg_color = Color(0.92, 0.45, 0.08, 0.95)
	lb_sb.border_color = Color(1.0, 0.72, 0.2)
	lb_sb.set_border_width_all(3)
	lb_sb.set_corner_radius_all(6)
	lang_btn.add_theme_stylebox_override("normal", lb_sb)
	lang_btn.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85))
	lang_btn.add_theme_color_override("font_shadow_color", Color(0.35, 0.18, 0.0))
	lang_btn.add_theme_constant_override("shadow_outline_size", 4)
	app._hud.make_label("MenuInfo", Vector2(300, 970), app._tr("menu_info_joy") if app.local_input_mode == 1 else app._tr("menu_info"), 18, Color(1, 1, 1, 0.7))
	app.phase = app.GamePhase.MENU

func show_pause_menu() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var _xh = app.get_node_or_null("CrosshairLayer")
	if _xh: _xh.visible = false
	app._hud.clear_overlay_nodes()
	app.current_menu = "pause"
	app._hud.make_overlay("PauseOverlay", Color(0.02, 0.04, 0.08, 0.55))
	# Mini título del juego
	app._hud.make_label("PauseGame", Vector2(640, 120), "COSTA BLINDADA", 30, Color(0.6, 0.7, 0.88, 0.8))
	# PAUSA grande
	var pt = app._hud.make_label("PauseTitle", Vector2(740, 170), app._tr("pause_title"), 56, Color(1, 0.9, 0.4))
	pt.add_theme_color_override("font_shadow_color", Color(0.2, 0.15, 0.0))
	pt.add_theme_constant_override("shadow_outline_size", 8)
	var bx := 720.0
	var by := 370.0
	app._hud.make_button("PauseBtnStart", Vector2(bx, by), app._tr("pause_resume"), on_btn_start)
	app._hud.make_button("PauseBtnRestart", Vector2(bx, by + 80), app._tr("pause_restart"), on_btn_restart)
	app._hud.make_button("PauseBtnScores", Vector2(bx, by + 160), app._tr("menu_scores"), on_btn_scores)
	app._hud.make_button("PauseBtnOptions", Vector2(bx, by + 240), app._tr("menu_options"), on_btn_options)
	app._hud.make_button("PauseBtnMenu", Vector2(bx, by + 340), app._tr("pause_backmenu"), on_btn_back_to_menu)
	app._hud.make_button("PauseBtnQuit", Vector2(bx, by + 440), app._tr("menu_quit"), on_btn_quit)
	app._hud.make_label("PauseHint", Vector2(640, 930), app._tr("pause_hint"), 18, Color(1, 1, 1, 0.7))
	app.phase = app.GamePhase.PAUSE

func show_options() -> void:
	app.hs_return_phase = app.phase
	app._hud.clear_overlay_nodes()
	app.current_menu = "options"
	app._hud.make_overlay("OPOverlay", Color(0, 0, 0, 0.85))
	app._hud.make_label("OPTitle", Vector2(720, 240), app._tr("menu_options"), 48, Color(1, 0.9, 0.4))
	app.options_music_btn = app._hud.make_button("OPMusicBtn", Vector2(720, 380), app._tr("opt_music") % ("ON" if app.music_enabled else "OFF"), on_btn_music)
	app._hud.make_button("OPGraphicsBtn", Vector2(720, 480), app._tr("opt_graphics"), on_btn_graphics)
	app._hud.make_button("OPControlsBtn", Vector2(720, 580), app._tr("opt_controls"), app._on_btn_controls)
	app._hud.make_button("OPBtnBack", Vector2(720, 680), app._tr("opt_back"), on_btn_hs_back)

func show_graphics() -> void:
	app._hud.clear_overlay_nodes()
	app.current_menu = "graphics"
	app._hud.make_overlay("GFOverlay", Color(0, 0, 0, 0.88))
	app._hud.make_label("GFTitle", Vector2(700, 100), app._tr("opt_graphics"), 48, Color(1, 0.9, 0.4))
	# ─── Relación de aspecto ───
	app._hud.make_label("GFAspectLabel", Vector2(320, 190), app._tr("gf_aspect"), 24, Color(1, 1, 1, 0.85))
	var ax := 320.0
	for i in GameConfig.ASPECT_NAMES.size():
		var abtn = app._hud.make_button("GFAspectBtn%d" % i, Vector2(ax, 240), GameConfig.ASPECT_NAMES[i], on_btn_aspect.bind(i))
		abtn.size = Vector2(160, 56)
		if i == app.aspect_idx:
			style_active(abtn)
		ax += 180.0
	# ─── Resolución (según el aspecto) ───
	app._hud.make_label("GFResLabel", Vector2(320, 330), app._tr("gf_res"), 24, Color(1, 1, 1, 0.85))
	var res_list: Array = app._resolutions()
	var rx := 320.0
	for i in res_list.size():
		var res: Vector2i = res_list[i]
		var btn = app._hud.make_button("GFResBtn%d" % i, Vector2(rx, 380), "%d×%d" % [res.x, res.y], on_btn_res.bind(i))
		btn.size = Vector2(180, 56)
		if res == app.game_resolution:
			style_active(btn)
		rx += 200.0
	# ─── Calidad gráfica ───
	app._hud.make_label("GFQualLabel", Vector2(320, 470), app._tr("gf_quality"), 24, Color(1, 1, 1, 0.85))
	var qx := 320.0
	for i in 3:
		var btn2 = app._hud.make_button("GFQualBtn%d" % i, Vector2(qx, 520), app._tr("q%d" % i), on_btn_quality.bind(i))
		btn2.size = Vector2(180, 56)
		if i == app.quality_level:
			style_active(btn2)
		qx += 200.0
	# ─── Modo de pantalla ───
	app._hud.make_label("GFModeLabel", Vector2(320, 610), app._tr("gf_mode"), 24, Color(1, 1, 1, 0.85))
	var mbtn1 = app._hud.make_button("GFModeWindow", Vector2(320, 660), app._tr("gf_window"), on_btn_window_mode.bind(false))
	mbtn1.size = Vector2(180, 56)
	var mbtn2 = app._hud.make_button("GFModeFull", Vector2(520, 660), app._tr("gf_full"), on_btn_window_mode.bind(true))
	mbtn2.size = Vector2(320, 56)  # mas ancho: el texto "PANTALLA COMPLETA" quedaba al limite del boton
	if app.fullscreen:
		style_active(mbtn2)
	else:
		style_active(mbtn1)
	# ─── Upscale 3D: FSR / DLSS / OFF (DLSS solo en engines con Streamline) ───
	var has_dlss: bool = app._engine_has_dlss()
	app._hud.make_label("GFUpLabel", Vector2(320, 750), app._tr("gf_upscale"), 24, Color(1, 1, 1, 0.85))
	var up_x := [320.0, 520.0, 720.0]
	var up_labels := ["FSR", "DLSS", "OFF"]
	var upbtns: Array = [null, null, null]
	for i in 3:
		if i == 1 and not has_dlss:
			continue  # el botón DLSS solo existe en engines que lo soportan
		var ubtn = app._hud.make_button("GFUpBtn%d" % i, Vector2(up_x[i], 800), up_labels[i], on_btn_upscaler.bind(i))
		ubtn.size = Vector2(180, 56)
		upbtns[i] = ubtn
	var active_up: int = app.upscaler
	if active_up == 1 and not has_dlss:
		active_up = 0  # DLSS guardado en un engine sin DLSS: en la práctica corre FSR
	if upbtns[active_up]:
		style_active(upbtns[active_up])
	# Frame Generation (DLSS-FG): solo engines con Streamline + RTX 40+
	var hint: String = app._tr("gf_fsr_hint")
	if has_dlss:
		app._hud.make_label("GFFgLabel", Vector2(1000, 750), app._tr("gf_fg_label"), 24, Color(1, 1, 1, 0.85))
		app.gf_fg_on_btn = app._hud.make_button("GFFgOn", Vector2(1000, 800), "ON", on_btn_fg.bind(true))
		app.gf_fg_on_btn.size = Vector2(140, 56)
		app.gf_fg_off_btn = app._hud.make_button("GFFgOff", Vector2(1190, 800), "OFF", on_btn_fg.bind(false))
		app.gf_fg_off_btn.size = Vector2(140, 56)
		if app.fg_enabled and active_up == 1:
			style_active(app.gf_fg_on_btn)
		else:
			style_active(app.gf_fg_off_btn)
		hint += " | " + app._tr("gf_fg_hint")
	# Modos de upscale (aplican a FSR y DLSS por igual)
	var fsr_x := [320.0, 660.0, 910.0]
	var fsr_w := [300.0, 210.0, 170.0]
	app.gf_fsr_mode_btns.clear()
	for i in 3:
		var fbtn = app._hud.make_button("GFFsrMode%d" % i, Vector2(fsr_x[i], 870), app._tr("fsr%d" % i), on_btn_fsr_mode.bind(i))
		fbtn.size = Vector2(fsr_w[i], 56)
		app.gf_fsr_mode_btns.append(fbtn)
	style_active(app.gf_fsr_mode_btns[app.fsr_mode])
	app._hud.make_label("GFHint", Vector2(320, 945), hint, 18, Color(1, 1, 1, 0.65))
	app._hud.make_button("GFBtnBack", Vector2(720, 1000), app._tr("opt_back"), on_btn_graphics_back)

# ESC = volver atrás en cualquier pantalla de menú (cada una sabe su destino)
func menu_back() -> void:
	if app.ui_select:
		app.ui_select.play()
	match app.current_menu:
		"input_choice":
			show_menu()
		"controls_kb":
			app._show_controls()
		"controls_joy":
			app._show_controls()
		"controls":
			show_options()
		"graphics":
			show_options()
		"options":
			# Igual que el botón VOLVER: si venía de la pausa, volver a la pausa
			if app.hs_return_phase == app.GamePhase.PAUSE:
				show_pause_menu()
			else:
				show_menu()
		"hs_main":
			if app.hs_return_phase == app.GamePhase.PAUSE:
				show_pause_menu()
			else:
				show_menu()
		"hs_mp":
			show_hs_main()
		"hs_cat":
			if app.hs_cat == "single":
				show_hs_main()
			else:
				show_hs_mp()
		"mp_select":
			show_menu()
		"lang":
			show_menu()
		"mp_create_join":
			app._show_mp_select()
		"mp_create_pw":
			app._show_mp_create_join(app.mp_last_n)
		"mp_browser":
			app._show_mp_create_join(app.mp_last_n)
		"mp_browser_search":
			app._show_mp_create_join(app.mp_last_n)
		"mp_host":
			show_menu()
		"mp_waiting":
			show_menu()
		"split_assign":
			show_input_choice("split")
		"error":
			app._mp_err_back.call()
		_:
			show_menu()

func style_active(btn: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 0.25, 0.05, 0.95)
	sb.border_color = Color(1.0, 0.8, 0.2)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))

func show_highscores() -> void:
	app.hs_return_phase = app.phase
	show_hs_main()

func show_hs_main() -> void:
	app._hud.clear_overlay_nodes()
	app.current_menu = "hs_main"
	app._hud.make_overlay("HSOverlay", Color(0, 0, 0, 0.85))
	app._hud.make_label("HSTitle", Vector2(660, 120), app._tr("menu_scores"), 48, Color(1, 0.9, 0.4))
	app._hud.make_button("HSBtnSingle", Vector2(620, 320), app._tr("hs_single"), on_btn_hs_single)
	app._hud.make_button("HSBtnMP", Vector2(620, 440), app._tr("menu_mp"), on_btn_hs_mp)
	app._hud.make_button("HSBtnBack", Vector2(720, 920), app._tr("opt_back"), on_btn_hs_back)

func on_btn_hs_single() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_hs_cat("single")

func on_btn_hs_mp() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_hs_mp()

func show_hs_mp() -> void:
	app._hud.clear_overlay_nodes()
	app.current_menu = "hs_mp"
	app._hud.make_overlay("HSOverlay", Color(0, 0, 0, 0.85))
	app._hud.make_label("HSTitle", Vector2(660, 120), app._tr("menu_mp"), 48, Color(1, 0.9, 0.4))
	app._hud.make_button("HSBtnP2", Vector2(660, 300), "%d %s" % [2, app._tr("players_word")], on_btn_hs_p2)
	app._hud.make_button("HSBtnP3", Vector2(660, 420), "%d %s" % [3, app._tr("players_word")], on_btn_hs_p3)
	app._hud.make_button("HSBtnP4", Vector2(660, 540), "%d %s" % [4, app._tr("players_word")], on_btn_hs_p4)
	app._hud.make_button("HSBtnBack2", Vector2(720, 920), app._tr("opt_back"), on_btn_hs_back_main)

func on_btn_hs_p2() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_hs_cat("2")

func on_btn_hs_p3() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_hs_cat("3")

func on_btn_hs_p4() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_hs_cat("4")

func on_btn_hs_back_main() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_hs_main()

func show_hs_cat(cat: String) -> void:
	app._hud.clear_overlay_nodes()
	app.current_menu = "hs_cat"
	app.hs_cat = cat
	app._hud.make_overlay("HSOverlay", Color(0, 0, 0, 0.85))
	var title: String = app._tr("hs_single") if cat == "single" else "%s %s" % [cat, app._tr("players_word")]
	app._hud.make_label("HSTitle", Vector2(600, 120), title, 48, Color(1, 0.9, 0.4))
	var lst := hs_list_for(cat)
	var rows := ""
	if lst.is_empty():
		rows = app._tr("hs_none")
	elif cat == "single":
		for i in lst.size():
			var hs = lst[i]
			rows += "%2d.   %s    %6d    %s %d\n" % [i + 1, hs["initials"], hs["score"], app._tr("wave_word"), hs["wave"]]
	else:
		for i in lst.size():
			var hs = lst[i]
			var pl: String = " · ".join(hs["players"])
			rows += "%2d.   %6d   %s %d   %s   %s\n" % [i + 1, hs["score"], app._tr("wave_word"), hs["wave"], pl, str(hs.get("date", ""))]
	app._hud.make_label("HSList", Vector2(480, 230), rows, 26)
	var clr = app._hud.make_button("HSClearBtn", Vector2(720, 800), app._tr("hs_clear"), on_btn_hs_clear)
	clr.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	clr.add_theme_color_override("font_hover_color", Color(1.0, 0.3, 0.28))
	clr.add_theme_color_override("font_pressed_color", Color(0.9, 0.2, 0.2))
	app._hud.make_button("HSBtnBack", Vector2(720, 900), app._tr("opt_back"), on_btn_hs_cat_back)

func on_btn_hs_clear() -> void:
	if app.ui_select:
		app.ui_select.play()
	if not app.hs_clear_arm:
		app.hs_clear_arm = true
		var b: Button = app.hud.get_node_or_null("HSClearBtn") as Button
		if b:
			b.text = app._tr("hs_clear_arm")
		return
	app.hs_clear_arm = false
	clear_hs_cat(app.hs_cat)
	show_hs_cat(app.hs_cat)

func clear_hs_cat(cat: String) -> void:
	if cat == "single":
		app.highscores = []
	else:
		app.hs_mp[cat] = []
	app._save_highscores()

func on_btn_hs_cat_back() -> void:
	if app.ui_select:
		app.ui_select.play()
	if app.hs_cat == "single":
		show_hs_main()
	else:
		show_hs_mp()

func hs_list_for(cat: String) -> Array:
	if cat == "single":
		return app.highscores
	return app.hs_mp.get(cat, [])

# ─── CALLBACKS DE BOTONES ───
func on_btn_start() -> void:
	if app.ui_select:
		app.ui_select.play()
	if app.phase == app.GamePhase.PAUSE:
		app._resume_game()
	else:
		show_input_choice("single")

# ─── MENÚ DE ELECCIÓN DE DISPOSITIVO (pre-partida) ───
# single: jugador solo · split: elige el J1 (J2 siempre joystick) · lan: cada PC elige el suyo
func show_input_choice(next: String) -> void:
	app.io_next = next
	if app.ui_select:
		app.ui_select.play()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	app._hud.clear_overlay_nodes()
	app.current_menu = "input_choice"
	app._hud.make_overlay("IOOverlay", Color(0.02, 0.04, 0.08, 0.6))
	var title = app._hud.make_label("IOTitle", Vector2(560, 280), app._tr("io_title"), 44, Color(0.75, 0.82, 0.95))
	title.add_theme_color_override("font_shadow_color", Color(0.1, 0.15, 0.3, 0.9))
	title.add_theme_constant_override("shadow_outline_size", 8)
	var bx := 720.0
	var by := 440.0
	app._hud.make_button("IOBtnKB", Vector2(bx, by), app._tr("io_kb"), on_io_kb)
	app._hud.make_button("IOBtnJoy", Vector2(bx, by + 80), app._tr("io_joy"), on_io_joy)
	if next == "split":
		app._hud.make_label("IOSplitHint", Vector2(600, 640), app._tr("io_split_hint"), 22, Color(0.85, 0.72, 0.35))
	app._hud.make_button("IOBtnBack", Vector2(720, 920), app._tr("opt_back"), on_io_back)

func on_io_kb() -> void:
	if app.ui_select:
		app.ui_select.play()
	app.local_input_mode = 0
	app.joy0_btn_prev.clear()
	if app.io_next == "split":
		app.split_j1_dev = 0
		app.split_j2_dev = 0
	io_go()

func on_io_joy() -> void:
	if app.ui_select:
		app.ui_select.play()
	app.local_input_mode = 1
	app.joy0_btn_prev.clear()
	if app.io_next == "split":
		show_split_assign()
	else:
		io_go()

func io_go() -> void:
	match app.io_next:
		"single":
			app._start_game()
		"split":
			app._start_split_game()
		"lan":
			app._show_mp_select()

func on_io_back() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_menu()

# ─── PANTALLA DE ASIGNACIÓN DE MANDOS (split, 2 joysticks) ───
func show_split_assign() -> void:
	app.local_input_mode = 1
	app.split_j1_dev = -1
	app.split_j2_dev = -1
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	app._hud.clear_overlay_nodes()
	app.current_menu = "split_assign"
	app._hud.make_overlay("AssignOverlay", Color(0, 0, 0, 0.88))
	app._hud.make_label("AssignTitle", Vector2(560, 140), app._tr("assign_title"), 46, Color(1, 0.9, 0.4))
	app._hud.make_label("AssignHint", Vector2(400, 250), app._tr("assign_hint"), 20, Color(1, 1, 1, 0.85))
	app._hud.make_label("AssignJ1Lbl", Vector2(320, 360), app._tr("assign_j1"), 30, Color(0.55, 0.85, 1.0))
	app._hud.make_label("AssignJ1Val", Vector2(320, 410), app._tr("assign_wait"), 24, Color(1, 1, 1, 0.65))
	app._hud.make_label("AssignJ2Lbl", Vector2(320, 500), app._tr("assign_j2"), 30, Color(0.55, 0.85, 1.0))
	app._hud.make_label("AssignJ2Val", Vector2(320, 550), app._tr("assign_wait"), 24, Color(1, 1, 1, 0.65))
	var start = app._hud.make_button("AssignStart", Vector2(560, 700), app._tr("assign_start"), on_split_assign_start)
	start.disabled = true
	app._hud.make_button("AssignBack", Vector2(720, 820), app._tr("opt_back"), on_assign_back)

func on_assign_back() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_input_choice("split")

func on_split_assign_start() -> void:
	if app.split_j1_dev < 0 or app.split_j2_dev < 0:
		return
	app._start_split_game()

func split_assign_claim(jb: InputEventJoypadButton) -> void:
	if not jb.pressed:
		return
	var dev := int(jb.device)
	if app.split_j1_dev < 0:
		app.split_j1_dev = dev
		update_split_assign_display()
		return
	if app.split_j2_dev < 0 and dev != app.split_j1_dev:
		app.split_j2_dev = dev
		update_split_assign_display()
		return
	if dev != app.split_j1_dev:
		return  # el otro pad no pisa el menú (evita "pelear")
	app._joy_menu_nav(jb)

func update_split_assign_display() -> void:
	var j1: Label = app.hud.get_node_or_null("AssignJ1Val") as Label
	var j2: Label = app.hud.get_node_or_null("AssignJ2Val") as Label
	if j1:
		j1.text = Input.get_joy_name(app.split_j1_dev) if app.split_j1_dev >= 0 else app._tr("assign_wait")
	if j2:
		j2.text = Input.get_joy_name(app.split_j2_dev) if app.split_j2_dev >= 0 else app._tr("assign_wait")
	var start: Button = app.hud.get_node_or_null("AssignStart") as Button
	if start:
		start.disabled = not (app.split_j1_dev >= 0 and app.split_j2_dev >= 0)

func on_btn_split_choice() -> void:
	show_input_choice("split")

func on_btn_lan_choice() -> void:
	show_input_choice("lan")

func on_btn_restart() -> void:
	app._restart_game()

func on_btn_back_to_menu() -> void:
	# Detiene la partida y vuelve al menú principal (para pasar a multijugador, etc.)
	app._mp_abort_cleanup()
	# Limpia el gestor de red si estaba en MP
	if app.net != null:
		app.net.cleanup()
		app.remove_child(app.net)
		app.net = null
	show_menu()

func on_btn_scores() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_highscores()

func on_btn_options() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_options()

func on_btn_lang() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_lang_select()

func show_lang_select() -> void:
	app._hud.clear_overlay_nodes()
	app.current_menu = "lang"
	app._hud.make_overlay("LangOverlay", Color(0, 0, 0, 0.85))
	app._hud.make_label("LangTitle", Vector2(620, 150), app._tr("lang_title"), 48, Color(1, 0.75, 0.25))
	var es_btn = app._hud.make_button("LangBtnES", Vector2(660, 320), app._tr("lang_es"), on_lang_pick.bind(0))
	es_btn.size = Vector2(320, 80)
	if app.lang == 0:
		style_active(es_btn)
	var en_btn = app._hud.make_button("LangBtnEN", Vector2(660, 440), app._tr("lang_en"), on_lang_pick.bind(1))
	en_btn.size = Vector2(320, 80)
	if app.lang == 1:
		style_active(en_btn)
	app._hud.make_button("LangBtnBack", Vector2(720, 900), app._tr("opt_back"), show_menu)

func on_lang_pick(i: int) -> void:
	if app.ui_select:
		app.ui_select.play()
	app.lang = i
	app._save_settings()
	show_menu()

func on_btn_quit() -> void:
	if app.ui_quit:
		app.ui_quit.play()
	app.get_tree().quit()

func on_btn_graphics() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_graphics()

func on_btn_aspect(i: int) -> void:
	if app.ui_select:
		app.ui_select.play()
	app.aspect_idx = i
	if not app._resolutions().has(app.game_resolution):
		# La resolución actual no existe en el nuevo aspecto: usar 1080p (720p en 16:10 si no)
		app._apply_resolution(Vector2i(1920, 1080) if app.aspect_idx == 0 else Vector2i(1920, 1200))
	else:
		app._save_settings()
	show_graphics()

func on_btn_window_mode(fs: bool) -> void:
	if app.ui_select:
		app.ui_select.play()
	app.fullscreen = fs
	app._apply_display_mode()
	show_graphics()

func on_btn_res(i: int) -> void:
	if app.ui_select:
		app.ui_select.play()
	app._apply_resolution(app._resolutions()[i])
	show_graphics()

func on_btn_quality(i: int) -> void:
	if app.ui_select:
		app.ui_select.play()
	app._apply_quality(i)
	show_graphics()

func on_btn_upscaler(u: int) -> void:
	if app.ui_select:
		app.ui_select.play()
	if u == 1 and not app._engine_has_dlss():
		return  # DLSS no disponible en este engine
	app.upscaler = u
	if u != 2:
		app.upscaler_last = u
	app._apply_fsr()
	show_graphics()

func on_btn_fsr_mode(m: int) -> void:
	if app.ui_select:
		app.ui_select.play()
	app.fsr_mode = m
	if app.upscaler == 2:
		app.upscaler = app.upscaler_last  # elegir un modo reactiva el último upscale usado
	app._apply_fsr()
	show_graphics()

func on_btn_fg(on: bool) -> void:
	if app.ui_select:
		app.ui_select.play()
	app.fg_enabled = on
	if on and app._engine_has_dlss():
		app.upscaler = 1  # Frame Generation requiere el pipeline DLSS
		app.upscaler_last = 1
	app._apply_fsr()
	show_graphics()

func on_btn_graphics_back() -> void:
	if app.ui_select:
		app.ui_select.play()
	show_options()

func on_btn_music() -> void:
	app._toggle_music()
	if app.options_music_btn:
		app.options_music_btn.text = app._tr("opt_music") % ("ON" if app.music_enabled else "OFF")

func on_btn_hs_back() -> void:
	if app.ui_select:
		app.ui_select.play()
	if app.hs_return_phase == app.GamePhase.PAUSE:
		show_pause_menu()
	else:
		show_menu()

