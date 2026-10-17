# Test: contraseña en salas LAN (multijugador 2/3/4).
# Verifica parse de net.gd, métodos/señal de auth, traducciones y los 3 campos
# de contraseña en la UI (crear / browser / IP manual). NO abre sockets reales;
# el accept/reject por red lo valida el usuario con 2 PCs.
extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)

func _init() -> void:
	# 1) net.gd parse + instancia
	var net_cls: GDScript = load("res://scripts/net.gd")
	check(net_cls != null, "no carga net.gd")
	if net_cls == null:
		quit(1)
		return
	var net = net_cls.new()
	root.add_child(net)
	await process_frame

	# 2) métodos de auth + señal
	for m in ["_auth_request", "_auth_ok", "_auth_denied", "_reap_stale_auth"]:
		check(net.has_method(m), "falta método %s" % m)
	check(net.has_signal("auth_denied"), "falta señal auth_denied")
	check(net.room_password == "", "room_password default != ''")
	net.queue_free()

	# 3) main.gd: traducciones + UI
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.hud == null:
		print("FALLO: hud null")
		quit(1)
		return

	for lang_i in [0, 1]:
		main.lang = lang_i
		check(main._tr("mp_pw") != "mp_pw", "lang %d: falta mp_pw" % lang_i)
		check(main._tr("mp_pw_room") != "mp_pw_room", "lang %d: falta mp_pw_room" % lang_i)
		check(main._tr("mp_pw_wrong") != "mp_pw_wrong", "lang %d: falta mp_pw_wrong" % lang_i)

	main._show_mp_create_join(2)
	var f1: LineEdit = main.hud.get_node_or_null("MpCreatePw") as LineEdit
	check(f1 != null, "falta MpCreatePw (crear)")
	check(f1 != null and f1.secret and f1.secret_character == "*", "MpCreatePw: secret/* mal")
	main._show_mp_browser([{"n": "Sala", "ip": "1.2.3.4", "players": 1, "max": 2}])
	var f2: LineEdit = main.hud.get_node_or_null("MpJoinPw") as LineEdit
	check(f2 != null, "falta MpJoinPw (browser)")
	check(f2 != null and f2.secret and f2.secret_character == "*", "MpJoinPw: secret/* mal")
	main._show_mp_browser_searching()
	var f3: LineEdit = main.hud.get_node_or_null("MpPwManual") as LineEdit
	check(f3 != null, "falta MpPwManual (IP manual)")
	check(f3 != null and f3.secret and f3.secret_character == "*", "MpPwManual: secret/* mal")

	# handler de rechazo existe en main
	check(main.has_method("_on_auth_denied"), "falta _on_auth_denied en main")

	if fails == 0:
		print("== MP-PW: OK ==")
	else:
		print("== MP-PW: %d fallos ==" % fails)
	quit(0 if fails == 0 else 1)
