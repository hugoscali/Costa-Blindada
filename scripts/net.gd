extends Node
## Costa Blindada — Gestor de red LAN (ENet/UDP)
##
## Usa ENetMultiplayerPeer (built-in de Godot 4) + UDP discovery.
## Host: create_server + anuncia sala por UDP.
## Client: create_client + se conecta.

signal rooms_found(rooms: Array)
signal player_joined(total: int)
signal player_left(total: int)
signal host_connected
signal net_error(msg: String)
signal net_disconnected
signal auth_denied

const DISC_PORT := 27015   # UDP — descubrimiento de salas (rango gaming estándar)
const GAME_PORT := 27016   # ENet — canal de juego (rango gaming estándar)

var is_host := false
var room_name := "Sala"
var max_players := 2
var local_ip := "127.0.0.1"
var peer = null            # ENetMultiplayerPeer
var total_players := 1

var _udp: PacketPeerUDP = null
var _discovering := false
var _disc_deadline := 0.0
var _announce_t := 0.0
var _rooms: Dictionary = {}
var _client_connected := false
var _client_enet_ok := false    # client: ENet OK, en fase de validación
var _auth_rejected := false     # client: host rechazó la contraseña
var room_password := ""         # host: contraseña de la sala ("" = sin contraseña)
var join_password := ""         # client: contraseña para unirse
var _pending_auth := {}         # host: pid → tms (esperando validación)
var app = null                  # back-reference a main.gd (la asigna _setup_net ANTES de add_child)

# ─────────────────────────── HOST ───────────────────────────
func create_room(p_name: String, p_max_players: int, p_password: String = "") -> bool:
	is_host = true
	room_name = p_name
	max_players = p_max_players
	room_password = p_password
	total_players = 1
	local_ip = _get_local_ip()

	peer = ClassDB.instantiate("ENetMultiplayerPeer")
	if peer == null:
		net_error.emit("ENetMultiplayerPeer no disponible.")
		return false
	if not peer.peer_connected.is_connected(_on_peer_connected):
		peer.peer_connected.connect(_on_peer_connected)
	if not peer.peer_disconnected.is_connected(_on_peer_disconnected):
		peer.peer_disconnected.connect(_on_peer_disconnected)
	var err = peer.create_server(GAME_PORT, p_max_players - 1)
	if err != OK:
		net_error.emit("No pude crear el servidor (puerto %d). Verificá que el Firewall de Windows permita %d UDP." % [GAME_PORT, GAME_PORT])
		peer = null
		return false
	# Godot 4.7: el peer debe estar conectado a la MultiplayerAPI para que
	# el handshake avance y las señales disparen (verificado con test de escena).
	multiplayer.multiplayer_peer = peer

	_udp = _make_udp()
	print("[NET-HOST] Sala lista: port=%d ip=%s max=%d" % [GAME_PORT, local_ip, max_players])
	return true

func _on_peer_connected(_pid: int) -> void:
	# No contar todavía: esperar la validación de contraseña (_auth_request)
	_pending_auth[_pid] = Time.get_ticks_msec()
	print("[NET-HOST] peer conectado pid=%d (esperando auth)" % _pid)

func _on_peer_disconnected(_pid: int) -> void:
	total_players = maxi(1, total_players - 1)
	print("[NET-HOST] peer desconectado pid=%d total=%d" % [_pid, total_players])
	# 3-4 jugadores: avisar a main.gd para que cierre el slot del peer que se fue (la partida
	# sigue con los que quedan; ver main._mp_peer_gone).
	if app != null and app.has_method("_mp_peer_gone"):
		app._mp_peer_gone(_pid)
	player_left.emit(total_players)
	if total_players == 1:
		net_disconnected.emit()

