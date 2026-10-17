# Test del botón BORRAR RANKING (menús de puntuaciones).
# Verifica: el botón aparece en cada categoría, la confirmación es de 2 pasos,
# y _clear_hs_cat limpia la categoría correcta (single + MP) sin tocar las otras.
# OJO: _clear_hs_cat() GUARDA en el archivo real → el shell restaura el backup
# original ANTES de terminar.
extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FALLO: " + msg)

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.hud == null:
		print("FALLO: hud null")
		quit(1)
		return

	# Estado controlado (no depende del archivo real)
	main.highscores = [
		{"initials": "AAA", "score": 100, "wave": 2},
		{"initials": "BBB", "score": 50, "wave": 1},
	]
	main.hs_mp = {
		"2": [{"score": 900, "wave": 3, "players": ["X", "Y"], "date": "01/01"}],
		"3": [{"score": 700, "wave": 2, "players": ["A", "B", "C"], "date": "01/01"}],
		"4": [{"score": 600, "wave": 2, "players": ["A", "B", "C", "D"], "date": "01/01"}],
	}
	main.lang = 0  # español para comparar textos

	# 1) El botón aparece en cada categoría
	# (las pantallas de puntuaciones están en scripts/menu_ui.gd: main._menu.*)
	for cat in ["single", "2", "3", "4"]:
		main._menu.show_hs_cat(cat)
		var b: Button = main.hud.get_node_or_null("HSClearBtn") as Button
		check(b != null, "%s: falta HSClearBtn" % cat)
		if b:
			check(b.text == "BORRAR RANKING", "%s: texto '%s' != BORRAR RANKING" % [cat, b.text])
		check(main.hs_clear_arm == false, "%s: arm debe empezar false" % cat)

	# 2) Confirmación de 2 pasos (single)
	main._menu.show_hs_cat("single")
	main._menu.on_btn_hs_clear()  # 1º click: arma (no borra)
	check(main.hs_clear_arm == true, "1º click: no armó")
	check(main.highscores.size() == 2, "1º click: ya borró (debe seguir con 2)")
	var b2: Button = main.hud.get_node_or_null("HSClearBtn") as Button
	check(b2 != null and b2.text == "¿SEGURO? BORRAR", "1º click: texto no cambió a confirmación")

	main._menu.on_btn_hs_clear()  # 2º click: confirma → borra
	check(main.hs_clear_arm == false, "2º click: arm no reseteó")
	check(main.highscores.size() == 0, "2º click: single no quedó vacío (%d)" % main.highscores.size())
	check(main.hs_mp["3"].size() == 1, "borro single: no tocó la categoría 3")

	# 3) Borra una categoría MP (2) sin tocar las demás
	main._menu.show_hs_cat("2")
	main._menu.on_btn_hs_clear()
	main._menu.on_btn_hs_clear()
	check(main.hs_mp["2"].size() == 0, "MP 2 no quedó vacío")
	check(main.hs_mp["3"].size() == 1, "MP 2: no tocó la 3")
	check(main.hs_mp["4"].size() == 1, "MP 2: no tocó la 4")

	# 4) Vista vacía muestra "hs_none"
	main._menu.show_hs_cat("single")
	var lst: Label = main.hud.get_node_or_null("HSList") as Label
	check(lst != null and lst.text.find("Sin puntuaciones") >= 0, "vista vacía no muestra hs_none")

	if fails == 0:
		print("== HS-CLEAR: OK ==")
	else:
		print("== HS-CLEAR: %d fallos ==" % fails)
	quit(0 if fails == 0 else 1)
