class_name SaveData
extends RefCounted
## Costa Blindada — persistencia en user:// (highscores.json + settings.json).
##
## Hace únicamente lectura/escritura de archivos y saneado/orden de datos. El
## estado vivo (listas de highscores y ajustes aplicados) sigue en main.gd, que
## es quien lo muestra en HUD/menús y quien lo aplica a la escena.
## main.gd delega así:
##   _load_highscores() -> SaveData.load_highscores()
##   _add_highscore(..) -> SaveData.add_highscore(highscores, ..) + guardar
##   _load_settings()   -> SaveData.read_settings()   (y lo valida/aplica)
##   _save_settings()   -> SaveData.write_settings(data)
##
## add_highscore / add_mp_highscore modifican la lista/diccionario que se les
## pasa (son referencias), igual que antes.

const HS_FILE := "user://highscores.json"
const HS_MAX := 10
const SETTINGS_FILE := "user://settings.json"

# ─── HIGH SCORES (top 10) ───
static func load_highscores() -> Dictionary:
	var single: Array = []
	var mp: Dictionary = {}
	if not FileAccess.file_exists(HS_FILE):
		return {"single": single, "mp": mp}
	var f := FileAccess.open(HS_FILE, FileAccess.READ)
	if f == null:
		return {"single": single, "mp": mp}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Array:
		# Formato antiguo: solo single player → migrar a la rama "single"
		parsed = {"single": parsed}
	if not (parsed is Dictionary):
		return {"single": single, "mp": mp}
	single = clean_single(parsed.get("single", []))
	var mp_raw = parsed.get("mp", {})
	if mp_raw is Dictionary:
		for k in mp_raw.keys():
			mp[str(k)] = clean_mp(mp_raw[k])
	return {"single": single, "mp": mp}

static func save_highscores(single: Array, mp: Dictionary) -> void:
	var f := FileAccess.open(HS_FILE, FileAccess.WRITE)
	if f:
		var data := {"v": 2, "single": single, "mp": mp}
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

static func today_str() -> String:
	return Time.get_date_string_from_system().substr(0, 5)  # DD/MM

static func qualifies(single: Array, p_score: int) -> bool:
	if p_score <= 0:
		return false
	if single.size() < HS_MAX:
		return true
	return p_score > single[HS_MAX - 1]["score"]

## Top-10 single: agrega, ordena y recorta la lista (in place).
## Devuelve la posición 1-based o -1 si quedó afuera del ranking.
static func add_highscore(single: Array, p_score: int, p_initials: String, p_wave: int) -> int:
	var clean := p_initials.strip_edges().to_upper()
	if clean.is_empty():
		clean = "???"
	clean = clean.left(3)
	while clean.length() < 3:
		clean = "_" + clean
	single.append({"score": p_score, "initials": clean, "wave": p_wave})
	single.sort_custom(func(a, b): return a["score"] > b["score"])
	if single.size() > HS_MAX:
		single.resize(HS_MAX)
	var rank := 1
	for hs in single:
		if hs["score"] == p_score and hs["initials"] == clean:
			return rank
		rank += 1
	return -1

## Top-10 de equipos por categoría (2/3/4). Devuelve la posición (1-based) o -1.
static func add_mp_highscore(mp: Dictionary, n_players: int, p_score: int, p_wave: int, p_players: Array) -> int:
	if p_score <= 0:
		return -1
	var key := str(n_players)
	var clean_players: Array = []
	for p in p_players:
		var v := str(p).strip_edges().to_upper().left(3)
		clean_players.append(v if v != "" else "???")
	var entry := {
		"score": p_score,
		"wave": p_wave,
		"players": clean_players,
		"date": today_str(),
		"_uid": Time.get_ticks_usec() + randi()
	}
	var lst: Array = mp.get(key, [])
	lst.append(entry)
	lst.sort_custom(func(a, b): return a["score"] > b["score"])
	lst.resize(mini(lst.size(), HS_MAX))
	mp[key] = lst
	var rank := -1
	for i in lst.size():
		if int(lst[i].get("_uid", -1)) == int(entry["_uid"]):
			rank = i + 1
			break
	for e in lst:
		e.erase("_uid")
	return rank

# Saneado de las listas leídas del JSON (tolera el formato viejo / entradas sucias)
static func clean_single(lst: Variant) -> Array:
	var out: Array = []
	if lst is Array:
		for entry in lst:
			if entry is Dictionary and entry.has("score") and entry.has("initials"):
				var ini := str(entry["initials"]).left(3)
				while ini.length() < 3:
					ini = "_" + ini
				out.append({
					"score": int(entry["score"]),
					"initials": ini,
					"wave": int(entry.get("wave", 1))
				})
	out.sort_custom(func(a, b): return a["score"] > b["score"])
	out.resize(mini(out.size(), HS_MAX))
	return out

static func clean_mp(lst: Variant) -> Array:
	var out: Array = []
	if lst is Array:
		for entry in lst:
			if entry is Dictionary and entry.has("score"):
				var players: Array = []
				var raw_pl = entry.get("players", [])
				if raw_pl is Array:
					for p in raw_pl:
						players.append(str(p).to_upper().left(3))
				out.append({
					"score": int(entry["score"]),
					"wave": int(entry.get("wave", 1)),
					"players": players,
					"date": str(entry.get("date", ""))
				})
	out.sort_custom(func(a, b): return a["score"] > b["score"])
	out.resize(mini(out.size(), HS_MAX))
	return out

# ─── AJUSTES (settings.json) ───
## Devuelve el diccionario guardado o null si no hay archivo / está corrupto.
static func read_settings() -> Variant:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return null
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if not f:
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return null

static func write_settings(data: Dictionary) -> void:
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