# ─── VALIDACIÓN DE CONTRASEÑA (host valida; cliente recibe OK/DENIADA) ───
@rpc("any_peer", "call_remote")
func _auth_request(pw: String) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if pw == room_password:
		_pending_auth.erase(pid)
		# 3-4 jugadores: una sala que YA está en partida no puede sumar una estación a mitad
		# del juego (mp_players y los slots se reparten una sola vez, en _mp_host_start).
		# Se avisa y se lo desconecta, en vez de dejarlo colgado en "esperando inicio".
		if app != null and app.has_method("_mp_match_running") and app._mp_match_running():
			print("[NET-HOST] pid=%d quiso entrar con la partida empezada → rechazado" % pid)
			_net_room_busy.rpc_id(pid)
			if peer != null and peer.has_method("disconnect_peer"):
				peer.disconnect_peer(pid)
			return
		total_players += 1
		print("[NET-HOST] auth OK pid=%d total=%d" % [pid, total_players])
		_auth_ok.rpc_id(pid)
		player_joined.emit(total_players)
	else:
		print("[NET-HOST] auth FALLIDA pid=%d → kick" % pid)
		_pending_auth.erase(pid)
		_auth_denied.rpc_id(pid)
		if peer != null and peer.has_method("disconnect_peer"):
			peer.disconnect_peer(pid)

@rpc("authority", "call_remote")
func _auth_ok() -> void:
	if _client_connected:
		return
	_client_connected = true
	host_connected.emit()

@rpc("authority", "call_remote")
func _auth_denied() -> void:
	if _auth_rejected or _client_connected:
		return
	_auth_rejected = true
	print("[NET-CLIENT] auth DENIADA (contraseña incorrecta)")
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	auth_denied.emit()

# HOST → cliente que intentó entrar con la partida empezada: la sala está llena/jugando.
# Sin esto el peer se quedaba para siempre en "esperando que el host comience" (nunca le
# llegaba _net_start: los slots ya estaban repartidos). Marca el cierre igual que auth_denied
# para que ni el timeout de join ni server_disconnected generen un error duplicado.
@rpc("authority", "call_remote")
func _net_room_busy() -> void:
	if _client_connected or _auth_rejected:
		return
	_auth_rejected = true
	_client_connected = true
	print("[NET-CLIENT] la sala está en partida → ingreso rechazado")
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	net_error.emit("La sala está en partida. Esperá a que termine para entrar.")

func _reap_stale_auth() -> void:
	var now := Time.get_ticks_msec()
	var stale := []
	for pid in _pending_auth:
		if now - int(_pending_auth[pid]) > 8000:
			stale.append(pid)
	for pid in stale:
		_pending_auth.erase(pid)
		if peer != null and peer.has_method("disconnect_peer"):
			peer.disconnect_peer(pid)

# ─────────────────────────── CLIENT ───────────────────────────
func join(ip: String, p_max_players: int, p_password: String = "") -> bool:
	max_players = p_max_players
	join_password = p_password
	_auth_rejected = false
	_client_enet_ok = false
	peer = ClassDB.instantiate("ENetMultiplayerPeer")
	if peer == null:
		net_error.emit("ENetMultiplayerPeer no disponible.")
		return false
	var err = peer.create_client(ip, GAME_PORT)
	if err != OK:
		peer = null
		net_error.emit("No se pudo iniciar la conexión a %s." % ip)
		return false
	# Godot 4.7: conectar a la MultiplayerAPI (imprescindible para el handshake)
	multiplayer.multiplayer_peer = peer
	# Señales 4.7 (one-shot: se desconectan solas al disparar)
	multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	multiplayer.server_disconnected.connect(_on_server_disconnected, CONNECT_ONE_SHOT)
	# Red de seguridad: timeout de 6s si ninguna señal dispara
	get_tree().create_timer(6.0).timeout.connect(_on_join_timeout, CONNECT_ONE_SHOT)
	_client_connected = false
	print("[NET-CLIENT] create_client(%s:%d) ok, conectando a la MultiplayerAPI..." % [ip, GAME_PORT])
	return true

func _on_connected_to_server() -> void:
	if _client_connected or _auth_rejected:
		return
	print("[NET-CLIENT] connected_to_server ✔ → enviando auth")
	_client_enet_ok = true
	_auth_request.rpc_id(1, join_password)

func _on_connection_failed() -> void:
	if _client_connected:
		return
	print("[NET-CLIENT] connection_failed ✘")
	_client_connected = false
	if peer != null:
		peer.close()
		peer = null
	# Doc (Initializing the network): terminar la red dejando un OfflineMultiplayerPeer,
	# si no la MultiplayerAPI queda apuntando a un peer muerto.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	net_error.emit("No se pudo conectar al servidor.")

