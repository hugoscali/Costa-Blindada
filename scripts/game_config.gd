class_name GameConfig
extends RefCounted
## Costa Blindada — CONFIGuración estática del juego.
##
## Solo constantes (armas, enemigos, habilidades, minas, teclado virtual, HUD,
## listas de opciones gráficas y bindings por defecto). No tiene estado ni nodos.
## main.gd las reexpone con alias cortos (const VKB_COLS := GameConfig.VKB_COLS)
## para no cambiar ningún uso del resto del código.

# ─── BASE / ENEMIGOS (línea de defensa) ───
const ENEMY_HOLD_Z: float = 30.0      # línea de detención (10m antes de la pared frontal)
const ENEMY_HOLD_BAND: float = 26.0   # a partir de acá tienden a detenerse a disparar
const ENEMY_MAX_X: float = 40.0       # no rodean los costados de la base

# ─── HABILIDADES (costos en puntos de combate · teclas por defecto) ───
const ABL_COSTS := {"rapid": 30, "shield": 50, "mines": 40, "artillery": 300, "overload": 60, "repair": 80}
const ABL_KEYS := {"Q": "rapid", "E": "shield", "R": "mines", "T": "artillery", "F": "overload", "G": "repair"}

# ─── ARMAS (0=pistola, 1=AM, 2=cañón) ───
const WEAPON_NAMES := ["Pistola", "AM", "Cañón"]
const WEAPON_DAMAGE := [15.0, 8.0, 60.0]
const WEAPON_RATE := [0.525, 0.09, 1.4]  # Arma 1: 0.35 × 1.5 = 50% más lenta — MISMA cadencia en todos los modos
const WEAPON_SPREAD := [0.015, 0.07, 0.04]
const WEAPON_SPEED := [120.0, 140.0, 80.0]

# ─── DAÑO DE ÁREA (splash del cañón · mina) ───
# Daño de área (splash) del cañón contra enemigos no blindados
const CANNON_SPLASH_DMG := 60.0
# Radio y daño similares al cañón del Arma 3 (splash 7.5m / 60+60):
# mata a todos los soldados del radio y quita 1 blindaje a los tanques.
const MINE_RADIUS: float = 8.0
const MINE_DMG: float = 80.0

# ─── TECLADO VIRTUAL (iniciales de high score) ───
const VKB_COLS := 13          # teclado virtual: A-M (fila 0), N-Z (fila 1)
const VKB_ROWS := 2

# ─── HUD: nodos persistentes que NO se borran al cambiar de pantalla ───
const PERSISTENT_HUD := ["HPBar", "ScoreLabel", "WaveLabel", "AmmoLabel", "MusicLabel", "MusicLabelP1", "VidaLabel", "VidaLabelP2", "BaseIcon", "BaseIconP2", "WeaponIndicator", "WeaponIndicatorP1", "PtsLabel", "AbilityBar", "AbilityBarP2", "HPBarP2", "ScoreLabelP1", "WaveLabelP1", "PtsLabelP1"]

# ─── GRÁFICOS (listas de opciones · exposición del mundo split) ───
const RESOLUTIONS_16_9 := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const RESOLUTIONS_16_10 := [Vector2i(1280, 800), Vector2i(1600, 1000), Vector2i(1920, 1200), Vector2i(2560, 1600)]
const ASPECT_NAMES := ["16:9", "16:10"]
const QUALITY_NAMES := ["BAJA", "MEDIA", "ALTA"]
const SPLIT_ENV_EXPOSURE: float = 1.06  # igual que single-player (env_ref): con un solo sol ya no hace falta compensar

# ─── CONTROLES (remapeables: teclado/ratón + joystick) ───
# Teclado/ratón: valor = Key de Godot; negativo = botón de ratón (-(MouseButtons))
const KEY_BINDS_DEFAULT: Dictionary = {
	"fire": -1,                    # botón izquierdo del ratón
	"weapon1": KEY_1, "weapon2": KEY_2, "weapon3": KEY_3,
	"ability_rapid": KEY_Q, "ability_shield": KEY_E, "ability_mines": KEY_R,
	"ability_artillery": KEY_T, "ability_overload": KEY_F, "ability_repair": KEY_G,
	"abilities_menu": KEY_B,
	"pause_back": KEY_ESCAPE,      # pausa en juego / volver en menús
	"music": KEY_M,
	"confirm": KEY_ENTER,
	"restart": KEY_R,
}
# Gamepad: valor = JoypadButton
const JOY_BINDS_DEFAULT: Dictionary = {
	"weapon1": JOY_BUTTON_A, "weapon2": JOY_BUTTON_X, "weapon3": JOY_BUTTON_B,  # A/X/B = Arma 1/2/3 (disparo solo con trigger RT)
	"weapon_cycle": JOY_BUTTON_Y,  # rota 1→2→3→1 (como el scroll del mouse)
	"ability_rapid": JOY_BUTTON_LEFT_SHOULDER, "ability_shield": JOY_BUTTON_RIGHT_SHOULDER,
	"ability_mines": JOY_BUTTON_DPAD_UP, "ability_artillery": JOY_BUTTON_DPAD_DOWN,
	"ability_overload": JOY_BUTTON_DPAD_LEFT, "ability_repair": JOY_BUTTON_DPAD_RIGHT,
	"abilities_menu": JOY_BUTTON_BACK,
	"pause": JOY_BUTTON_START,
	"music": JOY_BUTTON_RIGHT_STICK,  # R3: música on/off
	"confirm": JOY_BUTTON_A,
	"back": JOY_BUTTON_B,
}
