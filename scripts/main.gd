extends Node3D
## Beach Defense 2000 Remake - Main Game Script
## Builds the entire world, handles input, spawns enemies, manages waves.
##
## MÃ³dulos (scripts/*.gd): game_config.gd (constantes) Â· i18n.gd (ES/EN)
## Â· save_data.gd (highscores/ajustes en user://) Â· world_math.gd (terrain/scatter/AABB).
## main.gd es el orquestador: mantiene el estado y delega en esos mÃ³dulos.

# â”€â”€â”€ CONFIG (constantes: ver scripts/game_config.gd) â”€â”€â”€
# Alias cortos: el resto del cÃ³digo no cambia.
const ENEMY_HOLD_Z: float = GameConfig.ENEMY_HOLD_Z      # lÃ­nea de detenciÃ³n (10m antes de la pared frontal)
const ENEMY_HOLD_BAND: float = GameConfig.ENEMY_HOLD_BAND  # a partir de acÃ¡ tienden a detenerse a disparar
const ENEMY_MAX_X: float = GameConfig.ENEMY_MAX_X        # no rodean los costados de la base
const ABL_COSTS := GameConfig.ABL_COSTS                  # costos en puntos de combate
const ABL_KEYS := GameConfig.ABL_KEYS                    # tecla â†’ habilidad
const weapon_damage := GameConfig.WEAPON_DAMAGE
const weapon_rate := GameConfig.WEAPON_RATE        # cadencia por arma (ver nota en game_config)
const weapon_spread := GameConfig.WEAPON_SPREAD
const weapon_speed := GameConfig.WEAPON_SPEED
const CANNON_SPLASH_DMG := GameConfig.CANNON_SPLASH_DMG  # daÃ±o de Ã¡rea (splash) del caÃ±Ã³n
const MINE_RADIUS: float = GameConfig.MINE_RADIUS        # radio/daÃ±o de mina: similares al caÃ±Ã³n del Arma 3
const MINE_DMG: float = GameConfig.MINE_DMG
const VKB_COLS := GameConfig.VKB_COLS                    # teclado virtual: A-M (fila 0), N-Z (fila 1)
const VKB_ROWS := GameConfig.VKB_ROWS
const PERSISTENT_HUD := GameConfig.PERSISTENT_HUD        # nodos del HUD que NO se borran al cambiar de pantalla
const ASPECT_NAMES := GameConfig.ASPECT_NAMES
const QUALITY_NAMES := GameConfig.QUALITY_NAMES
const SPLIT_ENV_EXPOSURE: float = GameConfig.SPLIT_ENV_EXPOSURE  # igual que single-player (env_ref)
const KEY_BINDS_DEFAULT := GameConfig.KEY_BINDS_DEFAULT
const JOY_BINDS_DEFAULT := GameConfig.JOY_BINDS_DEFAULT

# â”€â”€â”€ STATE â”€â”€â”€
enum GamePhase { MENU, PLAYING, PAUSE, GAMEOVER }
var phase: GamePhase = GamePhase.MENU
var health: float = 150.0  # = vida de la base militar (los enemigos la atacan)
var score: int = 0
# â”€â”€â”€ BASE (objetivo de los enemigos) â”€â”€â”€
var base_target := Vector3(0.0, 1.5, 55.0)  # centro del recinto
# Los enemigos avanzan hacia la base pero se detienen a 10m de su frente (pared z=40), sin rodearla
var warship_spots: Array = []   # puntos de despegue (cubierta de cada buque) para helicÃ³pteros
var base_fire_group: Node3D = null
var base_fire_emitters: Array = []  # GPUParticles3D de fuego
var base_smoke_emitters: Array = []  # GPUParticles3D de humo
var base_fire_stage: int = 0  # 0=perfecto 1=leve 2=medio 3=alto/explosiones
var base_explosion_timer: float = 999.0
var game_generation: int = 0  # se incrementa al reiniciar: invalida callbacks de la partida anterior
var base_destroying: bool = false
var base_icon: Control = null
var base_icon_flames: Array = []
var base_icon_p2: Control = null
var base_icon_flames_p2: Array = []
var wave: int = 1
var current_weapon: int = 0  # 0=pistol, 1=SMG, 2=cannon
var ammo: Array = [999999, 300, 20]
var enemies: Array = []
var projectiles: Array = []
var enemy_projectiles: Array = []
var crates: Array = []
var crate_timer: float = 8.0

# â”€â”€â”€ PUNTOS DE COMBATE â”€â”€â”€
var combat_pts: int = 0
var abl_rapid_t: float = 0.0       # RÃ¡faga: 5s 3x velocidad disparo
var abl_shield_t: float = 0.0      # Escudo: 8s bloquea balas enemigas
var abl_overload_t: float = 0.0    # Sobrecarga: 5s 2x daÃ±o
var abl_mines: Array = []          # Minas activas [{node, armed:bool}]

# --- ARRANQUE RAPIDO PARA PROBAR (apagado) --------------------------------------
# Sirve para empezar la partida directo en una oleada alta, con puntos de combate y
# el cargamento correspondiente, y asi medir rendimiento sin jugar 10 oleadas.
# Apagado: arranca en la oleada 1 con 0 puntos, como siempre. Para usarlo de nuevo:
# DEBUG_START_WAVE = 10 y DEBUG_START_POINTS = 400.
var DEBUG_START_WAVE: int = 1
var DEBUG_START_POINTS: int = 0

func _debug_apply_start() -> void:
	if DEBUG_START_WAVE <= 1 and DEBUG_START_POINTS <= 0:
		return
	wave = DEBUG_START_WAVE
	combat_pts = DEBUG_START_POINTS
	ammo = [999999, 400, 50]

# â”€â”€â”€ I18N (ES / EN) â”€â”€â”€
var lang: int = 0  # 0 = EspaÃ±ol (default), 1 = English â€” persistido en settings.json

# Tablas ES/EN y el lookup: ver scripts/i18n.gd (class_name I18N).
func _tr(k: String) -> String:
	# Delegado en i18n.gd (tablas ES/EN + fallback al espaÃ±ol).
	return I18N.t(lang, k)
# Anti "explosiÃ³n fantasma": Ãºltimo boom de muerte (posiciÃ³n + tiempo). Si una bala
# del caÃ±Ã³n cae sobre un casco reciÃ©n destruido, no re-explota visualmente.
var last_kill_boom_pos: Vector3 = Vector3.ZERO
var last_kill_boom_t: float = -1000.0

# Wave
var enemies_to_spawn: int = 0
var spawn_timer: float = 0.0
var last_shot_time: float = 0.0

# Camera
var yaw: float = 0.0
var pitch: float = 0.0
var mouse_down: bool = false
var click_queued: bool = false  # semi-auto (weapon 1): one shot per click
var dual_toggle: int = 0  # dual-wield (weapon 2): alternate left/right muzzles

# Nodes
var camera: Camera3D
var world: Node3D
var hud: CanvasLayer
var crosshair_layer: CanvasLayer = null  # cache: evita get_node por string cada frame en _process
var crosshairs: Array = []  # [{root,h,v,dot,fx,fy,split}] para reposicionarlas a la resoluciÃ³n real (usa hud.gd vÃ­a app.crosshairs)
var audio_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var music_enabled: bool = true
var ui_select: AudioStreamPlayer
var ui_start: AudioStreamPlayer
var ui_quit: AudioStreamPlayer
var ui_gameover: AudioStreamPlayer
var ui_levelup: AudioStreamPlayer
var music_label: Control  # Button: mÃºsica on/off (estilo AbilityBar)
var music_label_p1: Control = null  # Button: mÃºsica on/off para P1 (split)

# â”€â”€â”€ HIGH SCORES / UI MENÃš â”€â”€â”€
# (archivo y top-10: ver scripts/save_data.gd â€” SaveData.HS_FILE / HS_MAX)
var highscores: Array = []  # [{"score":int, "initials":String, "wave":int}] top-10, mayor a menor
var hs_mp: Dictionary = {}   # multi: {"2":[...], "3":[...], "4":[...]} top-10 de equipos por categorÃ­a
var hs_cat := "single"       # categorÃ­a activa en el menÃº de puntuaciones
var hs_clear_arm := false    # paso 2 de confirmaciÃ³n del botÃ³n BORRAR RANKING (usa menu_ui.gd vÃ­a app.hs_clear_arm)
var entering_initials: bool = false
var initials: String = ""
var initials_label: Label = null
# (el teclado virtual ya no tiene estado acÃ¡: ver VirtualKeyboard en scripts/vkb.gd)
var hs_return_phase: GamePhase = GamePhase.MENU
var options_music_btn: Button = null
var current_menu := "menu"        # pantalla de menÃº activa (ESC = volver atrÃ¡s)
var _mp_err_back: Callable = Callable()  # se enlaza en _build_menu() (ver _menu.show_menu)

# â”€â”€â”€ GRÃFICOS (resoluciÃ³n + presets de calidad) â”€â”€â”€
# (settings.json: ver scripts/save_data.gd â€” SaveData.SETTINGS_FILE)
var aspect_idx: int = 0            # 0 = 16:9, 1 = 16:10
var fullscreen: bool = false       # modo de pantalla: ventana / pantalla completa
var game_resolution := Vector2i(1920, 1080)
var quality_level: int = 2  # 0=Baja 1=Media 2=Alta
var sky3d_node: WorldEnvironment = null
var sun_light: DirectionalLight3D = null
var env_ref: Environment = null
var particle_scale: float = 1.0  # escala de partÃ­culas segÃºn calidad
var upscaler := 0         # Upscale 3D: 0=FSR 1=DLSS 2=OFF (DLSS solo en engine con Streamline)
var upscaler_last := 0    # Ãºltimo upscale no-OFF (FSR o DLSS), para reactivar al pulsar un modo
var fsr_mode := 1         # 0=RENDIMIENTO 1=CALIDAD 2=ULTRA (aplica a FSR y DLSS)
var fg_enabled := false   # DLSS Frame Generation: solo engine con Streamline (fork rtx-godot) + RTX 40+
var gf_fsr_mode_btns: Array = []
var gf_fg_on_btn: Button = null
var gf_fg_off_btn: Button = null
var hud_scale := Vector2(1.0, 1.0)  # escala del HUD (diseÃ±ado a 1920x1080)
var mouse_sens: float = 1.0   # sensibilidad del mouse (1.0 = default)
var stick_sens: float = 1.0   # sensibilidad del stick (1.0 = default)
var local_input_mode: int = 0  # 0=mouse/teclado Â· 1=joystick (jugador local: solo, P1 split, LAN)
var joy0_btn_prev: Dictionary = {}  # edge detection de botones del joystick del slot 0
var io_next := "single"       # destino del menÃº de elecciÃ³n de dispositivo (single/split/lan)
# â”€â”€ NavegaciÃ³n de menÃºs con joystick (D-pad â†‘â†“ / stick izq Â· A confirma Â· B/START vuelve) â”€â”€
var menu_nav_buttons: Array = []
var menu_nav_index := 0
var menu_nav_focused: Button = null
var menu_nav_repeat_t := 0.0  # repeticion al mantener el stick

# â”€â”€â”€ CONTROLES (remapeables: teclado/ratÃ³n + joystick) â”€â”€â”€
# Teclado/ratÃ³n: valor = Key de Godot; negativo = botÃ³n de ratÃ³n (-(MouseButtons))
# Gamepad: valor = JoypadButton. Defaults: ver GameConfig.KEY_BINDS_DEFAULT / JOY_BINDS_DEFAULT
var key_binds: Dictionary = {}
var joy_binds: Dictionary = {}
var joy_trigger_axis: int = 5      # eje de trigger de disparo (5 = RT)
var _remap_capture: String = ""    # ""=inactivo | "k:<action>" | "j:<action>" | "jaxis"
var ct_rows: Array = []            # filas del menÃº Controles: [id, btn]
var ct_hint_lbl: Label = null

# â”€â”€â”€ LIFECYCLE â”€â”€â”€
func _ready() -> void:
	_hud = HudUI.new()
	_hud.app = self  # HudUI dibuja en el HUD; el estado sigue acÃ¡ (app -> self)
	randomize()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	_fx = FxPool.new()
	_fx.name = "FxPool"
	add_child(_fx)  # pool de VFX: ver scripts/fx_pool.gd
	_load_settings()
	_build_environment()
	_build_camera()
	_hud.build_hud()
	_build_vkb()  # necesita el HUD ya creado
	_build_audio()
	_apply_quality(quality_level)
	_apply_resolution(game_resolution)
	_apply_fsr()
	# Icono del juego en barra de tareas / titlebar: al correr con el binario del
	# engine (bat JUGAR o editor) el icono del proceso es el del engine; forzar el
	# propio. En el exe exportado refuerza el recurso incrustado por set_icon.ps1.
	# load() (no Image.load_from_file) porque en el export el png vive importado en el pck.
	var win_tex: CompressedTexture2D = load("res://icon.png")
	if win_tex != null:
		var win_img: Image = win_tex.get_image()
		if win_img != null:
			if win_img.get_format() != Image.FORMAT_RGBA8:
				win_img.convert(Image.FORMAT_RGBA8)
			DisplayServer.window_set_icon(win_img)
	if not Engine.is_editor_hint():
		# El engine DLSS (rtx-godot) corre como build editor-target (DEBUG_ENABLED) y agrega
		# "(DEBUG)" al titulo DESPUES del _ready (main.cpp ~4696). Forzar el titulo limpio
		# en el primer frame procesado, cuando el engine ya aplico el suyo.
		get_tree().process_frame.connect(_fix_window_title, CONNECT_ONE_SHOT)
	_load_highscores()
	_build_menu()  # necesita HUD, highscores y ajustes ya cargados
	_menu.show_menu()

func _fix_window_title() -> void:
	DisplayServer.window_set_title("Costa Blindada")

var water_node: MeshInstance3D
var _wmath := WorldMath.new()  # matemÃ¡tica de mundo + heightmap: ver scripts/world_math.gd
var rock_spots: Array = []  # [Vector2 pos_xz, float radio] â€” bloques para esquivar
var shake_amount: float = 0.0

# --- IA de evitacion en paralelo (WorkerThreadPool): ver scripts/enemy_ai.gd ---
# main.gd solo entrega posiciones planas y recibe vectores ya calculados; ningun
# hilo de trabajo toca nodos de la escena.
var _ai := EnemyAI.new()
var _ai_sold: PackedFloat32Array = PackedFloat32Array()    # (x, z) por soldado vivo
var _ai_tanks: PackedFloat32Array = PackedFloat32Array()   # (x, z) por tanque vivo
var _ai_rocks: PackedFloat32Array = PackedFloat32Array()   # (x, z, radio) cacheado de rock_spots
var _ai_bullets: PackedFloat32Array = PackedFloat32Array() # (x, z, dx, dz) balas del jugador

# --- Pool de VFX de explosion (particulas, destellos, luces): ver scripts/fx_pool.gd ---
# Antes cada impacto creaba y liberaba sus propios nodos y materiales en el hilo
# principal. El pool los reutiliza; las formulas de movimiento no cambian.
var _fx: FxPool = null

# --- Medidor de costo por subsistema -------------------------------------------
# Se uso para encontrar el cuello real del frame (era _update_projectiles) y ya no
# hace falta: los numeros que dio estan documentados en refactor_notes/. Si alguna
# vez hace falta volver a medir, la tecnica es la misma: dos Time.get_ticks_usec()
# por bloque de _process y mostrar el promedio cada 0.5 s.

# â”€â”€â”€ MULTIJUGADOR (LAN) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Host autoritativo: simula todo y broadcastea estado ~20 Hz.
# Clientes: envÃ­an input (apuntado/gatillo/arma) y renderizan el estado.
# El mundo se genera con una semilla compartida â†’ idÃ©ntico en todas las PCs.
var net: Node = null
var mp_role := 0                     # 0=offline, 1=host, 2=client
var mp_players := 1                  # jugadores en la partida (1-4)
var mp_seed := 0
var my_slot := 0                     # estaciÃ³n local 0..mp_players-1
# â”€â”€ SPLIT SCREEN 2P (local, mismas reglas que LAN) â”€â”€
var split_mode := false
var vp_a: SubViewport = null         # J1 (izquierda)
var vp_b: SubViewport = null         # J2 (derecha)
var cam_a: Camera3D = null
var cam_b: Camera3D = null
var tex_a: TextureRect = null
var tex_b: TextureRect = null
var yaw2 := 0.0                      # apuntado J2
var pitch2 := 0.0
var p2_weapon := 0
var p2_shoot_pressed := false
var p2_initials := ""
var p2_ini_cursor := 0
var _mirrors: Array = []             # [{orig, copies:[Node3D], ap_orig, ap_copies:[]}]
var base_hp_max := 150.0             # vida mÃ¡xima de la base (HUD %)
var slot_states: Array = []          # por slot: {weapon, ammo, last_shot, aim, shoot, score, kills}
var slot_by_pid: Dictionary = {}     # host: peer_id -> slot
var kill_credit_slot := -1           # host: slot de la bala en curso (crÃ©dito de kills)
var mp_roster: Array = []            # MP: iniciales por slot (host autoritativo, cliente copia)
var player_avatars: Array = []       # MP: tronera+torreta visible por estaciÃ³n [{base,turret}] (ver _build_player_avatars)
var mp_slot_stats: Array = []        # MP cliente: [[score, kills] por slot] (llega con game over)
var mp_go_phase := 0                 # MP game over: 0=ingreso iniciales, 1=esperando equipo, 2=guardado
var net_fx: Array = []               # host: FX acumulados para el prÃ³ximo estado
# (net_state_t/net_input_t y los loops de red viven en net.gd â€” Fase 3)
var net_enemy_nodes: Dictionary = {} # client: id -> {node, target:Vector3, state:int}
var net_proj_nodes: Array = []       # client: pool de balas [node, dir]
var net_eproj_nodes: Array = []      # client: pool de balas enemigas
var net_crate_nodes: Dictionary = {} # client: id -> {node, target:Vector3}
var _id_seq := 1                     # ids Ãºnicos de enemigos/cajas (host)

func _setup_net() -> void:
	net = load("res://scripts/net.gd").new()
	net.name = "Net"
	net.app = self  # back-reference: los @rpc del juego en Net delegan el estado en main.gd
	add_child(net)
	net.rooms_found.connect(_on_rooms_found)
	net.player_joined.connect(_on_mp_player_joined)
	net.player_left.connect(_on_mp_player_left)
	net.host_connected.connect(_on_host_connected)
	net.net_error.connect(_on_net_error)
	net.net_disconnected.connect(_on_net_disconnected)
	net.auth_denied.connect(_on_auth_denied)

# EstaciÃ³n de tiro del jugador a lo largo del frente (z=0, altura de ojo 5)
func _player_station(slot: int) -> Vector3:
	var n: int = maxi(1, mp_players)
	var xs: Array
	match n:
		1: xs = [0.0]
		2: xs = [-22.0, 22.0]
		3: xs = [-32.0, 0.0, 32.0]
		_: xs = [-42.0, -14.0, 14.0, 42.0]
	return Vector3(float(xs[mini(slot, xs.size() - 1)]), 5.0, 0.0)

# Ancla de cÃ¡mara local: TODOS los modos miran desde SU estaciÃ³n (_player_station), lado a
# lado: host LAN y J1 del split = estaciÃ³n 0 (izquierda), cliente LAN = la suya. El Ãºnico
# caso en el centro (0,5,0) es single player o un cliente que todavÃ­a no recibiÃ³ su slot
# (my_slot lo asigna el host en _net_start), para no teletransportarlo a media partida.
func _cam_anchor() -> Vector3:
	if mp_role == 1 or mp_role == 3:
		return _player_station(0)  # host LAN / J1 del split
	if mp_role == 2 and my_slot > 0 and my_slot < mp_players:
		return _player_station(my_slot)
	return Vector3(0, 5, 0)

func _new_slot_state() -> Dictionary:
	return {"weapon": 0, "ammo": [999999, 300, 20], "last_shot": 0.0, "aim": [0.0, 0.0], "shoot": false, "score": 0, "kills": 0}

# â”€â”€ INICIO DE PARTIDA â”€â”€
# HOST: reparte las estaciones. El host se queda el slot 0 y cada cliente recibe
# 1..mp_players-1 con un contador PROPIO, NO con el index del listado de get_peers():
# en Godot 4.7 ese listado no incluye al host (id 1), y usar el index hacÃ­a que el
# PRIMER cliente recibiera slot 0 â†’ host y cliente compartÃ­an estaciÃ³n y las balas del
# P2 salÃ­an por la estaciÃ³n del slot 0 (x-22, el lado izquierdo).
func _mp_assign_slots(pids: Array) -> void:
	slot_by_pid = {1: 0}
	var next_slot := 1
	for pid in pids:
		if pid != 1 and next_slot < mp_players:
			slot_by_pid[pid] = next_slot
			next_slot += 1

func _mp_host_start() -> void:
	if net == null or net.peer == null:
		return
	mp_role = 1  # FIX bug pre-refactor: el host NUNCA obtenÃ­a rol 1 (mp_role = 1 no se asignaba
	# en ningÃºn lado) â†’ corrÃ­a la rama "solo" de _process, el broadcast de estado (_net_host_loop)
	# era cÃ³digo muerto, _net_input descartaba el input de los clientes y el game over MP del host
	# no corrÃ­a. Con rol 1 activo: simulaciÃ³n + net._net_host_loop, crÃ©ditos de kill al slot 0
	# ("slot": 0 en _shoot), game over vÃ­a _mp_gameover_host e iniciales vÃ­a _mp_send_my_initials.
	mp_players = maxi(1, net.total_players)
	mp_seed = randi()
	# (multiplayer.multiplayer_peer ya lo asigna net.gd en create_room/join)
	# BUGFIX (estaciones compartidas): ver _mp_assign_slots.
	var pids: Array = multiplayer.get_peers()
	_mp_assign_slots(pids)
	slot_states = []
	for s in mp_players:
		slot_states.append(_new_slot_state())
	_start_net_local()
	for pid in pids:
		if pid != 1 and slot_by_pid.has(pid):
			net._net_start.rpc_id(pid, mp_seed, mp_players, int(slot_by_pid[pid]))

# _net_start (RPC): movido a net.gd (Fase 3). AllÃ¡ setea app.mp_seed/mp_players/my_slot/slot_states
# y vuelve a llamar _start_net_local() (mundo determinÃ­stico + _start_game_mp), todo acÃ¡ abajo.

# Vida de la base por cantidad de jugadores: 1P 100 Â· 2P 150 Â· 3P 200 Â· 4P 250.
# (Vive aparte de _start_net_local solo para poder comprobarla sin reconstruir el mundo.)
func _base_hp_for(n: int) -> float:
	return 100.0 + 50.0 * (maxi(1, n) - 1)

func _start_net_local() -> void:
	# Mundo determinÃ­stico: misma semilla â†’ misma playa, base, rocas, Ã¡rboles
	seed(mp_seed)
	# Liberar FUERA del Ã¡rbol: el Terrain3D (C++ GDExtension) al ser liberado en el Ã¡rbol
	# dispara "Resource file not found: res://" (carga de slot vacÃ­o)
	for ch in world.get_children():
		world.remove_child(ch)
		ch.queue_free()
	rock_spots.clear()
	_free_player_avatars()  # avatares de la partida MP anterior (si los habÃ­a)
	_build_environment()
	base_hp_max = _base_hp_for(mp_players)
	health = base_hp_max
	_start_game_mp()
	# Avatares visibles por estaciÃ³n (solo multijugador): para que los compaÃ±eros se
	# vean entre sÃ­. Sin esto cada jugador es una cÃ¡mara sin cuerpo y las balas del
	# otro aparecen del vacÃ­o.
	if mp_players >= 2:
		_build_player_avatars()

# â”€â”€â”€ AVATARES DE JUGADOR (tronera de bolsas + torreta por estaciÃ³n) â”€â”€â”€â”€â”€â”€
# La base (estÃ¡tica) y la torreta (rota con el apuntado) son NODOS SEPARADOS en
# la raÃ­z: el espejo del split solo sincroniza transforms de raÃ­z, una torreta
# hija de la base jamÃ¡s rotarÃ­a en las copias de los SubViewports.
const AVATAR_TINTS: Array = [
	Color(0.25, 0.85, 0.35),  # J1 verde
	Color(1.0, 0.55, 0.15),   # J2 naranja
	Color(0.30, 0.60, 1.0),   # J3 azul
	Color(0.85, 0.40, 0.95),  # J4 violeta
]

func _free_player_avatars() -> void:
	for av in player_avatars:
		for n in [av.get("base"), av.get("turret")]:
			if n != null and is_instance_valid(n):
				(n as Node).queue_free()
	player_avatars.clear()

func _build_player_avatars() -> void:
	_free_player_avatars()
	for s in mp_players:
		var pos := _player_station(s)
		var gy: float = _wmath.height(pos.x, 0.0)  # altura real de la playa en la estaciÃ³n
		# El eje del caÃ±o se pone a la ALTURA DE LA CÃMARA (estaciÃ³n y=5): como cada
		# jugador no ve su propio avatar, no hay riesgo de taparse la mira, y en la
		# pantalla del compaÃ±ero la bala sale del caÃ±o visible. El pivote queda 1.3
		# por debajo del caÃ±o (offset local de la torreta), nunca bajo la arena.
		var turret_y: float = maxf(gy + 1.0, pos.y - 1.3)
		# â”€â”€ Base estÃ¡tica: tronera en U abierta hacia adentro, bolsas hacia el mar (-Z) â”€â”€
		var base := Node3D.new()
		base.name = "PlayerAvatar_%d" % s
		base.position = Vector3(pos.x, gy, 0.0)
		add_child(base)
		var sand_a := StandardMaterial3D.new()
		sand_a.albedo_color = Color(0.55, 0.5, 0.36)
		sand_a.roughness = 1.0
		var sand_b := StandardMaterial3D.new()
		sand_b.albedo_color = Color(0.48, 0.43, 0.30)
		sand_b.roughness = 1.0
		var wood_mat := StandardMaterial3D.new()
		wood_mat.albedo_color = Color(0.55, 0.42, 0.28)
		wood_mat.roughness = 0.85
		var _box = func(parent: Node, sz: Vector3, cpos: Vector3, mat: Material, rot_y: float = 0.0) -> void:
			var mi := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = sz
			mi.mesh = m
			mi.material_override = mat
			mi.position = cpos
			mi.rotation.y = rot_y
			parent.add_child(mi)
		# Bolsas: arco x3 capas de 13 bolsas cubriendo el frente (Â±112Â° alrededor de -Z),
		# a escala de la torreta x4. Sin jitter aleatorio: host y cliente construyen
		# exactamente lo mismo sin depender del orden de la secuencia RNG.
		var steps := 13
		for layer in 3:
			var yy: float = 0.30 + float(layer) * 0.62
			var arc_off: float = 0.5 if layer % 2 == 1 else 0.0
			for i in steps:
				var a: float = lerpf(-1.95, 1.95, (float(i) + arc_off) / float(steps - 1))
				var bx: float = sin(a) * 3.2
				var bz: float = -cos(a) * 3.2
				# Cada bolsa se asienta en la altura REAL del terreno en su punto: la
				# playa tiene pendiente y en las estaciones de 3P/4P (x=Â±32/Â±42) el
				# nivel cambia varios metros respecto del centro.
				var by: float = yy + (_wmath.height(pos.x + bx, bz) - gy)
				_box.call(base, Vector3(1.6, 0.6, 0.95), Vector3(bx, by, bz), sand_a if (i + layer) % 2 == 0 else sand_b, a)
		# CajÃ³n central: pedestal de la torreta (x4 para sostener el caÃ±Ã³n grande)
		var crate_h: float = maxf(0.4, turret_y - gy - 0.8)
		_box.call(base, Vector3(4.8, crate_h, 4.8), Vector3(0, 0.05 + crate_h * 0.5, 0), wood_mat)
		# Etiqueta "J1/J2..." siempre de frente al espectador (billboard)
		var lbl := Label3D.new()
		lbl.text = "J%d" % (s + 1)
		lbl.font_size = 110
		lbl.pixel_size = 0.01
		lbl.outline_size = 8
		lbl.billboard = StandardMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, turret_y - gy + 3.2, 0.4)
		lbl.modulate = AVATAR_TINTS[s % AVATAR_TINTS.size()]
		base.add_child(lbl)
		# â”€â”€ Torreta: nodo independiente en la raÃ­z (el espejo del split sincroniza su rotaciÃ³n) â”€â”€
		var turret := Node3D.new()
		turret.name = "PlayerTurret_%d" % s
		turret.position = Vector3(pos.x, turret_y, 0.0)
		add_child(turret)
		# Cuerpo del caÃ±Ã³n: chapa militar (texturas de metal del techo de la base)
		var green_mat := StandardMaterial3D.new()
		green_mat.albedo_color = Color(0.42, 0.48, 0.36)
		green_mat.metallic = 0.55
		green_mat.roughness = 0.55
		green_mat.albedo_texture = load("res://assets/textures/metal_hull_basecolor.jpg")
		green_mat.normal_texture = load("res://assets/textures/metal_hull_normal.jpg")
		green_mat.roughness_texture = load("res://assets/textures/metal_hull_roughness.jpg")
		green_mat.uv1_scale = Vector3(1.5, 1.5, 1.5)
		# CaÃ±o: paneles de metal (las mismas texturas del portÃ³n de la base)
		var steel_mat := StandardMaterial3D.new()
		steel_mat.albedo_color = Color(0.62, 0.65, 0.68)
		steel_mat.metallic = 0.9
		steel_mat.roughness = 0.35
		steel_mat.albedo_texture = load("res://assets/textures/metal_panel_basecolor.jpg")
		steel_mat.normal_texture = load("res://assets/textures/metal_panel_normal.jpg")
		steel_mat.roughness_texture = load("res://assets/textures/metal_panel_roughness.jpg")
		steel_mat.uv1_scale = Vector3(2, 2, 2)
		var tint_mat := StandardMaterial3D.new()
		tint_mat.albedo_color = AVATAR_TINTS[s % AVATAR_TINTS.size()]
		tint_mat.emission = AVATAR_TINTS[s % AVATAR_TINTS.size()]
		tint_mat.emission_energy_multiplier = 0.6
		_box.call(turret, Vector3(3.4, 2.0, 4.4), Vector3(0, 0.6, 0), green_mat)  # cuerpo del caÃ±Ã³n (x4 total)
		var barrel := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.28
		bm.bottom_radius = 0.40
		bm.height = 7.2
		bm.radial_segments = 12
		barrel.mesh = bm
		barrel.material_override = steel_mat
		barrel.position = Vector3(0, 1.28, -4.0)
		barrel.rotation.x = -PI / 2.0  # eje del cilindro +Y â†’ -Z (apunta al mar)
		turret.add_child(barrel)
		# Chapa de color en la espalda: identifica cada estaciÃ³n de un vistazo
		_box.call(turret, Vector3(2.2, 1.5, 0.2), Vector3(0, 2.2, 2.3), tint_mat)
		# Estado inicial sin espejo (LAN/single): nadie ve su propia tronera. En split
		# el original no se renderiza y la visibilidad se maneja por copia cada frame.
		if not split_mode:
			base.visible = s != my_slot
			turret.visible = s != my_slot
		player_avatars.append({"base": base, "turret": turret})

# Cada torreta apunta con su slot: el propio con la cÃ¡mara local; los remotos con
# el aim que ya existe en slot_states (split J2 Â· host vÃ­a _net_input Â· cliente
# vÃ­a _apply_net_state).
# AdemÃ¡s cada jugador NO ve su propio avatar: la tronera/torreta existe para que
# lo vea el compaÃ±ero (uno ya tiene su viewmodel en la cÃ¡mara).
func _update_player_avatars() -> void:
	for s in player_avatars.size():
		var av: Dictionary = player_avatars[s]
		var t: Variant = av.get("turret")
		if t == null or not is_instance_valid(t):
			continue
		var yaw_a: float = 0.0
		var pitch_a: float = 0.0
		if s == my_slot:
			yaw_a = yaw
			pitch_a = pitch
		elif s < slot_states.size():
			yaw_a = float(slot_states[s].aim[0])
			pitch_a = float(slot_states[s].aim[1])
		else:
			continue
		(t as Node3D).rotation = Vector3(pitch_a, yaw_a, 0)
		# LAN/single: una sola cÃ¡mara por mÃ¡quina â†’ ocultar el nodo propio directamente.
		# En split no aplica: hay dos cÃ¡maras en la misma mÃ¡quina (se maneja abajo).
		if not split_mode:
			var vis: bool = s != my_slot
			for n in [av.get("base"), t]:
				if n != null and is_instance_valid(n):
					(n as Node3D).visible = vis
	if split_mode:
		_split_hide_own_avatar()

# Split: el original vive en el Ã¡rbol principal (inactivo); lo que se ve son las
# copes de los SubViewports. c1 = mitad IZQUIERDA (cÃ¡mara del J1) Â· c2 = derecha
# (cÃ¡mara del J2): cada mitad oculta el avatar de SU jugador. Se aplica DESPUÃ‰S
# de _update_split_mirrors (que iguala visible al original cada frame).
func _split_hide_own_avatar() -> void:
	for mi in _mirrors:
		var ov: Variant = mi["orig"]
		if ov == null or not is_instance_valid(ov):
			continue
		var nm: String = (ov as Node).name
		if not (nm.begins_with("PlayerAvatar_") or nm.begins_with("PlayerTurret_")):
			continue
		var s: int = int(nm.split("_")[1])
		var c1: Variant = mi["c1"]
		if c1 != null and is_instance_valid(c1):
			(c1 as Node3D).visible = s != 0
		var c2: Variant = mi["c2"]
		if c2 != null and is_instance_valid(c2):
			(c2 as Node3D).visible = s != 1

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
# SPLIT SCREEN 2P (local, mismas reglas que LAN: base compartida,
# slots propios, ranking de equipo, categorÃ­a 2P de puntuaciones).
# J1 = mouse/teclado (estado local) Â· J2 = gamepad (slot 1).
# Los nodos 3D dinÃ¡micos viven en el Ã¡rbol principal (lÃ³gica, ocultos);
# cada SubViewport tiene una copia visual sincronizada por frame.
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
var gun_a: Node3D = null  # split: viewmodel de arma del J1
var gun_b: Node3D = null  # split: viewmodel de arma del J2
var p2_btn_prev: Dictionary = {}  # split: edge detection de botones J2
var _fx_a: FxPool = null  # split: pool de VFX de la mitad IZQUIERDA (espejo de _fx)
var _fx_b: FxPool = null  # split: pool de VFX de la mitad DERECHA

# Sub-nodos que el juego rota por codigo (helices del helicoptero). El espejo de split
# iguala el nodo raiz del enemigo; si la helice no se copia tambien, el helicoptero vuela
# por las dos mitades con la helice quieta.
const SPLIT_SPIN_NODES: Array[String] = ["MainRotor", "TailRotor"]

# IntercepciÃ³n (polling por frame): un nodo 3D dinÃ¡mico nuevo en la raÃ­z â†’
# copia visible espejada en los 2 viewports
func _split_has_mirror(orig: Node) -> bool:
	for mi in _mirrors:
		if mi["orig"] == orig:
			return true
	return false

func _split_scan_new_nodes() -> void:
	for ch in get_children():
		# FxPool queda afuera: tiene su propio mecanismo de espejos (_fx_a / _fx_b).
		# Espejarlo aca dejaba una foto congelada de las particulas en cada mitad.
		if ch is Node3D and ch is not Camera3D and ch != world and not (ch is FxPool) and not _split_has_mirror(ch):
			_register_split_mirror(ch)

func _register_split_mirror(orig: Node3D) -> void:
	if vp_a == null or vp_b == null:
		return
	var c1: Node3D = _split_clone_into(orig, vp_a)
	var c2: Node3D = _split_clone_into(orig, vp_b)
	if c1 == null and c2 == null:
		return
	_mirrors.append({
		"orig": orig, "c1": c1, "c2": c2,
		"ap_o": orig.get_node_or_null("AnimationPlayer") as AnimationPlayer,
		"ap1": c1.get_node_or_null("AnimationPlayer") as AnimationPlayer if c1 != null else null,
		"ap2": c2.get_node_or_null("AnimationPlayer") as AnimationPlayer if c2 != null else null,
		"has_rifle": orig.get_node_or_null("Rifle") != null,
		"spins": _split_collect_spins(orig, c1, c2)
	})


# Pares (original, copia) de los sub-nodos animados por codigo (helices). Se resuelven
# al registrar el espejo: buscarlos por nombre cada frame sale caro y no hace falta.
func _split_collect_spins(orig: Node3D, c1: Node3D, c2: Node3D) -> Array:
	var out: Array = []
	for nm in SPLIT_SPIN_NODES:
		var so: Node3D = orig.get_node_or_null(nm) as Node3D
		if so == null:
			continue
		var s1: Node3D = null
		var s2: Node3D = null
		if c1 != null:
			s1 = c1.get_node_or_null(nm) as Node3D
		if c2 != null:
			s2 = c2.get_node_or_null(nm) as Node3D
		if s1 == null and s2 == null:
			continue
		out.append({"o": so, "c1": s1, "c2": s2})
	return out

func _split_clone_into(orig: Node3D, vp: SubViewport) -> Node3D:
	if vp == null:
		return null
	var copy: Node3D = orig.duplicate(true) as Node3D
	if copy == null:
		return null
	# Silenciar audio en la copia (el original ya suena en el Ã¡rbol principal)
	for a in copy.find_children("", "AudioStreamPlayer"):
		(a as AudioStreamPlayer).volume_db = -80.0
	for a3 in copy.find_children("", "AudioStreamPlayer3D"):
		(a3 as AudioStreamPlayer3D).volume_db = -80.0
	vp.add_child(copy)
	return copy

func _sync_split_copy(mi: Dictionary, orig: Node3D, ckey: String, akey: String) -> void:
	var c_v: Variant = mi[ckey]
	if c_v == null or not is_instance_valid(c_v):
		return
	var c := c_v as Node3D
	c.position = orig.position
	c.rotation = orig.rotation
	c.scale = orig.scale
	c.visible = orig.visible
	# Rifle del soldado (pose de disparo/apuntamiento)
	if bool(mi.get("has_rifle", false)):
		var g_o: Node = orig.get_node_or_null("Rifle")
		var g_c: Node = c.get_node_or_null("Rifle")
		if g_o != null and g_c != null:
			(g_c as Node3D).position = (g_o as Node3D).position
			(g_c as Node3D).rotation = (g_o as Node3D).rotation
	# Gear militar (casco/chaleco) â€” no-op si el modelo no lo lleva
	_sync_gear(c)
	# AnimaciÃ³n (soldados: walk/run/idle/shoot/fall)
	var ap_o: AnimationPlayer = mi["ap_o"]
	if ap_o != null and ap_o.current_animation != "":
		var ap_c: AnimationPlayer = mi[akey]
		if ap_o.is_playing():
			if ap_c != null:
				if ap_c.current_animation != ap_o.current_animation:
					ap_c.play(ap_o.current_animation, ap_o.speed_scale)
				ap_c.seek(ap_o.current_animation_position)
				ap_c.speed_scale = ap_o.speed_scale
		elif ap_c != null and ap_c.is_playing():
			ap_c.stop()

func _update_split_mirrors() -> void:
	if _mirrors.is_empty():
		return
	var to_prune: Array = []
	for mi in _mirrors:
		var orig_v: Variant = mi["orig"]
		if orig_v == null or not is_instance_valid(orig_v) or (orig_v as Node).get_parent() == null:
			to_prune.append(mi)
			continue
		var orig := orig_v as Node3D
		_sync_split_copy(mi, orig, "c1", "ap1")
		_sync_split_copy(mi, orig, "c2", "ap2")
		# Sub-nodos animados por codigo (helices): el raiz del espejo ya se igualo arriba,
		# falta la rotacion local de cada helice. Son 2 nodos por helicoptero, no por frame
		# de cada enemigo.
		for sp in mi.get("spins", []):
			var so: Node3D = sp["o"]
			if so == null or not is_instance_valid(so):
				continue
			for ck in ["c1", "c2"]:
				var cv: Variant = sp[ck]
				if cv == null or not is_instance_valid(cv):
					continue
				var cn := cv as Node3D
				cn.position = so.position
				cn.rotation = so.rotation
				cn.scale = so.scale
	for mi in to_prune:
		var c1v: Variant = mi["c1"]
		if c1v != null and is_instance_valid(c1v):
			(c1v as Node).queue_free()
		var c2v: Variant = mi["c2"]
		if c2v != null and is_instance_valid(c2v):
			(c2v as Node).queue_free()
		_mirrors.erase(mi)

func _split_viewport_size() -> Vector2i:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 2:
		return Vector2i(960, 1080)
	return Vector2i(int(vp.x * 0.5), int(vp.y))

# Mundo para un viewport: copia de `world` sin el Sky3D (script),
# reemplazado por WorldEnvironment + sol planos y confiables.
func _split_build_vp_world(vp: SubViewport) -> void:
	var wc: Node3D = world.duplicate(true) as Node3D
	if wc == null:
		return
	# Terrain3D (C++ GDExtension): la copia duplicada llega sin el atlas de texturas nativo.
	# Se descarta FUERA del Ã¡rbol (entrar/liberar la copia rota genera errores de carga vacÃ­os).
	var terr_dup := wc.get_node_or_null("Terrain3D")
	if terr_dup:
		wc.remove_child(terr_dup)
		terr_dup.free()
	vp.add_child(wc)
	# Ahora sÃ­, con wc en el Ã¡rbol: Terrain3D.material se crea en _ready del nodo fresco.
	_make_terrain3d(wc)
	# Sky3D â†’ WorldEnvironment plano, para no depender del nodo con script en la copia.
	# IMPORTANTE: duplicate(true) puede perder el script en la copia, por lo que NO
	# confiamos en ch.script: identificamos a Sky3D por su hijo SunLight o por su
	# environment (env_ref). Si se queda, trae su SunLight duplicado = DOBLE SOL =
	# exceso de brillo en split.
	var to_rm: Array = []
	for ch in wc.get_children():
		if ch is WorldEnvironment:
			var we_nd: WorldEnvironment = ch
			if we_nd.get_node_or_null("SunLight") != null or we_nd.environment == env_ref:
				to_rm.append(ch)
	for ch in to_rm:
		wc.remove_child(ch)
		(ch as Node).free()
	var we := WorldEnvironment.new()
	if env_ref != null:
		we.environment = env_ref.duplicate(true)
		# CalibraciÃ³n de brillo: en split el render va a una textura (espacio lineal) y
		# se muestra vÃ­a TextureRect, lo que sube el brillo respecto a single-player.
		# Bajamos la exposiciÃ³n para que la imagen coincida con el modo de 1 jugador.
		we.environment.tonemap_exposure = SPLIT_ENV_EXPOSURE
	vp.add_child(we)
	if sun_light != null:
		var sl: Light3D = sun_light.duplicate(true) as Light3D
		if sl != null:
			sl.transform = sun_light.global_transform
			vp.add_child(sl)

# El Terrain3D nativo hace LOD de fÃ­sica por cÃ¡mara; sin cÃ¡mara emite
# "Cannot find the active camera". Le asignamos la cÃ¡mara de su SubViewport.
func _split_assign_camera(vp: SubViewport, cam: Camera3D) -> void:
	for ch in vp.get_children():
		var t := ch.get_node_or_null("Terrain3D")
		if t != null and "set_camera" in t:
			t.set_camera(cam)

# El clone va DIRECTO al SubViewport (no como hijo de la cÃ¡mara): los hijos de cÃ¡mara
# dentro de un SubViewport no se renderizaban; los hijos directos del viewport sÃ­
# (igual que el mundo duplicado). Se sincroniza el transform por frame con su cÃ¡mara.
func _split_clone_gun(target_vp: SubViewport) -> Node3D:
	var gun_src: Node3D = camera.get_node_or_null("Gun") as Node3D
	if gun_src == null:
		return null
	var g: Node3D = gun_src.duplicate(true) as Node3D
	if g == null:
		return null
	# duplicate(true) corrompe el transform de nodos con escala negativa + rotaciÃ³n
	# (arma 2 espejada SMG_Left: pasa a (-x,-y,-z) y deja de renderizar en el SubViewport).
	# Resincronizo el basis EXACTO (position+rotation+scale) desde el original.
	_split_sync_gun_xform(g, gun_src)
	target_vp.add_child(g)
	return g

# Copia el basis local de cada holder de arma del original al clone (repara duplicate()).
func _split_sync_gun_xform(clone: Node3D, orig: Node3D) -> void:
	for nm in ["W_Pistol", "W_SMG", "W_Cannon", "MuzzleFlash"]:
		var o: Node = orig.get_node_or_null(nm)
		var c: Node = clone.get_node_or_null(nm)
		if o != null and c != null:
			(c as Node3D).transform = (o as Node3D).transform
	var os: Node = orig.get_node_or_null("W_SMG")
	var cs: Node = clone.get_node_or_null("W_SMG")
	if os != null and cs != null:
		for nm2 in ["SMG_Right", "SMG_Left"]:
			var o2: Node = os.get_node_or_null(nm2)
			var c2: Node = cs.get_node_or_null(nm2)
			if o2 != null and c2 != null:
				(c2 as Node3D).transform = (o2 as Node3D).transform

func _build_split_viewports() -> void:
	var vp_size := _split_viewport_size()
	# â”€â”€ Viewport J1 (mitad izquierda) â”€â”€
	vp_a = SubViewport.new()
	vp_a.name = "SplitVPA"
	vp_a.size = vp_size
	vp_a.msaa_3d = get_viewport().msaa_3d
	# Heredar el upscale FSR configurado en Opcionesâ†’GrÃ¡ficos (los SubViewport no lo heredan solos)
	vp_a.scaling_3d_mode = _scal_mode
	vp_a.scaling_3d_scale = _scal_scale
	vp_a.fsr_sharpness = _scal_sharp
	# own_world_3d: SI. Sin esto el SubViewport comparte el mundo de la escena y
	# renderiza el arma ORIGINAL (hijo de la camara principal) dentro de cada
	# mitad = caÃ±ones fantasma duplicados junto al clone.
	vp_a.own_world_3d = true
	add_child(vp_a)
	_split_build_vp_world(vp_a)
	cam_a = Camera3D.new()
	cam_a.name = "CamA"
	cam_a.fov = 65
	cam_a.current = true
	vp_a.add_child(cam_a)
	_split_assign_camera(vp_a, cam_a)
	gun_a = _split_clone_gun(vp_a)
	# â”€â”€ Viewport J2 (mitad derecha) â”€â”€
	vp_b = SubViewport.new()
	vp_b.name = "SplitVPB"
	vp_b.size = vp_size
	vp_b.msaa_3d = get_viewport().msaa_3d
	vp_b.scaling_3d_mode = _scal_mode  # idem J1: heredar el upscale de las vistas de juego
	vp_b.scaling_3d_scale = _scal_scale
	vp_b.fsr_sharpness = _scal_sharp
	vp_b.own_world_3d = true  # idem J1: aisla el mundo y evita el arma original duplicada
	add_child(vp_b)
	_split_build_vp_world(vp_b)
	cam_b = Camera3D.new()
	cam_b.name = "CamB"
	cam_b.fov = 65
	cam_b.current = true
	vp_b.add_child(cam_b)
	_split_assign_camera(vp_b, cam_b)
	gun_b = _split_clone_gun(vp_b)
	# VFX: el arbol principal no se renderiza en split, así que cada mitad necesita su
	# propio pool. Sin esto, en 2P local no explota nada ni se ve el destello del cañón.
	_split_build_fx_pools()
	# El raiz pasa a ser solo compositor 2D de las dos mitades: apagar su upscale 3D.
	_root_scaling_for_split()
	# â”€â”€ Display: 2 TextureRect (mitad de pantalla) sobre el canvas principal â”€â”€
	var disp := CanvasLayer.new()
	disp.name = "SplitDisplay"
	disp.layer = 5  # por debajo del HUD (layer 10)
	add_child(disp)
	tex_a = _split_make_tex(vp_a, "A")
	tex_b = _split_make_tex(vp_b, "B")
	_update_split_viewport_sizes()

# Los dos pools espejo viven DENTRO de cada SubViewport: ahi es donde se renderiza.
# _fx queda como despachador (FxPool no crea nada propio cuando tiene espejos), así el
# split cuesta dos mitades y no tres.
func _split_build_fx_pools() -> void:
	if _fx == null or vp_a == null or vp_b == null:
		return
	_fx_a = FxPool.new()
	_fx_a.name = "FxPoolA"
	vp_a.add_child(_fx_a)
	_fx_b = FxPool.new()
	_fx_b.name = "FxPoolB"
	vp_b.add_child(_fx_b)
	_fx.clear_mirrors()
	_fx.add_mirror(_fx_a)
	_fx.add_mirror(_fx_b)
	# Las explosiones Binbun (instancias de escena) tambien necesitan su copia en cada
	# mitad: un free-list por pool, con el mismo indice que los espejos (0 = A, 1 = B).
	_vfx_free_m = [{}, {}]


func _split_make_tex(vp: SubViewport, tag: String) -> TextureRect:
	var tex := TextureRect.new()  # "tex" (no "tr": esa variable shadowea a Object.tr)
	tex.name = "SplitTex" + tag
	tex.texture = vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disp: Node = get_node_or_null("SplitDisplay")
	if disp != null:
		disp.add_child(tex)
	return tex

func _update_split_viewport_sizes() -> void:
	if vp_a == null or tex_a == null or tex_b == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 2 or vp.y <= 2:
		return
	var half := Vector2(vp.x * 0.5, vp.y)
	tex_a.position = Vector2.ZERO
	tex_a.size = half
	tex_b.position = Vector2(half.x, 0.0)
	tex_b.size = half
	var vs := Vector2i(int(half.x), int(half.y))
	vp_a.size = vs
	vp_b.size = vs

func _set_gun_visible(gun: Node3D, i: int) -> void:
	if gun == null:
		return
	var w0: Node = gun.get_node_or_null("W_Pistol")
	var w1: Node = gun.get_node_or_null("W_SMG")
	var w2: Node = gun.get_node_or_null("W_Cannon")
	if w0 != null:
		w0.visible = (i == 0)
	if w1 != null:
		w1.visible = (i == 1)
	if w2 != null:
		w2.visible = (i == 2)

func _start_split_game() -> void:
	# Ningun menu queda "abierto". Si current_menu siguiera valiendo "split_assign",
	# main._input manda todos los botones del mando a la pantalla de asignacion: la partida
	# se juega igual (el input de juego se consulta por polling), pero en el game over el
	# D-pad y A nunca llegan al teclado virtual de las iniciales.
	current_menu = ""
	var was_split: bool = split_mode  # true si es REINICIO (ya existÃ­an viewports)
	if ui_start:
		ui_start.play()
	if music_enabled and music_player:
		music_player.play()
	# Limpieza total de la partida anterior (game over, pausa, o partida LAN)
	_mp_abort_cleanup()
	# Reglas LAN 2P: base 150 HP, slots propios, ranking de equipo
	mp_role = 3
	mp_players = 2
	my_slot = 0
	mp_seed = randi()
	slot_states = []
	slot_states.append(_new_slot_state())
	slot_states.append(_new_slot_state())
	# Reset local J1
	current_weapon = 0
	yaw = 0.0
	pitch = 0.0
	last_shot_time = 0.0
	mouse_down = false
	game_generation += 1
	# Emitters de fuego de base de la partida anterior: el mundo se reconstruye
	base_fire_emitters.clear()
	base_smoke_emitters.clear()
	base_fire_group = null
	base_fire_stage = 0
	# Mundo determinÃ­stico + inicio de partida (misma ruta que LAN local)
	_start_net_local()
	# REINICIO: los viewports y el mundo viejos mueren en queue_free (fin de frame).
	# Si se construyen los nuevos en el mismo frame, conviven 6 mundos a la vez
	# (pico de memoria GPU) y los SubViewports nuevos pueden renderizarse vacÃ­os
	# (pantalla azul). Espero un frame para que los viejos se liberen primero.
	if was_split:
		await get_tree().process_frame
	# â”€â”€ Montar pantalla dividida â”€â”€
	_build_split_viewports()
	split_mode = true
	if camera != null:
		camera.current = false  # el render lo hacen los SubViewports
	if world != null:
		world.visible = false
		# El Terrain3D principal (oculto en split) sigue corriendo LOD de fÃ­sica y
		# busca cÃ¡mara activa; con la principal ya no current, emite "_grab_camera".
		# Le asignamos la cÃ¡mara explÃ­citamente (fix nativo documentado).
		var main_terr := world.get_node_or_null("Terrain3D")
		if main_terr != null and camera != null and "set_camera" in main_terr:
			main_terr.set_camera(camera)
	# â”€â”€ Neutralizar post-proceso del viewport PRINCIPAL en split â”€â”€
	# En split el viewport principal solo muestra las 2 texturas del split (que ya
	# estÃ¡n tone-mapeadas + con su propio glow). Pero el WorldEnvironment del Sky3D
	# sigue activo (es Node, no se apaga con world.visible=false) y aplica glow/
	# tonemap ENCIMA de esas imÃ¡genes â†’ doble bloom = "exceso de iluminaciÃ³n".
	# Apagamos el post-proceso principal para que las imÃ¡genes se vean como se
	# renderizaron en el SubViewport (igual que single-player).
	var main_env: Environment = env_ref
	if main_env:
		main_env.glow_enabled = false
		main_env.ssao_enabled = false
		main_env.sdfgi_enabled = false
		main_env.ssr_enabled = false
		main_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		main_env.tonemap_exposure = 1.0
	# Estado J2 (gamepad)
	yaw2 = 0.0
	pitch2 = 0.0
	p2_weapon = 0
	p2_shoot_pressed = false
	p2_initials = ""
	p2_ini_cursor = 0
	p2_btn_prev.clear()
	joy0_btn_prev.clear()
	_set_gun_visible(gun_a, 0)
	_set_gun_visible(gun_b, 0)
	_split_relayout_hud()
	phase = GamePhase.PLAYING
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_split_show_controls_hint()

func _split_feed_slots(delta: float) -> void:
	if slot_states.size() < 2:
		return
	if _abl1_open:
		return  # menÃº de habilidades de P2 abierto: combate de J2 congelado (P1 sigue activo)
	var st: Dictionary = slot_states[1]
	var dev: int = _p2_joy_dev()  # J2: si J1 eligiÃ³ joystick, J2 usa el OTRO pad (dev 1)
	# â”€â”€ Apuntado J2 (stick IZQUIERDO) â”€â”€
	var ax: float = Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	var ay: float = Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	if absf(ax) > 0.12:
		yaw2 -= ax * 1.7 * stick_sens * delta
	if absf(ay) > 0.12:
		pitch2 -= ay * 1.2 * stick_sens * delta
	pitch2 = clampf(pitch2, -1.2, 0.6)
	st.aim = [yaw2, pitch2]
	# â”€â”€ Cambio de arma (remapeable en Opciones â†’ Controles) â”€â”€
	if _split_btn_edge("w1", Input.is_joy_button_pressed(dev, _jb("weapon1"))):
		_split_switch_weapon(0)
	if _split_btn_edge("w2", Input.is_joy_button_pressed(dev, _jb("weapon2"))):
		_split_switch_weapon(1)
	if _split_btn_edge("w3", Input.is_joy_button_pressed(dev, _jb("weapon3"))):
		_split_switch_weapon(2)
	if _split_btn_edge("wc", Input.is_joy_button_pressed(dev, _jb("weapon_cycle"))):
		var wc_cur: int = int(st.get("weapon", 0))
		_split_switch_weapon((wc_cur + 1) % 3)  # rota 1â†’2â†’3â†’1
	# â”€â”€ Habilidades (remapeables) â”€â”€
	if _split_btn_edge("ab1", Input.is_joy_button_pressed(dev, _jb("ability_rapid"))):
		_activate_ability(_ability_key("ability_rapid"))
	if _split_btn_edge("ab2", Input.is_joy_button_pressed(dev, _jb("ability_shield"))):
		_activate_ability(_ability_key("ability_shield"))
	if _split_btn_edge("ab3", Input.is_joy_button_pressed(dev, _jb("ability_mines"))):
		_activate_ability(_ability_key("ability_mines"))
	if _split_btn_edge("ab4", Input.is_joy_button_pressed(dev, _jb("ability_artillery"))):
		_activate_ability(_ability_key("ability_artillery"))
	if _split_btn_edge("ab5", Input.is_joy_button_pressed(dev, _jb("ability_overload"))):
		_activate_ability(_ability_key("ability_overload"))
	if _split_btn_edge("ab6", Input.is_joy_button_pressed(dev, _jb("ability_repair"))):
		_activate_ability(_ability_key("ability_repair"))
	# â”€â”€ MenÃº de habilidades â”€â”€
	if _split_btn_edge("abm", Input.is_joy_button_pressed(dev, _jb("abilities_menu"))):
		_toggle_abilities_menu(1)  # P2: el menÃº se ubica en su mitad (derecha)
	# â”€â”€ MÃºsica on/off â”€â”€
	if _split_btn_edge("mus", Input.is_joy_button_pressed(dev, _jb("music"))):
		_toggle_music()
	# â”€â”€ Disparo: solo trigger (RT por defecto). A/X/B son las armas 1/2/3 â”€â”€
	if Input.get_joy_axis(dev, joy_trigger_axis) > 0.5:
		st.shoot = true

func _split_btn_edge(k: String, pressed: bool) -> bool:
	var prev: bool = bool(p2_btn_prev.get(k, false))
	p2_btn_prev[k] = pressed
	return pressed and not prev

# â”€â”€â”€ ASIGNACIÃ“N DE MANDOS (split) â”€â”€â”€
# El 1er mando en presionar un botÃ³n = JUGADOR 1 (controla el menÃº); el 2Âº = JUGADOR 2.
var split_j1_dev := 0   # pad del J1 (split); default 0
var split_j2_dev := 1   # pad del J2 (split); default 1 (0 si J1 = teclado/mouse)

func _j1_joy_dev() -> int:
	# J1 en split usa su pad asignado; en single/LAN usa el pad primario (0)
	if mp_role == 3:
		return split_j1_dev if split_j1_dev >= 0 else 0
	return 0

# Dispositivo del J2 (split): el pad asignado (fallback a la lÃ³gica por opciÃ³n de J1).
func _p2_joy_dev() -> int:
	return split_j2_dev if split_j2_dev >= 0 else (1 if local_input_mode == 1 else 0)

func _joy0_edge(k: String, pressed: bool) -> bool:
	var prev: bool = bool(joy0_btn_prev.get(k, false))
	joy0_btn_prev[k] = pressed
	return pressed and not prev

# â”€â”€ SLOT 0 con JOYSTICK (solo / host LAN / P1 split / cliente LAN) â”€â”€
# Apunta con el stick DERECHO; armas y habilidades por botones remapeables
# (Opciones â†’ Controles â†’ Joystick). Reutiliza el estado global de slot 0
# (yaw/pitch, current_weapon, mouse_down, click_queued).
func _feed_joy_slot0(delta: float) -> void:
	var dev: int = _j1_joy_dev()
	# â”€â”€ Apuntado (stick IZQUIERDO) â”€â”€
	var ax: float = Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	var ay: float = Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	if absf(ax) > 0.12:
		yaw -= ax * 1.7 * stick_sens * delta
	if absf(ay) > 0.12:
		pitch -= ay * 1.2 * stick_sens * delta
	pitch = clampf(pitch, -1.2, 0.6)
	if camera != null:
		camera.rotation = Vector3(pitch, yaw, 0)
	# â”€â”€ Cambio de arma â”€â”€
	if _joy0_edge("w1", Input.is_joy_button_pressed(dev, _jb("weapon1"))):
		_switch_weapon(0)
	if _joy0_edge("w2", Input.is_joy_button_pressed(dev, _jb("weapon2"))):
		_switch_weapon(1)
	if _joy0_edge("w3", Input.is_joy_button_pressed(dev, _jb("weapon3"))):
		_switch_weapon(2)
	if _joy0_edge("wc", Input.is_joy_button_pressed(dev, _jb("weapon_cycle"))):
		_switch_weapon((current_weapon + 1) % 3)  # rota 1â†’2â†’3â†’1 como el scroll del mouse
	# â”€â”€ Habilidades â”€â”€
	if _joy0_edge("ab1", Input.is_joy_button_pressed(dev, _jb("ability_rapid"))):
		_activate_ability(_ability_key("ability_rapid"))
	if _joy0_edge("ab2", Input.is_joy_button_pressed(dev, _jb("ability_shield"))):
		_activate_ability(_ability_key("ability_shield"))
	if _joy0_edge("ab3", Input.is_joy_button_pressed(dev, _jb("ability_mines"))):
		_activate_ability(_ability_key("ability_mines"))
	if _joy0_edge("ab4", Input.is_joy_button_pressed(dev, _jb("ability_artillery"))):
		_activate_ability(_ability_key("ability_artillery"))
	if _joy0_edge("ab5", Input.is_joy_button_pressed(dev, _jb("ability_overload"))):
		_activate_ability(_ability_key("ability_overload"))
	if _joy0_edge("ab6", Input.is_joy_button_pressed(dev, _jb("ability_repair"))):
		_activate_ability(_ability_key("ability_repair"))
	# â”€â”€ MenÃº de habilidades â”€â”€
	if _joy0_edge("abm", Input.is_joy_button_pressed(dev, _jb("abilities_menu"))):
		_toggle_abilities_menu()
	# â”€â”€ MÃºsica on/off â”€â”€
	if _joy0_edge("mus", Input.is_joy_button_pressed(dev, _jb("music"))):
		_toggle_music()
	# â”€â”€ Disparo: solo trigger (eje remapeable, RT por defecto). A/X/B ahora son las armas 1/2/3 â”€â”€
	var trigg: float = Input.get_joy_axis(dev, joy_trigger_axis)
	mouse_down = trigg > 0.5

# â”€â”€ JOYSTICK (no split): navegaciÃ³n de menÃºs + pausa del jugador local â”€â”€
func _joy_menu_nav(jb: InputEventJoypadButton) -> void:
	if not jb.pressed:
		return
	var confirm := jb.button_index == _jb("confirm")
	var back := jb.button_index == _jb("back")
	if phase == GamePhase.MENU:
		if jb.button_index == JOY_BUTTON_DPAD_UP:
			_menu_nav_step(-1)
		elif jb.button_index == JOY_BUTTON_DPAD_DOWN:
			_menu_nav_step(1)
		elif confirm or jb.button_index == _jb("pause"):
			if not _menu_nav_confirm():
				match current_menu:
					"menu":
						_menu.show_input_choice("single")
					"input_choice":
						_menu.on_io_kb()  # A = opciÃ³n por defecto
					_: pass
		elif back:
			_menu.menu_back()
	elif phase == GamePhase.PAUSE:
		if jb.button_index == JOY_BUTTON_DPAD_UP:
			_menu_nav_step(-1)
		elif jb.button_index == JOY_BUTTON_DPAD_DOWN:
			_menu_nav_step(1)
		elif confirm or jb.button_index == _jb("pause"):
			if not _menu_nav_confirm() and current_menu == "pause":
				_resume_game()
		elif back:
			_menu.menu_back()
	elif phase == GamePhase.PLAYING:
		if _abilities_menu_open:
			# MenÃº de habilidades abierto: D-pad/stick navegan, A activa, START/B/SEL cierran
			if jb.button_index == JOY_BUTTON_DPAD_UP:
				_menu_nav_step(-1)
			elif jb.button_index == JOY_BUTTON_DPAD_DOWN:
				_menu_nav_step(1)
			elif confirm:
				if not _menu_nav_confirm():
					_toggle_abilities_menu()
			elif jb.button_index == _jb("pause") or back or jb.button_index == _jb("abilities_menu"):
				_toggle_abilities_menu()
		elif jb.button_index == _jb("pause"):
			_pause_game()
	elif phase == GamePhase.GAMEOVER:
		if _vkb.open and entering_initials:
			# Teclado virtual (joystick) â€” single player y LAN host/client:
			# D-pad mueve Â· A elige Â· B borra Â· START guarda Â· Y salta
			if jb.button_index == JOY_BUTTON_DPAD_UP:
				_vkb.move(-1, 0)
			elif jb.button_index == JOY_BUTTON_DPAD_DOWN:
				_vkb.move(1, 0)
			elif jb.button_index == JOY_BUTTON_DPAD_LEFT:
				_vkb.move(0, -1)
			elif jb.button_index == JOY_BUTTON_DPAD_RIGHT:
				_vkb.move(0, 1)
			elif jb.button_index == _jb("confirm"):
				_vkb.select()
			elif jb.button_index == _jb("back"):
				_vkb.backspace()
			elif jb.button_index == _jb("pause"):
				_vkb.submit()
			elif jb.button_index == _jb("weapon_cycle"):
				_vkb.skip()
		elif mp_role != 0:
			# Multi (LAN) ya sin teclado virtual: volver al menÃº con A o B
			if confirm or back:
				_menu.on_btn_back_to_menu()
		elif confirm or jb.button_index == _jb("pause"):
			_menu.show_menu()          # A / START â†’ menÃº (single player)
		elif back:
			_restart_game()       # B â†’ reiniciar (single player)

func _split_switch_weapon(i: int) -> void:
	p2_weapon = i
	if slot_states.size() > 1:
		slot_states[1].weapon = i
	_set_gun_visible(gun_b, i)
	_hud.update_hud()

func _split_input_joypad(jb: InputEventJoypadButton) -> void:
	if not jb.pressed:
		return
	if phase == GamePhase.MENU:
		if jb.button_index == JOY_BUTTON_DPAD_UP:
			_menu_nav_step(-1)
		elif jb.button_index == JOY_BUTTON_DPAD_DOWN:
			_menu_nav_step(1)
		elif jb.button_index == _jb("confirm") or jb.button_index == _jb("pause"):
			if not _menu_nav_confirm():
				if current_menu == "menu":
					_menu.show_input_choice("split")
				elif current_menu == "input_choice":
					_menu.on_io_kb()  # A = opciÃ³n por defecto
		elif jb.button_index == _jb("back"):
			_menu.menu_back()
	elif phase == GamePhase.PLAYING:
		# Ruteo por dispositivo: el pad de P2 (J2) controla SU menÃº; el resto, el de P1
		# Godot 4.7: la propiedad 'device_id' (base InputEvent) se renombrÃ³ a 'device'
		var p2_dev: int = _p2_joy_dev()
		var is_p2: bool = (int(jb.device) == p2_dev)
		if is_p2:
			if _abl1_open:
				# MenÃº de habilidades P2: D-pad navega, A activa, START/B/SEL cierran
				if jb.button_index == JOY_BUTTON_DPAD_UP:
					_abl1_nav_step(-1)
				elif jb.button_index == JOY_BUTTON_DPAD_DOWN:
					_abl1_nav_step(1)
				elif jb.button_index == _jb("confirm"):
					if not _abl1_nav_confirm():
						_toggle_abilities_menu(1)
				elif jb.button_index == _jb("pause") or jb.button_index == _jb("back") or jb.button_index == _jb("abilities_menu"):
					_toggle_abilities_menu(1)
			elif jb.button_index == _jb("pause"):
				_pause_game()
		else:
			if _abilities_menu_open:
				# MenÃº de habilidades P1: D-pad navega, A activa, START/B/SEL cierran
				if jb.button_index == JOY_BUTTON_DPAD_UP:
					_menu_nav_step(-1)
				elif jb.button_index == JOY_BUTTON_DPAD_DOWN:
					_menu_nav_step(1)
				elif jb.button_index == _jb("confirm"):
					if not _menu_nav_confirm():
						_toggle_abilities_menu(0)
				elif jb.button_index == _jb("pause") or jb.button_index == _jb("back") or jb.button_index == _jb("abilities_menu"):
					_toggle_abilities_menu(0)
			elif jb.button_index == _jb("pause"):
				_pause_game()
	elif phase == GamePhase.PAUSE:
		if jb.button_index == JOY_BUTTON_DPAD_UP:
			_menu_nav_step(-1)
		elif jb.button_index == JOY_BUTTON_DPAD_DOWN:
			_menu_nav_step(1)
		elif jb.button_index == _jb("confirm") or jb.button_index == _jb("pause"):
			if not _menu_nav_confirm() and current_menu == "pause":
				_resume_game()
		elif jb.button_index == _jb("back"):
			_menu.menu_back()
	elif phase == GamePhase.GAMEOVER:
		if mp_go_phase < 2:
			# Cada jugador navega SU VKB por su propio mando (D-pad mueve Â· A elige Â· B borra Â· START guarda Â· Y salta)
			var p2_dev: int = _p2_joy_dev()
			var is_p2: bool = (int(jb.device) == p2_dev)
			var pl: int = 1 if is_p2 else 0
			if pl == 0 and local_input_mode != 1:
				return  # P1 con teclado/mouse: su mando no controla el VKB (usa el teclado de PC)
			if not _svkb[pl].open:
				if jb.button_index == _jb("pause") or jb.button_index == _jb("confirm"):
					_svkb[pl].submit()  # ya enviÃ³: START/A â†’ confirma "???" (no-op si ya guardÃ³)
				return
			if jb.button_index == JOY_BUTTON_DPAD_UP:
				_svkb[pl].move(-1, 0)
			elif jb.button_index == JOY_BUTTON_DPAD_DOWN:
				_svkb[pl].move(1, 0)
			elif jb.button_index == JOY_BUTTON_DPAD_LEFT:
				_svkb[pl].move(0, -1)
			elif jb.button_index == JOY_BUTTON_DPAD_RIGHT:
				_svkb[pl].move(0, 1)
			elif jb.button_index == _jb("confirm"):
				_svkb[pl].select()
			elif jb.button_index == _jb("back"):
				_svkb[pl].backspace()
			elif jb.button_index == _jb("pause"):
				_svkb[pl].submit()
			elif jb.button_index == _jb("weapon_cycle"):
				_svkb[pl].skip()
		elif jb.button_index == _jb("pause") or jb.button_index == _jb("confirm"):
			_menu.on_btn_back_to_menu()

func _split_gameover() -> void:
	if ui_gameover:
		ui_gameover.play()
	phase = GamePhase.GAMEOVER
	mouse_down = false
	click_queued = false
	entering_initials = true
	initials = ""
	mp_go_phase = 0
	mp_roster = ["", ""]
	p2_initials = ""
	p2_ini_cursor = 0
	_mp_show_gameover_screen()
	# Red de seguridad: si alguien no envÃ­a iniciales, se guarda de todos modos
	get_tree().create_timer(60.0).timeout.connect(_mp_host_finish_save)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _split_p2_submit() -> void:
	# En split ambos jugadores son locales: P1 puede haber enviado ya (fase 1);
	# solo se bloquea cuando el guardado ya termino (fase 2)
	if mp_go_phase >= 2:
		return
	var clean := p2_initials.strip_edges().to_upper()
	while clean.length() < 3:
		clean += "?"
	while mp_roster.size() < 2:
		mp_roster.append("")
	mp_roster[1] = clean
	_mp_host_check_roster()
	_mp_local_sent_p2()

func _mp_local_sent_p2() -> void:
	for nm in ["GOInitialsPromptP2", "GOInitialsBoxesP2", "GOHintP2"]:
		var nd: Node = hud.get_node_or_null(nm)
		if nd:
			nd.queue_free()
	_svkb[1].clear()  # libera el VKB de P2
	var hint: Label = hud.get_node_or_null("GOHint") as Label
	if hint:
		hint.text = _tr("mpgo_sent")

func _split_update_p2_ini_display() -> void:
	var lbl: Label = hud.get_node_or_null("GOInitialsBoxesP2") as Label
	if lbl == null:
		return
	var shown := ""
	for i in 3:
		if i < p2_initials.length():
			shown += p2_initials[i].to_upper()
		else:
			shown += "_"
		if i == p2_ini_cursor and i < p2_initials.length():
			shown += "Â·"
		shown += "  "
	lbl.text = shown.strip_edges()

func _split_relayout_hud() -> void:
	# SimetrÃ­a P1/P2: mostrar el cluster completo en ambas mitades
	for nm in ["WeaponIndicatorP1", "MusicLabelP1", "AbilityBarP2", "HPBarP2", "VidaLabelP2", "BaseIconP2", "ScoreLabelP1", "WaveLabelP1", "PtsLabelP1"]:
		var nd: Node = hud.get_node_or_null(nm)
		if nd != null:
			nd.visible = true
	_hud.hud_cluster_split()  # espejo hacia el centro, filas sin solaparse
	_hud.update_hud()

func _split_show_controls_hint() -> void:
	var j1 := _hud.make_label("SplitHintJ1", Vector2(60, 40), _tr("split_hint_j1_joy") if local_input_mode == 1 else _tr("split_hint_j1"), 22, Color(1, 1, 1, 0.92))
	j1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	j1.add_theme_constant_override("shadow_outline_size", 4)
	var j2 := _hud.make_label("SplitHintJ2", Vector2(980, 40), _tr("split_hint_j2"), 22, Color(1, 1, 1, 0.92))
	j2.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	j2.add_theme_constant_override("shadow_outline_size", 4)
	get_tree().create_timer(7.0).timeout.connect(_free_split_hints)

func _free_split_hints() -> void:
	for nm in ["SplitHintJ1", "SplitHintJ2"]:
		var nd: Node = hud.get_node_or_null(nm)
		if nd:
			nd.queue_free()

func _teardown_split() -> void:
	split_mode = false
	_mirrors.clear()
	p2_btn_prev.clear()
	# VFX del split: liberar los pools de cada mitad y cortar los espejos. Si quedaran
	# espejos apuntando a pools muertos, el siguiente disparo escribiria en el vacio.
	for fxp in [_fx_a, _fx_b]:
		if fxp != null and is_instance_valid(fxp):
			fxp.release_all()
			fxp.queue_free()
	_fx_a = null
	_fx_b = null
	if _fx != null:
		_fx.clear_mirrors()
	_vfx_free_m = []
	_vfx_copies.clear()
	for vp in [vp_a, vp_b]:
		if vp != null and is_instance_valid(vp):
			(vp as Node).queue_free()
	vp_a = null
	vp_b = null
	cam_a = null
	cam_b = null
	gun_a = null
	gun_b = null
	var disp: Node = get_node_or_null("SplitDisplay")
	if disp:
		disp.queue_free()
	tex_a = null
	tex_b = null
	if camera != null:
		camera.current = true
	if world != null:
		world.visible = true
	# El raiz vuelve a ser la vista de juego: recupera el upscale/Frame Generation que
	# el usuario configuro (en split estaban apagados a proposito: ver _apply_fsr).
	_apply_fsr()
	for nm in ["WeaponIndicatorP1", "MusicLabelP1", "AbilityBarP2", "HPBarP2", "VidaLabelP2", "BaseIconP2", "ScoreLabelP1", "WaveLabelP1", "PtsLabelP1"]:
		var nd: Node = hud.get_node_or_null(nm)
		if nd != null:
			nd.visible = false
	_hud.hud_cluster_solo()  # restaurar posiciones de single player
	_hud.update_hud()

func _start_game_mp() -> void:
	current_menu = ""  # ninguna pantalla de menu sigue abierta durante la partida
	if ui_start:
		ui_start.play()
	if music_enabled and music_player:
		music_player.play()
	click_queued = false
	dual_toggle = 0
	phase = GamePhase.PLAYING
	score = 0
	wave = 1
	ammo = [999999, 300, 20]
	# Arma inicial limpia (evita que quede visible un grupo del arma de la partida anterior)
	current_weapon = 0
	_switch_weapon_visual()
	combat_pts = 0
	abl_rapid_t = 0.0
	abl_shield_t = 0.0
	abl_overload_t = 0.0
	abl_mines.clear()
	enemies.clear()
	projectiles.clear()
	enemy_projectiles.clear()
	if _fx != null:
		_fx.release_all()  # particulas y luces de vuelta al pool (no se liberan)
	_vfx_release_all()
	crates.clear()
	crate_timer = 8.0
	for pm in get_tree().get_nodes_in_group("PlayerMines"):
		(pm as Node).queue_free()
	for dn in get_tree().get_nodes_in_group("DynNodes"):
		(dn as Node).queue_free()
	for child in get_children():
		if child.name.begins_with("Enemy_") or child.name.begins_with("Proj_") or child.name.begins_with("EProj_") or child.name.begins_with("Crate_") or child.name.begins_with("Mine_"):
			child.queue_free()
	_hud.clear_overlay_nodes()
	base_destroying = false
	base_explosion_timer = 999.0
	# Cada jugador LAN arranca en SU estaciÃ³n (slot asignado por el host): vista lado a
	# lado como en split, y los orÃ­genes de disparo (_player_station) coinciden con la mira.
	camera.position = _cam_anchor()
	_apply_base_fire_stage(0)
	_debug_apply_start()  # TEMPORAL: arranque en oleada alta (el host lo manda a los clientes)
	if mp_role != 2:
		_start_wave()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# â”€â”€ LOOPS DE RED + ESTADO: movidos a net.gd (Fase 3) â”€â”€
# _net_host_loop / _net_client_loop / _send_net_state / _net_input (RPC) / _net_state (RPC) viven
# ahora en el hijo Net (misma ruta de nodo en host y cliente) y delegan en los miembros de main.gd.
# main._process los llama como net._net_host_loop(delta) / net._net_client_loop(delta).
# La APLICACIÃ“N del estado en el cliente (_apply_net_state) y los pools de nodos quedan acÃ¡ abajo.

func _apply_net_state(data: Dictionary) -> void:
	wave = int(data.get("wave", wave))
	score = int(data.get("score", score))
	health = float(data.get("hp", health))
	# FX del snapshot: se leen ANTES de reconciliar enemigos (las muertes de este frame
	# definen cÃ³mo se retira cada nodo) y se reproducen al final.
	var fx_list: Array = data.get("fx", [])
	var dying: Dictionary = {}
	for fx in fx_list:
		if str(fx[0]) == "kill" and fx.size() >= 3:
			dying[int(fx[1])] = str(fx[2])
	# Enemigos: reconciliar por id
	var seen: Dictionary = {}
	for ed in data.get("en", []):
		var id: int = ed[0]
		seen[id] = true
		var t: String = ed[1]
		var target := Vector3(ed[2], ed[3], ed[4])
		var ry: float = ed[5]
		var state_code: int = ed[7]
		if not net_enemy_nodes.has(id):
			var nd: Node3D = _make_net_enemy(t)
			nd.position = target
			nd.rotation.y = ry
			nd.name = "Enemy_%d" % id
			add_child(nd)
			net_enemy_nodes[id] = {"node": nd, "target": target, "state": state_code}
		else:
			var en: Dictionary = net_enemy_nodes[id]
			en.target = target
			en.state = state_code
			var nd2: Node3D = en.node
			nd2.rotation.y = ry
			# animaciÃ³n (soldados)
			var ap: AnimationPlayer = nd2.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap != null:
				var anim := "default/idle" if state_code == 1 else "default/run"
				if ap.has_animation(anim) and ap.current_animation != anim:
					ap.play(anim)
	for id in net_enemy_nodes.keys():
		if not seen.has(id):
			var dead: Node3D = net_enemy_nodes[id]["node"]
			net_enemy_nodes.erase(id)
			if dying.has(id):
				_net_enemy_death(dead, str(dying[id]))
			else:
				dead.queue_free()
	# Balas: pool fijo
	_sync_proj_pool(net_proj_nodes, data.get("pr", []))
	_sync_proj_pool(net_eproj_nodes, data.get("ep", []))
	# Cajas
	var cseen: Dictionary = {}
	for cd in data.get("cr", []):
		var id: int = cd[0]
		cseen[id] = true
		var target := Vector3(cd[1], cd[2], cd[3])
		if not net_crate_nodes.has(id):
			var nd: Node3D = _create_crate_mesh(str(cd[4]))
			nd.position = target
			nd.name = "Crate_%d" % id
			add_child(nd)
			net_crate_nodes[id] = {"node": nd, "target": target}
		else:
			(net_crate_nodes[id] as Dictionary)["target"] = target
	for id in net_crate_nodes.keys():
		if not cseen.has(id):
			(net_crate_nodes[id]["node"] as Node).queue_free()
			net_crate_nodes.erase(id)
	# Jugadores (municiÃ³n local + apuntado de los demÃ¡s para las torretas visibles)
	var players: Array = data.get("pl", [])
	if my_slot < players.size():
		var me: Array = players[my_slot]
		ammo[1] = int(me[1])
		ammo[2] = int(me[2])
	for s in players.size():
		if s != my_slot and s < slot_states.size() and players[s].size() >= 5:
			slot_states[s].aim = [float(players[s][3]), float(players[s][4])]
	# FX
	for fx in fx_list:
		_spawn_net_fx(fx)

# Muerte de un enemigo en el CLIENTE: el host ya enviÃ³ el boom de los vehÃ­culos; del soldado
# falta la voz de dolor y la animaciÃ³n de caÃ­da (en el cliente el nodo se borraba de golpe).
func _net_enemy_death(nd: Node3D, etype: String) -> void:
	if not is_instance_valid(nd):
		return
	if etype == "soldier":
		if soldier_pain_players.size() > 0:
			var pp: AudioStreamPlayer = soldier_pain_players[randi() % soldier_pain_players.size()]
			if pp.stream != null:
				pp.volume_db = pain_base_db + _net_sfx_db(nd.position)
				pp.play()
		var ap: AnimationPlayer = nd.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null and ap.has_animation("default/fall"):
			ap.play("default/fall")
			var ft := Timer.new()
			ft.one_shot = true
			ft.wait_time = 1.3
			nd.add_child(ft)
			ft.timeout.connect(_free_node.bind(nd))
			ft.start()
			return
	nd.queue_free()

func _sync_proj_pool(pool: Array, list: Array) -> void:
	while pool.size() < list.size():
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.9, 0.4)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.9, 0.4)
		mat.emission_energy_multiplier = 2.5
		m.material_override = mat
		add_child(m)
		pool.append([m, Vector3(0, 0, -1)])
	for i in list.size():
		var d: Array = list[i]
		var nd: Node3D = pool[i][0]
		nd.visible = true
		nd.position = Vector3(d[0], d[1], d[2])
		pool[i][1] = Vector3(d[3], d[4], d[5]).normalized()
	for i in range(list.size(), pool.size()):
		(pool[i][0] as Node3D).visible = false

func _make_net_enemy(t: String) -> Node3D:
	match t:
		"soldier":
			var s := _create_soldier_mesh()
			s.scale = Vector3.ONE * 1.3
			return s
		"boat":
			var b := _create_boat_mesh(6)
			return b
		"tank":
			return _create_tank_mesh()
		"plane":
			return _create_plane_mesh()
	return _create_soldier_mesh()

# â”€â”€ FX/AUDIO REMOTOS (host â†’ clientes) â”€â”€
# El host es dueÃ±o de la simulaciÃ³n: el cliente NO corre _update_projectiles ni _kill_enemy,
# asÃ­ que todo lo que suena o explota debe viajar en la lista fx del snapshot.
# AtenuaciÃ³n: 0 dB en la cÃ¡mara local, -âˆž fuera de NET_SFX_RANGE.
func _net_sfx_db(pos: Vector3) -> float:
	if camera == null:
		return 0.0
	var d: float = camera.global_position.distance_to(pos)
	var att: float = clampf(1.0 - d / NET_SFX_RANGE, 0.0, 1.0)
	if att <= 0.03:
		return -999.0
	return linear_to_db(att)

# Reproduce un audio_players[idx] en la escucha local, atenuado por su posiciÃ³n en el mundo.
# Con 3-4 jugadores llegan varios balazos por snapshot y CADA arma tiene un solo
# AudioStreamPlayer: si ese reproductor estÃ¡ sonando con un disparo MÃS CERCANO, el lejano se
# descarta en vez de cortarlo (evita microcortes y que un compaÃ±ero tape tu propio tiro).
func _play_net_sfx(idx: int, pos: Vector3) -> void:
	if idx < 0 or idx >= audio_players.size() or idx >= sfx_base_db.size():
		return
	var ap: AudioStreamPlayer = audio_players[idx]
	if ap.stream == null:
		return
	var db := _net_sfx_db(pos)
	if db <= -900.0:
		return
	var d: float = 0.0
	if camera != null:
		d = camera.global_position.distance_to(pos)
	if idx < sfx_playing_dist.size() and ap.playing and float(sfx_playing_dist[idx]) >= 0.0 and d > float(sfx_playing_dist[idx]):
		return
	if idx < sfx_playing_dist.size():
		sfx_playing_dist[idx] = d
	ap.volume_db = float(sfx_base_db[idx]) + db
	ap.play()

# Audio LOCAL (mi arma / mi mÃ¡quina): siempre desde el volumen base, porque _play_net_sfx
# deja el mismo AudioStreamPlayer atenuado por el disparo de otro jugador.
func _play_local_sfx(idx: int) -> void:
	if idx < 0 or idx >= audio_players.size():
		return
	var ap: AudioStreamPlayer = audio_players[idx]
	if ap.stream == null:
		return
	if idx < sfx_base_db.size():
		ap.volume_db = float(sfx_base_db[idx])
	if idx < sfx_playing_dist.size():
		sfx_playing_dist[idx] = 0.0  # el sonido propio es siempre el mÃ¡s cercano
	ap.play()

# HOST: chispas de impacto chico (pistola/AM, blindaje de tanque, casco, cajas). El grande
# viaja como "boom" desde _big_boom.
# HIT_SPARK_SIZE: las chispas son esferas CHICAS. Con el radio completo de _explode
# (0.1-0.5 m) cada impacto se veia como un racimo de pelotas, y con el FPS bajo cada
# particula quedaba visible varios frames: el racimo se leia como globos flotando.
# Los booms grandes (_big_boom, _kill_enemy) conservan el tamano completo.
const HIT_SPARK_SIZE: float = 0.24

func _hit_spark(pos: Vector3, count: int, color: Color, snd_idx: int = -1) -> void:
	_explode(pos, count, color, HIT_SPARK_SIZE)
	if snd_idx >= 0:
		_play_local_sfx(snd_idx)
	if mp_role == 1:
		net_fx.append(["spark", pos.x, pos.y, pos.z, count, color.r, color.g, color.b, snd_idx])

func _spawn_net_fx(fx: Array) -> void:
	var kind: String = str(fx[0])
	match kind:
		"boom":
			# ExplosiÃ³n grande del host (muerte de vehÃ­culo, caÃ±Ã³n, artillerÃ­a, base):
			# mismo visual + boom atenuado + sacudida en la pantalla del cliente.
			if fx.size() >= 5:
				var bp := Vector3(float(fx[1]), float(fx[2]), float(fx[3]))
				_big_boom(bp, float(fx[4]), Color(1.0, 0.45, 0.12), true, _net_sfx_db(bp))
		"spark":
			if fx.size() >= 8:
				var sp := Vector3(float(fx[1]), float(fx[2]), float(fx[3]))
				_explode(sp, int(fx[4]), Color(float(fx[5]), float(fx[6]), float(fx[7])), HIT_SPARK_SIZE)
				if fx.size() >= 9:
					_play_net_sfx(int(fx[8]), sp)
		"snd":
			# Disparo de cualquier jugador (incluido el propio: llega con el snapshot,
			# asÃ­ nunca suena un balazo que el host no llegÃ³ a disparar).
			if fx.size() >= 5:
				_play_net_sfx(int(fx[1]), Vector3(float(fx[2]), float(fx[3]), float(fx[4])))
		"flash":
			# Destello de boca de los demÃ¡s jugadores (antes este fx se enviaba y se descartaba)
			if fx.size() >= 7:
				_muzzle_flash(Vector3(fx[1], fx[2], fx[3]), Vector3(fx[4], fx[5], fx[6]).normalized(), false)
		"text":
			_spawn_floating_text(Vector3(fx[1], fx[2], fx[3]), str(fx[4]), Color(1, 1, 0.8))

# â”€â”€ DISPARO POR SLOT (host) â”€â”€
func _shoot_for(slot: int) -> bool:
	# Devuelve true si efectivamente disparÃ³ (para no reproducir audio en frames bloqueados por cadencia)
	if slot >= slot_states.size():
		return false
	var st: Dictionary = slot_states[slot]
	var now := Time.get_ticks_msec() / 1000.0
	var srate: float = float(weapon_rate[int(st.weapon)])
	if now - float(st.last_shot) < srate:
		return false
	st.last_shot = now
	var w: int = int(st.weapon)
	if w != 0 and int(st.ammo[w]) <= 0:
		return false
	if w != 0:
		st.ammo[w] = int(st.ammo[w]) - 1
	# DirecciÃ³n desde el apuntado del slot (s_yaw, s_pitch)
	var s_yaw: float = float(st.aim[0])
	var s_pitch: float = float(st.aim[1])
	var b := Basis(Vector3.UP, s_yaw) * Basis(Vector3.RIGHT, s_pitch)
	var dir := (b * Vector3(0, 0, -1))
	var spread: float = weapon_spread[w]
	dir += Vector3(randf_range(-spread, spread), randf_range(-spread, spread), 0)
	dir = dir.normalized()
	var origin := _player_station(slot)
	# La bala nace en la boca del caÃ±o de la torreta visible (misma altura que la
	# estaciÃ³n cuando hay avatar): en la pantalla del compaÃ±ero sale del caÃ±o, no del aire.
	var spawn_pos: Vector3 = origin
	if slot < player_avatars.size():
		var tv3: Variant = player_avatars[slot].get("turret")
		if tv3 != null and is_instance_valid(tv3):
			spawn_pos = Vector3(origin.x, (tv3 as Node3D).position.y + 1.28, origin.z)
	var size := 0.6 if w == 2 else 0.35
	var color := Color(1, 0.5, 0) if w == 2 else Color(1, 1, 0.3)
	var proj := _create_projectile(size, color)
	proj.position = spawn_pos + dir * 1.0
	proj.name = "Proj_%d" % projectiles.size()
	add_child(proj)
	projectiles.append({
		"node": proj, "dir": dir, "speed": weapon_speed[w],
		"damage": weapon_damage[w], "life": 5.0,
		"area": 1.5 if w == 2 else 0.0,
		"splash": 7.5 if w == 2 else 0.0,
		"slot": slot
	})
	# Efectos locales si es mi slot
	if slot == my_slot:
		_play_local_sfx(w)
		shake_amount = 0.15 if w != 2 else 0.4
	# Destello LOCAL en la torreta del otro jugador (host y split): sin esto el host
	# nunca ve los flashes que manda por net_fx (son solo para el cliente) y en split
	# no existe la red. El flash nace en el Ã¡rbol principal â†’ el espejo lo replica
	# en ambas mitades: los dos ven disparar el caÃ±Ã³n del compaÃ±ero.
	if (mp_role == 1 or mp_role == 3) and slot != my_slot and slot < player_avatars.size():
		var tv: Variant = player_avatars[slot].get("turret")
		if tv != null and is_instance_valid(tv):
			var tpos: Vector3 = (tv as Node3D).position
			_muzzle_flash(tpos + Vector3(0, 1.28, 0) + dir * 7.2, dir, w == 2)
	# FX para remotos (destello + balazo: los clientes los reproducen vÃ­a _spawn_net_fx).
	# Si hay avatar visible el destello va a la boca de su caÃ±Ã³n, no a la estaciÃ³n.
	if mp_role == 1:
		var fz: float = origin.y - 0.2
		if slot < player_avatars.size():
			var tv2: Variant = player_avatars[slot].get("turret")
			if tv2 != null and is_instance_valid(tv2):
				fz = (tv2 as Node3D).position.y + 1.28
		net_fx.append(["flash", origin.x, fz, origin.z, dir.x, dir.y, dir.z])
		net_fx.append(["snd", w, origin.x, origin.y, origin.z])
		# El host tambiÃ©n escucha los disparos de los demÃ¡s jugadores (atenuados por distancia)
		if slot != my_slot:
			_play_net_sfx(w, origin)
	return true

# â”€â”€ MP GAME OVER (hÃ­brido: score de equipo + ranking individual + iniciales) â”€â”€
func _mp_gameover_host() -> void:
	if ui_gameover:
		ui_gameover.play()
	phase = GamePhase.GAMEOVER
	entering_initials = true
	initials = ""
	mp_go_phase = 0
	mp_roster = []
	for s in mp_players:
		mp_roster.append("")
	_mp_show_gameover_screen()
	# Broadcast game over a los clientes con la estadÃ­stica final (los loops de red
	# solo corren en PLAYING, asÃ­ que esto va por RPC directo)
	var stats: Array = []
	for s in slot_states.size():
		var st: Dictionary = slot_states[s]
		stats.append([int(st.get("score", 0)), int(st.get("kills", 0))])
	net._net_gameover.rpc(score, wave, stats, mp_roster.duplicate())
	# Red de seguridad: si algÃºn jugador no envÃ­a iniciales, cerrar el guardado
	get_tree().create_timer(25.0).timeout.connect(_mp_host_finish_save)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# _net_gameover (RPC): movido a net.gd (Fase 3). AllÃ¡ delega en _mp_show_gameover_screen,
# _mp_client_timeout_save y los miembros app.* (score/wave/mp_slot_stats/mp_roster/phase).

func _is_mp_gameover() -> bool:
	return mp_role != 0 and phase == GamePhase.GAMEOVER and mp_go_phase < 2

func _mp_show_gameover_screen() -> void:
	_hud.clear_overlay_nodes()
	_hud.make_overlay("GOOverlay", Color(0, 0, 0, 0.85))
	_hud.make_label("GOTitle", Vector2(520, 110), _tr("mpgo_title") % wave, 44, Color(1, 0.3, 0.2))
	_hud.make_label("GOTeam", Vector2(640, 230), _tr("mpgo_team") % score, 34, Color(1, 0.9, 0.4))
	_mp_rebuild_ranking()
	if split_mode:
		# â”€â”€ Iniciales POR MITAD: P1 (teclado si eligiÃ³ KB/M, si no VKB por mando) Â· P2 (VKB por mando) â”€â”€
		_hud.make_centered_label("GOInitialsPrompt", 0, 540, 960, 40, _tr("mpgo_ini_j1"), 26, Color(0.6, 0.8, 1.0))
		initials_label = _hud.make_centered_label("GOInitialsBoxes", 0, 595, 960, 70, "_ _ _", 52, Color(1, 0.95, 0.5))
		if local_input_mode == 1:
			_svkb[0].show()  # P1 con joystick â†’ teclado virtual por mando
		else:
			_hud.make_centered_label("GOHintP1", 0, 705, 960, 30, _tr("mpgo_ini_j1_hint"), 18, Color(1, 1, 1, 0.75))
		_hud.make_centered_label("GOInitialsPromptP2", 960, 540, 960, 40, _tr("mpgo_ini_p2"), 26, Color(0.6, 0.8, 1.0))
		_hud.make_centered_label("GOInitialsBoxesP2", 960, 595, 960, 70, "_ _ _", 52, Color(1, 0.95, 0.5))
		_svkb[1].show()  # P2 siempre con joystick â†’ teclado virtual
	else:
		if local_input_mode == 1:
			# LAN con mando: misma disposicion que single player (por debajo del ranking) + teclado virtual
			_hud.make_label("GOInitialsPrompt", Vector2(430, 530), _tr("mpgo_ini_prompt"), 26, Color(1, 0.9, 0.4))
			initials_label = _hud.make_label("GOInitialsBoxes", Vector2(780, 610), "_ _ _", 56, Color(1, 0.95, 0.5))
		else:
			_hud.make_label("GOInitialsPrompt", Vector2(430, 680), _tr("mpgo_ini_prompt"), 26, Color(1, 0.9, 0.4))
			initials_label = _hud.make_label("GOInitialsBoxes", Vector2(780, 735), "_ _ _", 56, Color(1, 0.95, 0.5))
	_update_initials_display()
	if split_mode or local_input_mode == 0:
		_hud.make_label("GOHint", Vector2(540, 850), _tr("mpgo_hint"), 18, Color(1, 1, 1, 0.7))
	if not split_mode and local_input_mode == 1:
		_vkb.show()  # LAN host/client con mando: teclado virtual para las iniciales

func _roster_init_at(slot: int) -> String:
	if slot >= 0 and slot < mp_roster.size():
		var v := str(mp_roster[slot]).strip_edges()
		if v != "":
			return v
	return "???"

func _mp_rank_rows() -> Array:
	var rows: Array = []
	for s in mp_players:
		var sc := 0
		var kl := 0
		if (mp_role == 1 or mp_role == 3) and s < slot_states.size():
			var st: Dictionary = slot_states[s]
			sc = int(st.get("score", 0))
			kl = int(st.get("kills", 0))
		elif s < mp_slot_stats.size():
			sc = int(mp_slot_stats[s][0])
			kl = int(mp_slot_stats[s][1])
		rows.append([_roster_init_at(s), sc, kl])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows

func _mp_rebuild_ranking() -> void:
	# Re-dibuja ranking + MVP (libera los labels anteriores si ya existÃ­an)
	for nm in ["GORank", "GOMvp"]:
		var old: Node = hud.get_node_or_null(nm)
		if old:
			old.free()  # inmediato: evita leer el label viejo en el mismo frame
	var rows := _mp_rank_rows()
	var txt := ""
	for i in rows.size():
		var r: Array = rows[i]
		txt += " %d.   %s   %6d   %d %s\n" % [i + 1, r[0], r[1], r[2], _tr("mpgo_kills")]
	_hud.make_label("GORank", Vector2(520, 320), txt, 26)
	var mvp := "???"
	var best := -1
	for r in rows:
		if int(r[1]) > best:
			best = int(r[1])
			mvp = str(r[0])
	# El MVP va AL LADO de la tabla, no debajo: cada fila del ranking mide ~40 px, asÃ­ con
	# 3-4 filas el bloque llegaba a yâ‰ˆ475 y el MVP (debajo) chocaba con la Ãºltima fila y con
	# el pedido de iniciales en modo mando. La tabla mide ~332 px de ancho (iniciales + %6d),
	# x=920 la deja libre en 2P/3P/4P y no toca ninguna otra zona del game over.
	_hud.make_label("GOMvp", Vector2(920, 320), "MVP: %s" % mvp, 26, Color(0.5, 1.0, 0.5))

func _mp_send_my_initials(init: String) -> void:
	if mp_go_phase >= 1:
		return
	mp_go_phase = 1
	entering_initials = false
	var clean := init.strip_edges().to_upper().left(3)
	if clean.is_empty():
		clean = "???"
	if mp_role == 1 or mp_role == 3:
		if my_slot < mp_roster.size():
			mp_roster[my_slot] = clean
		_mp_host_check_roster()
	else:
		net._net_my_initials.rpc_id(1, {"slot": my_slot, "init": clean})
	_mp_local_sent()

# _net_my_initials (RPC): movido a net.gd (Fase 3); allÃ¡ actualiza app.mp_roster y llama
# _mp_host_check_roster() (acÃ¡ abajo).

func _mp_host_check_roster() -> void:
	if mp_go_phase >= 2 or mp_roster.size() < mp_players:
		return
	for i in mp_roster.size():
		if str(mp_roster[i]).strip_edges() == "":
			return
	_mp_host_finish_save()

func _mp_host_finish_save() -> void:
	if mp_go_phase >= 2:
		return
	var rank := _add_mp_highscore(mp_players, score, wave, mp_roster)
	mp_go_phase = 2
	if net != null:
		net._net_roster_done.rpc(rank, mp_roster.duplicate())
	_mp_local_saved(rank)

# _net_roster_done (RPC): movido a net.gd (Fase 3); allÃ¡ guarda la copia local del cliente
# vÃ­a _add_mp_highscore + _mp_local_saved (acÃ¡ abajo).

func _mp_client_timeout_save() -> void:
	if mp_role != 2 or mp_go_phase >= 2:
		return
	var rank := _add_mp_highscore(mp_players, score, wave, mp_roster)
	mp_go_phase = 2
	_mp_local_saved(rank)

func _mp_local_sent() -> void:
	if initials_label:
		initials_label.queue_free()
		initials_label = null
	for nm in ["GOInitialsPrompt", "GOHintP1"]:
		var nd: Node = hud.get_node_or_null(nm)
		if nd:
			nd.queue_free()
	_svkb[0].clear()  # libera el VKB de P1 (si estaba en split con joystick)
	_vkb.clear()   # libera el teclado virtual (LAN host/client con mando)
	var hint: Label = hud.get_node_or_null("GOHint") as Label
	if hint == null:
		hint = _hud.make_label("GOHint", Vector2(540, 850), "", 18, Color(1, 1, 1, 0.7))
	hint.text = _tr("mpgo_sent")

func _mp_local_saved(rank: int) -> void:
	entering_initials = false
	if initials_label:
		initials_label.queue_free()
		initials_label = null
	_mp_rebuild_ranking()  # ahora con todas las iniciales + MVP real
	if _svkb.size() == 2:
		_svkb[0].clear()  # los 2 VKB del split quedan limpios: si uno queda "open" el
		_svkb[1].clear()  # proximo game over muestra un teclado demas o bloquea una mitad
	_vkb.clear()  # por seguridad: ningÃºn teclado virtual sigue visible tras guardar
	var hint: Label = hud.get_node_or_null("GOHint") as Label
	if hint == null:
		hint = _hud.make_label("GOHint", Vector2(540, 850), "", 18, Color(1, 1, 1, 0.7))
	var extra := _tr("mpgo_saved_extra") % rank if rank > 0 else ""
	hint.text = extra + _tr("mpgo_enter_menu")

# â”€â”€ CALLBACKS DE RED (referenciados por _setup_net) â”€â”€
func _on_rooms_found(rooms: Array) -> void:
	if phase != GamePhase.MENU and not _is_mp_ui():
		return
	if rooms.is_empty():
		# Sin salas detectadas: quedarnos en la pantalla de IP manual (sin borrar lo escrito)
		_show_mp_browser_searching(true)
	else:
		_show_mp_browser(rooms)

func _on_mp_player_joined(total: int) -> void:
	print("[NET-UI] jugador sumado: %d/%d" % [total, net.max_players])
	_mp_refresh_host_lobby(total)

func _on_mp_player_left(total: int) -> void:
	print("[NET-UI] jugador se fue: %d/%d" % [total, net.max_players])
	_mp_refresh_host_lobby(total)

# Â¿La partida del host estÃ¡ en curso? (usado por net.gd para rechazar ingresos tardÃ­os:
# los slots y mp_players se reparten una sola vez en _mp_host_start)
func _mp_match_running() -> bool:
	if mp_role != 1:
		return false
	if phase == GamePhase.PLAYING:
		return true
	return phase == GamePhase.GAMEOVER and mp_go_phase < 2

# â”€â”€ PEER QUE SE VA EN MITAD DE LA PARTIDA (3-4 jugadores) â”€â”€
# DecisiÃ³n de esta sesiÃ³n: la partida CONTINÃšA con los que quedan. NO se toca mp_players ni
# las estaciones: mover de lado a los que siguen jugando (y cambiar la vida de la base a
# mitad de la partida) es peor que dejar un lugar vacÃ­o y visible en el ranking.
# Lo que sÃ­ se cierra: el slot del peer ido deja de recibir input y, si estÃ¡bamos en GAME
# OVER, sus iniciales se completan en "???" al instante â€” sin esto el guardado esperaba los
# 25 s de la red de seguridad por un peer que ya no existe (y el resto del equipo mirando).
func _mp_peer_gone(pid: int) -> void:
	if mp_role != 1 or not slot_by_pid.has(pid):
		return
	var s: int = int(slot_by_pid[pid])
	slot_by_pid.erase(pid)
	if s < slot_states.size():
		slot_states[s].shoot = false  # nadie dispara por un jugador que se cayÃ³
	if phase == GamePhase.GAMEOVER and mp_go_phase < 2 and s < mp_roster.size():
		if str(mp_roster[s]).strip_edges() == "":
			mp_roster[s] = "???"
		_mp_host_check_roster()

# Actualiza la lobby del host: contador de jugadores y habilita INICIAR PARTIDA al llegar a 2.
# Los nodos viven bajo hud (make_label/make_button), por eso se buscan desde hud (igual que MpIpInput).
func _mp_refresh_host_lobby(total: int) -> void:
	var lbl: Label = hud.get_node_or_null("MpPlayersLabel") as Label
	if lbl:
		lbl.text = _tr("mp_players_now") % [total, net.max_players]
	var btn: Button = hud.get_node_or_null("MpStartBtn") as Button
	if btn:
		btn.disabled = total < 2

func _on_host_connected() -> void:
	print("[NET-UI] host_connected â†’ esperando inicio")
	mp_role = 2
	_show_mp_waiting()

func _on_net_error(msg: String) -> void:
	print("[NET-UI] ERROR: %s (host=%s)" % [msg, net.is_host])
	# Si el fallo fue al intentarnos unir, volver a la pantalla de IP para reintentar
	var back: Callable = _menu.show_menu
	if not net.is_host:
		back = _show_mp_create_join.bind(mp_last_n)
	_mp_show_error(msg, back)

func _on_net_disconnected() -> void:
	if mp_role == 1:
		# Host: el Ãºltimo cliente se fue â†’ detener la partida (si corrÃ­a) y volver a la lobby
		_mp_abort_cleanup()
		if net != null:
			_show_mp_host_screen()
		else:
			_menu.show_menu()
	elif mp_role == 2:
		# Cliente: perder la conexiÃ³n no debe dejar la partida corriendo detrÃ¡s del error
		_mp_abort_cleanup()
		_mp_show_error(_tr("mp_err_conn_lost"), _menu.show_menu)

func _on_auth_denied() -> void:
	print("[NET-UI] auth deniada (contraseÃ±a incorrecta)")
	mp_role = 0
	_mp_show_error(_tr("mp_pw_wrong"), _show_mp_select)

# â”€â”€ UI MULTIJUGADOR â”€â”€
var _mp_ui_active := false
var mp_ip_edit: LineEdit = null  # referencia directa al input de IP (pantalla de unir)
var mp_last_n := 2               # cantidad de jugadores elegida (los botones VOLVER la reutilizan)

func _is_mp_ui() -> bool:
	return _mp_ui_active

func _mp_show_error(msg: String, back: Callable = _menu.show_menu) -> void:
	_hud.clear_overlay_nodes()
	current_menu = "error"
	_mp_err_back = back  # ESC usa el mismo destino que el botÃ³n VOLVER
	_hud.make_overlay("MpErrOverlay", Color(0, 0, 0, 0.85))
	_hud.make_label("MpErrTitle", Vector2(620, 350), msg, 36, Color(1, 0.4, 0.3))
	_hud.make_button("MpErrBack", Vector2(720, 550), _tr("opt_back"), back)
	_mp_ui_active = true

func _show_mp_select() -> void:
	if net == null:
		_setup_net()
	_hud.clear_overlay_nodes()
	current_menu = "mp_select"
	_hud.make_overlay("MpSelOverlay", Color(0, 0, 0, 0.82))
	_hud.make_label("MpSelTitle", Vector2(620, 180), _tr("mp_sel_title"), 48, Color(1, 0.9, 0.4))
	_hud.make_label("MpSelHint", Vector2(420, 280), _tr("mp_sel_hint"), 22, Color(1, 1, 1, 0.8))
	_hud.make_button("MpSel2", Vector2(560, 400), "%d %s" % [2, _tr("players_word")], _on_mp_select_players.bind(2))
	_hud.make_button("MpSel3", Vector2(560, 490), "%d %s" % [3, _tr("players_word")], _on_mp_select_players.bind(3))
	_hud.make_button("MpSel4", Vector2(560, 580), "%d %s" % [4, _tr("players_word")], _on_mp_select_players.bind(4))
	_hud.make_button("MpSelBack", Vector2(720, 750), _tr("opt_back"), _menu.show_menu)
	_mp_ui_active = true

func _on_mp_select_players(n: int) -> void:
	mp_last_n = n
	_show_mp_create_join(n)

func _show_mp_create_join(n: int) -> void:
	_hud.clear_overlay_nodes()
	current_menu = "mp_create_join"
	_hud.make_overlay("MpCJOverlay", Color(0, 0, 0, 0.85))
	_hud.make_label("MpCJTitle", Vector2(560, 150), _tr("mp_room_title") % n, 42, Color(1, 0.9, 0.4))
	# La contraseÃ±a ya NO aparece acÃ¡: vive dentro del flujo CREAR SALA
	# (_show_mp_create_password), que es donde tiene sentido pedirla.
	_hud.make_button("MpCreateBtn", Vector2(560, 320), _tr("mp_create"), _show_mp_create_password.bind(n))
	_hud.make_button("MpJoinBtn", Vector2(560, 420), _tr("mp_join_search"), _on_mp_discover)
	_hud.make_label("MpCJHint", Vector2(420, 560), _tr("mp_cj_hint"), 20, Color(1, 1, 1, 0.7))
	_hud.make_button("MpCJBack", Vector2(720, 740), _tr("opt_back"), _show_mp_select)
	_mp_ui_active = true

# Paso intermedio de CREAR: contraseÃ±a opcional de la sala antes de abrirla.
func _show_mp_create_password(n: int) -> void:
	_hud.clear_overlay_nodes()
	current_menu = "mp_create_pw"
	_hud.make_overlay("MpCpOverlay", Color(0, 0, 0, 0.85))
	_hud.make_label("MpCpTitle", Vector2(560, 150), _tr("mp_create_pw_title") % n, 42, Color(1, 0.9, 0.4))
	_hud.make_label("MpCreatePwLbl", Vector2(560, 260), _tr("mp_pw"), 22, Color(1, 1, 1, 0.8))
	var pw := LineEdit.new()
	pw.name = "MpCreatePw"
	pw.position = Vector2(560, 300)
	pw.size = Vector2(560, 50)
	pw.placeholder_text = "sin contraseÃ±a"
	pw.secret = true
	pw.secret_character = "*"
	pw.add_theme_font_size_override("font_size", 26)
	hud.add_child(pw)
	_hud.make_button("MpCreateGo", Vector2(560, 400), _tr("mp_create"), _on_mp_create.bind(n))
	_hud.make_label("MpCpHint", Vector2(420, 540), _tr("mp_cj_hint"), 20, Color(1, 1, 1, 0.7))
	_hud.make_button("MpCpBack", Vector2(720, 740), _tr("opt_back"), _show_mp_create_join.bind(n))
	_mp_ui_active = true

func _on_mp_create(n: int) -> void:
	if net == null:
		_setup_net()
	var room_nm := "Sala_%d" % n
	var pw_edit: LineEdit = hud.get_node_or_null("MpCreatePw") as LineEdit
	var pw := pw_edit.text.strip_edges() if pw_edit else ""
	if not net.create_room(room_nm, n, pw):
		_mp_show_error(_tr("mp_err_create"))
		return
	_show_mp_host_screen()

func _on_mp_discover() -> void:
	if net == null:
		_setup_net()
	_show_mp_browser_searching()
	net.discover(3.0)

func _show_mp_browser(rooms: Array) -> void:
	_hud.clear_overlay_nodes()
	current_menu = "mp_browser"
	_hud.make_overlay("MpBrOverlay", Color(0, 0, 0, 0.88))
	_hud.make_label("MpBrTitle", Vector2(620, 120), _tr("mp_rooms"), 44, Color(1, 0.9, 0.4))
	# ContraseÃ±a de la sala (compartida por el botÃ³n UNIRSE)
	_hud.make_label("MpJoinPwLbl", Vector2(300, 210), _tr("mp_pw_room"), 20, Color(1, 1, 1, 0.8))
	var pw := LineEdit.new()
	pw.name = "MpJoinPw"
	pw.position = Vector2(300, 250)
	pw.size = Vector2(400, 48)
	pw.placeholder_text = "sin contraseÃ±a"
	pw.secret = true
	pw.secret_character = "*"
	pw.add_theme_font_size_override("font_size", 24)
	hud.add_child(pw)
	var y := 340.0
	if rooms.is_empty():
		_hud.make_label("MpBrEmpty", Vector2(620, 440), _tr("mp_rooms_empty"), 26, Color(1, 1, 1, 0.7))
	else:
		for i in rooms.size():
			var r: Dictionary = rooms[i]
			var txt: String = "%s  [%s]  %d/%d" % [str(r.get("n", "?")), str(r.get("ip", "?")), int(r.get("players", 0)), int(r.get("max", 0))]
			_hud.make_label("MpBrRow%d" % i, Vector2(300, y), txt, 24)
			_hud.make_button("MpBrJoin%d" % i, Vector2(960, y - 10), _tr("mp_join"), _on_mp_join.bind(str(r.get("ip", "")), int(r.get("max", 2))))
			y += 70.0
	_hud.make_button("MpBrRefresh", Vector2(560, 820), _tr("mp_refresh"), _on_mp_discover)
	_hud.make_button("MpBrBack", Vector2(720, 900), _tr("opt_back"), _show_mp_create_join.bind(mp_last_n))
	_mp_ui_active = true

func _show_mp_browser_searching(not_found: bool = false) -> void:
	_hud.clear_overlay_nodes()
	current_menu = "mp_browser_search"
	# Conservar el IP ya escrito (el input se reconstruye al volver de la bÃºsqueda)
	var prev_ip := ""
	var old_ip: Node = hud.get_node_or_null("MpIpInput")
	if old_ip is LineEdit:
		prev_ip = (old_ip as LineEdit).text.strip_edges()
	_hud.make_overlay("MpBrOverlay", Color(0, 0, 0, 0.88))
	_hud.make_label("MpBrTitle", Vector2(620, 140), _tr("mp_join_room"), 44, Color(1, 0.9, 0.4))
	var hint_text := _tr("mp_ip_hint") if not not_found else \
		_tr("mp_ip_hint2")
	_hud.make_label("MpBrWait", Vector2(520, 230), hint_text, 24, Color(1, 1, 1, 0.85))
	# IP input
	var ip_edit := LineEdit.new()
	ip_edit.name = "MpIpInput"
	ip_edit.position = Vector2(600, 330)
	ip_edit.size = Vector2(400, 50)
	ip_edit.placeholder_text = "192.168.1.XX"
	ip_edit.add_theme_font_size_override("font_size", 26)
	ip_edit.text = prev_ip if prev_ip != "" else "127.0.0.1"  # default local
	hud.add_child(ip_edit)
	mp_ip_edit = ip_edit
	# ContraseÃ±a input
	var pw_edit := LineEdit.new()
	pw_edit.name = "MpPwManual"
	pw_edit.position = Vector2(600, 400)
	pw_edit.size = Vector2(400, 50)
	pw_edit.placeholder_text = "contraseÃ±a (opcional)"
	pw_edit.secret = true
	pw_edit.secret_character = "*"
	pw_edit.add_theme_font_size_override("font_size", 26)
	hud.add_child(pw_edit)
	_hud.make_button("MpJoinManual", Vector2(600, 490), _tr("mp_connect"), _on_mp_join_manual)
	_hud.make_button("MpBrRefresh", Vector2(600, 590), _tr("mp_search"), _on_mp_discover)
	_hud.make_button("MpBrBack", Vector2(720, 700), _tr("opt_back"), _show_mp_create_join.bind(mp_last_n))
	_mp_ui_active = true

func _on_mp_join_manual() -> void:
	var ip_edit: LineEdit = mp_ip_edit if mp_ip_edit != null and is_instance_valid(mp_ip_edit) else hud.get_node_or_null("MpIpInput") as LineEdit
	var ip: String = ip_edit.text.strip_edges() if ip_edit else "127.0.0.1"
	if ip == "" or ip == "0.0.0.0":
		_mp_show_error(_tr("mp_err_ip"))
		return
	var pw_edit: LineEdit = hud.get_node_or_null("MpPwManual") as LineEdit
	var pw := pw_edit.text.strip_edges() if pw_edit else ""
	if net == null:
		_setup_net()
	_show_mp_waiting()
	if not net.join(ip, 4, pw):
		_mp_show_error(_tr("mp_err_connect") % ip)

func _on_mp_join(ip: String, n: int) -> void:
	if net == null:
		_setup_net()
	var pw_edit: LineEdit = hud.get_node_or_null("MpJoinPw") as LineEdit
	var pw := pw_edit.text.strip_edges() if pw_edit else ""
	_show_mp_waiting()
	if not net.join(ip, n, pw):
		_mp_show_error(_tr("mp_err_connect") % ip)

func _show_mp_host_screen() -> void:
	_hud.clear_overlay_nodes()
	current_menu = "mp_host"
	_hud.make_overlay("MpHostOverlay", Color(0, 0, 0, 0.85))
	_hud.make_label("MpHostTitle", Vector2(620, 160), _tr("mp_room_created"), 44, Color(0.6, 1.0, 0.6))
	_hud.make_label("MpHostIP", Vector2(620, 270), "IP: %s" % str(net.local_ip if net else "?"), 28)
	_hud.make_label("MpPlayersLabel", Vector2(620, 340), _tr("mp_players_lbl") % (net.max_players if net else 2), 26)
	var start_btn := _hud.make_button("MpStartBtn", Vector2(720, 480), _tr("mp_start"), _on_mp_host_start_btn)
	start_btn.disabled = (net == null or net.total_players < 2)
	_hud.make_label("MpHostHint", Vector2(560, 600), _tr("mp_wait_players"), 20, Color(1, 1, 1, 0.7))
	_hud.make_button("MpHostBack", Vector2(720, 740), _tr("mp_back_menu"), _menu.show_menu)
	_mp_ui_active = true

func _on_mp_host_start_btn() -> void:
	if net == null or net.total_players < 2:
		return
	_mp_ui_active = false
	_mp_host_start()

func _show_mp_waiting() -> void:
	_hud.clear_overlay_nodes()
	current_menu = "mp_waiting"
	_hud.make_overlay("MpWaitOverlay", Color(0, 0, 0, 0.85))
	_hud.make_label("MpWaitTitle", Vector2(620, 300), _tr("mp_connecting"), 44, Color(1, 0.9, 0.4))
	_hud.make_label("MpWaitHint", Vector2(620, 420), _tr("mp_waiting"), 24, Color(1, 1, 1, 0.7))
	_hud.make_button("MpWaitCancel", Vector2(720, 560), _tr("mp_cancel"), _menu.show_menu)
	_mp_ui_active = true

func _process(delta: float) -> void:

	# â”€â”€ NavegaciÃ³n con joystick: MENÃš/PAUSA o menÃº de habilidades abierto.
	#    Activa si hay pad conectado (futuro: todo por joystick) â”€â”€
	var nav_ctx: bool = (phase == GamePhase.MENU or phase == GamePhase.PAUSE) or (phase == GamePhase.PLAYING and (_abilities_menu_open or _abl1_open))
	if _remap_capture == "" and nav_ctx and Input.get_connected_joypads().size() > 0:
		# Auto-foco en el primer botÃ³n al abrir una pantalla (sin sonido)
		if menu_nav_focused == null and not menu_nav_buttons.is_empty():
			_menu_nav_step(0, false)
		var devs: Array = [1, 0] if split_mode else [0]
		var sy: float = 0.0
		for d in devs:
			sy = Input.get_joy_axis(int(d), JOY_AXIS_LEFT_Y)
			if absf(sy) > 0.55:
				break
		if absf(sy) > 0.55:
			menu_nav_repeat_t -= delta
			if menu_nav_repeat_t <= 0.0:
				_menu_nav_step(1 if sy > 0.0 else -1)
				menu_nav_repeat_t = 0.18
		else:
			menu_nav_repeat_t = 0.0

	_update_hud_scale()
	# Destellos, anillos y luces de explosion: se integran siempre (igual que los
	# Tween de antes, que seguian corriendo en pausa y en el game over).
	if _fx != null:
		_fx.tick_fx(delta)
	_vfx_tick(delta)  # expira y devuelve al pool las instancias Binbun activas
	# â”€â”€ Crosshair: visible solo durante gameplay activo (sin menÃºs) â”€â”€
	if crosshair_layer != null:
		crosshair_layer.visible = (phase == GamePhase.PLAYING) and not _abilities_menu_open and not _abl1_open
	# Camera shake decay (la ancla respeta la estaciÃ³n del cliente LAN, ver _cam_anchor)
	if shake_amount > 0.0:
		shake_amount = maxf(0.0, shake_amount - delta * 8.0)
		camera.position = _cam_anchor() + Vector3(
			randf_range(-1, 1) * shake_amount,
			randf_range(-1, 1) * shake_amount,
			randf_range(-1, 1) * shake_amount
		)
	else:
		camera.position = _cam_anchor()
	if phase == GamePhase.PLAYING:
		if mp_role == 0:
			# Solo (offline): simulaciÃ³n completa local
			if local_input_mode == 1 and not _abilities_menu_open:
				_feed_joy_slot0(delta)
			_handle_input()
			_update_projectiles(delta)
			_update_enemies(delta)
			_update_particles(delta)
			_update_wave(delta)
			_update_crates(delta)
			_update_base_fire(delta)
			_update_abilities(delta)
			_hud.update_hud()
		elif mp_role == 1:
			# Host: simula todo + loops de red
			if local_input_mode == 1 and not _abilities_menu_open:
				_feed_joy_slot0(delta)
			_handle_input()
			_update_projectiles(delta)
			_update_enemies(delta)
			_update_particles(delta)
			_update_wave(delta)
			_update_crates(delta)
			_update_base_fire(delta)
			_update_abilities(delta)
			_hud.update_hud()
			net._net_host_loop(delta)
		elif mp_role == 3:
			# Split 2P: simulaciÃ³n completa local + disparos de ambos slots
			if local_input_mode == 1 and not _abilities_menu_open:
				_feed_joy_slot0(delta)  # P1 con joystick
			_handle_input()
			_split_feed_slots(delta)
			for s in slot_states.size():
				var stf: Dictionary = slot_states[s]
				if stf.shoot:
					stf.shoot = false
					var fired: bool = _shoot_for(int(s))
					# Solo suena si REALMENTE disparÃ³ (antes sonaba por frame â†’ distorsiÃ³n al mantener)
					if int(s) == 1 and fired:
						var w2s: int = int(slot_states[1].get("weapon", 0))
						_play_local_sfx(w2s)
			_update_projectiles(delta)
			_update_enemies(delta)
			_update_particles(delta)
			_update_wave(delta)
			_update_crates(delta)
			_update_base_fire(delta)
			_update_abilities(delta)
			_hud.update_hud()
			_split_scan_new_nodes()
			_update_split_mirrors()
			if cam_a != null:
				cam_a.transform = camera.transform
				if gun_a != null:
					gun_a.transform = cam_a.transform
			if cam_b != null:
				# J2 en SU estaciÃ³n (derecha). El offset contra _cam_anchor() (estaciÃ³n 0 del J1)
				# arrastra solo el shake de la cÃ¡mara principal, no la distancia entre estaciones.
				cam_b.position = _player_station(1) + (camera.position - _cam_anchor())
				cam_b.rotation = Vector3(pitch2, yaw2, 0)
				if gun_b != null:
					gun_b.transform = cam_b.transform
		else:
			# Cliente: solo input + red + HUD
			if local_input_mode == 1 and not _abilities_menu_open:
				_feed_joy_slot0(delta)
			_handle_input()
			_update_particles(delta)
			_update_base_fire(delta)
			_hud.update_hud()
			net._net_client_loop(delta)
		# MP: cada torreta apunta con su slot (ver _update_player_avatars)
		if mp_players > 1:
			_update_player_avatars()

# â”€â”€â”€ SOMBRAS DEL SOL (valores verificados en rtx-godot 4.8) â”€â”€â”€
# DirectionalLight3D.directional_shadow_mode: 0=Orthogonal (Fast) Â· 1=PSSM 2 Splits
# Â· 2=PSSM 4 Splits (default del engine). Cada split recorre TODA la geometria
# visible y el skinning de esos passes se hace por CPU: menos splits = menos CPU.
const SHADOW_MODE_PSSM_2: int = 1
const SHADOW_MODE_PSSM_4: int = 2
const SHADOW_MAX_DISTANCE_M: float = 100.0  # 0 = toda la escena (mas caro)
# BaseMaterial3D.ShadowCastingSetting: 0=Off Â· 1=On Â· 2=Double-Sided Â· 3=Shadows Only
const SHADOW_CASTING_OFF: int = 0
const SHADOW_CASTING_ON: int = 1
# Soldados: cada surface del rig se dibuja de nuevo en cada split de la cascada.
# Con SSAO siguen teniendo contacto con el suelo. Cambiar a true para sombra dura.
const SOLDIER_CAST_SHADOW: bool = true   # ON por pedido: sombras duras en los soldados

# â”€â”€â”€ ENVIRONMENT â”€â”€â”€
func _build_environment() -> void:
	# Sky3D addon: real sky, sun and clouds (replaces old procedural sky)
	var sky3d_script: Script = load("res://addons/sky_3d/src/Sky3D.gd")
	var sky3d := WorldEnvironment.new()
	sky3d.set_script(sky3d_script)
	world.add_child(sky3d)
	sky3d_node = sky3d
	sun_light = sky3d.sun
	env_ref = sky3d.environment
	# Freeze time: stable bright day for gameplay
	sky3d.tod.game_time_enabled = false
	sky3d.tod.pause()
	# Sun high, from behind the base (+Z), like the old light
	sky3d.sky.sun_altitude = deg_to_rad(42.0)
	sky3d.sky.sun_azimuth = deg_to_rad(90.0)
	# Bright tropical beach
	sky3d.sun_energy = 1.6
	sky3d.ambient_energy = 1.15
	sky3d.sky_contribution = 1.0
	sky3d.clouds_enabled = true
	sky3d.cloud_intensity = 0.4
	sky3d.wind_speed = 2.0
	sky3d.sun.shadow_bias = 0.1
	sky3d.sun.shadow_normal_bias = 0.03
	# Cascadas: 4 splits -> 2 splits. Es la mitad del trabajo de sombra (draw calls
	# + skinning por CPU) sobre TODA la escena, oleada tras oleada.
	sky3d.sun.directional_shadow_mode = SHADOW_MODE_PSSM_2
	sky3d.sun.directional_shadow_blend_splits = true
	sky3d.sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE_M

	# â”€â”€ Realism post-processing: SSAO (contact shadows) + SDFGI (global illumination) + Glow + SSR (reflections) â”€â”€
	var env: Environment = sky3d.environment
	if env:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.06
		# SSAO â€” contact shadows give depth / kill the flat look
		env.ssao_enabled = true
		env.ssao_radius = 0.4
		env.ssao_intensity = 1.6
		env.ssao_power = 1.5
		env.ssao_detail = 0.8
		env.ssao_sharpness = 0.6
		env.ssao_light_affect = 0.4
		# SDFGI â€” global illumination (soft bounced light, removes flatness)
		env.sdfgi_enabled = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.5
		env.sdfgi_max_distance = 120.0
		env.sdfgi_energy = 1.0
		env.sdfgi_read_sky_light = true
		env.sdfgi_normal_bias = 0.05
		# Glow â€” subtle bloom on sun, water highlights, muzzle flash
		env.glow_enabled = true
		env.glow_intensity = 0.35
		env.glow_bloom = 0.15
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		# SSR â€” screen-space reflections (water + ground)
		env.ssr_enabled = true
		env.ssr_max_steps = 96
		env.ssr_fade_in = 0.5
		env.ssr_fade_out = 0.08
		env.ssr_depth_tolerance = 0.02

	# â•â•â• TERRAIN3D GROUND (sand â†’ grass, wet sand, dunes at horizon) â•â•â•
	_build_terrain3d()
	# OCEAN (Godot SSR Water â€” SSR + transparencia + olas 3D + espuma de orilla)
	var ocean_mesh := PlaneMesh.new()
	ocean_mesh.size = Vector2(300, 230)
	ocean_mesh.subdivide_width = 200
	ocean_mesh.subdivide_depth = 150
	var ocean_shader := load("res://assets/ssr_water/water.gdshader")
	var ocean_mat := ShaderMaterial.new()
	ocean_mat.shader = ocean_shader
	# Texturas de ola (ruido continuo, canales idÃ©nticos â†’ la altura se lee del canal G)
	var wave_a_noise := FastNoiseLite.new()
	wave_a_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	wave_a_noise.frequency = 0.0005
	wave_a_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	var wave_a_tex := NoiseTexture2D.new()
	wave_a_tex.noise = wave_a_noise
	wave_a_tex.width = 256
	wave_a_tex.height = 256
	wave_a_tex.seamless = true
	var wave_b_noise := FastNoiseLite.new()
	wave_b_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	wave_b_noise.frequency = 0.0225
	var wave_b_tex := NoiseTexture2D.new()
	wave_b_tex.noise = wave_b_noise
	wave_b_tex.width = 256
	wave_b_tex.height = 256
	wave_b_tex.seamless = true
	# Normales de detalle de superficie (mapas de normales seamless)
	var snorm_a_noise := FastNoiseLite.new()
	snorm_a_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	snorm_a_noise.frequency = 0.007
	var snorm_a_tex := NoiseTexture2D.new()
	snorm_a_tex.noise = snorm_a_noise
	snorm_a_tex.width = 256
	snorm_a_tex.height = 256
	snorm_a_tex.seamless = true
	snorm_a_tex.as_normal_map = true
	snorm_a_tex.seamless_blend_skirt = 0.5
	var snorm_b_noise := FastNoiseLite.new()
	snorm_b_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	snorm_b_noise.frequency = 0.02
	snorm_b_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	var snorm_b_tex := NoiseTexture2D.new()
	snorm_b_tex.noise = snorm_b_noise
	snorm_b_tex.width = 256
	snorm_b_tex.height = 256
	snorm_b_tex.seamless = true
	snorm_b_tex.as_normal_map = true
	snorm_b_tex.seamless_blend_skirt = 0.5
	# â”€â”€ ParÃ¡metros SSR Water (ajuste tropical) â”€â”€
	ocean_mat.set_shader_parameter("color_shallow", Color(0.05, 0.45, 0.5))
	ocean_mat.set_shader_parameter("color_deep", Color(0.0, 0.18, 0.28))
	ocean_mat.set_shader_parameter("transparency", 0.65)
	ocean_mat.set_shader_parameter("metallic", 0.0)
	ocean_mat.set_shader_parameter("roughness", 0.15)
	ocean_mat.set_shader_parameter("max_visible_depth", 20.0)
	ocean_mat.set_shader_parameter("wave_a", wave_a_tex)
	ocean_mat.set_shader_parameter("wave_b", wave_b_tex)
	ocean_mat.set_shader_parameter("wave_move_direction_a", Vector2(-1, 0))
	ocean_mat.set_shader_parameter("wave_move_direction_b", Vector2(0, 1))
	ocean_mat.set_shader_parameter("wave_noise_scale_a", 15.0)
	ocean_mat.set_shader_parameter("wave_noise_scale_b", 15.0)
	ocean_mat.set_shader_parameter("wave_time_scale_a", 0.15)
	ocean_mat.set_shader_parameter("wave_time_scale_b", 0.15)
	ocean_mat.set_shader_parameter("wave_height_scale", 0.25)
	ocean_mat.set_shader_parameter("wave_normal_flatness", 50.0)
	ocean_mat.set_shader_parameter("surface_normals_a", snorm_a_tex)
	ocean_mat.set_shader_parameter("surface_normals_b", snorm_b_tex)
	ocean_mat.set_shader_parameter("surface_normals_move_direction_a", Vector2(-1, 0.2))
	ocean_mat.set_shader_parameter("surface_normals_move_direction_b", Vector2(0.2, 1))
	ocean_mat.set_shader_parameter("surface_texture_roughness", 0.15)
	ocean_mat.set_shader_parameter("surface_texture_scale", 0.1)
	ocean_mat.set_shader_parameter("surface_texture_time_scale", 0.06)
	# SSR: cobertura sobre todo el ocÃ©ano (defaults = ALTA; _apply_quality ajusta por calidad)
	ocean_mat.set_shader_parameter("ssr_resolution", 1.0)
	ocean_mat.set_shader_parameter("ssr_max_travel", 150.0)
	ocean_mat.set_shader_parameter("ssr_max_diff", 15.0)
	ocean_mat.set_shader_parameter("ssr_mix_strength", 0.85)
	ocean_mat.set_shader_parameter("ssr_screen_border_fadeout", 0.3)
	ocean_mat.set_shader_parameter("refraction_intensity", 0.35)
	ocean_mat.set_shader_parameter("border_color", Color(1, 1, 1))
	ocean_mat.set_shader_parameter("border_scale", 1.5)
	ocean_mat.set_shader_parameter("border_near", 0.5)
	ocean_mat.set_shader_parameter("border_far", 300.0)
	var ocean := MeshInstance3D.new()
	ocean.mesh = ocean_mesh
	ocean.material_override = ocean_mat
	ocean.position = Vector3(0, -0.35, -100)
	world.add_child(ocean)
	water_node = ocean
	# â•â•â• BEACH DETAILS â•â•â•
	# Driftwood
	for i in 4:
		var dw := MeshInstance3D.new()
		var dwm := CylinderMesh.new()
		dwm.top_radius = 0.03
		dwm.bottom_radius = 0.05
		dwm.height = randf_range(1.0, 2.5)
		var dwm_mat := StandardMaterial3D.new()
		dwm_mat.albedo_color = Color(0.4, 0.3, 0.18)
		dwm_mat.roughness = 0.95
		dw.mesh = dwm
		dw.material_override = dwm_mat
		dw.position = Vector3(randf_range(-30, 30), 0.05, randf_range(5, 25))
		dw.rotation = Vector3(randf_range(0, 0.3), randf_range(0, PI), randf_range(-0.2, 0.2))
		world.add_child(dw)
	# Shells (small white spheres scattered)
	for i in 15:
		var sh := MeshInstance3D.new()
		var shm := SphereMesh.new()
		shm.radius = randf_range(0.03, 0.08)
		shm.height = shm.radius * 1.5
		var sh_mat := StandardMaterial3D.new()
		sh_mat.albedo_color = Color(0.9, 0.88, 0.8)
		sh_mat.roughness = 0.4
		sh.mesh = shm
		sh.material_override = sh_mat
		sh.position = Vector3(randf_range(-25, 25), 0.03, randf_range(2, 30))
		world.add_child(sh)
	# Seaweed (dark green patches)
	for i in 8:
		var sw := MeshInstance3D.new()
		var swm := SphereMesh.new()
		swm.radius = randf_range(0.2, 0.5)
		swm.height = swm.radius * 0.4
		var sw_mat := StandardMaterial3D.new()
		sw_mat.albedo_color = Color(0.1, 0.3, 0.15)
		sw_mat.roughness = 1.0
		sw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sw_mat.albedo_color = Color(0.1, 0.3, 0.15, 0.8)
		sw.mesh = swm
		sw.material_override = sw_mat
		sw.position = Vector3(randf_range(-20, 20), 0.02, randf_range(-3, 5))
		world.add_child(sw)

	# â•â•â• TREES (real 3D models) â•â•â•
	var npath := "res://assets/nature/"
	var tree_types: Array = ["CommonTree_1", "CommonTree_2", "CommonTree_3", "Pine_1", "Pine_2", "TwistedTree_1", "TwistedTree_3"]
	# Solo 8 Ã¡rboles flanqueando la base (antes 15 amontonados; el resto quedÃ³ en _build_forest distribuido)
	var tree_positions: Array = [
		Vector3(-48, 0, 54), Vector3(48, 0, 58), Vector3(-72, 0, 62),
		Vector3(72, 0, 56), Vector3(-95, 0, 70), Vector3(95, 0, 66),
		Vector3(-118, 0, 58), Vector3(118, 0, 72)
	]
	for i in tree_positions.size():
		var tname: String = tree_types[i % tree_types.size()]
		_place_asset(world, npath + tname + ".gltf", tree_positions[i], randf_range(0.8, 1.4), randf_range(0, PI * 2))
	# â•â•â• ROCKS (realistic coastal boulders â€” Poly Haven CC0) â•â•â•
	# Pilas de rocas a escala reducida (antes 0.8-1.3 ocupaban media playa y los soldados se trababan en ellas)
	var rock_defs: Array = [
		[Vector3(-15, 0, 2), 0.5], [Vector3(20, 0, 3), 0.4], [Vector3(-8, 0, 5), 0.35],
		[Vector3(35, 0, 4), 0.55], [Vector3(-30, 0, 1), 0.45], [Vector3(50, 0, 2), 0.5]
	]
	for d in rock_defs:
		var rpos: Vector3 = d[0]
		var rrad: float = float(d[1]) * 14.1 + 1.5
		# MP 3P/4P: las troneras de los avatares (radio ~3.4 m) viven en esta misma
		# franja (zâ‰ˆ0) y varias rocas fijas caerÃ­an encima de las estaciones Â±32/Â±42.
		# Empujar toda pila cuya distancia mÃ¡xima toque una estaciÃ³n. SINGLE y 2P
		# (split/LAN) quedan INTACTOS â€” el layout de 2 ya estÃ¡ validado visualmente.
		# Host/clientes aplican la misma correcciÃ³n (mismo mp_players â†’ mismo mundo).
		if mp_players >= 3:
			for guard in 6:
				var moved := false
				for s in mp_players:
					var sx: float = _player_station(s).x
					if abs(rpos.x - sx) < rrad + 4.5:
						rpos.x = sx + (rrad + 4.5) if rpos.x >= sx else sx - (rrad + 4.5)
						moved = true
				if not moved:
					break
		var rk := _create_coast_rock(rpos, d[1], randf_range(0, PI * 2))
		if rk:
			world.add_child(rk)
		# La pila mide hasta ~28 m de largo a escala 1 (y gira aleatoriamente):
		# radio = semieje mayor * escala + margen, para cubrir la pila en TODAS las direcciones
		rock_spots.append([Vector2(rpos.x, rpos.z), rrad])
	# Small scattered pebbles (cheap, low-poly)
	for i in 8:
		var pn: String = "Pebble_Round_%d" % (1 + i % 2)
		_place_asset(world, npath + pn + ".gltf", Vector3(randf_range(-45, 45), 0, randf_range(-1, 8)), randf_range(0.4, 0.9), randf_range(0, PI * 2))
	# â•â•â• BUSHES & PLANTS (real 3D) â•â•â•
	for i in 10:
		var bpos := Vector3(randf_range(-60, 60), 0, randf_range(45, 75))
		_place_asset(world, npath + "Bush_Common.gltf", bpos, randf_range(0.6, 1.2), randf_range(0, PI * 2))
	for i in 6:
		var ppos := Vector3(randf_range(-50, 50), 0, randf_range(40, 70))
		_place_asset(world, npath + "Plant_1.gltf", ppos, randf_range(0.5, 1.0), randf_range(0, PI * 2))
	# â•â•â• GRASS (real 3D) â•â•â•
	for i in 30:
		var gpos := Vector3(randf_range(-45, 45), 0, randf_range(8, 60))
		_place_asset(world, npath + "Grass_Common_Tall.gltf" if i % 2 == 0 else npath + "Grass_Wispy_Short.gltf", gpos, randf_range(0.5, 1.2), randf_range(0, PI * 2))
	# â•â•â• FLOWERS (beach detail) â•â•â•
	for i in 8:
		var fpos := Vector3(randf_range(-30, 30), 0, randf_range(6, 30))
		_place_asset(world, npath + "Flower_3_Single.gltf" if i % 2 == 0 else npath + "Flower_4_Group.gltf", fpos, randf_range(0.4, 0.8), randf_range(0, PI * 2))
	# â•â•â• FERNS, CLOVER & MUSHROOMS (extra detail) â•â•â•
	for i in 10:
		var fepos := Vector3(randf_range(-50, 50), 0, randf_range(35, 70))
		_place_asset(world, npath + "Fern_1.gltf", fepos, randf_range(0.7, 1.3), randf_range(0, PI * 2))
	for i in 12:
		var cpos := Vector3(randf_range(-45, 45), 0, randf_range(20, 60))
		_place_asset(world, npath + "Clover_1.gltf" if i % 2 == 0 else npath + "Clover_2.gltf", cpos, randf_range(0.5, 1.0), randf_range(0, PI * 2))
	for i in 5:
		var mpos := Vector3(randf_range(-60, 60), 0, randf_range(40, 70))
		_place_asset(world, npath + "Mushroom_Common.gltf" if i % 2 == 0 else npath + "Mushroom_Laetiporus.gltf", mpos, randf_range(0.5, 0.9), randf_range(0, PI * 2))
	for i in 6:
		var p7pos := Vector3(randf_range(-55, 55), 0, randf_range(30, 65))
		_place_asset(world, npath + "Plant_7.gltf", p7pos, randf_range(0.5, 1.0), randf_range(0, PI * 2))
	# â•â•â• PALMERAS cerca de la base (silueta tropical) â•â•â•
	for i in 4:
		var dpos := Vector3(randf_range(-80, 80), 0, randf_range(60, 90))
		var dpalm := "coconut_palm.glb" if i % 2 == 0 else "queen_palm.glb"
		var dscale := 0.5 if dpalm == "coconut_palm.glb" else 0.95
		_place_asset(world, "res://assets/trees/" + dpalm, dpos, dscale * randf_range(0.9, 1.1), randf_range(0, PI * 2))

	# WARSHIPS (background) â€” 6 buques de guerra (GLB), distancias y tamaÃ±os variados
	var ship_defs := [
		[Vector3(-120, 0, -150), 135.0, 0.12, 0],
		[Vector3(-45, 0, -185), 90.0, -0.08, 1],
		[Vector3(25, 0, -140), 70.0, 0.2, 1],
		[Vector3(85, 0, -195), 160.0, -0.15, 0],
		[Vector3(150, 0, -135), 75.0, 0.1, 1],
		[Vector3(-185, 0, -170), 110.0, -0.05, 0],
	]
	for sd in ship_defs:
		var sp: Vector3 = sd[0] as Vector3
		var sl: float = sd[1] as float
		world.add_child(_create_warship(sp, sl, sd[2] as float, sd[3] as int))
		# Punto de despegue sobre la cubierta (para los helicÃ³pteros)
		warship_spots.append(sp + Vector3(randf_range(-5.0, 5.0), sl * 0.12 + 3.0, randf_range(-5.0, 5.0)))

	# BUNKER (disabled â€” new military base behind the player)
	# world.add_child(_create_bunker())
	# MILITARY BASE (behind player)
	_build_military_base()
	_build_base_fire()
	# FOREST behind/around the base (call was lost in an edit â€” restoring vegetation)
	_build_forest()

# â”€â”€â”€ TERRAIN3D GROUND â”€â”€â”€
func _build_terrain3d() -> void:
	_make_terrain3d(world)

# Crea un Terrain3D fresco (determinÃ­stico) bajo `parent`.
# En split cada SubViewport necesita SU Terrain3D: es un GDExtension (C++) y
# world.duplicate(true) no replica su atlas de texturas nativo (la playa se ve sin textura).
func _make_terrain3d(parent: Node) -> void:
	# Texture assets: 0 = sand, 1 = grass
	var sand_ta := Terrain3DTextureAsset.new()
	sand_ta.name = "Sand"
	sand_ta.albedo_texture = load("res://assets/pbr/coast_sand/coast_sand_diff_2k.jpg")
	# Normal map + AO: grano de arena con relieve (antes se veÃ­a plana/papel tapiz)
	sand_ta.normal_texture = load("res://assets/pbr/coast_sand/coast_sand_normal_2k.jpg")
	sand_ta.normal_depth = 2.2
	sand_ta.ao_strength = 1.6
	sand_ta.roughness = 0.85
	sand_ta.uv_scale = 0.4
	sand_ta.detiling_rotation = 0.5
	sand_ta.detiling_shift = 0.3
	var grass_ta := Terrain3DTextureAsset.new()
	grass_ta.name = "Grass"
	grass_ta.albedo_texture = load("res://assets/textures/grass_basecolor.png")
	# Nota: sin normal_texture. El engine exige que todas las normales del set
	# compartan tamaÃ±o/formato/mipmaps (arena=2048Â²). Un 1Ã—1 plano generaba
	# 3Ã—ERROR por textura; vacÃ­o no valida y el pasto queda igual (plano).
	grass_ta.ao_strength = 1.4
	grass_ta.roughness = 0.8
	grass_ta.uv_scale = 0.2
	grass_ta.detiling_rotation = 1.3
	grass_ta.detiling_shift = 0.5
	var stone_ta := Terrain3DTextureAsset.new()
	stone_ta.name = "Stone"
	# Same look as the coast rocks near the camera (user-approved), big scale = no wallpaper
	stone_ta.albedo_texture = load("res://assets/pbr/coast_rocks_model/textures/coast_rocks_03_diff_2k.jpg")
	stone_ta.normal_texture = load("res://assets/pbr/coast_rocks_model/textures/coast_rocks_03_nor_gl_2k.jpg")
	stone_ta.normal_depth = 2.4
	stone_ta.ao_strength = 1.2
	stone_ta.roughness = 0.9
	stone_ta.uv_scale = 0.03
	stone_ta.detiling_rotation = 0.9
	stone_ta.detiling_shift = 0.2

	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	# add_child sin force_parented (terrain es nuevo, sin padre): mas limpio.
	# NOTA: el warning "instance_reset_physics_interpolation() is deprecated"
	# NO sale de esta linea; lo emite el plugin Terrain3D (v1.0.2, C++) al mover
	# su mesh cada frame. Es inofensivo (solo consola de debug) y upstream ya lo
	# arreglo en v1.1+ (issue TokisanGames/Terrain3D #934).
	parent.add_child(terrain)
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.assets = Terrain3DAssets.new()
	terrain.assets.set_texture(0, sand_ta)
	terrain.assets.set_texture(1, grass_ta)
	terrain.assets.set_texture(2, stone_ta)

	# Pre-generated maps: 512x512 px, 1 px = 1 m. 4 regions of 256 m cover world [-256,256)^2
	# 256 is a valid hint value for region_size (editor enum quirk, silenced)
	var SIZE := 512
	@warning_ignore("INT_AS_ENUM_WITHOUT_CAST", "INT_AS_ENUM_WITHOUT_MATCH")
	terrain.region_size = 256
	var origin := Vector3(-256, 0, -256)
	var hbytes := _load_terrain_bin("res://assets/terrain/terrain_height.bin")
	_wmath.terrain_h = hbytes.to_float32_array()  # (ver WorldMath.height)
	var height := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, hbytes)
	var control := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, _load_terrain_bin("res://assets/terrain/terrain_control.bin"))
	var color := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, _load_terrain_bin("res://assets/terrain/terrain_color.bin"))
	terrain.data.import_images([height, control, color], origin, 0.0, 1.0)

# â”€â”€â”€ MATEMÃTICA DE MUNDO: delegado en scripts/world_math.gd (class_name WorldMath) â”€â”€â”€
func _terrain_height(x: float, z: float) -> float:
	return _wmath.height(x, z)  # el heightmap vive en WorldMath.terrain_h

func _load_terrain_bin(path: String) -> PackedByteArray:
	return WorldMath.load_terrain_bin(path)

func _scatter_place(placed: Array, xmin: float, xmax: float, zmin: float, zmax: float, min_sp: float, corridor: float, corridor_z: float) -> Vector2:
	return WorldMath.scatter_place(placed, xmin, xmax, zmin, zmax, min_sp, corridor, corridor_z)

func _build_forest() -> void:
	# â•â•â• FOREST DISTRIBUIDO: base â†’ pie de las montaÃ±as â•â•â•
	# Antes: 88 Ã¡rboles amontonados en z 52..158 (muro). Ahora: ~45 Ã¡rboles
	# repartidos en z 55..190 con separaciÃ³n mÃ­nima, corredor central libre
	# para ver las montaÃ±as del fondo, y sub-bosque reducido.
	var npath := "res://assets/nature/"
	var tpath := "res://assets/trees/"
	var trees: Array = [
		["oak.glb", 1.0],
		["elm.glb", 0.65],
		["acacia.glb", 1.15],
		["bloodwood.glb", 1.0],
	]
	var placed: Array = []
	var ft := 0

	# â”€â”€ Ãrboles grandes: 36 en zona media (z 55..130, separaciÃ³n 22 m) â”€â”€
	for _i in 36:
		var p := _scatter_place(placed, -140.0, 140.0, 55.0, 130.0, 22.0, 26.0, 115.0)
		var tdef: Array = trees[ft % trees.size()]
		var sc: float = float(tdef[1]) * randf_range(0.85, 1.25)
		_place_asset(world, tpath + str(tdef[0]), Vector3(p.x, 0.04, p.y), sc, randf_range(0, PI * 2))
		ft += 1
	# â”€â”€ Ãrbos lejanos: 12 en zona profunda (z 140..190, mÃ¡s grandes, flancos) â”€â”€
	for _i in 12:
		var p := _scatter_place(placed, -150.0, 150.0, 140.0, 190.0, 26.0, 60.0, 195.0)
		var tdef2: Array = trees[ft % trees.size()]
		_place_asset(world, tpath + str(tdef2[0]), Vector3(p.x, 0.04, p.y), float(tdef2[1]) * randf_range(1.3, 1.9), randf_range(0, PI * 2))
		ft += 1
	# â”€â”€ Bloodwood oscuro: 4, esparcidos (reemplaza a los Ã¡rboles muertos) â”€â”€
	for _i in 4:
		var p := _scatter_place(placed, -130.0, 130.0, 70.0, 170.0, 20.0, 24.0, 120.0)
		_place_asset(world, tpath + "bloodwood.glb", Vector3(p.x, 0.04, p.y), randf_range(0.9, 1.2), randf_range(0, PI * 2))
	# â”€â”€ Palmeras tropicales: 10 junto a la transiciÃ³n playa/bosque â”€â”€
	for _i in 10:
		var px2 := randf_range(-90.0, 90.0)
		if absf(px2) < 18.0:
			px2 = 20.0 if px2 >= 0.0 else -20.0
		var pz2 := randf_range(24.0, 48.0)
		_place_asset(world, tpath + ("coconut_palm.glb" if randf() < 0.5 else "queen_palm.glb"), Vector3(px2, 0.0, pz2), (0.5 if randf() < 0.5 else 0.95) * randf_range(0.85, 1.15), randf_range(0, PI * 2))
	# â”€â”€ Sub-bosque (reducido y repartido) â”€â”€
	var small: Array = []
	# Arbustos: 22
	for _i in 22:
		var p := _scatter_place(small, -130.0, 130.0, 60.0, 175.0, 14.0, 18.0, 120.0)
		_place_asset(world, npath + ("Bush_Common_Flowers.gltf" if randf() < 0.25 else "Bush_Common.gltf"), Vector3(p.x, 0.04, p.y), randf_range(0.7, 1.5), randf_range(0, PI * 2))
	# Helechos: 28
	for _i in 28:
		var p := _scatter_place(small, -130.0, 130.0, 58.0, 170.0, 12.0, 16.0, 120.0)
		_place_asset(world, npath + "Fern_1.gltf", Vector3(p.x, 0.04, p.y), randf_range(0.8, 1.6), randf_range(0, PI * 2))
	# Pasto: 55
	for _i in 55:
		var p := _scatter_place(small, -135.0, 135.0, 56.0, 175.0, 9.0, 14.0, 120.0)
		var gname: String
		match randi() % 4:
			0: gname = "Grass_Common_Tall.gltf"
			1: gname = "Grass_Common_Short.gltf"
			2: gname = "Grass_Wispy_Tall.gltf"
			_: gname = "Grass_Wispy_Short.gltf"
		_place_asset(world, npath + gname, Vector3(p.x, 0.04, p.y), randf_range(0.6, 1.4), randf_range(0, PI * 2))
	# Plantas: 14
	for _i in 14:
		var p := _scatter_place(small, -120.0, 120.0, 60.0, 165.0, 12.0, 16.0, 120.0)
		var pname: String
		match randi() % 4:
			0: pname = "Plant_1_Big.gltf"
			1: pname = "Plant_1.gltf"
			2: pname = "Plant_7_Big.gltf"
			_: pname = "Plant_7.gltf"
		_place_asset(world, npath + pname, Vector3(p.x, 0.04, p.y), randf_range(0.6, 1.2), randf_range(0, PI * 2))
	# TrÃ©bol: 18
	for _i in 18:
		var p := _scatter_place(small, -120.0, 120.0, 60.0, 165.0, 11.0, 14.0, 120.0)
		_place_asset(world, npath + ("Clover_1.gltf" if randf() < 0.5 else "Clover_2.gltf"), Vector3(p.x, 0.04, p.y), randf_range(0.5, 1.0), randf_range(0, PI * 2))
	# Flores: 8
	for _i in 8:
		var p := _scatter_place(small, -110.0, 110.0, 60.0, 140.0, 12.0, 14.0, 120.0)
		_place_asset(world, npath + ("Flower_4_Group.gltf" if randf() < 0.5 else "Flower_3_Group.gltf"), Vector3(p.x, 0.04, p.y), randf_range(0.5, 1.0), randf_range(0, PI * 2))
	# Hongos: 5
	for _i in 5:
		var p := _scatter_place(small, -100.0, 100.0, 62.0, 140.0, 14.0, 12.0, 120.0)
		_place_asset(world, npath + ("Mushroom_Common.gltf" if randf() < 0.5 else "Mushroom_Laetiporus.gltf"), Vector3(p.x, 0.04, p.y), randf_range(0.6, 1.1), randf_range(0, PI * 2))
	# Forest edge bushes at the beach transition (sides only)
	for i in 8:
		var fx := 25.0 + i * 13.0
		_place_asset(world, npath + "Bush_Common.gltf", Vector3(fx, 0.0, randf_range(27, 34)), randf_range(1.0, 1.8), randf_range(0, PI * 2))
		_place_asset(world, npath + "Bush_Common.gltf", Vector3(-fx, 0.0, randf_range(27, 34)), randf_range(1.0, 1.8), randf_range(0, PI * 2))

	# Nubes: las aporta Sky3D (procedurales en el cielo); los elipsoides viejos se eliminaron

func _create_warship(pos: Vector3, target_len: float, rot_y: float, ship_idx: int) -> Node3D:
	# Buques de guerra realistas (GLB): eje largo hacia Z, escala = target_len
	var g := Node3D.new()
	g.position = pos
	var holder := Node3D.new()
	g.add_child(holder)
	var path := "res://assets/vehicles/ship_a.glb" if ship_idx % 2 == 0 else "res://assets/vehicles/ship_b.glb"
	var model: Node3D = load(path).instantiate()
	holder.add_child(model)
	var bb := _world_aabb(holder)
	if bb.size.x > bb.size.z:
		model.rotation.y = -PI / 2.0
		bb = _world_aabb(holder)
	var big: float = bb.size.x
	if bb.size.z > big: big = bb.size.z
	var s: float = target_len / big if big > 0.0 else 1.0
	model.position = -bb.get_center()
	holder.scale = Vector3.ONE * s
	# Flotante: quilla 0.9 m bajo la lÃ­nea de agua (y=-0.35), el casco queda arriba
	holder.position = Vector3(0.0, bb.size.y * 0.5 * s - 0.9, 0.0)
	holder.rotation.y = rot_y
	return g
func _create_bunker() -> Node3D:
	var g := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.44, 0.38)
	mat.roughness = 0.85
	# Base
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8, 2.5, 5)
	base.mesh = bm
	base.material_override = mat
	base.position = Vector3(0, 1.25, 6)
	g.add_child(base)
	# Top
	var top := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 1.5
	tm.bottom_radius = 2
	tm.height = 1.8
	top.mesh = tm
	top.material_override = mat
	top.position = Vector3(0, 3.6, 6)
	g.add_child(top)
	# Sandbags
	var bag_mat := StandardMaterial3D.new()
	bag_mat.albedo_color = Color(0.55, 0.5, 0.35)
	bag_mat.roughness = 1.0
	for row in 2:
		for i in range(-3, 4):
			var bag := MeshInstance3D.new()
			var bagm := SphereMesh.new()
			bagm.radius = 0.35
			bagm.height = 0.7
			bag.mesh = bagm
			bag.material_override = bag_mat
			bag.position = Vector3(i * 0.75, 0.25 + row * 0.3, 1.5 + row * 0.3)
			bag.scale.z = 1.4
			g.add_child(bag)
	return g

# â”€â”€â”€ BASE FIRE (objetivo enemigo: el fuego FlameFX crece con el daÃ±o de la base) â”€â”€â”€
func _build_base_fire() -> void:
	# El mundo se reconstruye en cada partida (_start_net_local libera los hijos de world,
	# incluidos los emitters anteriores). Sin este clear, el array guarda referencias
	# ya liberadas y _apply_base_fire_stage llama sobre nodos muertos (error GDScript).
	base_fire_emitters.clear()
	base_smoke_emitters.clear()
	base_fire_group = Node3D.new()
	base_fire_group.name = "BaseFire"
	world.add_child(base_fire_group)
	var fire_scene: PackedScene = load("res://assets/BinbunVFX_Vol2/FlameFX/effects/fire/vfx_basic_fire_01.tscn")
	var fire_spots := [Vector3(-18, 2.5, 55), Vector3(20, 2.5, 60), Vector3(0, 2.5, 68), Vector3(8, 3.5, 43)]
	for i in fire_spots.size():
		var f: Node3D
		if fire_scene != null:
			f = fire_scene.instantiate()
		else:
			f = _make_fire_emitter()
		f.position = fire_spots[i]
		base_fire_emitters.append(f)
		base_fire_group.add_child(f)
		_set_fire_emitter_on(f, false, 0.0)
	var smoke_spots := [Vector3(-18, 7, 55), Vector3(20, 7, 60), Vector3(0, 7, 68)]
	for i in smoke_spots.size():
		var s := _make_smoke_emitter(smoke_spots[i])
		base_smoke_emitters.append(s)
		base_fire_group.add_child(s)

# Control de un emisor de fuego (FlameFX o fallback): visibilidad + emision + luz + escala
func _set_fire_emitter_on(f: Node3D, on: bool, scale_f: float) -> void:
	f.visible = on
	if not on:
		return
	var parts: GPUParticles3D = f.get_node_or_null("Particles") as GPUParticles3D
	if parts != null:
		parts.emitting = true
		parts.amount = int(24 + 40.0 * scale_f)
	var light: OmniLight3D = f.get_node_or_null("OmniLight3D") as OmniLight3D
	if light != null:
		light.light_energy = 6.0 * scale_f
	f.scale = Vector3.ONE * (0.7 + 0.8 * scale_f)

func _make_fire_emitter() -> Node3D:
	# Fallback procedural con la misma estructura (Particles + OmniLight3D)
	var root := Node3D.new()
	root.name = "FireFallback"
	var p := GPUParticles3D.new()
	p.name = "Particles"
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 10.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 4.5
	m.gravity = Vector3(0, 2.0, 0)
	m.scale_min = 1.6
	m.scale_max = 3.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.5))
	ramp.set_color(1, Color(0.9, 0.25, 0.05))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	m.color = Color(1.0, 0.5, 0.12)
	p.process_material = m
	p.amount = 24
	p.lifetime = 0.9
	p.emitting = false
	root.add_child(p)
	var li := OmniLight3D.new()
	li.name = "OmniLight3D"
	li.light_color = Color(1.0, 0.5, 0.2)
	li.light_energy = 0.0
	li.omni_range = 8.0
	root.add_child(li)
	return root

func _make_smoke_emitter(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 18.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 2.0
	m.gravity = Vector3(0, 0.6, 0)
	m.scale_min = 3.0
	m.scale_max = 6.0
	m.color = Color(0.12, 0.12, 0.12, 0.55)
	p.process_material = m
	p.amount = 20
	p.lifetime = 2.2
	p.position = pos
	p.emitting = false
	return p

# % de vida restante de la base
func _base_hp_pct() -> float:
	return clampf(health / base_hp_max, 0.0, 1.0)

# Etapa 0=perfecto 1=leve 2=medio 3=alto(+explosiones)
func _base_stage() -> int:
	var pct := _base_hp_pct()
	if pct > 0.75:
		return 0
	if pct > 0.50:
		return 1
	if pct > 0.25:
		return 2
	return 3

func _apply_base_fire_stage(stage: int) -> void:
	base_fire_stage = stage
	var active := 0
	var scale_f := 0.0
	match stage:
		0:
			active = 0
		1:
			active = 1
			scale_f = 0.5   # fuego leve (75%)
		2:
			active = 2
			scale_f = 1.0   # fuego medio (50%)
		3:
			active = base_fire_emitters.size()
			scale_f = 1.8   # fuego alto (25%)
	for i in base_fire_emitters.size():
		var f: Node3D = base_fire_emitters[i]
		if not is_instance_valid(f):
			continue
		_set_fire_emitter_on(f, i < active, scale_f)
	for i in base_smoke_emitters.size():
		var s: GPUParticles3D = base_smoke_emitters[i]
		if not is_instance_valid(s):
			continue
		s.emitting = (active > 0 and i < active)

# ActualizaciÃ³n por frame: aplica etapa, explosiones recurrentes e icono
func _update_base_fire(delta: float) -> void:
	var stage := _base_stage()
	if stage != base_fire_stage:
		_apply_base_fire_stage(stage)
	# Fuego alto (25%) o base destruida: explosiones recurrentes
	if base_fire_stage >= 3 or base_destroying:
		base_explosion_timer -= delta
		if base_explosion_timer <= 0.0:
			_base_random_explosion()
			base_explosion_timer = randf_range(1.0, 2.4)
	_hud.update_base_icon()

func _base_random_explosion() -> void:
	if mp_role == 2:
		return  # cliente LAN: los booms de la base los manda el host por net_fx (evita duplicarlos)
	var pts := [Vector3(-18, 3, 55), Vector3(20, 3, 60), Vector3(0, 3, 68), Vector3(8, 4, 43), Vector3(-30, 3, 58), Vector3(30, 3, 62)]
	var pt: Vector3 = pts[randi() % pts.size()]
	_big_boom(pt + Vector3(0, 1, 0), 1.4, Color(1.0, 0.5, 0.15), true)

# DaÃ±o a la base (los enemigos la atacan, no al jugador)
func _damage_base(amount: float) -> void:
	if base_destroying:
		return
	if abl_shield_t > 0.0:
		return  # Escudo activo: bloquea todo daÃ±o a la base
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_base_destroyed()

# Secuencia final: explosiones recurrentes y luego game over
func _base_destroyed() -> void:
	if base_destroying:
		return
	base_destroying = true
	_apply_base_fire_stage(3)
	var pts := [Vector3(-18, 3, 55), Vector3(20, 3, 60), Vector3(0, 3, 68), Vector3(8, 4, 43)]
	var gen := game_generation
	for i in pts.size():
		var pt: Vector3 = pts[i]
		var tw := create_tween()
		tw.tween_interval(0.55 * float(i))
		tw.tween_callback(Callable(self, "_base_boom_gen").bind(gen, pt))
	var tw_end := create_tween()
	tw_end.tween_interval(0.55 * float(pts.size()) + 0.4)
	tw_end.tween_callback(Callable(self, "_gameover_gen").bind(gen))

func _base_boom_gen(gen: int, pt: Vector3) -> void:
	if gen != game_generation:
		return  # viene de una partida anterior: no explotar en la nueva
	_base_boom(pt)

func _gameover_gen(gen: int) -> void:
	if gen != game_generation:
		return  # la partida ya se reiniciÃ³: no pisar la nueva
	if split_mode and mp_role == 3:
		_split_gameover()
	elif mp_role == 1:
		_mp_gameover_host()
	else:
		_gameover()

func _spawn_base_fire(pos: Vector3) -> void:
	# Fuego FlameFX persistente sobre los restos de la base
	var sc: PackedScene = load("res://assets/BinbunVFX_Vol2/FlameFX/effects/fire/vfx_basic_fire_01.tscn")
	if sc == null:
		return
	var f: Node3D = sc.instantiate()
	f.add_to_group("BaseBoomFire")  # se limpia al reiniciar
	f.position = pos + Vector3(0, 0.5, 0)
	f.scale = Vector3.ONE * 1.6
	add_child(f)

func _base_boom(pt: Vector3) -> void:
	_big_boom(pt, 2.2, Color(1.0, 0.45, 0.12), true)
	_spawn_base_fire(pt)
	shake_amount = maxf(shake_amount, 1.0)

func _build_military_base() -> void:
	# â•â•â• MILITARY BASE (behind the player) â€” walled compound, guard towers, hangars, helipad â•â•â•
	var base_group := Node3D.new()
	base_group.name = "MilitaryBase"
	world.add_child(base_group)

	# â”€â”€ Materials â”€â”€
	# Concrete with procedural noise variation (breaks up the flat look)
	var cnoise := FastNoiseLite.new()
	cnoise.noise_type = FastNoiseLite.TYPE_PERLIN
	cnoise.frequency = 0.11
	cnoise.fractal_octaves = 5
	var ctex := NoiseTexture2D.new()
	ctex.noise = cnoise
	ctex.width = 256
	ctex.height = 256
	ctex.normalize = true
	var cramp := Gradient.new()
	cramp.set_color(0, Color(0.70, 0.72, 0.68))
	cramp.set_color(1, Color(1.06, 1.06, 1.03))
	ctex.color_ramp = cramp
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.48, 0.51, 0.48)
	concrete.albedo_texture = ctex
	concrete.roughness = 0.92
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.32, 0.35, 0.32)
	wall_mat.albedo_texture = ctex
	wall_mat.roughness = 0.88
	var asphalt_mat := StandardMaterial3D.new()
	asphalt_mat.albedo_color = Color(0.20, 0.21, 0.23)
	asphalt_mat.roughness = 0.95
	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.88, 0.88, 0.85)
	white_mat.roughness = 0.6
	var fabric_mat := StandardMaterial3D.new()
	fabric_mat.albedo_color = Color(0.45, 0.50, 0.33)
	fabric_mat.roughness = 0.95
	var dark_open_mat := StandardMaterial3D.new()
	dark_open_mat.albedo_color = Color(0.08, 0.08, 0.08)
	dark_open_mat.roughness = 1.0
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.55, 0.58, 0.62)
	metal_mat.metallic = 0.8
	metal_mat.roughness = 0.45
	metal_mat.albedo_texture = load("res://assets/textures/metal_panel_basecolor.jpg")
	metal_mat.normal_texture = load("res://assets/textures/metal_panel_normal.jpg")
	metal_mat.roughness_texture = load("res://assets/textures/metal_panel_roughness.jpg")
	metal_mat.uv1_scale = Vector3(2, 2, 1)
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.55, 0.42, 0.28)
	wood_mat.roughness = 0.85
	var sandbag_mat := StandardMaterial3D.new()
	sandbag_mat.albedo_color = Color(0.55, 0.5, 0.36)
	sandbag_mat.roughness = 1.0
	var tank_mat := StandardMaterial3D.new()
	tank_mat.albedo_color = Color(0.75, 0.78, 0.75)
	tank_mat.roughness = 0.5
	tank_mat.metallic = 0.3
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.35, 0.40, 0.38)
	roof_mat.metallic = 0.7
	roof_mat.roughness = 0.4
	roof_mat.albedo_texture = load("res://assets/textures/metal_hull_basecolor.jpg")
	roof_mat.normal_texture = load("res://assets/textures/metal_hull_normal.jpg")
	roof_mat.roughness_texture = load("res://assets/textures/metal_hull_roughness.jpg")
	roof_mat.uv1_scale = Vector3(2, 1, 1)
	var dark_box_mat := StandardMaterial3D.new()
	dark_box_mat.albedo_color = Color(0.22, 0.24, 0.24)
	dark_box_mat.roughness = 0.8
	var light_pole_mat := StandardMaterial3D.new()
	light_pole_mat.albedo_color = Color(0.25, 0.27, 0.28)
	light_pole_mat.metallic = 0.6
	light_pole_mat.roughness = 0.5

	# â”€â”€ Helpers â”€â”€
	var _box = func(parent: Node, sz: Vector3, pos: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = sz
		mi.mesh = m
		mi.material_override = mat
		mi.position = pos
		mi.rotation.y = rot_y
		parent.add_child(mi)
		return mi
	var _cyl = func(parent: Node, rt: float, rb: float, h: float, pos: Vector3, mat: Material, radial: int = 12) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = rt
		m.bottom_radius = rb
		m.height = h
		m.radial_segments = radial
		mi.mesh = m
		mi.material_override = mat
		mi.position = pos
		parent.add_child(mi)
		return mi

	# â”€â”€ Asphalt pad â”€â”€
	_box.call(base_group, Vector3(88, 0.3, 34), Vector3(0, 0.15, 55), asphalt_mat)

	# â”€â”€ Perimeter wall (front at z=40, gate gap in the middle) â”€â”€
	_box.call(base_group, Vector3(40, 3.4, 1.2), Vector3(-24.5, 1.7, 40), wall_mat)
	_box.call(base_group, Vector3(40, 3.4, 1.2), Vector3(24.5, 1.7, 40), wall_mat)
	_box.call(base_group, Vector3(90, 3.4, 1.2), Vector3(0, 1.7, 70), wall_mat)
	_box.call(base_group, Vector3(1.2, 3.4, 30), Vector3(-44.5, 1.7, 55), wall_mat)
	_box.call(base_group, Vector3(1.2, 3.4, 30), Vector3(44.5, 1.7, 55), wall_mat)

	# â”€â”€ Gate (open bars + guard posts + guard booth) â”€â”€
	_box.call(base_group, Vector3(1.2, 4.2, 1.2), Vector3(-5, 2.1, 40), concrete)
	_box.call(base_group, Vector3(1.2, 4.2, 1.2), Vector3(5, 2.1, 40), concrete)
	var gate_l: MeshInstance3D = _box.call(base_group, Vector3(5.5, 0.25, 0.5), Vector3(-0.0, 1.1, 40), metal_mat, 0.5)
	gate_l.position = Vector3(-7.8, 1.1, 41.8)
	var gate_r: MeshInstance3D = _box.call(base_group, Vector3(5.5, 0.25, 0.5), Vector3(0.0, 1.1, 40), metal_mat, -0.5)
	gate_r.position = Vector3(7.8, 1.1, 41.8)
	# Guard booth
	_box.call(base_group, Vector3(3, 3, 3), Vector3(8.5, 1.5, 42.5), concrete)
	var booth_roof := MeshInstance3D.new()
	var brc := CylinderMesh.new()
	brc.top_radius = 0.05
	brc.bottom_radius = 2.6
	brc.height = 1.4
	brc.radial_segments = 4
	booth_roof.mesh = brc
	booth_roof.material_override = roof_mat
	booth_roof.position = Vector3(8.5, 4.2, 42.5)
	booth_roof.rotation.y = PI / 4
	base_group.add_child(booth_roof)

	# â”€â”€ Sandbags along the front wall â”€â”€
	var bag_row = func(z: float, x0: float, x1: float, step: float) -> void:
		var x := x0
		while x <= x1:
			var bag := MeshInstance3D.new()
			var bsm := SphereMesh.new()
			bsm.radius = 0.34
			bsm.height = 0.75
			bag.mesh = bsm
			bag.material_override = sandbag_mat
			bag.position = Vector3(x, 0.3, z)
			bag.scale = Vector3(1, 0.8, 1.5)
			base_group.add_child(bag)
			x += step
	bag_row.call(38.2, -42.0, -8.0, 0.85)
	bag_row.call(38.2, 8.0, 42.0, 0.85)

	# â”€â”€ Guard towers (4 corners) â”€â”€
	var tower = func(x: float, z: float) -> void:
		for lx in [-1.1, 1.1]:
			for lz in [-1.1, 1.1]:
				_cyl.call(base_group, 0.14, 0.18, 8.5, Vector3(x + lx, 4.25, z + lz), metal_mat, 8)
		for side in 4:
			var ang := side * PI / 2 + PI / 4
			var brace: MeshInstance3D = _box.call(base_group, Vector3(3.0, 0.12, 0.12), Vector3(x, 4.25, z), metal_mat, ang)
			brace.rotation.z = 0.5 if side < 2 else -0.5
		_box.call(base_group, Vector3(4, 0.3, 4), Vector3(x, 8.6, z), wood_mat)
		_box.call(base_group, Vector3(3.6, 2.0, 3.6), Vector3(x, 9.9, z), metal_mat)
		# railings
		for rx in [-1.75, 1.75]:
			for rz in [-1.75, 1.75]:
				_cyl.call(base_group, 0.05, 0.05, 0.8, Vector3(x + rx, 11.3, z + rz), metal_mat, 6)
		_box.call(base_group, Vector3(3.6, 0.1, 0.1), Vector3(x, 11.5, z - 1.75), metal_mat)
		_box.call(base_group, Vector3(3.6, 0.1, 0.1), Vector3(x, 11.5, z + 1.75), metal_mat)
		_box.call(base_group, Vector3(0.1, 0.1, 3.6), Vector3(x - 1.75, 11.5, z), metal_mat)
		_box.call(base_group, Vector3(0.1, 0.1, 3.6), Vector3(x + 1.75, 11.5, z), metal_mat)
		# Roof
		var roof := MeshInstance3D.new()
		var rcm := CylinderMesh.new()
		rcm.top_radius = 0.05
		rcm.bottom_radius = 3.1
		rcm.height = 1.5
		rcm.radial_segments = 4
		roof.mesh = rcm
		roof.material_override = roof_mat
		roof.position = Vector3(x, 11.65, z)
		roof.rotation.y = PI / 4
		base_group.add_child(roof)
	tower.call(-44.5, 40)
	tower.call(44.5, 40)
	tower.call(-44.5, 70)
	tower.call(44.5, 70)

	# â”€â”€ Helipad (center) â”€â”€
	_cyl.call(base_group, 6.5, 6.5, 0.4, Vector3(0, 0.5, 55), concrete, 32)
	var ring := MeshInstance3D.new()
	var ringm := TorusMesh.new()
	ringm.inner_radius = 5.0
	ringm.outer_radius = 5.8
	ring.mesh = ringm
	ring.material_override = white_mat
	ring.rotation.x = PI / 2
	ring.position = Vector3(0, 0.75, 55)
	base_group.add_child(ring)
	_box.call(base_group, Vector3(0.9, 0.1, 4.6), Vector3(-1.7, 0.78, 55), white_mat)
	_box.call(base_group, Vector3(0.9, 0.1, 4.6), Vector3(1.7, 0.78, 55), white_mat)
	_box.call(base_group, Vector3(4.4, 0.1, 0.9), Vector3(0, 0.78, 55), white_mat)
	# Hedge lights around the helipad
	for i in 8:
		var a := i * PI / 4
		var light := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.12
		light.mesh = lm
		var lm2 := StandardMaterial3D.new()
		lm2.albedo_color = Color(1.5, 1.5, 1.2)
		lm2.emission_enabled = true
		lm2.emission = Color(0.8, 0.8, 0.5)
		light.material_override = lm2
		light.position = Vector3(cos(a) * 6.2, 0.9, 55 + sin(a) * 6.2)
		base_group.add_child(light)

	# â”€â”€ Arched hangars (NATO tents) â”€â”€
	var hangar = func(x: float, z: float, rot_y: float) -> void:
		var holder := Node3D.new()
		holder.position = Vector3(x, 0.3, z)
		holder.rotation.y = rot_y
		base_group.add_child(holder)
		var arch := MeshInstance3D.new()
		var asm := SphereMesh.new()
		asm.radius = 3.6
		asm.height = 3.6
		asm.radial_segments = 20
		asm.rings = 8
		arch.mesh = asm
		arch.material_override = fabric_mat
		arch.position = Vector3(0, 0.1, 0)
		arch.scale = Vector3(1.0, 0.85, 1.5)
		holder.add_child(arch)
		_box.call(holder, Vector3(3.4, 2.6, 0.4), Vector3(0, 1.3, 5.2), dark_open_mat)
		# Frame ribs
		for rz in [-4.0, -2.0, 0.0, 2.0, 4.0]:
			var rib := MeshInstance3D.new()
			var rim := TorusMesh.new()
			rim.inner_radius = 3.3
			rim.outer_radius = 3.6
			rib.mesh = rim
			rib.material_override = fabric_mat
			rib.position = Vector3(0, 0.1, rz)
			rib.rotation.z = PI / 2
			rib.scale = Vector3(0.85, 1, 1)
			holder.add_child(rib)
	hangar.call(-28, 48, 0.0)
	hangar.call(-28, 62, 0.0)
	hangar.call(28, 48, 0.0)
	hangar.call(28, 62, 0.0)

	# â”€â”€ HQ building (right back) â”€â”€
	_box.call(base_group, Vector3(14, 5, 9), Vector3(12, 2.5, 63), concrete)
	_box.call(base_group, Vector3(15, 0.4, 10), Vector3(12, 5.2, 63), roof_mat)
	_cyl.call(base_group, 0.06, 0.1, 3, Vector3(17, 6.9, 63), metal_mat, 8)
	var ant := MeshInstance3D.new()
	var antm := SphereMesh.new()
	antm.radius = 0.25
	ant.mesh = antm
	ant.material_override = metal_mat
	ant.position = Vector3(17, 8.5, 63)
	base_group.add_child(ant)
	# Rooftop details: AC condensers + roof access + water tank
	_box.call(base_group, Vector3(1.5, 1.0, 1.5), Vector3(8, 5.8, 64.5), metal_mat)
	_box.call(base_group, Vector3(1.5, 1.0, 1.5), Vector3(10.5, 5.8, 61.5), metal_mat)
	_box.call(base_group, Vector3(2.2, 1.9, 2.2), Vector3(16, 6.2, 65.5), concrete)
	_cyl.call(base_group, 1.0, 1.0, 1.0, Vector3(16, 7.6, 65.5), tank_mat, 12)
	# Door + windows
	_box.call(base_group, Vector3(2, 2.6, 0.3), Vector3(12, 1.3, 58.4), dark_box_mat)
	_box.call(base_group, Vector3(1.6, 1.2, 0.3), Vector3(6, 3.2, 58.4), dark_box_mat)
	_box.call(base_group, Vector3(1.6, 1.2, 0.3), Vector3(12, 3.2, 58.4), dark_box_mat)
	_box.call(base_group, Vector3(1.6, 1.2, 0.3), Vector3(18, 3.2, 58.4), dark_box_mat)

	# â”€â”€ Barracks (left back) â”€â”€
	_box.call(base_group, Vector3(13, 4.5, 8), Vector3(-13, 2.25, 64), concrete)
	_box.call(base_group, Vector3(14, 0.4, 9), Vector3(-13, 4.7, 64), roof_mat)
	_box.call(base_group, Vector3(1.8, 2.4, 0.3), Vector3(-13, 1.2, 60.2), dark_box_mat)
	_box.call(base_group, Vector3(1.4, 1.1, 0.3), Vector3(-18, 2.9, 60.2), dark_box_mat)
	_box.call(base_group, Vector3(1.4, 1.1, 0.3), Vector3(-13, 2.9, 60.2), dark_box_mat)
	_box.call(base_group, Vector3(1.4, 1.1, 0.3), Vector3(-8, 2.9, 60.2), dark_box_mat)

	# â”€â”€ Water tower (left front) â”€â”€
	for lx in [-0.9, 0.9]:
		for lz in [-0.9, 0.9]:
			_cyl.call(base_group, 0.12, 0.15, 7, Vector3(-32 + lx, 3.5, 47 + lz), metal_mat, 8)
	_cyl.call(base_group, 2.2, 2.2, 2.8, Vector3(-32, 8.4, 47), tank_mat, 16)
	var wtdome := MeshInstance3D.new()
	var wtm := SphereMesh.new()
	wtm.radius = 2.2
	wtm.height = 2.2
	wtdome.mesh = wtm
	wtdome.material_override = tank_mat
	wtdome.position = Vector3(-32, 9.8, 47)
	wtdome.scale = Vector3(1, 0.5, 1)
	base_group.add_child(wtdome)

	# â”€â”€ Fuel storage depot (large cylindrical tanks + gantry) â”€â”€
	var fuel_mat := StandardMaterial3D.new()
	fuel_mat.albedo_color = Color(0.52, 0.30, 0.24)
	fuel_mat.metallic = 0.55
	fuel_mat.roughness = 0.5
	var fuel_tank = func(x: float, z: float, r: float, h: float) -> void:
		_cyl.call(base_group, r, r, h, Vector3(x, h / 2 + 0.3, z), fuel_mat, 20)
		var cap := MeshInstance3D.new()
		var capm := SphereMesh.new()
		capm.radius = r
		capm.height = r
		cap.mesh = capm
		cap.material_override = fuel_mat
		cap.position = Vector3(x, h + 0.3, z)
		cap.scale = Vector3(1, 0.45, 1)
		base_group.add_child(cap)
		_cyl.call(base_group, r + 0.15, r + 0.25, 0.5, Vector3(x, 0.55, z), concrete, 20)
	fuel_tank.call(-24, 65, 2.5, 5.2)
	fuel_tank.call(-17, 67, 2.1, 4.4)
	_box.call(base_group, Vector3(7, 0.3, 0.3), Vector3(-20.5, 5.6, 66), metal_mat)
	_cyl.call(base_group, 0.14, 0.14, 3.5, Vector3(-20.5, 3.5, 66), metal_mat, 6)

	# â”€â”€ Radar dish on a tower (iconic military element) â”€â”€
	var radar_mat := StandardMaterial3D.new()
	radar_mat.albedo_color = Color(0.80, 0.82, 0.80)
	radar_mat.metallic = 0.5
	radar_mat.roughness = 0.45
	_cyl.call(base_group, 0.45, 0.65, 7.5, Vector3(36, 3.75, 63), radar_mat, 8)
	var dish := MeshInstance3D.new()
	var dishm := SphereMesh.new()
	dishm.radius = 2.0
	dishm.height = 1.2
	dish.mesh = dishm
	dish.material_override = radar_mat
	dish.position = Vector3(36, 8.2, 63)
	dish.scale = Vector3(1.25, 0.7, 1.25)
	dish.rotation.x = -0.55
	dish.rotation.z = 0.5
	base_group.add_child(dish)
	_cyl.call(base_group, 0.05, 0.05, 1.6, Vector3(36, 8.2, 63), radar_mat, 6)

	# â”€â”€ Flag pole near the gate â”€â”€
	_cyl.call(base_group, 0.07, 0.11, 11.5, Vector3(-3, 5.75, 45), metal_mat, 6)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.18, 0.34, 0.55)
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag_mat.roughness = 0.9
	var flag := MeshInstance3D.new()
	var flagm := PlaneMesh.new()
	flagm.size = Vector2(2.8, 1.7)
	flag.mesh = flagm
	flag.material_override = flag_mat
	flag.position = Vector3(-1.55, 10.4, 45)
	base_group.add_child(flag)

	# â”€â”€ Front bunker emplacements (concrete mounds + gun ports, flanking the gate) â”€â”€
	var bunker = func(x: float, z: float) -> void:
		var mound := MeshInstance3D.new()
		var mm := SphereMesh.new()
		mm.radius = 2.4
		mm.height = 2.4
		mound.mesh = mm
		mound.material_override = concrete
		mound.position = Vector3(x, 0.5, z)
		mound.scale = Vector3(1.1, 0.65, 1.25)
		base_group.add_child(mound)
		_box.call(base_group, Vector3(1.7, 1.0, 0.4), Vector3(x, 0.95, z - 1.7), dark_open_mat)
		bag_row.call(z - 2.1, x - 2.6, x + 2.6, 0.8)
	bunker.call(-20, 44)
	bunker.call(20, 44)

	# â”€â”€ Supply area: crates, barrels, containers â”€â”€
	var crate = func(x: float, z: float, s: float, rot: float) -> void:
		_box.call(base_group, Vector3(s, s, s), Vector3(x, s / 2 + 0.3, z), wood_mat, rot)
	crate.call(33, 54, 1.1, 0.2)
	crate.call(35, 55.5, 0.9, -0.3)
	crate.call(34, 57.5, 1.0, 0.7)
	crate.call(36.5, 54, 0.8, 0.1)
	_cyl.call(base_group, 0.35, 0.35, 1.1, Vector3(38.5, 0.85, 56), metal_mat, 10)
	_cyl.call(base_group, 0.35, 0.35, 1.1, Vector3(39.3, 0.85, 54.5), metal_mat, 10)
	# Container
	_box.call(base_group, Vector3(6, 2.4, 2.6), Vector3(-38, 1.5, 58), dark_box_mat)
	_box.call(base_group, Vector3(6.2, 2.5, 2.7), Vector3(-38, 1.5, 62), concrete)
	# Fuel drums
	_cyl.call(base_group, 0.4, 0.4, 1.2, Vector3(20, 0.9, 46), dark_box_mat, 10)
	_cyl.call(base_group, 0.4, 0.4, 1.2, Vector3(21.2, 0.9, 47.2), metal_mat, 10)

	# â”€â”€ Light poles (4) â”€â”€
	var light_pole = func(x: float, z: float) -> void:
		_cyl.call(base_group, 0.08, 0.12, 6, Vector3(x, 3, z), light_pole_mat, 8)
		_box.call(base_group, Vector3(1.0, 0.3, 0.4), Vector3(x, 6, z), light_pole_mat)
		var lamp := MeshInstance3D.new()
		var lpm := SphereMesh.new()
		lpm.radius = 0.18
		lamp.mesh = lpm
		var lpm2 := StandardMaterial3D.new()
		lpm2.albedo_color = Color(1.6, 1.6, 1.3)
		lpm2.emission_enabled = true
		lpm2.emission = Color(0.9, 0.9, 0.6)
		lamp.material_override = lpm2
		lamp.position = Vector3(x, 5.85, z)
		base_group.add_child(lamp)
	light_pole.call(-38, 42)
	light_pole.call(38, 42)
	light_pole.call(-38, 68)
	light_pole.call(38, 68)

	# â”€â”€ Reused asset props â”€â”€
	_place_asset(base_group, "res://assets/models/Security Light/1k/security_light_1k.gltf", Vector3(-24, 0, 43), 1.0, 0.0)
	_place_asset(base_group, "res://assets/models/Security Light/1k/security_light_1k.gltf", Vector3(24, 0, 43), 1.0, 0.0)
	_place_asset(base_group, "res://assets/models/Propane Tank/1k/propane_tank_1k.gltf", Vector3(24, 0, 66), 0.8, 0.0)
	_place_asset(base_group, "res://assets/models/Propane Tank/1k/propane_tank_1k.gltf", Vector3(26, 0, 66), 0.8, 0.3)
	_place_asset(base_group, "res://assets/models/Industrial Storage Cart/1k/industrial_storage_cart_1k.gltf", Vector3(-22, 0.3, 55), 0.9, 0.1)

func _place_asset(parent: Node3D, path: String, pos: Vector3, sc: float, rot_y: float) -> void:
	var scene: PackedScene = load(path)
	if scene:
		var node: Node3D = scene.instantiate()
		node.position = pos
		node.scale = Vector3.ONE * sc
		node.rotation.y = rot_y
		parent.add_child(node)

func _create_coast_rock(pos: Vector3, sc: float, rot_y: float) -> Node3D:
	var scene: PackedScene = load("res://assets/pbr/coast_rocks_model/coast_rocks_03_2k.gltf")
	if scene == null:
		return null
	var node: Node3D = scene.instantiate()
	node.position = pos
	node.scale = Vector3.ONE * sc
	node.rotation.y = rot_y
	return node

# â”€â”€â”€ CAMERA â”€â”€â”€
func _build_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 5, 0)
	camera.fov = 65
	add_child(camera)
	# Build gun viewmodel attached to camera
	var gun := _build_gun_viewmodel()
	camera.add_child(gun)

# â”€â”€â”€ AUDIO â”€â”€â”€
var audio_players: Array = []
var sfx_base_db: Array = []          # volumen base de cada audio_players[] (para atenuar sin acumular)
var sfx_playing_dist: Array = []     # metros del sonido que hoy ocupa cada audio_players[] (-1 = libre)
var pain_base_db := -3.0             # volumen base de las voces de dolor
var explosion_base_db := 0.0         # volumen base de explosion_sfx
const NET_SFX_RANGE := 170.0         # alcance de un SFX remoto atenuado (metros)
var explosion_sfx: AudioStreamPlayer = null   # gran boom realista (arma3, minas, vehÃ­culos)
var missile_sfx: AudioStreamPlayer = null     # silbato de caÃ­da + explosiÃ³n (artillerÃ­a / misil)
var soldier_pain_players: Array = []  # voces humanas de dolor (Mixkit, licencia free)
const SFX_PACK := "res://Sound FX Starter Pack Vol. 1"

func _load_sfx(rel: String) -> AudioStream:
	var path := SFX_PACK + "/" + rel
	var s: AudioStream = load(path)
	if s == null:
		push_warning("SFX not found: " + path)
	return s

func _make_ui(rel: String, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _load_sfx(rel)
	p.volume_db = vol
	add_child(p)
	return p

func _toggle_music() -> void:
	music_enabled = !music_enabled
	if music_enabled:
		music_player.play()
		if ui_select:
			ui_select.play()
	else:
		music_player.stop()
		if ui_quit:
			ui_quit.play()
	if music_label:
		music_label.text = _music_lbl_text()
	if music_label_p1:
		music_label_p1.text = _music_lbl_text()
	_save_settings()
func _build_audio() -> void:
	# Volumen BASE de cada SFX: el cliente LAN los reproduce atenuados por distancia
	# (ver _net_sfx_db), asÃ­ que siempre se juega desde este valor, nunca acumulado.
	sfx_base_db = []
	pain_base_db = -3.0
	explosion_base_db = 0.0
	# Pistol: short, sharp, high crack
	var ap1 := AudioStreamPlayer.new()
	ap1.stream = _load_sfx("Hollywood/Titan Handgun.wav")  # pistol
	ap1.volume_db = -4.0
	sfx_base_db.append(ap1.volume_db)
	add_child(ap1)
	audio_players.append(ap1)
	# SMG: medium, punchy
	var ap2 := AudioStreamPlayer.new()
	ap2.stream = _load_sfx("Sci-Fi/Pulse Sniper.wav")  # SMG
	ap2.volume_db = -3.0
	sfx_base_db.append(ap2.volume_db)
	add_child(ap2)
	audio_players.append(ap2)
	# Cannon: long, deep, heavy boom
	var ap3 := AudioStreamPlayer.new()
	ap3.stream = _load_sfx("Hollywood/Mega Bomb.wav")  # cannon
	ap3.volume_db = -2.0
	sfx_base_db.append(ap3.volume_db)
	add_child(ap3)
	audio_players.append(ap3)
	# Explosion: gran boom realista (SoundJay, royalty-free)
	var ap4 := AudioStreamPlayer.new()
	var exp_stream: AudioStream = load("res://assets/sfx/explosion_big.wav")
	if exp_stream == null:
		exp_stream = _load_sfx("Motions and Impacts/Impact Redwood.wav")
	ap4.stream = exp_stream
	ap4.volume_db = 0.0
	explosion_base_db = ap4.volume_db
	sfx_base_db.append(ap4.volume_db)
	add_child(ap4)
	audio_players.append(ap4)
	explosion_sfx = ap4
	# Misil / artillerÃ­a: silbato de caÃ­da + explosiÃ³n (SoundJay, royalty-free)
	var ap5 := AudioStreamPlayer.new()
	var mis_stream: AudioStream = load("res://assets/sfx/missile_bomb.wav")
	if mis_stream == null:
		mis_stream = _load_sfx("Hollywood/Mega Bomb.wav")
	ap5.stream = mis_stream
	ap5.volume_db = -2.0
	sfx_base_db.append(ap5.volume_db)
	add_child(ap5)
	audio_players.append(ap5)
	missile_sfx = ap5
	# Soldier pain: voces humanas reales (3 variantes para superposiciÃ³n y variedad)
	var pain_files := [
		"res://assets/sfx/soldier_pain_man.wav",
		"res://assets/sfx/soldier_pain_ow.wav",
		"res://assets/sfx/soldier_pain_scream.wav",
	]
	for pf in pain_files:
		var st_pain: AudioStream = load(pf)
		if st_pain == null:
			push_warning("Soldier pain SFX no encontrado: " + pf)
			continue
		var pp := AudioStreamPlayer.new()
		pp.stream = st_pain
		pp.volume_db = pain_base_db
		add_child(pp)
		soldier_pain_players.append(pp)
	# â”€â”€ Background music (ocean ambience loop) â”€â”€
	music_player = AudioStreamPlayer.new()
	var mstream: AudioStream = _load_sfx("Environment/Ocean Loop.wav")
	music_player.stream = mstream
	if mstream is AudioStreamWAV:
		mstream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		mstream.loop_end = -1
	# Ocean Loop is a quiet ambience file (peak ~ -14 dBFS); boost it so it's audible as background (~ -6 dBFS)
	music_player.volume_db = 8.0
	add_child(music_player)
	# â”€â”€ UI sounds â”€â”€
	ui_select = _make_ui("UI & Menus/Select.wav", -8.0)
	ui_start = _make_ui("UI & Menus/Start.wav", -6.0)
	ui_quit = _make_ui("UI & Menus/Quit Out.wav", -8.0)
	ui_gameover = _make_ui("Jingles & Stingers/Game Over.wav", -6.0)
	ui_levelup = _make_ui("Jingles & Stingers/Load In.wav", -8.0)
	# Un -1 por cada audio_players: ningÃºn sonido ocupando su reproductor (ver _play_net_sfx)
	sfx_playing_dist = []
	for ap in audio_players:
		sfx_playing_dist.append(-1.0)

# â”€â”€â”€ GUN VIEWMODEL â”€â”€â”€
func _build_gun_viewmodel() -> Node3D:
	var gun := Node3D.new()
	gun.name = "Gun"
	# â”€â”€ Arma 1 (Suomi, centrada, semi-auto) â”€â”€
	# Solo caÃ±Ã³n: ocultamos cargador y piezas pequeÃ±as (se veÃ­an feas en pantalla).
	var SMG_OSCURAR := ["Magazine", "MagazineRelease", "Trigger", "Bolt", "Ejector"]
	var w0 := _fit_weapon("res://assets/guns2/smg.glb", "W_Pistol", Vector3(0.0, -0.17, -0.42), 0.72, 0.0, SMG_OSCURAR)
	w0.rotation.y = 0.0
	gun.add_child(w0)
	# â”€â”€ Arma 2 (Suomi doble: ametralladora de doble caÃ±Ã³n) â”€â”€
	# Dos armas SIMÃ‰TRICAS (posiciÃ³n Â±offset + rotaciÃ³n Y Â±tilt) para que AMBAS
	# muestren la misma cara (lado del aro) y converjan en V hacia el centro,
	# como una ametralladora de doble caÃ±Ã³n. Ref: probe_shots/w2_off0.10_tilt0.30.
	# El caÃ±Ã³n izquierdo va un poco mÃ¡s afuera (-0.17) para balancear la vista en pantalla.
	# NOTA: usamos SOLO rotaciones (NUNCA scale negativa) â†’ seguro con duplicate(true)
	# en el split (la scale negativa corrumpÃ­a a -1,-1,-1; verificado en test_split.gd).
	var dual := Node3D.new()
	dual.name = "W_SMG"
	var w1r := _fit_weapon("res://assets/guns2/smg.glb", "SMG_Right", Vector3(0.10, -0.18, -0.4), 0.72, 0.0, SMG_OSCURAR)
	w1r.rotation.y = 0.30
	dual.add_child(w1r)
	var w1l := _fit_weapon("res://assets/guns2/smg.glb", "SMG_Left", Vector3(-0.17, -0.18, -0.4), 0.72, 0.0, SMG_OSCURAR)
	w1l.rotation.y = -0.30
	dual.add_child(w1l)
	_fix_cull(dual)
	dual.visible = false
	gun.add_child(dual)
	# â”€â”€ CaÃ±Ã³n (caÃ±onera naval, caÃ±Ã³n largo hacia adelante) â”€â”€
	var w2 := _build_cannon_viewmodel()
	w2.visible = false
	gun.add_child(w2)
	# â”€â”€ MUZZLE FLASH (shared) â”€â”€
	var flash := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.04
	fm.height = 0.08
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1, 0.9, 0.3)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1, 0.8, 0.2)
	flash_mat.emission_energy_multiplier = 6.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.albedo_color = Color(1, 0.9, 0.3, 0.9)
	flash.mesh = fm
	flash.material_override = flash_mat
	flash.position = Vector3(0.17, -0.14, -0.85)
	flash.visible = false
	flash.name = "MuzzleFlash"
	gun.add_child(flash)
	return gun

# â”€â”€â”€ VIEWMODEL FIT HELPERS (delegado en WorldMath) â”€â”€â”€
func _xform_aabb(bb: AABB, t: Transform3D) -> AABB:
	return WorldMath.xform_aabb(bb, t)

func _combined_aabb(root: Node3D, base: Transform3D) -> AABB:
	return WorldMath.combined_aabb(root, base)

func _world_aabb(root: Node3D) -> AABB:
	return WorldMath.world_aabb(root)

func _fit_weapon(path: String, wname: String, target_pos: Vector3, scale_f: float, rot_y: float = 0.0, hide_parts: Array = []) -> Node3D:
	var holder := Node3D.new()
	holder.name = wname
	var ps: PackedScene = load(path)
	var model: Node3D = ps.instantiate()
	model.rotation.y = rot_y
	var bb := _combined_aabb(model, model.transform)
	model.position = -bb.position
	holder.add_child(model)
	holder.scale = Vector3(scale_f, scale_f, scale_f)
	holder.position = target_pos
	for hp in hide_parts:
		var n := model.find_child(hp, true, false)
		if n is Node3D:
			(n as Node3D).visible = false
	return holder

func _build_cannon_viewmodel() -> Node3D:
	# Arma 3: SMG (mismo modelo que arma 1) â€” centrada, perspectiva "caÃ±Ã³n desde arriba"
	var cannon := Node3D.new()
	cannon.name = "W_Cannon"
	var SMG_OSCURAR := ["Magazine", "MagazineRelease", "Trigger", "Bolt", "Ejector"]
	var holder := _fit_weapon("res://assets/guns2/smg.glb", "CannonBody", Vector3(0.0, -0.20, -0.55), 0.95, 0.0, SMG_OSCURAR)
	cannon.add_child(holder)
	return cannon

# Disable backface culling (fixes mirrored/negative-scale viewmodels)
func _fix_cull(root: Node) -> void:
	var done: Array = []
	_fix_cull_rec(root, done)

func _fix_cull_rec(root: Node, done: Array) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mats: Array = []
			if mi.material_override is StandardMaterial3D:
				mats.append(mi.material_override)
			elif mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var sm: Material = mi.mesh.surface_get_material(i)
					if sm is StandardMaterial3D:
						mats.append(sm)
			for m in mats:
				if not done.has(m):
					done.append(m)
					(m as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		elif child is Node:
			_fix_cull_rec(child, done)

# Brighten all standard materials under a node (multiplies albedo, once per material)
func _brighten_rec(root: Node, factor: float, done: Array) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mats: Array = []
			if mi.material_override is StandardMaterial3D:
				mats.append(mi.material_override)
			elif mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var sm: Material = mi.mesh.surface_get_material(i)
					if sm is StandardMaterial3D:
						mats.append(sm)
			for m in mats:
				if not done.has(m):
					done.append(m)
					(m as StandardMaterial3D).albedo_color = (m as StandardMaterial3D).albedo_color * factor
		elif child is Node:
			_brighten_rec(child, factor, done)

func _switch_weapon_visual() -> void:
	var gun := camera.get_node_or_null("Gun") as Node3D
	if not gun:
		return
	var w0 := gun.get_node_or_null("W_Pistol")
	var w1 := gun.get_node_or_null("W_SMG")
	var w2 := gun.get_node_or_null("W_Cannon")
	if w0: w0.visible = (current_weapon == 0)
	if w1: w1.visible = (current_weapon == 1)
	if w2: w2.visible = (current_weapon == 2)

# â”€â”€â”€ HUD: implementaciÃ³n en scripts/hud.gd (class_name HudUI) â”€â”€â”€
# main.gd sigue siendo dueÃ±o de hud (CanvasLayer), crosshair_layer y del estado que
# el HUD muestra; HudUI crea y actualiza sus nodos leyendo eso por app.*.
var _hud: HudUI = null

# â”€â”€â”€ NAVEGACIÃ“N DE MENÃšS CON JOYSTICK â”€â”€â”€
# Los botones de cada pantalla se registran en orden de creaciÃ³n (arriba â†’ abajo).
# D-pad â†‘â†“ (o stick izq, por frame) mueven el foco; A confirma el botÃ³n enfocado; B vuelve.
func _menu_nav_reset() -> void:
	if menu_nav_focused != null and is_instance_valid(menu_nav_focused):
		_menu_nav_restore(menu_nav_focused)
	menu_nav_focused = null
	menu_nav_buttons.clear()
	menu_nav_index = 0
	menu_nav_repeat_t = 0.0

func _menu_nav_step(p_dir: int, p_sfx: bool = true) -> void:
	if menu_nav_buttons.is_empty():
		return
	var n: int = menu_nav_buttons.size()
	menu_nav_index = (menu_nav_index + p_dir) % n
	if menu_nav_index < 0:
		menu_nav_index += n
	var target: Button = menu_nav_buttons[menu_nav_index]
	if menu_nav_focused != null and is_instance_valid(menu_nav_focused) and menu_nav_focused != target:
		_menu_nav_restore(menu_nav_focused)
	menu_nav_focused = target
	_menu_nav_apply_focus(target)
	if p_sfx and ui_select:
		ui_select.play()

func _menu_nav_confirm() -> bool:
	if menu_nav_buttons.is_empty():
		return false
	if menu_nav_focused == null or not is_instance_valid(menu_nav_focused):
		menu_nav_focused = null
		_menu_nav_step(0)
	if menu_nav_focused == null or not is_instance_valid(menu_nav_focused):
		return false
	menu_nav_focused.pressed.emit()
	return true

func _menu_nav_apply_focus(b: Button) -> void:
	if not b.get_meta("nav_saved", false):
		b.set_meta("nav_saved", true)
		b.set_meta("nav_style", b.get_theme_stylebox("normal"))
		b.set_meta("nav_font", b.get_theme_color("font_color"))
	var base_style: StyleBox = b.get_meta("nav_style")
	var sb: StyleBox = base_style.duplicate() if base_style != null else StyleBoxFlat.new()
	if sb is StyleBoxFlat:
		var f: StyleBoxFlat = sb
		f.border_color = Color(1.0, 0.75, 0.25, 1.0)
		f.set_border_width_all(4)
		f.set_corner_radius_all(8)
		f.bg_color = f.bg_color.lerp(Color(1.0, 0.8, 0.3, 1.0), 0.3)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color(1.0, 0.93, 0.55))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.93, 0.55))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.93, 0.55))
	# MenÃº de habilidades: mover el foco tambiÃ©n muestra la descripciÃ³n (del jugador dueÃ±o del botÃ³n)
	if b.has_meta("abl_key"):
		_show_abl_desc(str(b.get_meta("abl_key")), int(b.get_meta("abl_player", 0)))

func _menu_nav_restore(b: Button) -> void:
	if not b.get_meta("nav_saved", false):
		return
	b.add_theme_stylebox_override("normal", b.get_meta("nav_style"))
	b.remove_theme_stylebox_override("hover")
	b.remove_theme_stylebox_override("pressed")
	b.add_theme_color_override("font_color", b.get_meta("nav_font"))
	b.remove_theme_color_override("font_hover_color")
	b.remove_theme_color_override("font_pressed_color")

# Controles del menÃº de habilidades: tecla + botÃ³n de joystick siempre visibles (B / SEL por defecto)
func _dev_abl_key() -> String:
	return "%s / %s" % [_bind_name_k(_kb("abilities_menu")), _bind_name_j(_jb("abilities_menu"))]

# Controles de cada habilidad: tecla + botÃ³n de joystick (Q/LB, E/RB, R/D-PAD â†‘, ...)
func _abl_key_disp(k: String) -> String:
	var action: String = {
		"Q": "ability_rapid", "E": "ability_shield", "R": "ability_mines",
		"T": "ability_artillery", "F": "ability_overload", "G": "ability_repair",
	}.get(k, "ability_rapid")
	return "%s / %s" % [_bind_name_k(_kb(action)), _bind_name_j(_jb(action))]

# Controles de mÃºsica: tecla + botÃ³n de joystick (M / R3 por defecto)
func _dev_music_key() -> String:
	return "%s / %s" % [_bind_name_k(_kb("music")), _bind_name_j(_jb("music"))]

func _music_lbl_text() -> String:
	var on: String = "ON" if music_enabled else "OFF"
	return _tr("hud_music") % [on, _dev_music_key()]

func _abl_hint_text() -> String:
	if mp_role == 3:
		return _tr("abl_hint_joy") % [_dev_abl_key()]
	return _tr("abl_hint") % [_dev_abl_key(), _bind_name_j(_jb("confirm"))]

# â”€â”€â”€ HIGH SCORES (top 10, persistent en user://highscores.json) â”€â”€â”€
# Leer/escribir/sanear vive en scripts/save_data.gd (class_name SaveData).
func _load_highscores() -> void:
	var data: Dictionary = SaveData.load_highscores()
	highscores = data["single"]
	hs_mp = data["mp"]

func _save_highscores() -> void:
	SaveData.save_highscores(highscores, hs_mp)

# Top-10 de equipos por categorÃ­a (2/3/4). Devuelve la posiciÃ³n (1-based) o -1.
func _add_mp_highscore(n_players: int, p_score: int, p_wave: int, p_players: Array) -> int:
	var rank: int = SaveData.add_mp_highscore(hs_mp, n_players, p_score, p_wave, p_players)
	_save_highscores()
	return rank

func _qualifies_highscore() -> bool:
	return SaveData.qualifies(highscores, score)

func _add_highscore(p_score: int, p_initials: String, p_wave: int) -> int:
	var rank: int = SaveData.add_highscore(highscores, p_score, p_initials, p_wave)
	_save_highscores()
	return rank

# â”€â”€â”€ AJUSTES (settings.json): resoluciÃ³n + calidad + mÃºsica â”€â”€â”€
# El archivo lo lee/escribe save_data.gd; acÃ¡ se valida y se aplica al juego.
func _load_settings() -> void:
	key_binds = KEY_BINDS_DEFAULT.duplicate()
	joy_binds = JOY_BINDS_DEFAULT.duplicate()
	joy_trigger_axis = 5
	var parsed = SaveData.read_settings()
	if parsed is Dictionary:
		if parsed.has("resolution") and parsed["resolution"] is Array:
			var r = parsed["resolution"]
			if (r as Array).size() == 2:
				game_resolution = Vector2i(int(r[0]), int(r[1]))
		if parsed.has("quality"):
			quality_level = clampi(int(parsed["quality"]), 0, 2)
		if parsed.has("music"):
			music_enabled = bool(parsed["music"])
		if parsed.has("upscaler"):
			upscaler = clampi(int(parsed["upscaler"]), 0, 2)
			upscaler_last = upscaler if upscaler != 2 else 0
		elif parsed.has("fsr"):
			# MigraciÃ³n del setting viejo ("fsr": true/false) al esquema FSR/DLSS/OFF:
			# conserva lo que el usuario tenÃ­a (upscale on â†’ DLSS si el engine lo tiene, si no FSR).
			upscaler = 1 if bool(parsed["fsr"]) and _engine_has_dlss() else (0 if bool(parsed["fsr"]) else 2)
			upscaler_last = upscaler if upscaler != 2 else 0
		if parsed.has("fsr_mode"):
			fsr_mode = clampi(int(parsed["fsr_mode"]), 0, 2)
		if parsed.has("fg"):
			fg_enabled = bool(parsed["fg"])
		if parsed.has("aspect"):
			aspect_idx = clampi(int(parsed["aspect"]), 0, 1)
		if parsed.has("fullscreen"):
			fullscreen = bool(parsed["fullscreen"])
		if parsed.has("lang"):
			lang = clampi(int(parsed["lang"]), 0, 1)
		if parsed.has("keybinds") and parsed["keybinds"] is Dictionary:
			var kb: Dictionary = parsed["keybinds"]
			for a in KEY_BINDS_DEFAULT:
				if kb.has(a):
					key_binds[a] = int(kb[a])
		if parsed.has("joybinds") and parsed["joybinds"] is Dictionary:
			var jb: Dictionary = parsed["joybinds"]
			for a in JOY_BINDS_DEFAULT:
				if jb.has(a):
					joy_binds[a] = int(jb[a])
		if parsed.has("joyaxis"):
			joy_trigger_axis = clampi(int(parsed["joyaxis"]), 0, 10)
		if parsed.has("mouse_sens"):
			mouse_sens = clampf(float(parsed["mouse_sens"]), 0.2, 3.0)
		if parsed.has("stick_sens"):
			stick_sens = clampf(float(parsed["stick_sens"]), 0.2, 3.0)
		# Asegurar resoluciÃ³n vÃ¡lida para la relaciÃ³n de aspecto elegida
		if not _resolutions().has(game_resolution):
			game_resolution = Vector2i(1920, 1200) if aspect_idx == 1 else Vector2i(1920, 1080)

func _save_settings() -> void:
	var data := {
		"resolution": [game_resolution.x, game_resolution.y],
		"quality": quality_level,
		"music": music_enabled,
		"upscaler": upscaler,
		"fsr_mode": fsr_mode,
		"fg": fg_enabled,
		"aspect": aspect_idx,
		"fullscreen": fullscreen,
		"lang": lang,
		"keybinds": key_binds,
		"joybinds": joy_binds,
		"joyaxis": joy_trigger_axis,
		"mouse_sens": mouse_sens,
		"stick_sens": stick_sens
	}
	SaveData.write_settings(data)
# Presets de calidad: baja (PCs modestos) / media / alta (alto rendimiento)
func _apply_quality(level: int) -> void:
	quality_level = level
	var env: Environment = env_ref
	if env:
		match level:
			0:  # BAJA â€” sin post-procesado, para PCs modestos
				env.ssao_enabled = false
				env.sdfgi_enabled = false
				env.ssr_enabled = false
				env.glow_enabled = false
			1:  # MEDIA â€” SSAO + glow, sin GI/reflejos en tiempo real
				env.ssao_enabled = true
				env.sdfgi_enabled = false
				env.ssr_enabled = false
				env.glow_enabled = true
			2:  # ALTA â€” todo: SSAO + SDFGI + SSR + glow (alto rendimiento)
				env.ssao_enabled = true
				env.sdfgi_enabled = true
				env.sdfgi_cascades = 4
				env.ssr_enabled = true
				env.ssr_max_steps = 96
				env.glow_enabled = true
	if env:
		env.ssil_enabled = (level == 2)
	# Detalle de partÃ­culas segÃºn calidad
	particle_scale = [0.4, 0.7, 1.0][level]
	# Detalle de la malla del ocÃ©ano (menos subdivisiones = mÃ¡s barato)
	if water_node and water_node.mesh is PlaneMesh:
		var pm: PlaneMesh = water_node.mesh
		match level:
			0:
				pm.subdivide_width = 60
				pm.subdivide_depth = 45
			1:
				pm.subdivide_width = 120
				pm.subdivide_depth = 90
			2:
				pm.subdivide_width = 200
				pm.subdivide_depth = 150
	# SSR del ocÃ©ano (refleja buques/barcos en el agua): alcance de la ray segÃºn calidad
	if water_node and water_node.material_override is ShaderMaterial:
		var wm: ShaderMaterial = water_node.material_override
		match level:
			0:  # BAJA â€” SSR desactivado (mÃ¡ximo FPS en PCs modestos)
				wm.set_shader_parameter("ssr_max_travel", 0.0)
			1:  # MEDIA â€” SSR de alcance medio
				wm.set_shader_parameter("ssr_max_travel", 90.0)
				wm.set_shader_parameter("ssr_max_diff", 10.0)
				wm.set_shader_parameter("ssr_resolution", 1.25)
			2:  # ALTA â€” SSR sobre todo el ocÃ©ano
				wm.set_shader_parameter("ssr_max_travel", 150.0)
				wm.set_shader_parameter("ssr_max_diff", 15.0)
				wm.set_shader_parameter("ssr_resolution", 1.0)
	if sky3d_node:
		sky3d_node.clouds_enabled = level > 0
	_save_settings()

# Upscale 3D: usa DLSS si el engine lo soporta (builds rtx-godot / fork NVIDIA con
# Streamline); si no, FSR 2.2 (integrado en Godot oficial). Renderiza el 3D a menor
# escala y hace upscale. Solo escala el mundo 3D; el HUD 2D se mantiene a resoluciÃ³n
# completa (texto nÃ­tido).
# RENDIMIENTO = mÃ¡s FPS | CALIDAD = balanceado | ULTRA = mejor imagen
const SCALING_3D_MODE_DLSS := 6  # Viewport.SCALING_3D_MODE_DLSS en el fork rtx-godot (enum 4.8)

var dlss_supported := false  # true si el engine en ejecuciÃ³n expone DLSS (lo calcula _apply_fsr)

# Upscale que usan las vistas de juego (raiz en single, mitades en split): ver _apply_fsr()
var _scal_mode: int = 0
var _scal_scale: float = 1.0
var _scal_sharp: float = 0.0

# Detecta APIs exclusivas del engine con Streamline (singleton + propiedad frame_generation).
# Sondea en vez de tocar las constantes del fork para que el script parsee tambiÃ©n en Godot 4.7.
func _engine_has_dlss() -> bool:
	if not ClassDB.class_exists("Streamline"):
		return false
	var vp := get_viewport()
	if vp == null:
		return false
	for p in vp.get_property_list():
		if str(p.get("name", "")) == "frame_generation":
			return true
	return false

func _apply_fsr() -> void:
	var vp := get_viewport()
	dlss_supported = _engine_has_dlss()
	var use_dlss := upscaler == 1 and dlss_supported
	var use_fsr := upscaler == 0 or (upscaler == 1 and not dlss_supported)  # DLSS pedido pero no disponible: FSR
	if use_dlss:
		# DLSS Super Resolution: RENDIMIENTO=rendimiento, CALIDAD=calidad, ULTRA=DLAA (sin upscale)
		vp.set("scaling_3d_mode", SCALING_3D_MODE_DLSS)
		vp.set("scaling_3d_scale", [0.5, 0.67, 1.0][fsr_mode])
		if int(vp.get("scaling_3d_mode")) != SCALING_3D_MODE_DLSS:
			use_dlss = false  # la GPU/engine no aceptÃ³ DLSS: fallback FSR abajo
			vp.set("scaling_3d_scale", 1.0)
	if use_dlss:
		pass  # ya configurado arriba
	elif use_fsr:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = [0.66, 0.75, 0.85][fsr_mode]
		vp.fsr_sharpness = 0.2
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
	# DLSS Frame Generation (fork + RTX 40+): intercala frames generados entre los
	# renderizados. Requiere que el scaling estÃ© en DLSS; en split puede no inicializar.
	if dlss_supported:
		vp.set("frame_generation", fg_enabled and use_dlss)
	# Config de upscale de las VISTAS DE JUEGO: en single es el viewport raiz; en split
	# son las dos mitades. Se guarda para que _build_split_viewports() y cambiar las
	# opciones a mitad de split usen exactamente la misma config.
	_scal_mode = int(vp.get("scaling_3d_mode"))
	_scal_scale = float(vp.get("scaling_3d_scale"))
	_scal_sharp = float(vp.get("fsr_sharpness"))
	# Split: el viewport raiz NO renderiza 3D (camera.current = false, world oculto).
	# Dejarle DLSS/Frame Generation hace que corra el pase de upscale + optical flow del
	# SDK sobre un buffer vacio, a resolucion completa de ventana. Medido en oleada 12 con
	# dos jugadores: 74 FPS -> 105 FPS. Las mitades conservan su propio DLSS, y volver a
	# single lo restaura _teardown_split().
	if split_mode:
		_root_scaling_for_split()
	# Split: los SubViewport tienen su propio scaling 3D (no heredan del root):
	# propagar la misma configuraciÃ³n a las mitades de J1/J2.
	for sub in [vp_a, vp_b]:
		if sub:
			sub.scaling_3d_mode = _scal_mode
			sub.scaling_3d_scale = _scal_scale
			sub.fsr_sharpness = _scal_sharp
	_save_settings()

# El viewport raiz deja de ser una vista de juego en pantalla dividida: apaga su upscale
# 3D y el Frame Generation (no hay camara activa ni world visible: solo gastaria GPU).
func _root_scaling_for_split() -> void:
	var vpr = get_viewport()
	vpr.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vpr.scaling_3d_scale = 1.0
	if dlss_supported:
		vpr.set("frame_generation", false)


func _resolutions() -> Array:
	# Resoluciones disponibles segÃºn la relaciÃ³n de aspecto elegida
	var lst := GameConfig.RESOLUTIONS_16_9 if aspect_idx == 0 else GameConfig.RESOLUTIONS_16_10
	return lst.duplicate()

func _apply_display_mode() -> void:
	var mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	_save_settings()  # persistir el modo ventana/pantalla completa entre sesiones

func _apply_resolution(res: Vector2i) -> void:
	game_resolution = res
	# Primero el tamaÃ±o (modo ventana), luego el modo: a pantalla completa usa el tamaÃ±o como resoluciÃ³n nativa
	DisplayServer.window_set_size(res)
	_apply_display_mode()
	_update_hud_scale()
	_save_settings()

# Escala todos los nodos del HUD (diseÃ±ados a 1920Ã—1080) a la resoluciÃ³n actual de la ventana
func _update_hud_scale() -> void:
	if not hud:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return
	var s := Vector2(vp.x / 1920.0, vp.y / 1080.0)
	if s == hud_scale:
		return
	hud_scale = s
	for child in hud.get_children():
		if mp_role == 3 and (_abl_menu_nodes.has(child) or _abl1_nodes.has(child)):
			child.scale = s * 0.5  # split: menÃº de habilidades contenido en la mitad del jugador
		else:
			child.scale = s
	# Split: mantener los rectÃ¡ngulos/viewports a la mitad actual de la ventana
	if split_mode:
		_update_split_viewport_sizes()

# â”€â”€â”€ CONTROLES (remapeo de teclado/ratÃ³n + joystick) â”€â”€â”€
func _on_btn_controls() -> void:
	if ui_select:
		ui_select.play()
	_show_controls()

func _kb(action: String) -> int:
	return int(key_binds.get(action, KEY_BINDS_DEFAULT[action]))

func _jb(action: String) -> int:
	return int(joy_binds.get(action, JOY_BINDS_DEFAULT[action]))

func _ability_key(action: String) -> String:
	match action:
		"ability_rapid": return "Q"
		"ability_shield": return "E"
		"ability_mines": return "R"
		"ability_artillery": return "T"
		"ability_overload": return "F"
		"ability_repair": return "G"
	return ""

func _bind_name_k(v: int) -> String:
	if v < 0:
		match -v:
			1: return _tr("ct_mouse_l")
			2: return _tr("ct_mouse_m")
			3: return _tr("ct_mouse_r")
		return "MB%d" % (-v)
	match v:
		KEY_ESCAPE: return "ESC"
		KEY_ENTER: return _tr("ct_enter")
		KEY_SPACE: return _tr("ct_space")
		KEY_BACKSPACE: return "BACKSPACE"
		KEY_TAB: return "TAB"
		KEY_SHIFT: return "SHIFT"
		KEY_CTRL: return "CTRL"
		KEY_ALT: return "ALT"
		KEY_LEFT: return "â†"
		KEY_RIGHT: return "â†’"
		KEY_UP: return "â†‘"
		KEY_DOWN: return "â†“"
	if v >= KEY_F1 and v <= KEY_F12:
		return "F%d" % (v - KEY_F1 + 1)
	if v >= KEY_KP_0 and v <= KEY_KP_9:
		return "NUM" + char(48 + (v - KEY_KP_0))
	if v >= 65 and v <= 90:
		return char(v)
	if v >= 48 and v <= 57:
		return char(v)
	return "KEY %d" % v

func _bind_name_j(v: int) -> String:
	match v:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-PAD â†‘"
		JOY_BUTTON_DPAD_DOWN: return "D-PAD â†“"
		JOY_BUTTON_DPAD_LEFT: return "D-PAD â†"
		JOY_BUTTON_DPAD_RIGHT: return "D-PAD â†’"
		JOY_BUTTON_BACK: return "SEL"
		JOY_BUTTON_START: return "START"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_GUIDE: return "GUIDE"
	return "BTN %d" % v

func _ct_row_text(action: String) -> String:
	var base: String = {
		"fire": "act_fire", "weapon1": "act_w1", "weapon2": "act_w2", "weapon3": "act_w3", "weapon_cycle": "act_wcycle",
		"abilities_menu": "act_abmenu", "pause_back": "act_pause", "pause": "act_pause",
		"music": "act_music", "confirm": "act_confirm", "restart": "act_restart", "back": "act_back",
	}.get(action, "")
	if action.begins_with("ability_"):
		var aname: String = {
			"ability_rapid": "abl_name_q", "ability_shield": "abl_name_e", "ability_mines": "abl_name_r",
			"ability_artillery": "abl_name_t", "ability_overload": "abl_name_f", "ability_repair": "abl_name_g",
		}.get(action, "")
		return _tr("act_abl") + ": " + _tr(aname)
	return _tr(base)

var ct_sens_val_lbl: Label = null

func _show_controls() -> void:
	# Sub-menÃº: elegir quÃ© dispositivo configurar (teclado/mouse o joystick)
	hs_return_phase = phase
	_hud.clear_overlay_nodes()
	current_menu = "controls"
	_hud.make_overlay("CTOverlay", Color(0, 0, 0, 0.88))
	_hud.make_label("CTTitle", Vector2(720, 110), _tr("ct_title"), 48, Color(1, 0.9, 0.4))
	var bx := 720.0
	_hud.make_button("CTBtnKb", Vector2(bx, 340), _tr("ct_kbd"), _show_controls_kb).size = Vector2(480, 62)
	_hud.make_button("CTBtnJoy", Vector2(bx, 450), _tr("ct_joy"), _show_controls_joy).size = Vector2(480, 62)
	var bb := _hud.make_button("CTBtnBack", Vector2(640, 940), _tr("opt_back"), _on_ct_back)
	bb.size = Vector2(260, 52)

func _show_controls_kb() -> void:
	hs_return_phase = phase
	_hud.clear_overlay_nodes()
	current_menu = "controls_kb"
	ct_rows = []
	_hud.make_overlay("CTOverlay", Color(0, 0, 0, 0.88))
	_hud.make_label("CTTitle", Vector2(140, 70), _tr("ct_kbd"), 40, Color(1, 0.9, 0.4))
	var k_actions: Array = [
		"fire", "weapon1", "weapon2", "weapon3",
		"ability_rapid", "ability_shield", "ability_mines",
		"ability_artillery", "ability_overload", "ability_repair",
		"abilities_menu", "pause_back", "music", "confirm", "restart",
	]
	for i in k_actions.size():
		var action: String = k_actions[i]
		var ry: int = 168 + i * 48
		var lbl := _hud.make_label("CTK%d" % i, Vector2(140, ry + 4), _ct_row_text(action), 19, Color(1, 1, 1, 0.9))
		lbl.size = Vector2(360, 36)
		var btn := _hud.make_button("CTKB%d" % i, Vector2(520, ry), _bind_name_k(int(key_binds[action])), _on_ct_remap.bind("k", action))
		btn.size = Vector2(280, 42)
		btn.add_theme_font_size_override("font_size", 20)
		ct_rows.append(["k:" + action, btn])
	# Sensibilidad del mouse (columna derecha)
	_hud.make_label("CTSenHdr", Vector2(850, 175), _tr("ct_mouse_sens"), 24, Color(0.7, 0.8, 1.0))
	_make_slider("CTSensSlider", Vector2(850, 225), mouse_sens, _on_mouse_sens_changed)
	ct_sens_val_lbl = _hud.make_label("CTSenVal", Vector2(850, 275), "%.2fx" % mouse_sens, 26, Color(1, 0.9, 0.4))
	ct_sens_val_lbl.size = Vector2(360, 30)
	_ct_bottom_bar()

func _show_controls_joy() -> void:
	hs_return_phase = phase
	_hud.clear_overlay_nodes()
	current_menu = "controls_joy"
	ct_rows = []
	_hud.make_overlay("CTOverlay", Color(0, 0, 0, 0.88))
	_hud.make_label("CTTitle", Vector2(140, 70), _tr("ct_joy"), 40, Color(1, 0.9, 0.4))
	var j_actions: Array = [
		"weapon1", "weapon2", "weapon3", "weapon_cycle",
		"ability_rapid", "ability_shield", "ability_mines",
		"ability_artillery", "ability_overload", "ability_repair",
		"abilities_menu", "pause", "music", "confirm", "back",
	]
	for i in j_actions.size():
		var action: String = j_actions[i]
		var ry: int = 168 + i * 48
		var lbl := _hud.make_label("CTJ%d" % i, Vector2(140, ry + 4), _ct_row_text(action), 19, Color(1, 1, 1, 0.9))
		lbl.size = Vector2(360, 36)
		var btn := _hud.make_button("CTJB%d" % i, Vector2(520, ry), _bind_name_j(int(joy_binds[action])), _on_ct_remap.bind("j", action))
		btn.size = Vector2(280, 42)
		btn.add_theme_font_size_override("font_size", 20)
		ct_rows.append(["j:" + action, btn])
	# Trigger (eje analÃ³gico)
	var ax_i := j_actions.size()
	var ary: int = 168 + ax_i * 48
	_hud.make_label("CTAxisLbl", Vector2(140, ary + 4), _tr("act_trig"), 19, Color(1, 1, 1, 0.9)).size = Vector2(360, 36)
	var abtn := _hud.make_button("CTAxisBtn", Vector2(520, ary), _tr("act_axis") % joy_trigger_axis, _on_ct_remap.bind("axis", "jaxis"))
	abtn.size = Vector2(280, 42)
	abtn.add_theme_font_size_override("font_size", 20)
	ct_rows.append(["jaxis", abtn])
	# Sensibilidad del stick (columna derecha)
	_hud.make_label("CTSenHdr", Vector2(850, 175), _tr("ct_stick_sens"), 24, Color(0.7, 0.8, 1.0))
	_make_slider("CTSensSlider", Vector2(850, 225), stick_sens, _on_stick_sens_changed)
	ct_sens_val_lbl = _hud.make_label("CTSenVal", Vector2(850, 275), "%.2fx" % stick_sens, 26, Color(1, 0.9, 0.4))
	ct_sens_val_lbl.size = Vector2(360, 30)
	_ct_bottom_bar()

# Barra inferior de las pantallas de controles: hint + reset + volver
func _ct_bottom_bar() -> void:
	ct_hint_lbl = _hud.make_label("CTHint", Vector2(140, 1002), _tr("ct_hint"), 18, Color(1, 0.85, 0.5))
	var rbtn := _hud.make_button("CTBtnReset", Vector2(1000, 1010), _tr("ct_reset"), _on_ct_reset)
	rbtn.size = Vector2(360, 52)
	var bbtn := _hud.make_button("CTBtnBack", Vector2(640, 1010), _tr("opt_back"), _on_ct_back)
	bbtn.size = Vector2(260, 52)

func _make_slider(p_name: String, p_pos: Vector2, p_value: float, p_cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.name = p_name
	s.position = p_pos
	s.size = Vector2(450, 24)
	s.min_value = 0.2
	s.max_value = 3.0
	s.step = 0.05
	s.value = p_value
	s.value_changed.connect(p_cb)
	hud.add_child(s)
	return s

func _on_mouse_sens_changed(v: float) -> void:
	mouse_sens = v
	if ct_sens_val_lbl:
		ct_sens_val_lbl.text = "%.2fx" % v
	_save_settings()

func _on_stick_sens_changed(v: float) -> void:
	stick_sens = v
	if ct_sens_val_lbl:
		ct_sens_val_lbl.text = "%.2fx" % v
	_save_settings()

func _ct_set_row_text(rid: String, text: String) -> void:
	for r in ct_rows:
		if (r[0] as String) == rid:
			(r[1] as Button).text = text
			return

func _on_ct_remap(dev: String, action: String) -> void:
	if ui_select:
		ui_select.play()
	var rid: String = "jaxis" if dev == "axis" else dev + ":" + action
	_remap_capture = rid
	var msg: String = _tr("ct_press_axis") if dev == "axis" else (_tr("ct_press_key") if dev == "k" else _tr("ct_press_btn"))
	_ct_set_row_text(rid, msg)
	if ct_hint_lbl:
		ct_hint_lbl.text = _tr("ct_hint_cap")

func _on_ct_reset() -> void:
	if ui_select:
		ui_select.play()
	key_binds = KEY_BINDS_DEFAULT.duplicate()
	joy_binds = JOY_BINDS_DEFAULT.duplicate()
	joy_trigger_axis = 5
	mouse_sens = 1.0
	stick_sens = 1.0
	_save_settings()
	# reconstruye la pantalla actual con los valores por defecto
	if current_menu == "controls_joy":
		_show_controls_joy()
	else:
		_show_controls_kb()

func _on_ct_back() -> void:
	if ui_select:
		ui_select.play()
	if current_menu == "controls_kb" or current_menu == "controls_joy":
		_show_controls()  # de pantalla de detalle â†’ sub-menÃº de dispositivos
	else:
		_menu.show_options()

func _remap_end() -> void:
	var cap := _remap_capture
	_remap_capture = ""
	if cap == "jaxis":
		_ct_set_row_text("jaxis", _tr("act_axis") % joy_trigger_axis)
	elif cap.begins_with("k:"):
		var a: String = cap.substr(2)
		_ct_set_row_text(cap, _bind_name_k(int(key_binds[a])))
	elif cap.begins_with("j:"):
		var b: String = cap.substr(2)
		_ct_set_row_text(cap, _bind_name_j(int(joy_binds[b])))
	if ct_hint_lbl:
		ct_hint_lbl.text = _tr("ct_hint")

func _remap_handle_event(event: InputEvent) -> void:
	var cap := _remap_capture
	if cap == "":
		return
	# ESC siempre cancela el captura
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_remap_end()
		return
	if cap == "jaxis":
		if event is InputEventJoypadMotion and event.pressed:
			var jm := event as InputEventJoypadMotion
			if absf(jm.axis_value) > 0.4:
				joy_trigger_axis = jm.axis
				_save_settings()
				_remap_end()
		return
	var dev: String = cap.substr(0, 1)
	var action: String = cap.substr(2)
	if dev == "k":
		if event is InputEventKey and event.pressed:
			var k := event as InputEventKey
			if k.keycode == KEY_NONE:
				return
			key_binds[action] = int(k.keycode)
			_save_settings()
			_remap_end()
		elif event is InputEventMouseButton and event.pressed:
			key_binds[action] = -int((event as InputEventMouseButton).button_index)
			_save_settings()
			_remap_end()
	elif dev == "j":
		if event is InputEventJoypadButton and event.pressed:
			joy_binds[action] = int((event as InputEventJoypadButton).button_index)
			_save_settings()
			_remap_end()

# Limpieza completa de partida + estado de red (vuelta a menÃº o abandono de sala).
# La partida no debe seguir corriendo detrÃ¡s del menÃº.
func _mp_abort_cleanup() -> void:
	phase = GamePhase.MENU
	click_queued = false
	mouse_down = false
	enemies.clear()
	projectiles.clear()
	enemy_projectiles.clear()
	if _fx != null:
		_fx.release_all()  # particulas y luces de vuelta al pool (no se liberan)
	_vfx_release_all()
	crates.clear()
	for pm in get_tree().get_nodes_in_group("PlayerMines"):
		(pm as Node).queue_free()
	for dn in get_tree().get_nodes_in_group("DynNodes"):
		(dn as Node).queue_free()
	for child in get_children():
		if child.name.begins_with("Enemy_") or child.name.begins_with("Proj_") or child.name.begins_with("EProj_") or child.name.begins_with("Crate_") or child.name.begins_with("Mine_") or child.name.begins_with("FX_") or child.name == "ShieldVis":
			child.queue_free()
	_vfx_release_all()  # devuelve las instancias Binbun al pool (no las libera)
	# Estado de red: pools de nodos y FX pendientes
	net_enemy_nodes.clear()
	net_proj_nodes.clear()
	net_eproj_nodes.clear()
	net_crate_nodes.clear()
	net_fx.clear()
	_free_player_avatars()
	slot_states.clear()
	slot_by_pid.clear()
	mp_go_phase = 0
	mp_roster.clear()
	mp_slot_stats.clear()
	kill_credit_slot = -1
	base_destroying = false
	base_explosion_timer = 999.0
	_apply_base_fire_stage(0)
	_hud.clear_overlay_nodes()
	mp_role = 0
	mp_players = 1
	my_slot = 0
	if split_mode:
		_teardown_split()

func _restart_game() -> void:
	if ui_select:
		ui_select.play()
	# Split 2P: reinicio sin recarga de escena (mantiene el modo 2 jugadores)
	if split_mode or mp_role == 3:
		_start_split_game()
		return
	# Guardar la puntuaciÃ³n actual antes de reiniciar
	if score > 0:
		_add_highscore(score, "???", wave)
	get_tree().reload_current_scene()

# â”€â”€â”€ MENÃšS: implementaciÃ³n en scripts/menu_ui.gd (class_name MenuUI) â”€â”€â”€
# main.gd mantiene phase/current_menu/ajustes/highscores y el input; MenuUI dibuja
# las pantallas (inicio, pausa, opciones, grÃ¡ficos, puntuaciones, idioma, dispositivos,
# asignaciÃ³n de mandos del split) y delega el flujo de vuelta acÃ¡ (app.*).
var _menu: MenuUI = null

func _build_menu() -> void:
	_menu = MenuUI.new()
	_menu.app = self
	_mp_err_back = _menu.show_menu  # destino del botÃ³n VOLVER del error de red

# â”€â”€â”€ TECLADO VIRTUAL (iniciales) â”€â”€â”€
# La implementaciÃ³n estÃ¡ en scripts/vkb.gd (class_name VirtualKeyboard): single usa uno
# de una fila; el split usa dos, uno por mitad. Cada instancia es dueÃ±a de su cursor y de
# si estÃ¡ visible; las iniciales y el guardado siguen acÃ¡ y se pasan por callbacks.
var _vkb: VirtualKeyboard = null
var _svkb: Array[VirtualKeyboard] = []  # [VKB de P1, VKB de P2] en el game over split

func _build_vkb() -> void:
	_vkb = VirtualKeyboard.new()
	_svkb = [VirtualKeyboard.new(), VirtualKeyboard.new()]
	var all: Array[VirtualKeyboard] = [_vkb, _svkb[0], _svkb[1]]
	for kb in all:
		kb.hud = hud
		kb.cb_label = _hud.make_label
		kb.cb_centered = _hud.make_centered_label
		kb.cb_tr = _tr
	_vkb.player = -1
	# Los callbacks de iniciales reciben (ini_index, ...) desde el propio VKB:
	# asÃ­ no hace falta bind(), que agrega sus argumentos AL FINAL del llamado.
	_vkb.ini_index = 0
	_vkb.cb_get_initials = _ini_get
	_vkb.cb_set_initials = _ini_set
	_vkb.cb_submit = _vkb_submit_single
	_vkb.cb_skip = _skip_initials
	for p in 2:
		_svkb[p].player = p
		_svkb[p].ini_index = p
		_svkb[p].cb_get_initials = _ini_get
		_svkb[p].cb_set_initials = _ini_set
		_svkb[p].cb_submit = _vkb_submit_split.bind(p)
		_svkb[p].cb_skip = _vkb_skip_split.bind(p)
		_svkb[p].ui_select = ui_select  # beep al mover/seleccionar (solo en split)

# Iniciales: single usa p=0 (las de P2 tienen su propio cursor de texto).
func _ini_get(p: int) -> String:
	return p2_initials if p == 1 else initials

func _ini_set(p: int, v: String) -> void:
	if p == 1:
		p2_ini_cursor = 0
		p2_initials = v
		_split_update_p2_ini_display()
	else:
		initials = v
		_update_initials_display()

func _vkb_submit_single() -> void:
	_submit_initials()

func _vkb_submit_split(p: int) -> void:
	if p == 1:
		_split_p2_submit()
	else:
		_mp_send_my_initials(_ini_get(p))

func _vkb_skip_split(p: int) -> void:
	if p == 1:
		p2_initials = ""
		_split_p2_submit()
	else:
		_mp_send_my_initials("")

# â”€â”€â”€ GAME OVER + INICIALES (estilo arcade) â”€â”€â”€
func _gameover() -> void:
	if ui_gameover:
		ui_gameover.play()
	phase = GamePhase.GAMEOVER
	mouse_down = false
	click_queued = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var _xh := get_node_or_null("CrosshairLayer")
	if _xh: _xh.visible = false
	_hud.clear_overlay_nodes()
	_hud.make_overlay("GameOverOverlay", Color(0, 0, 0, 0.85))
	_hud.make_label("GameOverTitle", Vector2(700, 200), "GAME OVER", 56, Color(1, 0.3, 0.25))
	_hud.make_label("GameOverScore", Vector2(640, 350), _tr("go_score_wave") % [score, wave], 34)
	entering_initials = false
	initials = ""
	_vkb.open = false
	if _qualifies_highscore():
		entering_initials = true
		_hud.make_label("GOInitialsPrompt", Vector2(430, 530), _tr("go_new_record"), 28, Color(1, 0.9, 0.4))
		initials_label = _hud.make_label("GOInitialsBoxes", Vector2(780, 610), "_ _ _", 64, Color(1, 0.95, 0.5))
		if local_input_mode == 1 and mp_role == 0:
			_vkb.show()
		else:
			_hud.make_label("GOInitialsHint", Vector2(560, 750), _tr("go_ini_hint"), 18, Color(1, 1, 1, 0.7))
		_update_initials_display()
	else:
		var go_hint := _tr("go_hint_menu_joy") if local_input_mode == 1 else _tr("go_hint_menu")
		_hud.make_label("GOHint", Vector2(500, 620), go_hint, 26, Color(1, 1, 1, 0.8))

func _update_initials_display() -> void:
	if initials_label:
		var shown := ""
		for i in 3:
			if i < initials.length():
				shown += initials[i].to_upper() + "  "
			else:
				shown += "_  "
		initials_label.text = shown.strip_edges()


func _handle_initials_key(key: InputEventKey) -> void:
	var kc := int(key.keycode)
	if kc == _kb("confirm"):
		_submit_initials()
	elif kc == _kb("pause_back"):
		_skip_initials()
	elif key.keycode == KEY_BACKSPACE:
		if initials.length() > 0:
			initials = initials.left(initials.length() - 1)
			_update_initials_display()
	else:
		var u: int = key.unicode
		var is_upper: bool = u >= 65 and u <= 90
		var is_lower: bool = u >= 97 and u <= 122
		var is_digit: bool = u >= 48 and u <= 57
		if (is_upper or is_lower or is_digit) and initials.length() < 3:
			# Acepta minÃºsculas y mayÃºsculas; siempre muestra en mayÃºscula
			initials += char(u).to_upper()
			_update_initials_display()

func _submit_initials() -> void:
	if _is_mp_gameover():
		_mp_send_my_initials(initials)
		return
	var rank := _add_highscore(score, initials, wave)
	_finalize_gameover(rank)

func _skip_initials() -> void:
	if _is_mp_gameover():
		_mp_send_my_initials("???")
		return
	_finalize_gameover(-1)

func _finalize_gameover(p_rank: int) -> void:
	entering_initials = false
	_vkb.clear()
	if initials_label:
		initials_label.queue_free()
		initials_label = null
	for n in ["GOInitialsPrompt", "GOInitialsHint"]:
		var nd: Node = hud.get_node_or_null(n)
		if nd:
			nd.queue_free()
	var extra := ""
	if p_rank > 0:
		extra = _tr("go_saved") % p_rank
	var go_hint := _tr("go_hint_menu_joy") if local_input_mode == 1 else _tr("go_hint_menu")
	_hud.make_label("GOHint", Vector2(480, 700), "%s\n\n%s" % [extra, go_hint], 26, Color(1, 1, 1, 0.85))

# â”€â”€â”€ PAUSE â”€â”€â”€
func _pause_game() -> void:
	mouse_down = false
	if ui_select:
		ui_select.play()
	# Freeze soldier animations while paused
	for e in enemies:
		var ap: AnimationPlayer = (e["node"] as Node).get_node_or_null("AnimationPlayer")
		if ap != null:
			ap.speed_scale = 0.0
	_menu.show_pause_menu()

func _resume_game() -> void:
	if ui_select:
		ui_select.play()
	for e in enemies:
		var ap: AnimationPlayer = (e["node"] as Node).get_node_or_null("AnimationPlayer")
		if ap != null:
			ap.speed_scale = 1.0
	_hud.clear_overlay_nodes()
	phase = GamePhase.PLAYING
	var _xh := get_node_or_null("CrosshairLayer")
	if _xh: _xh.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# â”€â”€â”€ INPUT â”€â”€â”€
func _input(event: InputEvent) -> void:
	# â”€â”€ Remap: capturando nueva tecla/botÃ³n (se consume todo el input) â”€â”€
	if _remap_capture != "":
		_remap_handle_event(event)
		get_viewport().set_input_as_handled()
		return
	# â”€â”€ GAMEPAD: split (J2) o joystick local (menÃºs siempre; partida si eligiÃ³ joystick) â”€â”€
	if event is InputEventJoypadButton:
		# "split_assign" solo vale mientras el menu esta abierto: si el valor quedara despues
		# de empezar la partida, los botones del mando se pierden ahi y nunca llegan al
		# teclado virtual del game over (iniciales imposibles con joystick).
		if current_menu == "split_assign" and phase == GamePhase.MENU:
			_menu.split_assign_claim(event as InputEventJoypadButton)
		elif split_mode:
			_split_input_joypad(event as InputEventJoypadButton)
		else:
			_joy_menu_nav(event as InputEventJoypadButton)
		return
	# ── GAME OVER: clic sobre una letra del teclado virtual ──
	# En split cada mitad tiene el suyo; la letra se elige con el mouse sin tocar el mando.
	# No interfiere con el disparo: en GAMEOVER el mouse ya no apunta (esta rama es exclusiva).
	if phase == GamePhase.GAMEOVER and entering_initials and event is InputEventMouseButton:
		var mbk := event as InputEventMouseButton
		if mbk.pressed and mbk.button_index == MOUSE_BUTTON_LEFT:
			var hit: bool = false
			if split_mode:
				if _svkb.size() == 2:
					hit = _svkb[0].pick_at(mbk.position) or _svkb[1].pick_at(mbk.position)
			elif _vkb != null:
				hit = _vkb.pick_at(mbk.position)
			if hit:
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		var kc := int(key.keycode)  # comparo como int (evita el cast de enum)
		if phase == GamePhase.MENU:
			if kc == _kb("confirm"):
				# Confirmar inicia solo desde el menÃº principal (antes arrancaba partida desde cualquier submenÃº)
				if current_menu == "menu":
					_menu.show_input_choice("single")
			elif kc == _kb("pause_back"):
					_menu.menu_back()
		elif phase == GamePhase.PLAYING:
			if kc == _kb("weapon1"): _switch_weapon(0)
			if kc == _kb("weapon2"): _switch_weapon(1)
			if kc == _kb("weapon3"): _switch_weapon(2)
			if kc == _kb("music"): _toggle_music()
			if kc == _kb("pause_back"):
				if _abilities_menu_open:
					_toggle_abilities_menu()
				else:
					_pause_game()
			# Habilidades
			if kc == _kb("ability_rapid"): _activate_ability(_ability_key("ability_rapid"))
			if kc == _kb("ability_shield"): _activate_ability(_ability_key("ability_shield"))
			if kc == _kb("ability_mines"): _activate_ability(_ability_key("ability_mines"))
			if kc == _kb("ability_artillery"): _activate_ability(_ability_key("ability_artillery"))
			if kc == _kb("ability_overload"): _activate_ability(_ability_key("ability_overload"))
			if kc == _kb("ability_repair"): _activate_ability(_ability_key("ability_repair"))
			if kc == _kb("abilities_menu"): _toggle_abilities_menu()
		elif phase == GamePhase.PAUSE:
			if kc == _kb("pause_back"):
				# Solo el menÃº de pausa reanuda; submenÃºs (opciones/grÃ¡ficos) hacen "volver atrÃ¡s"
				if current_menu == "pause":
					_resume_game()
				else:
					_menu.menu_back()
			elif kc == _kb("restart") and current_menu == "pause":
				_restart_game()  # solo desde el menÃº de pausa, no desde submenÃºs
			elif kc == _kb("music"): _toggle_music()
		elif phase == GamePhase.GAMEOVER:
			if entering_initials:
				# El teclado de PC SIEMPRE puede editar las iniciales de P1 (en split es lo unico
				# que tiene P1 si no tiene mando, y convive con el mando de P2 sin pelearse).
				_handle_initials_key(key)
			else:
				if kc == _kb("restart") and mp_role == 0:
					_restart_game()
				elif kc == _kb("confirm") or kc == _kb("pause_back"):
					if mp_role != 0:
						_menu.on_btn_back_to_menu()  # MP: limpia el estado de red antes del menÃº
					else:
						_menu.show_menu()
	if phase == GamePhase.PLAYING:
		# Disparo con tecla mapeada (si el disparo se remapeÃ³ a una tecla)
		if not _abilities_menu_open and _kb("fire") > 0 and event is InputEventKey:
			var kf := event as InputEventKey
			if int(kf.keycode) == _kb("fire"):
				mouse_down = kf.pressed
				if kf.pressed and current_weapon == 0:
					click_queued = true
		if event is InputEventMouseMotion and not _abilities_menu_open and local_input_mode == 0:
			var motion := event as InputEventMouseMotion
			var ms: float = 0.002 * mouse_sens
			yaw -= motion.relative.x * ms
			pitch -= motion.relative.y * ms
			pitch = clampf(pitch, -1.2, 0.6)
			
			camera.rotation = Vector3(pitch, yaw, 0)
		if event is InputEventMouseButton and not _abilities_menu_open and local_input_mode == 0:
			var mb := event as InputEventMouseButton
			if _kb("fire") < 0 and mb.button_index == -_kb("fire"):
				mouse_down = mb.pressed
				if mb.pressed and current_weapon == 0:
					click_queued = true
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				_switch_weapon((current_weapon + 1) % 3)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				_switch_weapon((current_weapon + 2) % 3)

func _handle_input() -> void:
	# Cliente MP: no dispara local, solo marca el input para enviar al host
	if mp_role == 2:
		if my_slot >= slot_states.size():
			return
		var st: Dictionary = slot_states[my_slot]
		st.aim = [yaw, pitch]
		st.weapon = current_weapon
		if mouse_down:
			st.shoot = true  # Todas las armas: dispara al mantener (host aplica cadencia)
		return

	# Solo / Host: disparo local â€” todas las armas disparan al mantener presionado
	if mouse_down:
		_shoot()

# â”€â”€â”€ GAME FLOW â”€â”€â”€
func _start_game() -> void:
	current_menu = ""  # ninguna pantalla de menu sigue abierta durante la partida
	if ui_start:
		ui_start.play()
	if music_enabled and music_player:
		music_player.play()
	# â”€â”€ RESET COMPLETO DE ESTADO (evita fugas de la partida anterior) â”€â”€
	click_queued = false
	mouse_down = false
	last_shot_time = 0.0
	dual_toggle = 0
	current_weapon = 0
	_switch_weapon_visual()
	yaw = 0.0
	pitch = 0.0
	camera.rotation = Vector3(pitch, yaw, 0)
	# Invalidar callbacks pendientes de la partida anterior (booms de base, artillerÃ­a, etc.)
	game_generation += 1
	# Timers one-shot colgados del nodo raÃ­z (artillerÃ­a, etc.)
	for ch in get_children():
		if ch is Timer:
			ch.queue_free()
	# Fuegos persistentes de la destrucciÃ³n de base anterior
	for nbf in get_tree().get_nodes_in_group("BaseBoomFire"):
		(nbf as Node).queue_free()
	phase = GamePhase.PLAYING
	health = 150.0  # base al 100% (estado perfecto)
	score = 0
	wave = 1
	ammo = [999999, 300, 20]
	combat_pts = 0
	abl_rapid_t = 0.0
	abl_shield_t = 0.0
	abl_overload_t = 0.0
	abl_mines.clear()
	enemies.clear()
	projectiles.clear()
	enemy_projectiles.clear()
	if _fx != null:
		_fx.release_all()  # particulas y luces de vuelta al pool (no se liberan)
	_vfx_release_all()
	crates.clear()
	crate_timer = 8.0
	# Remove old enemy/projectile/mine/VFX nodes (los VFX se agregan al nodo raÃ­z y no se liberaban solas)
	# Limpieza por grupo: a prueba de renombrados por colisiÃ³n de nombres y de nodos sin nombre
	_free_player_avatars()  # avatares de una partida MP anterior (single no los construye)
	for pm in get_tree().get_nodes_in_group("PlayerMines"):
		(pm as Node).queue_free()
	for dn in get_tree().get_nodes_in_group("DynNodes"):
		(dn as Node).queue_free()
	for child in get_children():
		if child.name.begins_with("Enemy_") or child.name.begins_with("Proj_") or child.name.begins_with("EProj_") or child.name.begins_with("Crate_") or child.name.begins_with("Mine_") or child.name.begins_with("FX_") or child.name == "ShieldVis":
			child.queue_free()
	# Limpiar la lista de VFX activos
	_vfx_release_all()  # devuelve las instancias Binbun al pool (no las libera)
	# Clear all transient overlays; keep persistent HUD (hp, score, wave, weapon, ammo, music)
	_hud.clear_overlay_nodes()
	entering_initials = false
	initials = ""
	# Base intacta al comenzar (apaga fuego/humo de una partida anterior)
	base_destroying = false
	base_explosion_timer = 999.0
	_apply_base_fire_stage(0)
	_debug_apply_start()  # TEMPORAL: arranque en oleada alta (ver DEBUG_START_WAVE)
	_start_wave()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _switch_weapon(i: int) -> void:
	current_weapon = i
	if mp_role == 2 and my_slot < slot_states.size():
		slot_states[my_slot].weapon = i
	elif mp_role == 3 and slot_states.size() > 0:
		slot_states[0].weapon = i
	_switch_weapon_visual()
	if split_mode and gun_a != null:
		_set_gun_visible(gun_a, i)
	# Update weapon indicator
	var wpn_lbl: Label = hud.get_node_or_null("WeaponIndicator/WeaponLabel") as Label
	if wpn_lbl:
		var wname: String = _tr("wpn%d" % i)
		var wammo: String = "âˆž" if i == 0 else str(ammo[i])
		wpn_lbl.text = "  %s: %s  " % [wname, wammo]

# â”€â”€â”€ HABILIDADES ESPECIALES â”€â”€â”€
func _update_abilities(delta: float) -> void:
	# Timers
	if abl_rapid_t > 0.0: abl_rapid_t = maxf(0.0, abl_rapid_t - delta)
	if abl_shield_t > 0.0: abl_shield_t = maxf(0.0, abl_shield_t - delta)
	if abl_overload_t > 0.0: abl_overload_t = maxf(0.0, abl_overload_t - delta)
	# Minas: colisiÃ³n con enemigos (validar instancias ANTES de asignarlas a variables tipadas)
	var mines_to_remove: Array = []
	for i in abl_mines.size():
		var mn: Dictionary = abl_mines[i]
		var mine_node: Node3D = null
		if mn.has("node") and is_instance_valid(mn["node"]):
			mine_node = mn["node"]
		if mine_node == null:
			mines_to_remove.append(i)
			continue
		# Detona si hay un enemigo DENTRO del radio (2.5 m) â†’ onda expansiva AoE
		var detonar := false
		for j in enemies.size():
			var en: Dictionary = enemies[j]
			var enode_v: Variant = en.get("node")
			if enode_v == null or not is_instance_valid(enode_v):
				continue
			var enode: Node3D = enode_v
			if enode.position.distance_to(mine_node.position) < 2.5:
				detonar = true
				break
		if detonar:
			_mine_explosion(mine_node.position)
			mine_node.queue_free()
			mines_to_remove.append(i)
	# Remover minas activadas (de atrÃ¡s hacia adelante)
	for i in range(mines_to_remove.size() - 1, -1, -1):
		abl_mines.erase(mines_to_remove[i])

# â”€â”€â”€ MENÃš DE HABILIDADES (tecla B) â”€â”€â”€
var _abilities_menu_open := false   # P1/solo: menÃº de habilidades abierto
var _abl1_open := false             # P2 (split): menÃº abierto â€” INDEPENDIENTE del de P1
var _abl_menu_nodes: Array = []    # P1/solo: nodos del menÃº (escala a su mitad en split)
var _abl1_nodes: Array = []        # P2 (split): nodos del menÃº
var _abl1_nav := {"btns": [], "focus": null, "idx": 0}  # P2 (split): navegaciÃ³n independiente

func _abl_nodes_of(p: int) -> Array:
	return _abl1_nodes if p == 1 else _abl_menu_nodes

# (Nombres y descripciones de habilidades: ver tablas en scripts/i18n.gd â†’ abl_name_* / abl_desc_*)

func _toggle_abilities_menu(p_player: int = 0) -> void:
	var now_open: bool
	if p_player == 1:
		_abl1_open = not _abl1_open
		now_open = _abl1_open
	else:
		_abilities_menu_open = not _abilities_menu_open
		now_open = _abilities_menu_open
	if now_open:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_show_abilities_menu(p_player)
	else:
		# Cierra SOLO el menÃº de este jugador (en split no afecta al otro)
		var nodes: Array = _abl_nodes_of(p_player)
		for nd in nodes:
			if is_instance_valid(nd):
				var n := nd as Node
				if n.get_parent() != null:
					n.get_parent().remove_child(n)
				n.queue_free()
		nodes.clear()
		if p_player == 0:
			if menu_nav_focused != null and is_instance_valid(menu_nav_focused):
				_menu_nav_restore(menu_nav_focused)
			menu_nav_focused = null
			menu_nav_buttons.clear()
			menu_nav_index = 0
		else:
			_abl1_nav = {"btns": [], "focus": null, "idx": 0}
		if not _abilities_menu_open and not _abl1_open and phase == GamePhase.PLAYING:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _show_abilities_menu(p: int) -> void:
	# Limpieza acotada: libera solo los nodos previos de ESTE jugador (en split no toca los del otro)
	var nodes: Array = _abl_nodes_of(p)
	for nd in nodes:
		if is_instance_valid(nd):
			var n := nd as Node
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	nodes.clear()
	if p == 0:
		if menu_nav_focused != null and is_instance_valid(menu_nav_focused):
			_menu_nav_restore(menu_nav_focused)
		menu_nav_focused = null
		menu_nav_buttons.clear()
		menu_nav_index = 0
	else:
		_abl1_nav = {"btns": [], "focus": null, "idx": 0}

	var suf := str(p)  # sufijo de nodo por jugador (AbBtn_Q0 / AbBtn_Q1)
	var abl_overlay := _hud.make_overlay("AbMenuOverlay" + suf, Color(0.02, 0.04, 0.08, 0.78))
	nodes.append(abl_overlay)
	var abl_title := _hud.make_label("AbTitle" + suf, Vector2(700, 140), _tr("abl_title"), 48, Color(1.0, 0.85, 0.3))
	nodes.append(abl_title)
	var abl_pts := _hud.make_label("AbPts" + suf, Vector2(760, 220), _tr("abl_pts") % combat_pts, 26, Color(1.0, 0.9, 0.4))
	nodes.append(abl_pts)
	# Columna izquierda: 6 botones apilados (bajado hacia el centro de la pantalla)
	var keys := ["Q", "E", "R", "T", "F", "G"]
	var bx := 160.0
	var by := 320.0
	for i in keys.size():
		var k: String = keys[i]
		var abl_nm: String = ABL_KEYS[k]
		var cost: int = ABL_COSTS[abl_nm]
		var abl_disp: String = _tr("abl_name_" + k.to_lower())
		var affordable: bool = combat_pts >= cost
		var btn := _hud.make_button("AbBtn_%s%s" % [k, suf], Vector2(bx, by + i * 100), "%s â€” %s  (%d)" % [_abl_key_disp(k), abl_disp, cost], _on_abl_btn.bind(k, p), false)
		btn.disabled = not affordable
		btn.set_meta("abl_key", k)  # navegaciÃ³n por joystick: el foco muestra la descripciÃ³n
		btn.set_meta("abl_player", p)
		# Solo en single (ratÃ³n) el hover muestra la descripciÃ³n. En split (joystick) la
		# descripciÃ³n la maneja el FOCO de cada jugador, y el mouse NO debe pisar el menÃº
		# (antes el mouse de P1 borraba la descripciÃ³n de P2 al pasar por sus botones).
		if p == 0 and mp_role != 3:
			btn.mouse_entered.connect(_show_abl_desc.bind(k, p))
			btn.mouse_exited.connect(_clear_abl_desc.bind(p))
		nodes.append(btn)
		if p == 0:
			menu_nav_buttons.append(btn)
		else:
			(_abl1_nav["btns"] as Array).append(btn)
	# Recuadro derecho: descripciÃ³n
	var desc_panel := PanelContainer.new()
	desc_panel.name = "AbDescPanel" + suf
	desc_panel.position = Vector2(750, 250)
	desc_panel.size = Vector2(1100, 560)
	var dp_sb := StyleBoxFlat.new()
	dp_sb.bg_color = Color(0.03, 0.05, 0.1, 0.85)
	dp_sb.border_width_top = 2
	dp_sb.border_width_bottom = 2
	dp_sb.border_width_left = 2
	dp_sb.border_width_right = 2
	dp_sb.border_color = Color(0.3, 0.4, 0.6, 0.6)
	dp_sb.corner_radius_top_left = 8
	dp_sb.corner_radius_top_right = 8
	dp_sb.corner_radius_bottom_left = 8
	dp_sb.corner_radius_bottom_right = 8
	dp_sb.content_margin_left = 30
	dp_sb.content_margin_right = 30
	dp_sb.content_margin_top = 25
	dp_sb.content_margin_bottom = 25
	desc_panel.add_theme_stylebox_override("panel", dp_sb)
	var desc_lbl := Label.new()
	desc_lbl.name = "AbDescLabel"
	desc_lbl.text = _tr("abl_placeholder")
	desc_lbl.add_theme_font_size_override("font_size", 30)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(600, 300)
	desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_panel.add_child(desc_lbl)
	desc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(desc_panel)
	nodes.append(desc_panel)
	var abl_hint := _hud.make_label("AbHint" + suf, Vector2(640, 940), _abl_hint_text(), 20, Color(1, 1, 1, 0.6))
	nodes.append(abl_hint)
	# Split: el menÃº se contiene a la mitad del jugador que lo abriÃ³ (no invade la vista del otro)
	if mp_role == 3:
		var vps := get_viewport().get_visible_rect().size
		var off := Vector2(vps.x * 0.5, 0.0) if p == 1 else Vector2.ZERO
		for nd in nodes:
			(nd as Control).position = (nd as Control).position * 0.5 + off
			(nd as Control).scale = hud_scale * 0.5
	# Auto-foco inicial cuando se navega por joystick (split): muestra la 1Âª descripciÃ³n.
	# P2 usa su navegaciÃ³n propia (_abl1_nav); P1 en split usa la global (menu_nav_*).
	if mp_role == 3:
		var fbtns: Array = (menu_nav_buttons if p == 0 else _abl1_nav["btns"]) as Array
		if not fbtns.is_empty():
			var f0: Button = fbtns[0]
			if p == 1:
				_abl1_nav["idx"] = 0
				_abl1_nav["focus"] = f0
			else:
				menu_nav_index = 0
				menu_nav_focused = f0
			_menu_nav_apply_focus(f0)

func _show_abl_desc(k: String, p: int = 0) -> void:
	var desc_lbl: Label = hud.get_node_or_null("AbDescPanel%s/AbDescLabel" % p) as Label
	if desc_lbl:
		desc_lbl.text = "%s\n\n%s" % [_tr("abl_name_" + k.to_lower()), _tr("abl_desc_" + k.to_lower())]
		desc_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))

func _clear_abl_desc(p: int = 0) -> void:
	var desc_lbl: Label = hud.get_node_or_null("AbDescPanel%s/AbDescLabel" % p) as Label
	if desc_lbl:
		desc_lbl.text = _tr("abl_placeholder")
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))

func _on_abl_btn(k: String, p: int = 0) -> void:
	_activate_ability(k)
	# Refresca SOLO el menÃº de este jugador (no toca el del otro en split)
	_show_abilities_menu(p)

# â”€â”€â”€ NAVEGACIÃ“N DEL MENÃš DE P2 (split): independiente de la global â”€â”€â”€
func _abl1_nav_step(p_dir: int) -> void:
	var btns: Array = _abl1_nav["btns"]
	if btns.is_empty():
		return
	var idx: int = int(_abl1_nav["idx"])
	idx = (idx + p_dir) % btns.size()
	if idx < 0:
		idx += btns.size()
	var target: Button = btns[idx]
	var focus: Button = _abl1_nav["focus"]
	if focus != null and is_instance_valid(focus) and focus != target:
		_menu_nav_restore(focus)
	_abl1_nav["idx"] = idx
	_abl1_nav["focus"] = target
	_menu_nav_apply_focus(target)
	if ui_select:
		ui_select.play()

func _abl1_nav_confirm() -> bool:
	var btns: Array = _abl1_nav["btns"]
	if btns.is_empty():
		return false
	var focus: Button = _abl1_nav["focus"]
	if focus == null or not is_instance_valid(focus):
		focus = btns[0] as Button
		_abl1_nav["focus"] = focus
		_abl1_nav["idx"] = 0
		_menu_nav_apply_focus(focus)
	focus.pressed.emit()
	return true

func _activate_ability(key: String) -> void:
	var abl_name: String = ABL_KEYS.get(key, "")
	var cost: int = ABL_COSTS.get(abl_name, 9999)
	if combat_pts < cost:
		_spawn_floating_text(camera.position + Vector3(0, -1, -3), _tr("ft_notenough") % [combat_pts, cost], Color(1, 0.4, 0.4))
		return
	combat_pts -= cost
	match abl_name:
		"rapid":
			abl_rapid_t = 5.0
			_spawn_floating_text(camera.position + Vector3(0, -0.5, -3), _tr("ft_burst"), Color(0.3, 1.0, 0.3))
		"shield":
			abl_shield_t = 8.0
			_spawn_floating_text(camera.position + Vector3(0, -0.5, -3), _tr("ft_shield"), Color(0.3, 0.6, 1.0))
			_spawn_shield_visual()
		"mines":
			_place_mines(8)
			_spawn_floating_text(camera.position + Vector3(0, -0.5, -3), _tr("ft_mines"), Color(0.9, 0.7, 0.2))
		"artillery":
			_fire_artillery()
			_spawn_floating_text(camera.position + Vector3(0, 0.5, -5), _tr("ft_bomb"), Color(1.0, 0.5, 0.2))
		"overload":
			abl_overload_t = 5.0
			ammo[2] = mini(ammo[2] + 5, 999)
			_spawn_floating_text(camera.position + Vector3(0, -0.5, -3), _tr("ft_overload"), Color(1.0, 0.8, 0.3))
		"repair":
			var heal := base_hp_max * 0.3
			health = minf(health + heal, base_hp_max)
			_spawn_floating_text(Vector3(0, 3, 15), _tr("ft_repair") % heal, Color(0.4, 1.0, 0.4))
	_hud.update_hud()

# â”€â”€â”€ DETONACIÃ“N DE MINA (AoE) â”€â”€â”€
# Radio y daÃ±o: ver GameConfig.MINE_RADIUS / MINE_DMG (similares al caÃ±Ã³n del Arma 3).
func _mine_explosion(pos: Vector3) -> void:
	# La onda expansiva puede llevar a enemigos fuera del trigger: matan a todos del radio
	var to_kill: Array = []
	for j in range(enemies.size()):
		var e: Dictionary = enemies[j]
		var en_v: Variant = e.get("node")
		if en_v == null or not is_instance_valid(en_v):
			continue
		var enode: Node3D = en_v
		if enode.position.distance_to(pos) > MINE_RADIUS:
			continue
		if e["type"] == "tank":
			# Tanque: -1 blindaje (igual que el splash del caÃ±Ã³n)
			var armor: int = int(e.get("armor", 2))
			armor -= 1
			e["armor"] = armor
			_hit_spark(enode.position, 8, Color(0.85, 0.8, 0.3))
			if armor <= 0:
				to_kill.append(j)
		else:
			e["health"] = float(e["health"]) - MINE_DMG
			if float(e["health"]) <= 0.0:
				to_kill.append(j)
	# Boom grande (1 sola explosiÃ³n, coherente con la regla de booms)
	_big_boom(pos, 1.3, Color(1.0, 0.6, 0.2), true)
	# Matar de atrÃ¡s hacia adelante para no desfasar Ã­ndices
	for i in range(to_kill.size() - 1, -1, -1):
		_kill_enemy(int(to_kill[i]))

# Distancia mÃ­nima a cualquier punto (9999 si la lista estÃ¡ vacÃ­a) â€” delegado en WorldMath
func _min_dist_to(positions: Array, p: Vector3) -> float:
	return WorldMath.min_dist_to(positions, p)

func _place_mines(count: int) -> void:
	# Cobertura de TODO el frente (incl. laterales) SIN agrupar activaciones seguidas:
	#  - grilla 2 filas Ã— 4 columnas (cobertura garantizada de la banda)
	#  - offset aleatorio POR ACTIVACIÃ“N (cada R cae en otro sector)
	#  - jitter amplio (Â±5m) + rechazo: cada candidata se re-rollea hasta quedar
	#    a â‰¥8m de cualquier mina ya activa (o toma la mejor de 13 intentos)
	var cols_x := [-34.0, -11.5, 11.5, 34.0]
	var rows_z := [-24.0, -12.0]
	var off_x := randf_range(-8.0, 8.0)
	var off_z := randf_range(-4.0, 4.0)
	var existing: Array = []
	for mn in abl_mines:
		if mn.has("node") and is_instance_valid(mn["node"]):
			existing.append((mn["node"] as Node3D).position)
	for i in count:
		var variant := 1 if i % 2 == 0 else 2
		var m := _create_mine_visual(variant)
		var col: int = i % cols_x.size()
		var row: int = int(floor(i / float(cols_x.size()))) % rows_z.size()  # divisiÃ³n float + floor = Ã­ndice de fila (sin aviso de divisiÃ³n entera)
		# Etapa 1: mejor candidato de 25 alrededor de la celda de la grilla (â‰¥8m objetivo)
		var best_x := clampf(cols_x[col] + off_x + randf_range(-5.0, 5.0), -38.0, 38.0)
		var best_z := clampf(rows_z[row] + off_z + randf_range(-4.0, 4.0), -30.0, -8.0)
		var best_d := _min_dist_to(existing, Vector3(best_x, 0, best_z))
		for t in 24:
			var tx := clampf(cols_x[col] + off_x + randf_range(-5.0, 5.0), -38.0, 38.0)
			var tz := clampf(rows_z[row] + off_z + randf_range(-4.0, 4.0), -30.0, -8.0)
			var d := _min_dist_to(existing, Vector3(tx, 0, tz))
			if d > best_d:
				best_d = d
				best_x = tx
				best_z = tz
			if d >= 8.0:
				break
		# Etapa 2: si quedÃ³ <5m de alguna mina, re-busca en banda amplia (Â±18m)
		if best_d < 5.0:
			for t in 40:
				var tx := clampf(cols_x[col] + randf_range(-18.0, 18.0), -38.0, 38.0)
				var tz := clampf(rows_z[row] + off_z + randf_range(-6.0, 6.0), -30.0, -8.0)
				var d := _min_dist_to(existing, Vector3(tx, 0, tz))
				if d > best_d:
					best_d = d
					best_x = tx
					best_z = tz
				if d >= 8.0:
					break
		var px := best_x
		var pz := best_z
		m.position = Vector3(px, _terrain_height(px, pz) + 0.16, pz)
		m.rotation.y = randf_range(0.0, TAU)
		m.name = "Mine_%d" % i
		m.add_to_group("PlayerMines")
		add_child(m)
		abl_mines.append({"node": m, "armed": true})
		existing.append(Vector3(px, 0, pz))

func _create_mine_visual(variant: int) -> Node3D:
	# Mina 3D autocontenida (estilo low-poly, coherente con el resto del juego).
	# variant 1 = mina domo con placa de presiÃ³n; variant 2 = klaymore direccional.
	var root := Node3D.new()
	var olive := Color(0.26, 0.28, 0.17)   # verde oliva
	var dark := Color(0.14, 0.14, 0.15)    # gris oscuro (klaymore)
	var steel := Color(0.34, 0.35, 0.37)   # aro metÃ¡lico
	var black := Color(0.07, 0.07, 0.07)
	var red := Color(0.74, 0.08, 0.07)     # botÃ³n de armado (pequeÃ±o, no "globo")

	if variant == 2:
		# â”€â”€ Klaymore direccional (caja baja + placa frontal inclinada) â”€â”€
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.56, 0.24, 0.36)
		body.mesh = bm
		body.material_override = _mat_std(dark, 0.75, 0.30)
		root.add_child(body)
		var plate := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.5, 0.22, 0.06)
		plate.mesh = pm
		plate.material_override = _mat_std(black, 0.5, 0.4)
		plate.position = Vector3(0.0, 0.02, 0.17)
		plate.rotation.x = -0.32
		root.add_child(plate)
		var btn := MeshInstance3D.new()
		var btm := CylinderMesh.new()
		btm.top_radius = 0.055; btm.bottom_radius = 0.07; btm.height = 0.06
		btn.mesh = btm
		btn.material_override = _mat_emis(red, 0.35, Color(0.45, 0.06, 0.05))
		btn.position = Vector3(0.0, 0.15, -0.06)
		root.add_child(btn)
	else:
		# â”€â”€ Mina domo con placa de presiÃ³n â”€â”€
		var body := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.42; bm.bottom_radius = 0.5; bm.height = 0.3; bm.radial_segments = 20
		body.mesh = bm
		body.material_override = _mat_std(olive, 0.9, 0.1)
		root.add_child(body)
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.34; rm.bottom_radius = 0.36; rm.height = 0.06; rm.radial_segments = 20
		ring.mesh = rm
		ring.material_override = _mat_std(steel, 0.55, 0.7)
		ring.position = Vector3(0.0, 0.15, 0.0)
		root.add_child(ring)
		var btn := MeshInstance3D.new()
		var btm := CylinderMesh.new()
		btm.top_radius = 0.09; btm.bottom_radius = 0.11; btm.height = 0.06; btm.radial_segments = 16
		btn.mesh = btm
		btn.material_override = _mat_emis(red, 0.35, Color(0.45, 0.06, 0.05))
		btn.position = Vector3(0.0, 0.2, 0.0)
		root.add_child(btn)
	return root

func _mat_std(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func _mat_emis(color: Color, roughness: float, emis: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.1
	m.emission_enabled = true
	m.emission = emis
	return m

func _fire_artillery() -> void:
	# 24 misiles (3x) repartidos por TODA la playa: desde la orilla (zâ‰ˆ-28)
	# hasta la lÃ­nea donde los soldados se detienen frente a la base (zâ‰ˆ26),
	# cubriendo el ancho completo incluidos los laterales. DaÃ±o 160 por impacto.
	if missile_sfx != null:
		missile_sfx.play()  # silbato de la barrera entrante
	var cols_x := [-34.0, -17.0, 0.0, 17.0, 34.0]
	var rows_z := [-28.0, -14.0, 0.0, 14.0, 26.0]
	var targets: Array = []
	for r in rows_z.size():
		for c in cols_x.size():
			var tx := clampf(cols_x[c] + randf_range(-4.0, 4.0), -40.0, 40.0)
			var tz := clampf(rows_z[r] + randf_range(-3.0, 3.0), -33.0, 28.0)
			targets.append(Vector3(tx, _terrain_height(tx, tz) + 0.3, tz))
	targets.shuffle()
	for i in mini(24, targets.size()):
		_drop_artillery_missile(targets[i], 0.35 + i * 0.22)

func _drop_artillery_missile(target: Vector3, delay: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = delay
	add_child(t)
	t.timeout.connect(_launch_art_missile.bind(target))
	t.start()

func _launch_art_missile(target: Vector3) -> void:
	# Misil visible que cae del cielo al punto de impacto y explota
	var mis := _create_missile()
	mis.scale = Vector3.ONE * 1.8
	var start := target + Vector3(randf_range(-5, 5), 60.0 + randf_range(0, 20), randf_range(-5, 5))
	mis.position = start
	add_child(mis)
	mis.add_to_group("DynNodes")
	mis.look_at(target, Vector3.UP)
	var tw := create_tween()
	tw.tween_property(mis, "position", target, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_artillery_impact.bind(target))
	tw.tween_callback(mis.queue_free)

func _artillery_impact(pos: Vector3) -> void:
	# DaÃ±o en Ã¡rea a enemigos (colectar primero, matar despuÃ©s). 160 por impacto (2x).
	var to_kill: Array = []
	var kills_vehicle := false
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		var enode: Node3D = e["node"]
		if enode.position.distance_to(pos) < 10.0:
			e["health"] = float(e["health"]) - 160.0
			if float(e["health"]) <= 0.0:
				to_kill.append(i)
				if e["type"] == "boat" or e["type"] == "plane" or e["type"] == "tank":
					kills_vehicle = true
	# Anti doble explosiÃ³n: si el impacto destruye un vehÃ­culo, su boom de muerte
	# reemplaza al de artillerÃ­a. Si solo cae sobre soldados/agua, suena el boom.
	if not kills_vehicle:
		_big_boom(pos, 1.9, Color(1.0, 0.5, 0.1), true)
	# Matar de atrÃ¡s hacia adelante para no desfasar Ã­ndices
	for i in range(to_kill.size() -1, -1, -1):
		_kill_enemy(to_kill[i])

func _spawn_shield_visual() -> void:
	# Escudo sobre la BASE MILITAR (z 40-70, x Â±45)
	var sh := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sh.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 1.0, 0.15)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sh.material_override = mat
	sh.position = Vector3(0, 0, 55)  # centro de la base
	sh.scale = Vector3(50, 12, 20)  # cubre x Â±50, y 0-12, z 35-75
	sh.name = "ShieldVis"
	add_child(sh)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 8.0
	add_child(t)
	t.timeout.connect(_free_node.bind(sh))
	t.start()

func shockwave_shake(amt: float) -> void:
	shake_amount = maxf(shake_amount, amt)

# â”€â”€â”€ WAVE SYSTEM â”€â”€â”€
# Escala de enemigos por cantidad de jugadores (decisiÃ³n de la sesiÃ³n 3P/4P): la vida de la
# base ya escala (base_hp_max = 100 + 50*(n-1)) y cada estaciÃ³n suma fuego, asÃ­ que sin mÃ¡s
# enemigos una partida de 4 era mucho mÃ¡s fÃ¡cil que una de 2.
# La fÃ³rmula arranca reciÃ©n con 3 jugadores: SINGLE (n=1) y SPLIT/LAN 2P (n=2) quedan con
# factor 1.0, exactamente como estaban validados.
func _spawn_scale() -> float:
	if mp_players >= 3:
		return 0.6 + 0.4 * float(mp_players)  # 3P x1.8 Â· 4P x2.2
	return 1.0  # single y 2P (LAN o split): sin cambios

# Intervalo entre lanchas: con 3-4 jugadores se acorta en la misma proporciÃ³n que la
# cantidad (una oleada de 4P no puede durar el doble que una de 2P). Para 1P/2P devuelve
# EXACTAMENTE el valor de siempre (piso 0.6 s); con escala aplica un piso propio de 0.45 s
# para que el spawn nunca sea un goteo instantÃ¡neo.
func _spawn_gap() -> float:
	var base := maxf(0.6, 3.5 - wave * 0.2)
	var spawn_scale := _spawn_scale()
	if spawn_scale <= 1.0:
		return base
	return maxf(0.45, base / spawn_scale)

func _start_wave() -> void:
	var spawn_scale := _spawn_scale()
	# Cantidad de lanchas de la oleada (los aviones aparecen aparte, ver _update_wave)
	enemies_to_spawn = maxi(1, int(float(3 + wave * 2) * spawn_scale))
	# La misma escala acorta el intervalo entre lanchas: la oleada dura lo mismo pero con
	# mÃ¡s enemigos (si no, en 4P el spawn de una oleada tardaba el doble). Ver _spawn_gap.
	spawn_timer = 0.0

func _update_wave(delta: float) -> void:
	if enemies_to_spawn > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			_spawn_boat()
			if wave >= 3 and randf() < 0.3:
				_spawn_plane_from_warship()
			enemies_to_spawn -= 1
			spawn_timer = _spawn_gap()
	elif enemies.size() == 0:
		if ui_levelup:
			ui_levelup.play()
		wave += 1
		ammo[1] = mini(ammo[1] + 80, 400)
		ammo[2] = mini(ammo[2] + 5, 50)
		combat_pts += 25  # bonus por completar oleada
		_start_wave()

# â”€â”€â”€ SPAWNING â”€â”€â”€
func _spawn_boat() -> void:
	var side := randf_range(-50, 50)
	var dist := randf_range(50, 80)
	var count := 6
	var boat := _create_boat_mesh(count)
	boat.position = Vector3(side, -0.1, -dist)  # hull floats on the water (waterline y=-0.35)
	boat.name = "Enemy_Boat_%d" % enemies.size()
	add_child(boat)
	boat.add_to_group("DynNodes")
	var has_tank: bool = wave >= 3 and randf() < 0.4
	var bid := _id_seq
	_id_seq += 1
	enemies.append({
		"id": bid, "node": boat, "type": "boat", "health": 30.0 + wave * 5.0,
		"speed": 2.5 + wave * 0.2, "soldiers": count,
		"shore_z": randf_range(-40, -34),
		"has_tank": has_tank
	})

func _heli_init(e: Dictionary) -> void:
	# Ã“rbita alrededor de la base (se acerca al jugador y la rodea; nunca sale solo)
	e["orbit_cx"] = base_target.x
	e["orbit_cz"] = base_target.z
	e["orbit_r"] = randf_range(26.0, 42.0)
	e["orbit_alt"] = randf_range(14.0, 22.0)
	e["orbit_speed"] = randf_range(0.20, 0.34)
	e["orbit_dir"] = 1.0 if randf() < 0.5 else -1.0
	e["orbit_ang"] = randf_range(0.0, TAU)

func _spawn_plane_from_warship() -> void:
	# Sale de un buque de guerra aleatorio (sobre la cubierta) y vuela hacia la base
	var spawn_pos := Vector3(randf_range(-60.0, 60.0), 22.0, -150.0)
	if warship_spots.size() > 0:
		spawn_pos = warship_spots[randi() % warship_spots.size()]
	var plane := _create_plane_mesh()
	plane.position = spawn_pos
	plane.name = "Enemy_Plane_%d" % enemies.size()
	add_child(plane)
	plane.add_to_group("DynNodes")
	var pid2 := _id_seq
	_id_seq += 1
	var e := {
		"id": pid2, "node": plane, "type": "plane", "health": minf(40.0 + wave * 5.0, 180.0),
		"speed": 11.0 + wave * 0.35, "shoot_timer": 999.0,
		"phase": "approach"
	}
	_heli_init(e)
	enemies.append(e)

func _disembark_soldier(e: Dictionary) -> void:
	var node: Node3D = e["node"]
	var pos: Vector3 = node.position
	pos.z = -21.0 + randf_range(-6.0, 7.0)  # banda amplia de playa seca (mas dispersion)
	pos.x += randf_range(-14, 14)            # dispersion lateral amplia (evitar peloton)
	pos.x = clampf(pos.x, -38.0, 38.0)
	pos.y = _terrain_height(pos.x, pos.z)
	var soldier := _create_soldier_mesh()
	soldier.position = pos
	soldier.scale = Vector3(1.3, 1.3, 1.3)  # 2.0x reducido 35% (usuario)
	soldier.name = "Enemy_Soldier_%d" % enemies.size()
	add_child(soldier)
	soldier.add_to_group("DynNodes")
	var sid := _id_seq
	_id_seq += 1
	enemies.append({
		"id": sid, "node": soldier, "type": "soldier", "health": 8.0,  # one-shot by arma 1 (15) y arma 2 (8)
		"speed": (2.0 + wave * 0.15) * randf_range(0.85, 1.25), "shoot_timer": 0.4,
		"state": "running", "run_dir": Vector2(randf_range(-1.0, 1.0), 1.6).normalized(),
		"stop_t": randf_range(1.5, 4.0), "shots_left": 0, "aim_t": 0.0
	})

func _disembark_tank(e: Dictionary) -> void:
	var node: Node3D = e["node"]
	var pos: Vector3 = node.position
	pos.z = -26.0 + randf_range(-2.0, 4.0)  # dry beach, just in front of the waterline
	pos.x += randf_range(-4, 4)
	pos.y = 0.0
	var tank := _create_tank_mesh()
	tank.position = pos
	tank.name = "Enemy_Tank_%d" % enemies.size()
	add_child(tank)
	tank.add_to_group("DynNodes")
	var tid2 := _id_seq
	_id_seq += 1
	enemies.append({
		"id": tid2, "node": tank, "type": "tank", "health": 2.0, "armor": 2,
		"speed": 1.0 + wave * 0.05, "shoot_timer": randf_range(3, 5)
	})
# â”€â”€â”€ ENEMY MESHES â”€â”€â”€
func _create_soldier_mesh() -> Node3D:
	# Soldado realista con AK (char_soldier.glb, CC0, con animaciones)
	var model_scene: PackedScene = load("res://assets/soldiers2/char_soldier.glb")
	if model_scene == null:
		return _create_soldier_fallback()
	var model: Node3D = model_scene.instantiate()

	# â”€â”€ Esconder el rack de armas ANTES de medir (inflarÃ­an el tamaÃ±o): solo queda el AK â”€â”€
	var hide_weapons := ["Revolver", "Sniper", "Revolver_Small", "Pistol", "SMG",
		"GrenadeLauncher", "ShortCannon", "Shotgun", "Sniper_2", "RocketLauncher",
		"Shovel", "Knife_1", "Knife_2"]
	for mi_node in model.find_children("", "MeshInstance3D"):
		var mi := mi_node as MeshInstance3D
		if mi != null and hide_weapons.has(mi.name):
			# Se LIBERAN, no solo se esconden: 13 MeshInstance3D por soldado quedaban
			# atados al Skeleton3D como superficies skinned que nunca se dibujaban.
			mi.visible = false
			mi.free()

	# â”€â”€ Normalizar: alto 1.75 m, pies en y=0, centrado en el origen â”€â”€
	var combined := AABB()
	var has_any := false
	for mi_node in model.find_children("", "MeshInstance3D"):
		var mi := mi_node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		# AABB en el espacio del root: encadenar transforms hasta el root
		var t := Transform3D.IDENTITY
		var p: Node3D = mi
		while p != null and p != model:
			t = p.transform * t
			p = p.get_parent() as Node3D
		var aab: AABB = t * mi.mesh.get_aabb()
		if has_any:
			combined = combined.merge(aab)
		else:
			combined = aab
		has_any = true
	if not has_any:
		model.free()
		return _create_soldier_fallback()
	var sc: float = 1.75 / maxf(combined.size.y, 0.0001)
	var content := model.get_node_or_null("RootNode") as Node3D
	if content != null:
		content.position = Vector3(
			-((combined.position.x + combined.end.x) * 0.5),
			-combined.position.y,
			-((combined.position.z + combined.end.z) * 0.5)
		)
	model.scale = Vector3(sc, sc, sc)

	# Game-logic animation aliases (walk/idle/run/shoot/fall)
	var ap := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null:
		var lib := AnimationLibrary.new()
		_alias_anim(ap, lib, "walk", "CharacterArmature|Run", true)
		_alias_anim(ap, lib, "idle", "CharacterArmature|Idle", true)
		_alias_anim(ap, lib, "run", "CharacterArmature|Run", true)
		_alias_anim(ap, lib, "shoot", "CharacterArmature|Idle_Shoot", false)
		_alias_anim(ap, lib, "fall", "CharacterArmature|Death", false)
		ap.add_animation_library("default", lib)

	# Rifle (holder vacÃ­o: contrato de fogonazo; el AK propio del modelo se anima solo)
	var gun := Node3D.new()
	gun.name = "Rifle"
	var inv_sc: float = 1.0 / sc  # el root estÃ¡ escalado; compensar a unidades mundo
	gun.scale = Vector3(inv_sc, inv_sc, inv_sc)
	gun.position = Vector3(0.2, 0.95, 0.28) * inv_sc
	gun.rotation = Vector3(0, -PI / 2, 0.35)
	model.add_child(gun)
	model.set_meta("gun_inv_scale", inv_sc)
	var mflash := MeshInstance3D.new()
	var mfm := SphereMesh.new()
	mfm.radius = 0.06
	var mfm_mat := StandardMaterial3D.new()
	mfm_mat.albedo_color = Color(1, 0.9, 0.4)
	mfm_mat.emission_enabled = true
	mfm_mat.emission = Color(1, 0.8, 0.25)
	mfm_mat.emission_energy_multiplier = 8.0
	mflash.mesh = mfm
	mflash.material_override = mfm_mat
	mflash.position = Vector3(0.5, 0.0, 0.0)
	mflash.visible = false
	mflash.name = "MuzzleFlash"
	gun.add_child(mflash)

	_apply_soldier_shadow(model)
	return model

# Sombras duras de soldados (SOLDIER_CAST_SHADOW = true por pedido).
# El costo real es (superficies VISIBLES del rig) x (splits de la cascada): por eso
# el rack de armas del GLB se libera en _create_soldier_mesh y las mallas ocultas
# no proyectan. Con el rig actual quedan 5 mallas visibles (Body, Head, AK, 2 hombreras).
func _apply_soldier_shadow(model: Node3D) -> void:
	var stack: Array = [model]
	while stack.size() > 0:
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			var mi: MeshInstance3D = nd
			if SOLDIER_CAST_SHADOW and mi.visible:
				mi.cast_shadow = SHADOW_CASTING_ON
			else:
				mi.cast_shadow = SHADOW_CASTING_OFF
		for ch in nd.get_children():
			stack.append(ch)

# â”€â”€â”€ Military gear (rigid accessories synced to skeleton bones) â”€â”€â”€
func _add_military_gear(model: Node3D) -> void:
	if model.get_node_or_null("GearHelmet") != null:
		return
	var skel: Skeleton3D = model.get_node_or_null("Rig/Skeleton3D") as Skeleton3D
	var defs: Array = [
		["DEF-head", Vector3(0, 0.11, 0.02), "GearHelmet", "helmet", Color(0.24, 0.27, 0.16)],
		["DEF-spine.002", Vector3(0, 0.02, 0.04), "GearVest", "vest", Color(0.27, 0.30, 0.18)],
		["DEF-hips", Vector3(0, -0.03, 0.0), "GearBelt", "belt", Color(0.16, 0.15, 0.11)],
		["DEF-foot.L", Vector3(0, -0.02, 0.05), "GearBootL", "boot", Color(0.13, 0.13, 0.10)],
		["DEF-foot.R", Vector3(0, -0.02, 0.05), "GearBootR", "boot", Color(0.13, 0.13, 0.10)],
		["DEF-spine.001", Vector3(0, 0.14, -0.16), "GearPack", "pack", Color(0.22, 0.25, 0.15)],
	]
	for d in defs:
		var node := MeshInstance3D.new()
		node.name = d[2]
		match d[3]:
			"helmet":
				var sm := CylinderMesh.new()
				sm.bottom_radius = 0.125
				sm.top_radius = 0.055
				sm.height = 0.17
				sm.radial_segments = 16
				node.mesh = sm
			"vest":
				var bm := BoxMesh.new()
				bm.size = Vector3(0.30, 0.27, 0.26)
				node.mesh = bm
			"belt":
				var bm := BoxMesh.new()
				bm.size = Vector3(0.33, 0.08, 0.31)
				node.mesh = bm
			"boot":
				var bm := BoxMesh.new()
				bm.size = Vector3(0.10, 0.12, 0.22)
				node.mesh = bm
			"pack":
				var bm := BoxMesh.new()
				bm.size = Vector3(0.26, 0.30, 0.14)
				node.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = d[4]
		mat.roughness = 0.9
		node.material_override = mat
		node.position = d[1]
		node.set_meta("gear_bone", d[0])
		model.add_child(node)
	if skel == null:
		return
	model.set_meta("gear_items", [])
	for n in model.get_children():
		if n.has_meta("gear_bone"):
			var bi: int = skel.find_bone(n.get_meta("gear_bone"))
			if bi >= 0:
				model.get_meta("gear_items").append([n, bi, n.position])

func _sync_gear(model: Node3D) -> void:
	if not model.has_meta("gear_items"):
		return
	var items: Array = model.get_meta("gear_items")
	if items.is_empty():
		return
	var skel: Skeleton3D = model.get_node_or_null("Rig/Skeleton3D") as Skeleton3D
	if skel == null:
		return
	for it in items:
		var n: MeshInstance3D = it[0]
		var bi: int = it[1]
		n.transform = skel.get_bone_global_pose(bi) * Transform3D(Basis(), it[2])

func _enemy_muzzle_flash(soldier: Node3D) -> void:
	var gun := soldier.get_node_or_null("Rifle") as Node3D
	if gun == null:
		return
	var flash := gun.get_node_or_null("MuzzleFlash") as MeshInstance3D
	if flash == null:
		return
	flash.visible = true
	var tw := create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(func(): flash.visible = false)

func _set_soldier_gun_pose(soldier: Node3D, aiming: bool) -> void:
	var gun := soldier.get_node_or_null("Rifle") as Node3D
	if gun == null:
		return
	var gs: float = float(soldier.get_meta("gun_inv_scale")) if soldier.has_meta("gun_inv_scale") else 1.0
	if aiming:
		gun.position = Vector3(0.16, 1.08, 0.3) * gs  # in hand range, barrel toward player
		gun.rotation = Vector3(0, -PI / 2, 0.12)
	else:
		gun.position = Vector3(0.2, 0.95, 0.28) * gs
		gun.rotation = Vector3(0, -PI / 2, 0.35)

func _attach_anim(lib: AnimationLibrary, anim_name: String, fbx_path: String, src_name: String, loop: bool) -> void:
	var scene: PackedScene = load(fbx_path)
	if scene == null:
		return
	var root: Node = scene.instantiate()
	var src_ap: AnimationPlayer = root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if src_ap != null and src_ap.has_animation(src_name):
		var anim: Animation = src_ap.get_animation(src_name)
		if loop:
			anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(anim_name, anim)
	root.free()

func _create_soldier_fallback() -> Node3D:
	# Fallback: Human Basic Motions pack (animated)
	var model_scene: PackedScene = load("res://assets/humans/HumanM_Model.fbx")
	if model_scene == null:
		var g := Node3D.new()
		var body := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.3
		bm.height = 1.7
		body.mesh = bm
		body.position = Vector3(0, 0.85, 0)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.38, 0.43, 0.26)
		body.material_override = bmat
		g.add_child(body)
		return g
	var model: Node3D = model_scene.instantiate()
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	model.add_child(ap)
	var lib := AnimationLibrary.new()
	_attach_anim(lib, "walk", "res://assets/humans/animations/HumanM@Walk01_Forward.fbx", "HumanM_Walk01_Forward", true)
	_attach_anim(lib, "idle", "res://assets/humans/animations/HumanM@Idle01.fbx", "HumanM_Idle01", true)
	_attach_anim(lib, "run", "res://assets/humans/animations/HumanM@Run01_Forward.fbx", "HumanM_Run01_Forward", true)
	_attach_anim(lib, "fall", "res://assets/humans/animations/HumanM@Fall01.fbx", "HumanM_Fall01", false)
	ap.add_animation_library("default", lib)
	var gun_scene: PackedScene = load("res://assets/guns/ak47.glb")
	if gun_scene != null:
		var gun: Node3D = gun_scene.instantiate()
		gun.name = "Rifle"
		gun.position = Vector3(0.2, 0.95, 0.28)
		gun.rotation = Vector3(0, -PI / 2, 0.35)
		model.add_child(gun)
		# Muzzle flash at barrel tip (gun local +X is the barrel axis)
		var mflash := MeshInstance3D.new()
		var mfm := SphereMesh.new()
		mfm.radius = 0.05
		var mfm_mat := StandardMaterial3D.new()
		mfm_mat.albedo_color = Color(1, 0.9, 0.4)
		mfm_mat.emission_enabled = true
		mfm_mat.emission = Color(1, 0.8, 0.25)
		mfm_mat.emission_energy_multiplier = 8.0
		mfm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mflash.mesh = mfm
		mflash.material_override = mfm_mat
		mflash.position = Vector3(0.48, 0.0, 0.0)
		mflash.visible = false
		mflash.name = "MuzzleFlash"
		gun.add_child(mflash)

	_add_military_gear(model)
	_apply_soldier_shadow(model)
	return model

func _alias_anim(ap: AnimationPlayer, lib: AnimationLibrary, alias_name: String, src_name: String, loop: bool) -> void:
	if not ap.has_animation(src_name):
		return
	if lib.has_animation(alias_name):
		return
	var anim: Animation = ap.get_animation(src_name).duplicate()
	if loop:
		anim.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation(alias_name, anim)

func _free_node(n: Node) -> void:
	n.queue_free()

func _create_boat_mesh(_soldiers: int) -> Node3D:
	# Military landing craft (CC0 GLB) â€” soldiers are hidden on board, they appear at the shore
	var g := Node3D.new()
	var ps: PackedScene = load("res://assets/boats/tugboat.glb")
	if ps:
		var root: Node3D = ps.instantiate()
		# Combined local AABB (model is in cm)
		var bb := AABB()
		var stack: Array = [root]
		while stack.size() > 0:
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				if mi.mesh:
					var la: AABB = mi.transform * mi.mesh.get_aabb()
					bb = la if not bb.has_volume() else bb.merge(la)
			for c in n.get_children():
				stack.append(c)
		if bb.has_volume():
			var s: float = 12.25 / maxf(bb.size.x, bb.size.z)  # ~12.25 m landing craft (x2.5 luego -30%)
			var center := bb.get_center()
			root.scale = Vector3.ONE * s
			root.position = -Vector3(center.x, bb.position.y, center.z) * s  # center + keel on water
			root.rotation.y = PI / 2  # model bow (+X) faces travel direction (+Z)
			# Military olive tint (this build has no mesh modulate -> tinted material overrides)
			var tint := Color(0.55, 0.6, 0.45)
			var mstack: Array = [root]
			while mstack.size() > 0:
				var mn: Node = mstack.pop_back()
				if mn is MeshInstance3D:
					var mi2 := mn as MeshInstance3D
					if mi2.mesh:
						var sc: int = mi2.mesh.get_surface_count()
						for i in sc:
							var src: Material = mi2.get_active_material(i)
							if src is StandardMaterial3D:
								var sm: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
								sm.albedo_color = sm.albedo_color * tint
								mi2.set_surface_override_material(i, sm)
					for c2 in mn.get_children():
						mstack.append(c2)
			g.add_child(root)
	else:
		# Fallback: simple box hull
		var boat_mat := StandardMaterial3D.new()
		boat_mat.albedo_color = Color(0.45, 0.5, 0.35)
		boat_mat.roughness = 0.7
		var hull := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(4.0, 0.8, 2.0)
		hull.mesh = hm
		hull.material_override = boat_mat
		hull.position = Vector3(0, 0.4, 0)
		g.add_child(hull)
	return g

func _create_tank_mesh() -> Node3D:
	# Tanque realista (GLB) â€” caÃ±Ã³n hacia -Z (se orienta con look_at hacia la base)
	var g := Node3D.new()
	var holder := Node3D.new()
	g.add_child(holder)
	var _tscene = load("res://assets/vehicles/tank.glb")
	if _tscene == null:
		return g
	var model: Node3D = _tscene.instantiate()
	model.rotation.y = -PI / 2.0  # caÃ±Ã³n nativo (-X) -> -Z
	holder.add_child(model)
	var bb := _world_aabb(holder)
	var big: float = bb.size.x
	if bb.size.y > big: big = bb.size.y
	if bb.size.z > big: big = bb.size.z
	var s: float = 12.0 / big if big > 0.0 else 1.0  # ~3x el tanque anterior
	# Centrar solo X/Z: la base del casco apoyada en el suelo (no a mitad de hondo)
	var tc: Vector3 = bb.get_center()
	model.position = Vector3(-tc.x, -bb.position.y, -tc.z)
	holder.scale = Vector3.ONE * s
	return g
func _create_plane_mesh() -> Node3D:
	# HelicÃ³ptero de ataque (Apache-like), autocontenido, nariz hacia +X.
	var g := Node3D.new()
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.30, 0.34, 0.28)  # verde militar
	hull.roughness = 0.55
	hull.metallic = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.16, 0.15)
	dark.roughness = 0.7
	dark.metallic = 0.3
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.10, 0.16, 0.22)
	glass.roughness = 0.08
	glass.metallic = 0.9
	# Fuselaje (cÃ¡psula estilizada)
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.62
	bm.height = 2.6
	bm.radial_segments = 14
	bm.rings = 8
	body.mesh = bm
	body.material_override = hull
	body.scale = Vector3(2.2, 1.0, 0.95)
	g.add_child(body)
	# Morro
	var nose := MeshInstance3D.new()
	var nsm := SphereMesh.new()
	nsm.radius = 0.42
	nose.mesh = nsm
	nose.material_override = hull
	nose.position = Vector3(1.25, -0.12, 0)
	nose.scale = Vector3(1.3, 0.8, 0.85)
	g.add_child(nose)
	# Canopy (vidrio)
	var canopy := MeshInstance3D.new()
	var canm := SphereMesh.new()
	canm.radius = 0.4
	canopy.mesh = canm
	canopy.material_override = glass
	canopy.position = Vector3(1.05, 0.16, 0)
	canopy.scale = Vector3(1.0, 0.7, 0.85)
	g.add_child(canopy)
	# Cabina de cola (taper)
	var tailbody := MeshInstance3D.new()
	var tbm := CylinderMesh.new()
	tbm.top_radius = 0.18
	tbm.bottom_radius = 0.4
	tbm.height = 2.4
	tailbody.mesh = tbm
	tailbody.material_override = hull
	tailbody.rotation.z = PI / 2.0
	tailbody.position = Vector3(-1.9, 0.15, 0)
	g.add_child(tailbody)
	# Ala de cola (vertical + horizontal)
	var finv := MeshInstance3D.new()
	var fvm := BoxMesh.new()
	fvm.size = Vector3(0.12, 1.1, 0.18)
	finv.mesh = fvm
	finv.material_override = hull
	finv.position = Vector3(-3.15, 0.6, 0)
	g.add_child(finv)
	var finh := MeshInstance3D.new()
	var fhm := BoxMesh.new()
	fhm.size = Vector3(0.35, 0.08, 0.7)
	finh.mesh = fhm
	finh.material_override = dark
	finh.position = Vector3(-3.15, 0.15, 0)
	g.add_child(finh)
	# Puntas de ala con misiles (ataque)
	for zz in [-0.7, 0.7]:
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.9, 0.1, 0.35)
		wing.mesh = wm
		wing.material_override = hull
		wing.position = Vector3(0.3, -0.15, zz)
		g.add_child(wing)
		var pod := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.09
		pm.bottom_radius = 0.09
		pm.height = 0.8
		pod.mesh = pm
		pod.material_override = dark
		pod.rotation.x = PI / 2.0
		pod.position = Vector3(0.3, -0.45, zz)
		g.add_child(pod)
	# Skids (aterrizaje)
	for zz in [-0.55, 0.55]:
		var skid := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.08
		sm.bottom_radius = 0.08
		sm.height = 2.4
		skid.mesh = sm
		skid.material_override = dark
		skid.rotation.z = PI / 2.0
		skid.position = Vector3(0.2, -0.75, zz)
		g.add_child(skid)
		for xx in [-0.5, 0.8]:
			var strut := MeshInstance3D.new()
			var stm := BoxMesh.new()
			stm.size = Vector3(0.09, 0.4, 0.09)
			strut.mesh = stm
			strut.material_override = dark
			strut.position = Vector3(xx, -0.55, zz)
			g.add_child(strut)
	# Rotor principal (gira, nodo "MainRotor")
	var rotor := Node3D.new()
	rotor.name = "MainRotor"
	rotor.position = Vector3(0.2, 0.85, 0)
	g.add_child(rotor)
	var spinner := MeshInstance3D.new()
	var spinm := SphereMesh.new()
	spinm.radius = 0.2
	spinner.mesh = spinm
	spinner.material_override = dark
	spinner.position = Vector3(0, 0.05, 0)
	spinner.scale = Vector3(1, 0.6, 1)
	rotor.add_child(spinner)
	for b in range(4):
		var blade := MeshInstance3D.new()
		var blm := BoxMesh.new()
		blm.size = Vector3(4.4, 0.05, 0.22)
		blade.mesh = blm
		blade.material_override = dark
		blade.position = Vector3(0, 0.12, 0)
		blade.rotation.y = b * (TAU / 4.0)
		rotor.add_child(blade)
	# Rotor de cola (gira, nodo "TailRotor")
	var trn := Node3D.new()
	trn.name = "TailRotor"
	trn.position = Vector3(-3.25, 0.6, 0.12)
	g.add_child(trn)
	for b in range(2):
		var tblade := MeshInstance3D.new()
		var tbbm := BoxMesh.new()
		tbbm.size = Vector3(0.05, 0.85, 0.14)
		tblade.mesh = tbbm
		tblade.material_override = dark
		tblade.rotation.x = b * (TAU / 2.0)
		trn.add_child(tblade)
	return g

# â”€â”€â”€ SHOOTING â”€â”€â”€
func _shoot() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var rate: float = float(weapon_rate[current_weapon])  # Arma 1: misma cadencia en todos los modos
	if abl_rapid_t > 0.0: rate /= 3.0  # RÃ¡faga: 3x velocidad
	if now - last_shot_time < rate:
		return
	last_shot_time = now
	if ammo[current_weapon] <= 0 and current_weapon != 0:
		return
	if current_weapon != 0:
		ammo[current_weapon] -= 1
	# DirecciÃ³n de disparo (con dispersiÃ³n) â€” primero, para usarla en el destello
	var dir := -camera.global_transform.basis.z
	var spread: float = weapon_spread[current_weapon]
	dir += Vector3(randf_range(-spread, spread), randf_range(-spread, spread), 0)
	dir = dir.normalized()
	# Boca del caÃ±Ã³n (espacio local de la cÃ¡mara)
	var muzzle_local: Vector3
	match current_weapon:
		0:
			muzzle_local = Vector3(0.0, -0.17, -0.85)
		1:
			dual_toggle = 1 - dual_toggle
			muzzle_local = Vector3(0.2, -0.16, -0.83) if dual_toggle == 0 else Vector3(-0.2, -0.16, -0.83)
		_:
			muzzle_local = Vector3(0.0, -0.16, -1.0)
	var muzzle_world := camera.global_transform * muzzle_local
	# Destello de boca: fuego que sale por el caÃ±Ã³n (doble en el arma 2)
	if current_weapon == 1:
		_muzzle_flash(camera.global_transform * Vector3(0.2, -0.16, -0.83), dir, false)
		_muzzle_flash(camera.global_transform * Vector3(-0.2, -0.16, -0.83), dir, false)
	else:
		_muzzle_flash(muzzle_world, dir, current_weapon == 2)
	# Sonido de disparo (distinto por arma)
	_play_local_sfx(current_weapon)
	# Sacudida de cÃ¡mara
	shake_amount = 0.15 if current_weapon != 2 else 0.4
	# Proyectil: arma 3 = misil (vuela y explota); resto = bala
	var proj: Node3D
	if current_weapon == 2:
		var mis := _create_missile()
		mis.scale = Vector3.ONE * 2.6  # visible a distancia (para leer la trayectoria)
		mis.position = muzzle_world + dir * 0.3
		proj = mis
	else:
		var b := _create_projectile(0.35, Color(1, 1, 0.3))
		b.position = muzzle_world + dir * 0.15
		proj = b
	proj.name = "Proj_%d" % projectiles.size()
	add_child(proj)
	# Host: el destello y el balazo local tambiÃ©n los oyen los clientes (el disparo del slot 0
	# no pasa por _shoot_for)
	if mp_role == 1:
		net_fx.append(["flash", muzzle_world.x, muzzle_world.y, muzzle_world.z, dir.x, dir.y, dir.z])
		net_fx.append(["snd", current_weapon, muzzle_world.x, muzzle_world.y, muzzle_world.z])
	var dmg: float = weapon_damage[current_weapon]
	if abl_overload_t > 0.0: dmg *= 2.0  # Sobrecarga: 2x daÃ±o
	projectiles.append({
		"node": proj, "dir": dir, "speed": weapon_speed[current_weapon],
		"damage": dmg, "life": 5.0,
		"area": 1.5 if current_weapon == 2 else 0.0,
		"splash": 7.5 if current_weapon == 2 else 0.0,
		"missile": current_weapon == 2,
		"slot": 0 if (mp_role == 1 or mp_role == 3) else -1
	})

func _create_projectile(radius: float, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.roughness = 0.3
	m.material_override = mat
	return m

func _enemy_shoot(from: Vector3, target: Vector3) -> void:
	var dir := (target - from).normalized()
	var proj := _create_projectile(0.1, Color(1, 0.1, 0.0))
	proj.position = from + dir
	proj.name = "EProj_%d" % enemy_projectiles.size()
	add_child(proj)
	enemy_projectiles.append({"node": proj, "dir": dir, "speed": 30.0, "life": 4.0})

# â”€â”€â”€ UPDATES â”€â”€â”€
# --- Indice de colision de proyectiles (ver scripts/hit_space.gd) --------------
# Una sola grilla por frame para los tres loops que eran O(balas x enemigos):
# deteccion de impacto, _cannon_will_kill_vehicle y _cannon_splash. Las reglas
# (radios, quien recibe el golpe, el orden) son las mismas de antes.
const MAX_HIT_RADIUS: float = 10.0   # la hitbox mas grande (tanque/avion); el resto va en HitSpace.rad
# Estela de los misiles: un puf cada MISSILE_TRAIL_GAP METROS recorridos, no uno por
# frame. Por frame quedaba una pared continua a 140 FPS y bolas sueltas y grandes a 20.
const MISSILE_TRAIL_GAP: float = 1.1
const MISSILE_TRAIL_PUFF: float = 0.22
var _hs: HitSpace = HitSpace.new()
var _hit_by_id: Dictionary = {}      # id -> indice actual en "enemies"
var _hit_by_id_n: int = -1           # -1 fuerza a rehacer el mapa (hubo kills)

func _hit_kind(t: String) -> int:
	match t:
		"soldier": return HitSpace.K_SOLDIER
		"boat": return HitSpace.K_BOAT
		"tank": return HitSpace.K_TANK
		"plane": return HitSpace.K_PLANE
	return HitSpace.K_OTHER

func _hit_rebuild() -> void:
	_hs.clear()
	_hit_by_id.clear()
	for j in enemies.size():
		var e: Dictionary = enemies[j]
		var nd_v: Variant = e.get("node")
		if nd_v == null or not is_instance_valid(nd_v):
			continue
		var nd: Node3D = nd_v
		var k: int = _hit_kind(str(e.get("type", "")))
		var r: float = 3.5
		match k:
			HitSpace.K_BOAT: r = 6.0
			HitSpace.K_TANK, HitSpace.K_PLANE: r = 10.0
		var eid: int = int(e.get("id", -1))
		_hs.add(nd.position, r, eid, j, k, e)
		if eid >= 0:
			_hit_by_id[eid] = j
	_hit_by_id_n = enemies.size()

# La lista de enemigos se acorta cuando mueren en el medio del frame: el mapa
# id -> indice se rehace una sola vez y vale hasta el proximo kill.
func _hit_index_of(id: int) -> int:
	if _hit_by_id_n != enemies.size():
		_hit_by_id.clear()
		for k in enemies.size():
			var eid2: int = int(enemies[k].get("id", -1))
			if eid2 >= 0:
				_hit_by_id[eid2] = k
		_hit_by_id_n = enemies.size()
	return int(_hit_by_id.get(id, -1))

func _update_projectiles(delta: float) -> void:
	_hit_rebuild()  # la grilla se construye antes de mover las balas: vale todo el frame
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		kill_credit_slot = int(p.get("slot", -1))  # kills de esta bala acreditan a su tirador
		var pnode: Node3D = p["node"]
		var pdir: Vector3 = p["dir"]
		var pspeed: float = p["speed"]
		var plife: float = p["life"]
		var pdamage: float = p["damage"]
		var parea: float = p["area"]
		var psplash: float = p.get("splash", 0.0)
		var pmissile: bool = bool(p.get("missile", false))
		pnode.position = pnode.position + pdir * pspeed * delta
		if pmissile:
			# Misil: se alinea a la trayectoria, llama viva y estela de humo CLARA
			# (humo claro contra el cielo = trayectoria legible para apuntar)
			pnode.look_at(pnode.position + pdir, Vector3.UP)
			var flame_n: Node = pnode.get_node_or_null("Flame")
			if flame_n:
				flame_n.scale = Vector3.ONE * randf_range(1.2, 2.2)
			# Estela FINA: un puf chiquito y claro, pero uno cada MISSILE_TRAIL_GAP
			# metros de recorrido (antes era uno por frame: pared blanca a 140 FPS y
			# bolas grandes y separadas a 20 FPS).
			var td: float = float(p.get("trail_d", 0.0)) + pspeed * delta
			if td >= MISSILE_TRAIL_GAP:
				td = 0.0
				_smoke_burst(pnode.position - pdir * 0.5, 1, 0.35, Color(0.92, 0.92, 0.88), MISSILE_TRAIL_PUFF, 0.4)
			p["trail_d"] = td
		plife -= delta
		if plife <= 0:
			pnode.queue_free()
			projectiles.remove_at(i)
			continue
		# Fuera del campo de juego no puede tocar a nadie: los enemigos nacen y viven
		# dentro de ~270 m y siempre vienen hacia la base. Soltar aca recorta el
		# tiempo que una bala perdida sigue costando CPU y un nodo dibujado.
		var cull_p: Vector3 = pnode.position
		if absf(cull_p.x) > 340.0 or absf(cull_p.z) > 340.0 or cull_p.y > 220.0 or cull_p.y < -30.0:
			pnode.queue_free()
			projectiles.remove_at(i)
			continue
		# Collision: sale de la grilla (ver HitSpace). Entre los solapados gana el de
		# indice mas alto en "enemies", igual que el for j descendente de antes.
		var hit := false
		var best_slot: int = _hs.best_hit(pnode.position, MAX_HIT_RADIUS + parea, parea)
		if best_slot >= 0:
			var j: int = _hit_index_of(_hs.ids[best_slot])
			if j >= 0:
				var e: Dictionary = enemies[j]
				hit = true
				if e["type"] == "tank" and psplash <= 0.0:
					# Tanks only take damage from the cannon â€” pistol/AM spark off the armor
					_hit_spark(pnode.position, 3, Color(0.7, 0.8, 1.0))
				elif psplash > 0.0:
					# Cannon: detonate â€” direct damage to the hit target + area splash
					# Regla anti "doble explosiÃ³n": la explosiÃ³n grande es SOLO de muerte.
					# - Barco/heli que sobrevive al disparo: chispa en el casco (sin boom grande).
					# - Barco/heli que muere (directo o splash): exactamente 1 explosiÃ³n (la de muerte).
					# - Soldados: boom de Ã¡rea SIEMPRE (arma de Ã¡rea; su muerte no genera boom).
					# - Tanque que sobrevive: feedback de blindaje; si la bala lo destruye,
					#   suena solo el boom de muerte (1 explosiÃ³n total).
					var will_kill := _cannon_will_kill_vehicle(pnode.position, e, pdamage, psplash)
					var etype: String = str(e["type"])
					if etype == "soldier":
						_big_boom(pnode.position, 1.1, Color(1, 0.65, 0.2), true)
					elif etype == "tank":
						if not will_kill:
							_big_boom(pnode.position, 1.1, Color(1, 0.65, 0.2), true)
					elif not will_kill:
						_cannon_hull_spark(pnode.position)
					if e["type"] == "tank":
						# El splash alcanza al tanque (alcance 12.5 > hitbox 11.5): 1 blindaje por bala
						_cannon_splash(pnode.position, psplash)
					else:
						# DaÃ±o directo al objetivo: con hitboxes grandes el splash a veces no lo alcanza
						var ehealth2: float = e["health"]
						ehealth2 -= pdamage
						e["health"] = ehealth2
						if ehealth2 <= 0.0:
							_kill_enemy(j)
						_cannon_splash(pnode.position, psplash)
				else:
					# Pistol / AM: single-target damage
					var ehealth: float = e["health"]
					ehealth -= pdamage
					e["health"] = ehealth
					_hit_spark(pnode.position, 4, Color(1, 0.7, 0))
					if ehealth <= 0:
						_kill_enemy(j)
		# Collision with supply crates
		for k in range(crates.size() - 1, -1, -1):
			var cnode: Node3D = crates[k]["node"]
			if pnode.position.distance_to(cnode.position + Vector3(0, 0.5, 0)) < 2.2 + parea:
				_open_crate(k)
				hit = true
				break
		# Cannon ground impact (sand) â†’ splash even if it didn't clip a target
		if not hit and psplash > 0.0 and pnode.position.y <= 0.5:
			# Anti "explosiÃ³n fantasma": si la bala muere sobre un casco reciÃ©n destruido
			# (â‰¤2.5s y â‰¤10m), se disuelve sin visual ni sonido (el boom de muerte ya
			# cubriÃ³ esa zona). Si el splash mata a un barco/heli/tank, su boom de
			# muerte reemplaza al de impacto. El splash de daÃ±o SÃ sigue aplicando.
			var _now_t: float = Time.get_ticks_msec() / 1000.0
			var _dxz: float = Vector2(pnode.position.x - last_kill_boom_pos.x, pnode.position.z - last_kill_boom_pos.z).length()
			var _near_kill: bool = (_now_t - last_kill_boom_t) <= 4.0 and _dxz <= 14.0
			var _dummy: Dictionary = {"type": "soldier", "health": 1.0}
			if not _near_kill and not _cannon_will_kill_vehicle(pnode.position, _dummy, 0.0, psplash):
				_big_boom(pnode.position + Vector3(0, 0.3, 0), 1.3, Color(1, 0.6, 0.2), true)
			_cannon_splash(pnode.position, psplash)
			hit = true
		if hit:
			pnode.queue_free()
			projectiles.remove_at(i)

func _kill_enemy(j: int) -> void:
	if j < 0 or j >= enemies.size():
		return
	var e: Dictionary = enemies[j]
	# Lo sacamos de la lista ANTES de los efectos: los kills anidados (radio de
	# fuego del tanque, splash) nunca pueden desfasar el Ã­ndice de esta entrada.
	enemies.remove_at(j)
	_hit_by_id_n = -1  # la lista se acorto: el mapa id -> indice se rehace al proximo uso
	# El cliente no corre esta funciÃ³n: avisarle quÃ© enemigo muriÃ³ y de quÃ© tipo, para que
	# retire el nodo con su animaciÃ³n de caÃ­da en vez de hacerlo desaparecer de golpe.
	if mp_role == 1:
		net_fx.append(["kill", int(e.get("id", -1)), str(e.get("type", ""))])
	var enode: Node3D = e["node"]
	var pts: int = 25
	var cpts: int = 5
	match e["type"]:
		"boat":
			pts = 50 * int(e["soldiers"])
			cpts = 10
		"tank":
			pts = 200
			cpts = 20
		"plane":
			pts = 100
			cpts = 15
	score += pts
	combat_pts += cpts
	# Multijugador: acreditar al tirador (slot) â€” score de equipo + ranking individual
	if kill_credit_slot >= 0 and kill_credit_slot < slot_states.size():
		var stc: Dictionary = slot_states[kill_credit_slot]
		stc["score"] = int(stc.get("score", 0)) + pts
		stc["kills"] = int(stc.get("kills", 0)) + 1
	# Oleada 7 en adelante: probabilidad de derrame de municiÃ³n (armas 2 y 3) â€”
	# balanceo para llegar a oleadas superiores
	_maybe_drop_ammo_on_kill(enode.position)
	if e["type"] == "soldier":
		# Soldiers: voz humana de dolor (aleatoria) + fall animation, then remove
		if soldier_pain_players.size() > 0:
			soldier_pain_players[randi() % soldier_pain_players.size()].play()
		var dap: AnimationPlayer = enode.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if dap != null and dap.has_animation("default/fall"):
			dap.play("default/fall")
			var ft := Timer.new()
			ft.one_shot = true
			ft.wait_time = 1.3
			enode.add_child(ft)
			ft.timeout.connect(_free_node.bind(enode))
			ft.start()
		else:
			_explode(enode.position, 10, Color(1, 0.7, 0.4))
			enode.queue_free()
	else:
		# VehÃ­culos: explosiÃ³n grande (luz + onda + humo) + boom realista
		# (Barco vuelve a 1.8: con el loop del VFX corregido ya no hay doble explosiÃ³n)
		var vscale: float = 1.8 if e["type"] == "boat" else (1.6 if e["type"] == "tank" else 1.5)
		_big_boom(enode.position, vscale, Color(1, 0.4, 0.1), true)
		last_kill_boom_pos = enode.position
		last_kill_boom_t = Time.get_ticks_msec() / 1000.0
		# El tanque explota con radio de fuego (8m): soldados cercanos mueren,
		# otros enemigos toman daÃ±o. (El boom grande ya sonÃ³ arriba: 1 sola explosiÃ³n.)
		if e["type"] == "tank":
			# Colectar kills y matar de atrÃ¡s hacia adelante (sin desfasar Ã­ndices)
			var to_kill: Array = []
			for k in range(enemies.size()):
				var ne: Dictionary = enemies[k]
				var nn_v: Variant = ne.get("node")
				if nn_v == null or not is_instance_valid(nn_v):
					continue
				var nn: Node3D = nn_v
				if nn.position.distance_to(enode.position) > 8.0:
					continue
				if str(ne.get("type", "")) == "soldier":
					ne["health"] = float(ne["health"]) - 100.0
				else:
					ne["health"] = float(ne["health"]) - 40.0
				if float(ne["health"]) <= 0.0:
					to_kill.append(k)
			for i in range(to_kill.size() - 1, -1, -1):
				_kill_enemy(int(to_kill[i]))
		enode.queue_free()

# Chispa de impacto del caÃ±Ã³n contra un casco (barco/heli) que sobrevive el disparo:
# feedback visual claro SIN explosiÃ³n grande (la explosiÃ³n grande es exclusiva de la muerte).
func _cannon_hull_spark(pos: Vector3) -> void:
	_hit_spark(pos, 9, Color(1.0, 0.8, 0.35))
	_flash_light(pos, Color(1.0, 0.75, 0.4), 7.0, 9.0, 0.18)

# Â¿Mata este disparo de caÃ±Ã³n a algÃºn vehÃ­culo (barco/heli/tank)?
# - Objetivo directo: daÃ±o directo + splash (el splash siempre lo alcanza: â‰¤7.5m).
# - Vecinos: solo splash, si estÃ¡n dentro del radio.
# Sirve para suprimir el boom de impacto cuando ya va a haber un boom de muerte
# â†’ un barco/heli nunca explota dos veces por el mismo disparo.
func _cannon_will_kill_vehicle(pos: Vector3, direct: Dictionary, pdamage: float, psplash: float) -> bool:
	var dtype: String = str(direct.get("type", ""))
	if dtype == "tank":
		return int(direct.get("armor", 2)) <= 1  # el splash quita 1 blindaje
	if dtype != "soldier" and psplash > 0.0:
		# Barco/heli directo: recibe daÃ±o directo + splash
		if float(direct["health"]) - pdamage - CANNON_SPLASH_DMG <= 0.0:
			return true
	# Otros barcos/helis dentro del radio del splash mueren por el splash
	if psplash > 0.0:
		var cn: int = _hs.candidates(pos, psplash)
		var r2: float = psplash * psplash
		for ci in cn:
			var slot: int = _hs.buf[ci]
			var k: int = _hs.kind[slot]
			if k == HitSpace.K_SOLDIER or k == HitSpace.K_TANK:
				continue
			if _hit_index_of(_hs.ids[slot]) < 0:
				continue  # ya murio en este frame: su boom de muerte ya cubre la zona
			var dx: float = pos.x - _hs.px[slot]
			var dy: float = pos.y - _hs.py[slot]
			var dz: float = pos.z - _hs.pz[slot]
			if dx * dx + dy * dy + dz * dz <= r2 and float(_hs.ent[slot]["health"]) - CANNON_SPLASH_DMG <= 0.0:
				return true
	return false

# Oleada 7+: cada kill tiene 15% de dejar municiÃ³n (+10 AM, +1 CaÃ±Ã³n).
# MP (host): se reparte a un slot aleatorio (justo entre jugadores) y el texto
# viaja por net_fx para que todos lo vean.
func _maybe_drop_ammo_on_kill(kill_pos: Vector3) -> void:
	if wave <= 6:
		return
	if randf() > 0.15:
		return
	var give_w2 := 10
	var give_w3 := 1
	var txt := _tr("ft_killammo") % [give_w2, give_w3]
	if (mp_role == 1 or mp_role == 3) and slot_states.size() > 0:
		var s: int = randi() % slot_states.size()
		_give_slot_ammo(s, 1, give_w2, 400)
		_give_slot_ammo(s, 2, give_w3, 50)
		_spawn_floating_text(kill_pos + Vector3(0, 1.5, 0), txt, Color(0.5, 0.9, 1.0))
		net_fx.append(["text", kill_pos.x, kill_pos.y + 1.5, kill_pos.z, txt])
	else:
		ammo[1] = mini(int(ammo[1]) + give_w2, 400)
		ammo[2] = mini(int(ammo[2]) + give_w3, 50)
		_spawn_floating_text(kill_pos + Vector3(0, 1.5, 0), txt, Color(0.5, 0.9, 1.0))

func _cannon_splash(pos: Vector3, radius: float) -> void:
	# Primero aplica dano a todos, luego recoge los kills y los mata de atras hacia
	# adelante (igual que antes). Los candidatos salen de la grilla y se ordenan por
	# el indice que cada enemigo tenia en "enemies" al construirla; al matar se
	# resuelve el indice actual por id, asi que los kills del propio frame no desfasan.
	var cn: int = _hs.candidates(pos, radius + 5.0)
	if cn == 0:
		return
	var slots: Array = []
	for ci in cn:
		var slot: int = _hs.buf[ci]
		var o: int = _hs.ord[slot]
		var at: int = slots.size()
		while at > 0 and int(_hs.ord[int(slots[at - 1])]) > o:
			at -= 1
		slots.insert(at, slot)  # insercion ordenada: siempre son unos pocos elementos
	var to_kill: Array = []
	for si in slots.size():
		var s2: int = int(slots[si])
		var e: Dictionary = _hs.ent[s2]
		var is_tank: bool = _hs.kind[s2] == HitSpace.K_TANK
		var dx2: float = pos.x - _hs.px[s2]
		var dy2: float = pos.y - _hs.py[s2]
		var dz2: float = pos.z - _hs.pz[s2]
		var reach: float = radius + (5.0 if is_tank else 0.0)
		if dx2 * dx2 + dy2 * dy2 + dz2 * dz2 > reach * reach:
			continue
		if is_tank:
			var armor: int = int(e.get("armor", 2))
			armor -= 1
			e["armor"] = armor
			_hit_spark(Vector3(_hs.px[s2], _hs.py[s2], _hs.pz[s2]), 8, Color(0.85, 0.8, 0.3))
			if armor <= 0:
				to_kill.append(s2)
		else:
			e["health"] -= CANNON_SPLASH_DMG
			if e["health"] <= 0.0:
				to_kill.append(s2)
	for i in range(to_kill.size() - 1, -1, -1):
		var kk: int = _hit_index_of(_hs.ids[int(to_kill[i])])
		if kk >= 0:
			_kill_enemy(kk)

# Recolecta posiciones planas (sin nodos) y deja la evitacion resuelta en los
# nucleos del CPU. El indice de cada soldado se guarda EN su propia entrada
# ("ai_i") para que la lectura siga siendo correcta aunque la lista se acorte
# cuando mueren enemigos durante el loop.
func _ai_solve(delta: float) -> void:
	_ai_sold.resize(0)
	_ai_tanks.resize(0)
	for e in enemies:
		var nd_v: Variant = e.get("node")
		if nd_v == null or not is_instance_valid(nd_v):
			e["ai_i"] = -1
			continue
		var et: String = str(e.get("type", ""))
		if et != "soldier" and et != "tank":
			e["ai_i"] = -1
			continue
		var nd: Node3D = nd_v
		if et == "soldier":
			e["ai_i"] = _ai_sold.size() >> 1
			_ai_sold.append(nd.position.x)
			_ai_sold.append(nd.position.z)
		else:
			e["ai_i"] = -1
			_ai_tanks.append(nd.position.x)
			_ai_tanks.append(nd.position.z)
	# Los campos de rocas no cambian nunca: se cachean una sola vez
	if _ai_rocks.size() != rock_spots.size() * 3:
		_ai_rocks.resize(0)
		for rp in rock_spots:
			var rp2: Array = rp
			_ai_rocks.append(float((rp2[0] as Vector2).x))
			_ai_rocks.append(float((rp2[0] as Vector2).y))
			_ai_rocks.append(float(rp2[1]))
	_ai_bullets.resize(0)
	for pd in projectiles:
		var pn: Node3D = pd["node"]
		var pdir: Vector3 = pd["dir"]
		_ai_bullets.append(pn.position.x)
		_ai_bullets.append(pn.position.z)
		_ai_bullets.append(pdir.x)
		_ai_bullets.append(pdir.y)
	_ai.solve(_ai_sold, _ai_tanks, _ai_rocks, _ai_bullets, delta)

func _update_enemies(delta: float) -> void:
	_ai_solve(delta)  # separacion + esquiva resueltas en paralelo (ver scripts/enemy_ai.gd)
	for i in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[i]
		var enode_v: Variant = e.get("node")
		if enode_v == null or not is_instance_valid(enode_v):
			enemies.remove_at(i)  # entrada corrupta: purgar sin romper el loop
			continue
		var enode: Node3D = enode_v
		var espeed: float = e["speed"]
		var ai_i: int = int(e.get("ai_i", -1))  # indice en los buffers de _ai (ver _ai_solve)
		match e["type"]:
			"boat":
				var epos: Vector3 = enode.position
				epos.z += espeed * delta
				epos.y = -0.1 + sin(Time.get_ticks_msec() * 0.003 + i) * 0.08  # gentle bob around waterline
				enode.position = epos
				for bc in enode.get_children():
					if (bc as Node3D) != null and bc.get_node_or_null("Rig/Skeleton3D") != null:
						_sync_gear(bc)
				var eshore: float = e["shore_z"]
				if epos.z >= eshore:
					var esoldiers: int = e["soldiers"]
					for s in range(esoldiers):
						_disembark_soldier(e)
					if e["has_tank"]:
						_disembark_tank(e)
					enode.queue_free()
					enemies.remove_at(i)
			"soldier":
				var sap: AnimationPlayer = enode.get_node_or_null("AnimationPlayer") as AnimationPlayer
				var aiming: bool = float(e.get("aim_t", 0.0)) > 0.0
				e["aim_t"] = maxf(0.0, float(e.get("aim_t", 0.0)) - delta)
				_set_soldier_gun_pose(enode, aiming)
				_sync_gear(enode)
				# Sigue el terreno (rocas/arena) para no atravesar la geometrÃ­a
				enode.position.y = _terrain_height(enode.position.x, enode.position.z)
				var spos2: Vector2 = Vector2(enode.position.x, enode.position.z)
				if e["state"] == "shooting":
					# â”€â”€ Stopped: face the military base (new target) and fire â”€â”€
					var to_base := base_target - enode.global_position
					enode.rotation.y = atan2(to_base.x, to_base.z)
					# Si quedÃ³ parado dentro de una pila de rocas, sale empujando hacia afuera
					var fr1: Vector2 = _ai.fixr_at(ai_i)  # empuje fuera de la roca (calculado en paralelo)
					if fr1.length_squared() > 0.000001:
						var fs1: float = minf(1.0, delta * 5.0)
						enode.position.x += fr1.x * fs1
						enode.position.z += fr1.y * fs1
						enode.position.y = _terrain_height(enode.position.x, enode.position.z)
					# Si un tanque lo estÃ¡ pisando, sale de su casco
					var ft1: Vector2 = _ai.fixt_at(ai_i)  # empuje fuera del casco del tanque (en paralelo)
					if ft1.length_squared() > 0.000001:
						var fs2: float = minf(1.0, delta * 6.0)
						enode.position.x += ft1.x * fs2
						enode.position.z += ft1.y * fs2
						enode.position.y = _terrain_height(enode.position.x, enode.position.z)
					if sap != null and sap.has_animation("default/idle") and sap.current_animation != "default/idle":
						sap.play("default/idle")
					var etimer: float = e["shoot_timer"]
					etimer -= delta
					e["shoot_timer"] = etimer
					if etimer <= 0:
						var aim_dir := Vector2(to_base.x, to_base.z).normalized()
						var shoot_from: Vector3 = enode.position + Vector3(aim_dir.x * 0.55, 1.43, aim_dir.y * 0.55)  # caÃ±Ã³n a 1.43 m (soldado x1.3)
						_enemy_shoot(shoot_from, base_target)
						_enemy_muzzle_flash(enode)
						e["aim_t"] = 1.0
						e["shots_left"] = int(e.get("shots_left", 1)) - 1
						if int(e.get("shots_left", 0)) <= 0:
							# Resume running to keep dodging
							e["state"] = "running"
							e["stop_t"] = randf_range(2.0, 4.5)
							var rd2: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 1.4)).normalized()
							e["run_dir"] = rd2
						else:
							e["shoot_timer"] = randf_range(1.0, 1.8)
				else:
					# â”€â”€ Running: dart around the beach dodging player bullets â”€â”€
					var run_dir: Vector2 = e.get("run_dir", Vector2(0.0, 1.0))
					if run_dir.length() < 0.01:
						run_dir = Vector2(0.0, 1.0)
						e["run_dir"] = run_dir
					# Evasion: push away from nearby player bullets
					var evasion: Vector2 = _ai.evade_at(ai_i)  # esquiva de balas (resuelta en paralelo)
					# Stay on the beach, advance up to 10m in front of the base, never behind/beside it
					var bounds := Vector2.ZERO
					if spos2.x < -ENEMY_MAX_X:
						bounds.x += 1.0
					if spos2.x > ENEMY_MAX_X:
						bounds.x -= 1.0
					if spos2.y < -33.0:
						bounds.y += 1.0
					if spos2.y > ENEMY_HOLD_Z:
						bounds.y -= 1.0
					# Esquivar los bloques de roca (no atravesarlos)
					bounds += _ai.soft_at(ai_i)  # desvio suave contra los bloques de roca (en paralelo)
					# CorrecciÃ³n dura: si metiÃ³ dentro del radio, lo saca directamente
					var fr2: Vector2 = _ai.fixr_at(ai_i)  # si metio dentro del radio, lo saca (en paralelo)
					if fr2.length_squared() > 0.000001:
						var fs3: float = minf(1.0, delta * 6.0)
						enode.position.x += fr2.x * fs3
						enode.position.z += fr2.y * fs3
					# CorrecciÃ³n dura contra tanques: si terminÃ³ dentro del casco, lo saca
					var ft2: Vector2 = _ai.fixt_at(ai_i)  # si termino dentro del casco, lo saca (en paralelo)
					if ft2.length_squared() > 0.000001:
						var fs4: float = minf(1.0, delta * 6.0)
						enode.position.x += ft2.x * fs4
						enode.position.z += ft2.y * fs4
					# Advance toward the base, then hold 10m in front of it (no longer gathering around the player)
					var to_hold: Vector2 = Vector2.ZERO
					if spos2.y < ENEMY_HOLD_BAND:
						to_hold = Vector2(0.0, 1.0) * clampf((ENEMY_HOLD_BAND - spos2.y) / 18.0, 0.3, 1.0)
					elif spos2.y > ENEMY_HOLD_Z:
						to_hold = Vector2(0.0, -1.0) * 0.7
					# DispersiÃ³n: alejarse de otros soldados cercanos (evitar pelotÃ³n)
					# y de los tanques (los esquivan, no los atraviesan)
					var sep: Vector2 = _ai.sep_at(ai_i)  # separacion del peloton (en paralelo, con rejilla espacial)
					var desired: Vector2 = run_dir + evasion * 2.4 + bounds * 3.2 + to_hold * 1.2 + sep * 1.8
					if desired.length() < 0.01:
						desired = run_dir
					desired = desired.normalized()
					run_dir = run_dir.lerp(desired, minf(1.0, delta * 3.5))
					if run_dir.length() < 0.01:
						run_dir = desired
					e["run_dir"] = run_dir
					enode.position.x += run_dir.x * espeed * 1.8 * delta
					enode.position.z += run_dir.y * espeed * 1.8 * delta
					# Face the model's +Z (front) toward the running direction
					enode.rotation.y = atan2(run_dir.x, run_dir.y)
					var run_anim: String = "default/run" if (sap != null and sap.has_animation("default/run")) else "default/walk"
					if sap != null and sap.current_animation != run_anim:
						sap.play(run_anim)
					# Randomly stop to shoot at the player
					var st: float = float(e.get("stop_t", 2.0)) - delta
					if st <= 0.0:
						e["state"] = "shooting"
						e["shots_left"] = 1 + (1 if randf() < 0.4 else 0)
						e["shoot_timer"] = 0.35
						e["stop_t"] = randf_range(2.0, 4.5)
					else:
						e["stop_t"] = st
			"tank":
				var epos3: Vector3 = enode.position
				var tpos2: Vector2 = Vector2(epos3.x, epos3.z)
				# Advance toward the base but hold 10m in front of it (no more reaching/destroying it)
				if tpos2.y < ENEMY_HOLD_Z:
					tpos2.y += espeed * delta
				tpos2.x = move_toward(tpos2.x, 0, 0.3 * delta)
				# Esquivar los bloques de roca: desvÃ­o lateral manteniendo el avance (+Z)
				for rps in rock_spots:
					var rpos: Vector2 = rps[0]
					var rrad: float = rps[1]
					var raway: Vector2 = tpos2 - rpos
					var rdist: float = raway.length()
					if rdist < rrad + 3.0:
						var side := Vector2(-raway.y, raway.x).normalized()
						if side.y < 0.0:
							side = -side
						tpos2 += side * (1.0 - rdist / (rrad + 3.0)) * espeed * 1.4 * delta
				epos3.x = tpos2.x
				epos3.z = tpos2.y
				# Sigue el terreno (rocas/arena): pasa por arriba, no atravesando
				epos3.y = _terrain_height(epos3.x, epos3.z)
				enode.position = epos3
				enode.look_at(base_target)
				var ttimer: float = e["shoot_timer"]
				ttimer -= delta
				e["shoot_timer"] = ttimer
				if ttimer <= 0:
					var tshoot_from: Vector3 = enode.position + Vector3(0, 2, -2)
					_enemy_shoot(tshoot_from, base_target)
					e["shoot_timer"] = randf_range(3, 5)
			"plane":
				# HelicÃ³ptero: (1) aproxima desde el buque hacia la base, (2) Ã³rbita y ataca
				if not e.has("orbit_ang"):
					_heli_init(e)
				var hphase: String = str(e.get("phase", "orbit"))
				var hmr := enode.get_node_or_null("MainRotor") as Node3D
				if hmr != null:
					hmr.rotation.y += delta * 34.0
				var htrn := enode.get_node_or_null("TailRotor") as Node3D
				if htrn != null:
					htrn.rotation.x += delta * 60.0
				if hphase == "approach":
					# Vuela desde el buque hacia la base (lÃ­nea recta, manteniendo altitud)
					var hsp: float = float(e["speed"])
					var hdir := (base_target - enode.position)
					hdir.y = 0.0
					if hdir.length() < 0.001:
						hdir = Vector3(0.0, 0.0, 1.0)
					hdir = hdir.normalized()
					enode.position += hdir * hsp * delta
					var halt_a: float = float(e["orbit_alt"])
					enode.position.y = move_toward(enode.position.y, halt_a, 24.0 * delta)
					var hto_a: Vector2 = Vector2(base_target.x - enode.position.x, base_target.z - enode.position.z)
					enode.rotation.y = atan2(-hto_a.y, hto_a.x)
					# Al llegar a radio de combate â†’ fase de Ã³rbita
					var hdist: float = (enode.position - base_target).length()
					var hor_r: float = float(e["orbit_r"])
					if hdist < hor_r + 5.0:
						e["phase"] = "orbit"
						e["orbit_ang"] = atan2(enode.position.z - base_target.z, enode.position.x - base_target.x)
						e["orbit_r"] = clampf(hdist, 24.0, 46.0)
						e["shoot_timer"] = randf_range(0.5, 1.2)
				else:
					# Ã“rbita alrededor de la base (no desaparece solo)
					var hang: float = float(e["orbit_ang"]) + float(e["orbit_dir"]) * float(e["orbit_speed"]) * delta
					e["orbit_ang"] = hang
					var hocx: float = float(e["orbit_cx"])
					var hoch: float = float(e["orbit_cz"])
					var hor: float = float(e["orbit_r"])
					var halt: float = float(e["orbit_alt"])
					enode.position.x = hocx + cos(hang) * hor
					enode.position.z = hoch + sin(hang) * hor
					enode.position.y = halt + sin(hang * 2.0 + i) * 1.5
					var hto: Vector2 = Vector2(base_target.x - enode.position.x, base_target.z - enode.position.z)
					enode.rotation.y = atan2(-hto.y, hto.x)
					# Disparo seguido (amenaza real)
					var ptimer: float = e["shoot_timer"]
					ptimer -= delta
					e["shoot_timer"] = ptimer
					if ptimer <= 0:
						var pshoot_from: Vector3 = enode.position + Vector3(0, -0.6, 0)
						_enemy_shoot(pshoot_from, base_target)
						e["shoot_timer"] = randf_range(1.0, 1.8)

	# Enemy projectiles
	for i in range(enemy_projectiles.size() - 1, -1, -1):
		var p: Dictionary = enemy_projectiles[i]
		var pnode: Node3D = p["node"]
		var pdir: Vector3 = p["dir"]
		var pspeed: float = p["speed"]
		var plife: float = p["life"]
		pnode.position = pnode.position + pdir * pspeed * delta
		plife -= delta
		if plife <= 0:
			pnode.queue_free()
			enemy_projectiles.remove_at(i)
			continue
		# Hit the military base (the new objective): impact zone behind the player
		var pp: Vector3 = pnode.position
		if pp.z > 36.0 and absf(pp.x) < 50.0 and pp.y < 12.0:
			if abl_shield_t > 0.0:
				# Escudo activo: absorbe el impacto (chispa azul, sin daÃ±o)
				_hit_spark(pp, 4, Color(0.4, 0.7, 1.0))
			else:
				_hit_spark(pp, 4, Color(1.0, 0.6, 0.2))
			pnode.queue_free()
			enemy_projectiles.remove_at(i)
			if abl_shield_t <= 0.0:
				_damage_base(1.0)
			continue

func _update_particles(delta: float) -> void:
	_fx.tick_particles(delta)  # misma fisica y mismo fade: ver scripts/fx_pool.gd

func _flash_light(pos: Vector3, color: Color, energy: float, radius: float, life: float) -> void:
	# Misma curva de energia (TRANS_QUAD + EASE_OUT), pero con luces recicladas y
	# techo de luces simultaneas: antes cada boom anadía una OmniLight3D nueva.
	_fx.add_light(pos, color, energy, radius, life)

func _smoke_burst(pos: Vector3, count: int, base_alpha: float = 0.5, smoke_color: Color = Color(0.16, 0.15, 0.14), puff_scale: float = 1.0, life_scale: float = 1.0) -> void:
	count = maxi(1, int(count * particle_scale))
	for i in count:
		# Mismos radios, velocidades, vidas y gravedad que antes.
		var r := randf_range(0.4, 0.9) * puff_scale
		_fx.add_particle(
			pos + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.7), randf_range(-0.6, 0.6)),
			Vector3(randf_range(-1.5, 1.5), randf_range(1.2, 3.2), randf_range(-1.5, 1.5)),
			randf_range(1.6, 3.0) * life_scale, 0.15, r, r * 2.0, smoke_color, 0.0, true, base_alpha, 1.0)

func _shockwave_ring(pos: Vector3, color: Color, scl: float) -> void:
	# Mismo anillo (cilindro r0.7 h0.18), misma expansion 0.4 -> 7.0*scl en 0.55 s con
	# TRANS_QUAD+EASE_OUT y mismo fade 0.8 -> 0. Ahora con nodo y material del pool.
	_fx.add_flash(pos + Vector3(0, 0.25, 0), true, Vector3.ONE * 0.4, Vector3.ONE * (7.0 * scl), color, 5.0, true, 0.8, 0.55, 0.55)

# â”€â”€â”€ BINBUN VFX (explosiones + destello de boquilla) con fallback procedural â”€â”€â”€
var _vfx_exp_ground: PackedScene = null
var _vfx_exp_air: PackedScene = null
var _vfx_exp_nuke: PackedScene = null
var _vfx_muzzle: PackedScene = null
var _vfx_loaded := false
# (antes existia _active_vfx: ahora las instancias viven en el pool de _vfx_free/_vfx_busy)

func _load_binbun_vfx() -> void:
	if _vfx_loaded:
		return
	_vfx_loaded = true
	# Binbun Explosion FX (rutas conocidas)
	_vfx_exp_ground = _try_load("res://assets/BinbunVFX_Vol2/ExplosionFX/effects/ground/vfx_ground_explosion_01.tscn")
	_vfx_exp_air = _try_load("res://assets/BinbunVFX_Vol2/ExplosionFX/effects/air/vfx_air_explosion_01.tscn")
	_vfx_exp_nuke = _try_load("res://assets/BinbunVFX_Vol2/ExplosionFX/effects/nuke/vfx_nuke_explosion_01.tscn")
	# Destello de boquilla (el pack aÃºn no estÃ¡; se descubre por keyword si aparece)
	var scenes: Array = []
	_collect_tscn("res://assets", scenes, 0)
	_vfx_muzzle = _pick_vfx(scenes, ["flash", "muzzle"], ["explosion", "smoke"])

func _try_load(p: String) -> PackedScene:
	if ResourceLoader.exists(p):
		var s: PackedScene = load(p)
		return s
	return null

func _pick_vfx(scenes: Array, must: Array, avoid: Array) -> PackedScene:
	for p in scenes:
		var lp: String = str(p).to_lower()
		var ok := false
		for w in must:
			if lp.find(str(w)) >= 0:
				ok = true
				break
		if not ok:
			continue
		var bad := false
		for w in avoid:
			if lp.find(str(w)) >= 0:
				bad = true
				break
		if bad:
			continue
		var sc: PackedScene = load(p)
		if sc != null:
			return sc
	return null

func _collect_tscn(path: String, out: Array, depth: int) -> void:
	if depth > 7:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			var full := path.path_join(fname)
			if dir.current_is_dir():
				if not fname.begins_with(".") and fname != "terrain":
					_collect_tscn(full, out, depth + 1)
			elif fname.ends_with(".tscn"):
				out.append(full)
		fname = dir.get_next()
	dir.list_dir_end()

# ─── POOL DE INSTANCIAS BINBUN ──────────────────────────────────────────────────
# sc.instantiate() de un VFX con GPUParticles + trails cuesta cientos de nodos, y
# antes se instanciaba uno por explosion (con su Timer propio). Se reutilizan
# instancias ocultas; el techo es solo un seguro para oleadas con muchas muertes
# simultaneas (mismo techo visual, costo de GPU acotado).
const VFX_CAP_GROUND: int = 8
const VFX_CAP_AIR: int = 8
const VFX_CAP_NUKE: int = 3
const VFX_CAP_MUZZLE: int = 10

var _vfx_free: Dictionary = {}   # PackedScene -> Array[Node3D] ocultos y listos
var _vfx_busy: Array = []        # [Node3D, segundos_restantes, PackedScene]
var _vfx_free_m: Array = []      # split: un Dictionary por pool espejo (0 = A, 1 = B)
var _vfx_copies: Dictionary = {} # split: instancia principal -> Array[Node3D], una por mitad

func _vfx_cap(sc: PackedScene) -> int:
	if sc == _vfx_exp_nuke:
		return VFX_CAP_NUKE
	if sc == _vfx_exp_air:
		return VFX_CAP_AIR
	if sc == _vfx_exp_ground:
		return VFX_CAP_GROUND
	return VFX_CAP_MUZZLE

func _vfx_take(sc: PackedScene) -> Node3D:
	var n: Node3D = _vfx_take_one(sc)
	if n != null:
		_vfx_ensure_copies(n, sc)  # split: una copia del efecto por cada mitad
	return n


func _vfx_take_one(sc: PackedScene) -> Node3D:
	var arr: Array = []
	if _vfx_free.has(sc):
		arr = _vfx_free[sc]
	if not arr.is_empty():
		var fn: Node3D = arr.pop_back()
		fn.visible = true
		return fn
	var live: int = 0
	for e in _vfx_busy:
		if e[2] == sc:
			live += 1
	if live >= _vfx_cap(sc):
		# Techo alcanzado: se roba la instancia mas avanzada de ESA escena.
		var bi: int = -1
		var best: float = 1e20
		for i in _vfx_busy.size():
			if _vfx_busy[i][2] == sc and float(_vfx_busy[i][1]) < best:
				best = float(_vfx_busy[i][1])
				bi = i
		if bi >= 0:
			var bn: Node3D = _vfx_busy[bi][0]
			_vfx_busy.remove_at(bi)
			bn.visible = true
			return bn
	var nn: Node3D = sc.instantiate()
	nn.name = "Vfx_%d" % _vfx_busy.size()
	if _fx != null:
		_fx.add_child(nn)  # viven bajo el pool: los limpiezas por nombre no las tocan
	else:
		add_child(nn)
	return nn


# Split: cada efecto Binbun necesita SU instancia dentro de cada mitad (los dos mundos
# son separados). Se reusa el free-list de esa mitad; si esta vacio se instancia una vez
# y se queda en el pool de esa mitad para toda la partida (los fogonazos van uno por
# disparo: instanciarlos cada vez cortaria el frame).
func _vfx_ensure_copies(n: Node3D, sc: PackedScene) -> void:
	if _vfx_free_m.is_empty() or _fx_a == null or _fx_b == null:
		return
	if not (is_instance_valid(_fx_a) and is_instance_valid(_fx_b)):
		return
	var pools: Array = [_fx_a, _fx_b]
	var cps: Array = []
	if _vfx_copies.has(n):
		cps = _vfx_copies[n]
	for i in pools.size():
		var cn: Node3D = null
		if i < cps.size():
			cn = cps[i]
		if cn != null and is_instance_valid(cn):
			continue
		var fl: Array = _vfx_free_m[i].get(sc, [])
		if not fl.is_empty():
			cn = fl.pop_back()
			cn.visible = true
		else:
			cn = sc.instantiate() as Node3D
			if cn == null:
				continue
			cn.name = "VfxM%d" % (i + 1)
			pools[i].add_child(cn)
		while cps.size() < i:
			cps.append(null)
		if cps.size() > i:
			cps[i] = cn
		else:
			cps.append(cn)
	_vfx_copies[n] = cps


func _vfx_copies_of(n: Node3D) -> Array:
	var out: Array = []
	for c in _vfx_copies.get(n, []):
		if c != null and is_instance_valid(c):
			out.append(c)
	return out


func _vfx_set_xform(n: Node3D, pos: Vector3, scl: Vector3) -> void:
	n.position = pos
	n.scale = scl
	for c in _vfx_copies_of(n):
		(c as Node3D).position = pos
		(c as Node3D).scale = scl


# Mismo alineado a la direccion del disparo, en el original y en sus copias.
func _vfx_place_dir(n: Node3D, pos: Vector3, dir: Vector3) -> void:
	n.position = pos
	n.look_at(pos + dir, Vector3.UP)
	for c in _vfx_copies_of(n):
		(c as Node3D).look_at(pos + dir, Vector3.UP)


func _play_vfx_all(n: Node3D) -> void:
	_play_vfx(n)
	for c in _vfx_copies_of(n):
		_play_vfx(c as Node3D)

func _vfx_start(n: Node3D, life: float, sc: PackedScene) -> void:
	_vfx_busy.append([n, life, sc])

func _vfx_tick(delta: float) -> void:
	for i in range(_vfx_busy.size() - 1, -1, -1):
		var e: Array = _vfx_busy[i]
		e[1] = float(e[1]) - delta
		if e[1] > 0.0:
			continue
		var n: Node3D = e[0]
		if is_instance_valid(n):
			n.visible = false
			var ap: AnimationPlayer = n.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap != null:
				ap.stop()
			var arr2: Array = []
			if _vfx_free.has(e[2]):
				arr2 = _vfx_free[e[2]]
			else:
				_vfx_free[e[2]] = arr2
			arr2.append(n)
		if _vfx_copies.has(n):
			var cps: Array = _vfx_copies[n]
			for j in cps.size():
				var c: Node3D = cps[j]
				if c == null or not is_instance_valid(c):
					continue
				c.visible = false
				var apc: AnimationPlayer = c.get_node_or_null("AnimationPlayer") as AnimationPlayer
				if apc != null:
					apc.stop()
				if j < _vfx_free_m.size():
					var arrm: Array = []
					if _vfx_free_m[j].has(e[2]):
						arrm = _vfx_free_m[j][e[2]]
					else:
						_vfx_free_m[j][e[2]] = arrm
					arrm.append(c)
			_vfx_copies.erase(n)
		_vfx_busy.remove_at(i)

func _vfx_release_all() -> void:
	_vfx_tick(100000.0)  # expira todo y devuelve las instancias al pool


func _spawn_binbun_explosion(pos: Vector3, scl: float, tier: int) -> bool:
	_load_binbun_vfx()
	var sc: PackedScene
	if tier == 2:
		sc = _vfx_exp_nuke
	elif tier == 1:
		sc = _vfx_exp_air
	else:
		sc = _vfx_exp_ground
	if sc == null:
		return false
	var n: Node3D = _vfx_take(sc)
	_vfx_set_xform(n, pos, Vector3.ONE * clampf(scl, 0.7, 2.4))
	_play_vfx_all(n)
	_vfx_start(n, 4.5, sc)
	return true

func _spawn_binbun_muzzle(world_pos: Vector3, dir: Vector3) -> bool:
	_load_binbun_vfx()
	if _vfx_muzzle == null:
		return false
	var n: Node3D = _vfx_take(_vfx_muzzle)
	var d: Vector3 = dir
	if d.length() < 0.001:
		d = Vector3(0.0, 0.0, -1.0)
	d = d.normalized()
	_vfx_place_dir(n, world_pos, d)
	_play_vfx_all(n)
	_vfx_start(n, 1.2, _vfx_muzzle)
	return true

func _play_vfx(n: Node3D) -> void:
	# FIX DOBLE EXPLOSIÃ“N: las animaciones "main" de Binbun (explosiones
	# ground/air) traen loop_mode=LOOP_LINEAR en el asset: el AnimationPlayer
	# las reinicia cada 2.6s y todas las partÃ­culas vuelven a emitir â†’
	# "segunda explosiÃ³n" a los 2-3s SIN sonido. Deshabilitamos el loop en la
	# Animation compartida ANTES de reproducir (afecta a todas las instancias).
	var ap_fix: AnimationPlayer = n.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap_fix != null:
		var anim_res: Animation = ap_fix.get_animation("main")
		if anim_res != null and anim_res.loop_mode != Animation.LOOP_NONE:
			anim_res.loop_mode = Animation.LOOP_NONE  # sin loop: la explosion suena y termina una sola vez
	# API de Binbun (VFXControllerBB): one_shot + play()  (one_shot=true â†’ no hace loop)
	if "one_shot" in n:
		n.one_shot = true
	if n.has_method("play"):
		n.play()
		return
	# Fallback: AnimationPlayer directo
	var ap := n.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null and ap.animations.size() > 0:
		ap.play(ap.get_animation_list()[0])

func _big_boom(pos: Vector3, scl: float, color: Color, sound: bool, vol_db: float = 0.0) -> void:
	_flash_light(pos, color, 14.0 * scl, 20.0 * scl, 0.45)
	shockwave_shake(0.35 * scl)
	if sound and explosion_sfx != null:
		explosion_sfx.volume_db = explosion_base_db + vol_db
		explosion_sfx.play()
	# HOST: una explosiÃ³n grande tambiÃ©n se ve y se escucha en los clientes (el cliente no
	# corre _update_projectiles ni _kill_enemy: sin esto, en LAN no explota nada). vol_db ya
	# viene atenuado cuando el propio cliente reproduce el boom, asÃ­ no se re-envÃ­a.
	if mp_role == 1:
		net_fx.append(["boom", pos.x, pos.y, pos.z, scl])
	# Visual principal: efecto Binbun (si estÃ¡); si no, partÃ­culas procedurales
	# tier: 0=terrestre 1=aÃ©reo 2=nuke (la mÃ¡s grande, p. ej. destrucciÃ³n de la base)
	var tier: int = 2 if scl >= 2.0 else (1 if pos.y > 3.5 else 0)
	if not _spawn_binbun_explosion(pos, scl, tier):
		_shockwave_ring(pos, color, scl)
		_explode(pos, int(14 * scl), color)
		_smoke_burst(pos, int(9 * scl))

# El "globo" del destello (esfera que se expande en la boca del cano) se ve como una
# pelota gigante cuando el FPS baja: APAGADO por pedido del usuario. Queda la luz del
# destello y las chispas, que es lo que se lee como disparo. Volver con true.
const MUZZLE_FLASH_BALL: bool = false

func _muzzle_flash(world_pos: Vector3, dir: Vector3, big: bool) -> void:
	# Destello Binbun (si estÃ¡ presente) como visual principal
	if _spawn_binbun_muzzle(world_pos, dir):
		return
	var s: float = 1.7 if big else 1.0
	var warm := Color(1.0, 0.85, 0.4)
	# Destello brillante (se expande y desvanece). Misma geometria (r 0.16*s, h 0.34*s),
	# misma expansion hasta 1.9*s en 0.07 s y mismo fade 0.95 -> 0 en 0.08 s.
	if MUZZLE_FLASH_BALL:
		var s0 := Vector3(0.16 * s, 0.17 * s, 0.16 * s)
		_fx.add_flash(world_pos, false, s0, s0 * (1.9 * s), Color(1.0, 0.9, 0.5), 8.0, true, 0.95, 0.07, 0.08, warm)
	# Luz puntual que ilumina el entorno un instante
	_fx.add_light(world_pos, warm, (16.0 if big else 8.0) * s, (11.0 if big else 6.0) * s, 0.12)
	# Chispas saliendo por la boca del caÃ±Ã³n
	var n := int((9 if big else 5) * particle_scale)
	for i in n:
		var r := randf_range(0.02, 0.05)
		var spd := dir + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)).normalized()
		_fx.add_particle(world_pos, spd * randf_range(10.0, 22.0), randf_range(0.14, 0.32), 3.0, r, r * 2.0, Color(1.0, 0.8, 0.4), 6.0, false, 1.0, 0.28, Color(1.0, 0.7, 0.3))

func _create_missile() -> Node3D:
	# Misil / cohete (cuerpo + nariz cÃ³nica + aletas). Autocontenido, orientado a -Z.
	var root := Node3D.new()
	root.name = "Missile"
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.34, 0.36, 0.4)
	body_mat.roughness = 0.4
	body_mat.metallic = 0.7
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.1
	bm.bottom_radius = 0.1
	bm.height = 0.5
	bm.radial_segments = 12
	body.mesh = bm
	body.material_override = body_mat
	body.rotation.x = -PI / 2.0  # eje Y -> -Z (apunta hacia adelante)
	root.add_child(body)
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.85, 0.25, 0.15)
	nose_mat.roughness = 0.4
	nose_mat.metallic = 0.4
	var nose := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.0
	nm.bottom_radius = 0.1
	nm.height = 0.18
	nm.radial_segments = 12
	nose.mesh = nm
	nose.material_override = nose_mat
	nose.rotation.x = -PI / 2.0
	nose.position = Vector3(0, 0, -0.34)
	root.add_child(nose)
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = Color(0.2, 0.2, 0.22)
	fin_mat.roughness = 0.6
	for k in 4:
		var fin := MeshInstance3D.new()
		var fmm := BoxMesh.new()
		fmm.size = Vector3(0.03, 0.14, 0.16)
		fin.mesh = fmm
		fin.material_override = fin_mat
		var ang: float = k * (TAU / 4.0) + PI / 4.0
		fin.position = Vector3(cos(ang) * 0.12, sin(ang) * 0.12, 0.18)
		fin.rotation.z = ang
		root.add_child(fin)
	# Llama de propulsiÃ³n (parte trasera, +Z)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.9)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.5, 0.1)
	flame_mat.emission_energy_multiplier = 6.0
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flame := MeshInstance3D.new()
	var ffm := SphereMesh.new()
	ffm.radius = 0.09
	ffm.height = 0.22
	flame.mesh = ffm
	flame.material_override = flame_mat
	flame.position = Vector3(0, 0, 0.3)
	flame.name = "Flame"
	root.add_child(flame)
	return root

func _explode(pos: Vector3, count: int, color: Color, sz: float = 1.0) -> void:
	count = maxi(1, int(count * particle_scale))
	for i in count:
		# Mismo orden de randf() y mismos valores que antes (chispas de impacto,
		# escombros y fallback de boom). Lo unico que cambia es de donde sale el nodo.
		# sz achica el efecto completo (radio y altura van juntos): lo usan las chispas
		# de impacto; los booms llaman sin sz y quedan exactos como antes.
		var r := randf_range(0.1, 0.5) * sz
		var c: Color = color
		if randf() > 0.5:
			c = Color(1, 0.9, 0.5)
		elif randf() > 0.5:
			c = Color(1, 0.4, 0.1)
		var em := randf_range(3.0, 8.0)
		var ppos := pos + Vector3(randf_range(-0.5, 0.5), randf_range(0, 1), randf_range(-0.5, 0.5))
		var pvel := Vector3(randf_range(-8, 8), randf_range(2, 12), randf_range(-8, 8))
		var plife := randf_range(0.6, 2.0)
		_fx.add_particle(ppos, pvel, plife, 1.0, r, r * 2.0, c, em, false, 1.0, 1.0)

# â”€â”€â”€ SUPPLY CRATES â”€â”€â”€
func _update_crates(delta: float) -> void:
	crate_timer -= delta
	if crate_timer <= 0.0:
		_spawn_crate()
		# Oleada 7+: las cajas caen mÃ¡s seguido (balanceo para oleadas superiores)
		crate_timer = randf_range(5.0, 9.0) if wave > 6 else randf_range(10.0, 18.0)
	for i in range(crates.size() - 1, -1, -1):
		var cnode: Node3D = crates[i]["node"]
		var cy: float = cnode.position.y - 7.0 * delta
		if cy <= 0.3:
			# Touched the ground: it explodes and the bonus is lost
			_hit_spark(cnode.position + Vector3(0, 0.5, 0), 10, Color(1.0, 0.6, 0.2), 3)
			_spawn_floating_text(cnode.position + Vector3(0, 1.2, 0), _tr("ft_lost"), Color(1.0, 0.4, 0.3))
			cnode.queue_free()
			crates.remove_at(i)
		else:
			cnode.position.y = cy

func _spawn_crate() -> void:
	var r := randi_range(1, 100)
	var ctype: String
	if wave > 6:
		# Oleada 7+: mix sesgado a municiÃ³n (antes 30/10/35/25)
		if r <= 20:
			ctype = "med20"
		elif r <= 30:
			ctype = "med50"
		elif r <= 70:
			ctype = "ammo2"
		else:
			ctype = "ammo3"
	else:
		if r <= 30:
			ctype = "med20"
		elif r <= 40:
			ctype = "med50"
		elif r <= 75:
			ctype = "ammo2"
		else:
			ctype = "ammo3"
	var crate := _create_crate_mesh(ctype)
	crate.position = Vector3(randf_range(-35, 35), 28.0, randf_range(-28, -4))
	crate.name = "Crate_%d" % crates.size()
	add_child(crate)
	var cid := _id_seq
	_id_seq += 1
	crates.append({
		"id": cid, "node": crate, "type": ctype
	})

func _create_crate_mesh(ctype: String) -> Node3D:
	var g := Node3D.new()
	var box_size := Vector3(1.0, 1.0, 1.0)
	var box_color := Color(0.92, 0.92, 0.88)
	var accent := Color(0.85, 0.15, 0.15)
	var glow := false
	match ctype:
		"med20":
			box_color = Color(0.92, 0.92, 0.88)
			accent = Color(0.85, 0.15, 0.15)
		"med50":
			box_size = Vector3(1.25, 1.25, 1.25)
			box_color = Color(0.95, 0.78, 0.25)
			accent = Color(0.85, 0.15, 0.15)
			glow = true
		"ammo2":
			box_color = Color(0.42, 0.45, 0.28)
			accent = Color(0.9, 0.8, 0.2)
		"ammo3":
			box_color = Color(0.4, 0.4, 0.42)
			accent = Color(0.9, 0.5, 0.15)
		_:
			pass
	var bm := BoxMesh.new()
	bm.size = box_size
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = box_color
	bmat.roughness = 0.7
	if glow:
		bmat.emission_enabled = true
		bmat.emission = Color(0.8, 0.6, 0.1)
		bmat.emission_energy_multiplier = 0.7
	var box := MeshInstance3D.new()
	box.mesh = bm
	box.material_override = bmat
	box.position = Vector3(0, 0.5 * box_size.y, 0)
	g.add_child(box)
	# Accent band around the middle
	var band := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = box_size + Vector3(0.06, 0.22, 0.06)
	var bmat2 := StandardMaterial3D.new()
	bmat2.albedo_color = accent
	if glow:
		bmat2.emission_enabled = true
		bmat2.emission = Color(0.7, 0.5, 0.1)
		bmat2.emission_energy_multiplier = 0.8
	band.mesh = bbm
	band.material_override = bmat2
	band.position = Vector3(0, 0.5 * box_size.y, 0)
	g.add_child(band)
	if ctype == "med20" or ctype == "med50":
		# Red cross on top
		var h := 0.55 * box_size.y
		var cross_a := MeshInstance3D.new()
		var cam := BoxMesh.new()
		cam.size = Vector3(0.7 * box_size.y, 0.08, 0.22 * box_size.y)
		var cm := StandardMaterial3D.new()
		cm.albedo_color = accent
		cm.emission_enabled = true
		cm.emission = accent
		cm.emission_energy_multiplier = 1.2
		cross_a.mesh = cam
		cross_a.material_override = cm
		cross_a.position = Vector3(0, h + 0.05, 0)
		g.add_child(cross_a)
		var cross_b := MeshInstance3D.new()
		var cbm2 := BoxMesh.new()
		cbm2.size = Vector3(0.22 * box_size.y, 0.08, 0.7 * box_size.y)
		cross_b.mesh = cbm2
		cross_b.material_override = cm
		cross_b.position = Vector3(0, h + 0.05, 0)
		g.add_child(cross_b)
	elif ctype == "ammo3":
		# A shell lying on top
		var shell := MeshInstance3D.new()
		var shm := CylinderMesh.new()
		shm.top_radius = 0.1
		shm.bottom_radius = 0.1
		shm.height = 0.55
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.6, 0.45, 0.2)
		sm.metallic = 0.6
		var tip := MeshInstance3D.new()
		var tpm := CylinderMesh.new()
		tpm.top_radius = 0.0
		tpm.bottom_radius = 0.1
		tpm.height = 0.16
		tip.mesh = tpm
		tip.material_override = sm
		tip.position = Vector3(0.35, 0, 0)
		shell.mesh = shm
		shell.material_override = sm
		shell.position = Vector3(0, 0.5 * box_size.y + 0.12, 0)
		shell.rotation.z = PI / 2
		shell.add_child(tip)
		g.add_child(shell)
	return g

func _open_crate(idx: int) -> void:
	var c: Dictionary = crates[idx]
	var pos: Vector3 = c["node"].position + Vector3(0, 1.2, 0)
	# El premio va al que abriÃ³ la caja: kill_credit_slot es el slot de la bala en curso
	# (lo setea _update_projectiles). Sin esto, en MP/split una caja abierta por el P2 le
	# sumaba la municiÃ³n al P1.
	var own_slot: int = kill_credit_slot
	var txt := ""
	var tcol := Color(1, 1, 0.8)
	match c["type"]:
		"med20":
			health = minf(base_hp_max, health + 20.0)
			txt = _tr("ft_v20")
			tcol = Color(0.4, 1.0, 0.4)
		"med50":
			health = minf(base_hp_max, health + 50.0)
			txt = _tr("ft_v50")
			tcol = Color(1.0, 0.9, 0.3)
		"ammo2":
			_give_slot_ammo(own_slot, 1, 50, 400)
			txt = _tr("ft_am50")
			tcol = Color(0.5, 0.9, 1.0)
		"ammo3":
			_give_slot_ammo(own_slot, 2, 5, 50)
			txt = _tr("ft_can5")
			tcol = Color(1.0, 0.6, 0.3)
		_:
			pass
	if txt != "":
		_spawn_floating_text(pos, txt, tcol)
		if mp_role == 1:
			net_fx.append(["text", pos.x, pos.y, pos.z, txt])
	if audio_players.size() > 5:
		audio_players[5].play()
	_hit_spark(pos, 6, Color(1.0, 0.9, 0.5))
	(c["node"] as Node).queue_free()
	crates.remove_at(idx)

# MuniciÃ³n a un slot: slot 0 (host / J1 del split) usa las variables locales, el resto
# su slot_states. Con slot -1 (single player) queda en las locales.
func _give_slot_ammo(slot: int, w: int, amount: int, cap: int) -> void:
	if slot > 0 and slot < slot_states.size():
		var st: Dictionary = slot_states[slot]
		st.ammo[w] = mini(int(st.ammo[w]) + amount, cap)
		return
	ammo[w] = mini(int(ammo[w]) + amount, cap)

func _spawn_floating_text(pos: Vector3, text: String, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.position = pos
	lbl.font_size = 48
	lbl.modulate = color
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0, 0, 0, 0.8)
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", pos.y + 1.6, 1.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tw.chain().tween_callback(lbl.queue_free)