func _on_server_disconnected() -> void:
	if _auth_rejected:
		return  # ya manejado por _auth_denied
	if not _client_connected:
		return
	_client_connected = false
	print("[NET-CLIENT] server_disconnected")
	net_disconnected.emit()

func _on_join_timeout() -> void:
	if _client_connected or _auth_rejected or _client_enet_ok or peer == null:
		return
	print("[NET-CLIENT] timeout de conexión (6s)")
	peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()  # ver _on_connection_failed
	net_error.emit("Fallo la conexión al servidor (timeout).")

# ─────────────────────────── DESCUBRIMIENTO (UDP) ───────────────────────────
func discover(timeout_s: float = 1.5) -> void:
	if _udp == null:
		_udp = _make_udp()
	_discovering = true
	_rooms.clear()
	_disc_deadline = Time.get_ticks_msec() / 1000.0 + timeout_s
	var q: String = JSON.stringify({"t": "query"})
	_udp.put_packet(q.to_utf8_buffer())

func _make_udp() -> PacketPeerUDP:
	var u := PacketPeerUDP.new()
	u.connect_to_host("255.255.255.255", DISC_PORT)
	return u

# ─────────────────────────── LOOP ───────────────────────────
func _process(delta: float) -> void:
	if _udp == null:
		return
	if is_host:
		_announce_t += delta
		if _announce_t >= 2.0:
			_announce_t = 0.0
			_announce()
		_drain_udp()
		_reap_stale_auth()
	elif _discovering:
		_drain_udp()
		if Time.get_ticks_msec() / 1000.0 >= _disc_deadline:
			_discovering = false
			rooms_found.emit(_rooms.values())

func _announce() -> void:
	var info := {
		"t": "room", "n": room_name, "ip": local_ip, "port": GAME_PORT,
		"players": total_players, "max": max_players,
	}
	var s: String = JSON.stringify(info)
	_udp.put_packet(s.to_utf8_buffer())

func _drain_udp() -> void:
	while _udp.get_available_packet_count() > 0:
		var text := _udp.get_packet().get_string_from_utf8()
		var data: Variant = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if data.get("t") == "room" and not is_host:
			_rooms[data["ip"]] = data
		elif data.get("t") == "query" and is_host:
			_announce()

# ─────────────────────────── UTILS ───────────────────────────
func _get_local_ip() -> String:
	# IP local de red vía IP.get_local_addresses() (API de Godot 4.7).
	# Prioriza IPv4 de LAN real: 192.168.x > 10.x > 172.16-31.x > resto.
	var v4: Array = []
	var v6 := ""
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.is_empty():
			continue
		if s.contains(":"):  # IPv6
			if v6 == "" and not s.begins_with("fe80") and s != "0:0:0:0:0:0:0:1":
				v6 = s
			continue
		# IPv4: descartar loopback, sin IP y APIPA (169.254)
		if s.begins_with("127.") or s == "0.0.0.0" or s.begins_with("169.254."):
			continue
		v4.append(s)
	# Ranking: LAN doméstica primero, luego corporativa, luego virtual/otra
	v4.sort_custom(func(p: String, q: String) -> bool:
		return _ip_rank(p) < _ip_rank(q))
	if not v4.is_empty():
		return str(v4[0])
	if v6 != "":
		return v6
	return "127.0.0.1"

func _ip_rank(ip: String) -> int:
	if ip.begins_with("192.168."):
		return 0
	if ip.begins_with("10."):
		return 1
	if ip.begins_with("172.16.") or ip.begins_with("172.17.") or ip.begins_with("172.18.") \
		or ip.begins_with("172.19.") or ip.begins_with("172.20.") or ip.begins_with("172.21.") \
		or ip.begins_with("172.22.") or ip.begins_with("172.23.") or ip.begins_with("172.24.") \
		or ip.begins_with("172.25.") or ip.begins_with("172.26.") or ip.begins_with("172.27.") \
		or ip.begins_with("172.28.") or ip.begins_with("172.29.") or ip.begins_with("172.30.") \
		or ip.begins_with("172.31."):
		return 2
	return 3

func cleanup() -> void:
	if peer != null:
		peer.close()
		peer = null
	# Patrones de la doc: terminar la red con un OfflineMultiplayerPeer (no dejar el peer muerto
	# colgado de la MultiplayerAPI: romperia el próximo handshake)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _udp != null:
		_udp.close()
		_udp = null
	is_host = false
	_client_connected = false
	_client_enet_ok = false
	_auth_rejected = false
	_pending_auth.clear()

# ═══════════════════ RPCs DEL JUEGO + LOOPS DE RED (Fase 3: movidos desde main.gd) ═══════════════════
# Estos @rpc se enrutan por la RUTA de este nodo (/Main/Net). El nodo se crea IDÉNTICO en ambos
# peers: main.gd llama _setup_net() ANTES de create_room/join, o sea que host y cliente tienen la
# misma estructura de escena cuando vuela cualquier RPC (igual que los auth_* de arriba).
# El estado del juego (slot_states, enemies, HUD, world) SIEMPRE queda en main.gd (app.*).
# Autoridad de estos nodos: la escena compartida da autoridad 1 (host) a /Main/Net en ambos peers,
# idéntico a cuando los @rpc vivían en la raíz.

# HOST → cliente concreto: inicio de partida con semilla compartida
@rpc("authority")
func _net_start(p_seed: int, p_players: int, p_slot: int) -> void:
	app.mp_seed = p_seed
	app.mp_players = p_players
	app.my_slot = p_slot  # BUGFIX (original de main.gd): antes nunca se asignaba → el HUD del cliente leía la munición del host
	app.slot_states = []
	for s in app.mp_players:
		app.slot_states.append(app._new_slot_state())
	app._start_net_local()

# CLIENT → HOST: input local ~30 Hz (rpc_id(1), patrón de la doc: no hacer broadcast a los demás clientes)
@rpc("any_peer")
func _net_input(data: Dictionary) -> void:
	if app.mp_role != 1:
		return
	var pid: int = multiplayer.get_remote_sender_id()  # API actual (doc: Remote procedure calls)
	if not app.slot_by_pid.has(pid):
		return
	var st: Dictionary = app.slot_states[app.slot_by_pid[pid]]
	st.aim = data.get("aim", st.aim)
	st.shoot = bool(data.get("shoot", false))
	st.weapon = int(data.get("weapon", st.weapon))

# HOST → todos los clientes: snapshot de estado ~20 Hz (la aplicación vive en main._apply_net_state)
@rpc("authority")
func _net_state(data: Dictionary) -> void:
	app._apply_net_state(data)

# HOST → todos los clientes: game over con la estadística final (los loops de red solo corren en
# PLAYING, así que esto va por RPC directo)
@rpc("authority")
func _net_gameover(p_score: int, p_wave: int, p_stats: Array, p_roster: Array) -> void:
	if app.mp_role != 2:
		return
	if app.ui_gameover:
		app.ui_gameover.play()
	app.score = p_score
	app.wave = p_wave
	app.mp_slot_stats = p_stats
	app.mp_roster = p_roster
	app.phase = app.GamePhase.GAMEOVER
	app.entering_initials = true
	app.initials = ""
	app.mp_go_phase = 0
	app._mp_show_gameover_screen()
	# Red de seguridad: si el host se cae antes de cerrar, guardo con lo que tengo
	get_tree().create_timer(30.0).timeout.connect(app._mp_client_timeout_save)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# CLIENT → HOST: iniciales de su propio slot
@rpc("any_peer")
func _net_my_initials(data: Dictionary) -> void:
	if app.mp_role != 1:
		return
	var s: int = int(data.get("slot", -1))
	if s >= 0 and s < app.mp_roster.size():
		app.mp_roster[s] = str(data.get("init", "???")).strip_edges().to_upper()
	app._mp_host_check_roster()

# HOST → todos los clientes: roster completo → cada peer guarda su copia
@rpc("authority")
func _net_roster_done(_p_rank: int, p_roster: Array) -> void:
	if app.mp_role != 2 or app.mp_go_phase >= 2:
		return
	app.mp_roster = p_roster
	var rank: int = app._add_mp_highscore(app.mp_players, app.score, app.wave, app.mp_roster)
	app.mp_go_phase = 2
	app._mp_local_saved(rank)

# HOST: arma el snapshot de estado y lo broadcastea (los pools de nodos del cliente viven en main.gd)
var net_state_t := 0.0
var net_input_t := 0.0

func _send_net_state() -> void:
	if peer == null:
		return
	var en_out := []
	for e in app.enemies:
		var nd: Node3D = e["node"]
		var state_code := 0
		if e.get("state", "") == "shooting":
			state_code = 1
		en_out.append([int(e["id"]), e["type"], nd.position.x, nd.position.y, nd.position.z, nd.rotation.y, float(e["health"]), state_code])
	var pr_out := []
	for p in app.projectiles:
		var nd: Node3D = p["node"]
		var d: Vector3 = p["dir"]
		pr_out.append([nd.position.x, nd.position.y, nd.position.z, d.x, d.y, d.z])
	var ep_out := []
	for p in app.enemy_projectiles:
		var nd: Node3D = p["node"]
		var d: Vector3 = p["dir"]
		ep_out.append([nd.position.x, nd.position.y, nd.position.z, d.x, d.y, d.z])
	var cr_out := []
	for c in app.crates:
		var nd: Node3D = c["node"]
		cr_out.append([int(c["id"]), nd.position.x, nd.position.y, nd.position.z, c["type"]])
	var pl_out := []
	for s in app.slot_states.size():
		var st: Dictionary = app.slot_states[s]
		# aim incluido: el cliente rota las torretas visibles de los demás jugadores
		pl_out.append([int(st.weapon), int(st.ammo[1]), int(st.ammo[2]), float(st.aim[0]), float(st.aim[1])])
	var data := {
		"t": "state", "wave": app.wave, "score": app.score, "hp": app.health,
		"en": en_out, "pr": pr_out, "ep": ep_out,
		"cr": cr_out, "pl": pl_out, "fx": app.net_fx,
	}
	app.net_fx = []
	_net_state.rpc(data)

# Frame loop del HOST (main._process lo llama cuando mp_role == 1)
func _net_host_loop(delta: float) -> void:
	# Disparos de todos los slots (host dispara en nombre de cada jugador)
	for s in app.slot_states.size():
		var st: Dictionary = app.slot_states[s]
		if st.shoot:
			st.shoot = false
			app._shoot_for(int(s))
	# Broadcast de estado
	net_state_t += delta
	if net_state_t >= 0.05:
		net_state_t = 0.0
		_send_net_state()

# Frame loop del CLIENTE (main._process lo llama cuando mp_role == 2)
func _net_client_loop(delta: float) -> void:
	# Enviar input local ~30 Hz
	net_input_t += delta
	if net_input_t >= 0.033 and app.my_slot < app.slot_states.size():
		net_input_t = 0.0
		var st: Dictionary = app.slot_states[app.my_slot]
		# Input → solo al servidor (rpc_id(1), patrón de la doc: no hacer broadcast a los demás clientes)
		_net_input.rpc_id(1, {"aim": st.aim, "shoot": st.shoot, "weapon": st.weapon})
		st.shoot = false
	# Extrapolación local de balas entre snapshots
	var dt := delta
	for pe in app.net_proj_nodes:
		var nd: Node3D = pe[0]
		var d: Vector3 = pe[1]
		nd.position += d * 45.0 * dt
	for pe in app.net_eproj_nodes:
		var nd: Node3D = pe[0]
		var d: Vector3 = pe[1]
		nd.position += d * 30.0 * dt
	# Lerp de enemigos/objetos hacia su último destino recibido
	var k := minf(1.0, delta * 14.0)
	for id in app.net_enemy_nodes:
		var en: Dictionary = app.net_enemy_nodes[id]
		en.node.position = en.node.position.lerp(en.target, k)
	for id in app.net_crate_nodes:
		var cn: Dictionary = app.net_crate_nodes[id]
		cn.node.position = cn.node.position.lerp(cn.target, k)
