@tool
extends Control

const ALLOWED_EXTENSIONS := ["mp3", "wav", "ogg"]
const FOLDERNAME := "Godot Music Player"

var currentSongs : Array[String] = []

var path : String
var configPath : String
var selectedSubfolder : String = ""
var lastSong : String

var isPaused : bool = false
var shuffle : bool = false

const SONG_ITEM : PackedScene = preload("uid://dw2lh43jvd7kd")
const FOLDER_ITEM : PackedScene = preload("uid://6224mv8h7hfp")

@onready var change_mode_button: Button = %ChangeModeButton
@onready var songs_list: VBoxContainer = %SongsList
@onready var music_player: AudioStreamPlayer = %MusicPlayer
@onready var settings: Control = %Settings
@onready var main: Control = %Main
@onready var volume_text: Label = %VolumeText
@onready var volume_slider: HSlider = %VolumeSlider
@onready var shuffle_checkbox: CheckBox = %ShuffleCheckbox
@onready var songName: RichTextLabel = %Name
@onready var time: RichTextLabel = %Time
@onready var back_to_root_button: Button = %BackToRootButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_scan_for_songs()
	_get_config_file()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var isPlaying := EditorInterface.is_playing_scene()
	
	if music_player.stream == null:
		return
	
	if isPlaying and !music_player.stream_paused:
		music_player.stream_paused = true
	elif !isPlaying and music_player.stream_paused and !isPaused :
		music_player.stream_paused = false
		
	var current_seconds := music_player.get_playback_position()
	var total_seconds := music_player.stream.get_length()
	
	time.text = "[b][rainbow][wave amp=10 freq=4]" + _make_good_time(current_seconds) + "/" + _make_good_time(total_seconds)

func _make_good_time(seconds : float) -> String:
	var total_seconds := int(seconds)
	var minutes := total_seconds / 60
	var remaining := total_seconds % 60
	var extraNumb = ""
	
	if remaining < 10:
		extraNumb = "0"
	
	return str(minutes) + ":" + extraNumb + str(remaining)

func _scan_for_songs() -> void:
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var dir := DirAccess.open(docs)
	
	path = docs.path_join(FOLDERNAME)
	
	if dir == null:
		push_error("Can't reach system documents!")
		return
	
	if !dir.dir_exists(FOLDERNAME):
		var newFolder :=  dir.make_dir(FOLDERNAME)
		if newFolder != OK:
			push_error("FAILED TO MAKE FOLDER!")
		else:
			print("Made new songs folder at: " + path)
			
			var newDialog = AcceptDialog.new()
			
			newDialog.title = "Welcome!"
			newDialog.dialog_text = "Welcome to Godot Music Player!\nWe just created a new folder at " + path + ".\nTo add new music, put a music file in this folder.\nIf you wish to use playlist, you can make a subfolder and put music files in there."
			
			newDialog.exclusive = false
			
			add_child(newDialog)
			newDialog.popup_centered()
	
	_clear_list()
	if selectedSubfolder != "":
		_get_folders(selectedSubfolder)
		_get_songs(selectedSubfolder)
	else:
		_get_folders(path)
		_get_songs(path)

func _clear_list() -> void:
	currentSongs = []
	
	for children in songs_list.get_children():
		if children != back_to_root_button:
			children.queue_free()
		else:
			back_to_root_button.visible = !selectedSubfolder == ""

func _get_folders(folder_path : String) -> void:
	var dir := DirAccess.open(folder_path)
	
	if dir == null:
		push_error("Can't open folder at: " + folder_path)
		return
	
	dir.list_dir_begin()
	
	var folder_name := dir.get_next()
	
	while folder_name != "":
		if dir.current_is_dir() and !folder_name.begins_with("."):
			var new_folder_item = FOLDER_ITEM.instantiate()
			
			new_folder_item.text = folder_name
			new_folder_item.folder_path = folder_path.path_join(folder_name)
			new_folder_item.folder_selected.connect(_on_folder_selected)
			
			songs_list.add_child(new_folder_item)
		
		folder_name = dir.get_next()
	
	dir.list_dir_end()

func _get_songs(folder_path: String) -> void:
	
	var dir := DirAccess.open(folder_path)
	
	if dir == null:
		push_error("Can't open folder at: " + folder_path)
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while  file_name != "":
		if !dir.current_is_dir():
			if ALLOWED_EXTENSIONS.has(file_name.get_extension().to_lower()):
				var new_song_item = SONG_ITEM.instantiate()
				
				new_song_item.text = file_name.get_file().get_basename()
				
				new_song_item.file_path = folder_path.path_join(file_name)
				
				currentSongs.append(folder_path.path_join(file_name))
				
				new_song_item.song_selected.connect(_play_new_song)
				
				songs_list.add_child(new_song_item)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func _play_new_song(song_path : String) -> void:
	
	var extension := song_path.get_extension().to_lower()
	var stream : AudioStream = null
	
	match extension:
		"mp3":
			stream = AudioStreamMP3.load_from_file(song_path)
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(song_path)
		"wav":
			stream = AudioStreamWAV.load_from_file(song_path)
		_:
			push_error("Trying to load unsupported file format at " + song_path + ", aborting...")
			return
	
	lastSong = song_path
	songName.text = "[b][rainbow][wave amp=10 freq=4]" + song_path.get_file().get_basename()
	
	music_player.stream = stream
	music_player.play()

func _on_folder_selected(folder_path : String) -> void:
	selectedSubfolder = folder_path
	_save()
	_scan_for_songs()

func _get_config_file() -> void:
	configPath = OS.get_user_data_dir().path_join("Godot Music Player/Config.ini")
	
	var config_dir = configPath.get_base_dir()
	
	if !DirAccess.dir_exists_absolute(config_dir):
		var new_dir := DirAccess.make_dir_recursive_absolute(config_dir)
		
		if new_dir != OK:
			push_error("Failed to create config dir: " + error_string(new_dir))
			return
		
	var config := ConfigFile.new()
	var config_loaded := config.load(configPath)
	
	if config_loaded == ERR_FILE_NOT_FOUND:
		config.set_value("player", "volume_db", -20)
		config.set_value("player", "last_song", "")
		config.set_value("player", "current_playlist", selectedSubfolder)
		config.set_value("player", "shuffle", shuffle)
		config.set_value("player", "paused", isPaused)
		
		var save := config.save(configPath)
		
		if save != OK:
			push_error("Failed to create config file: " + error_string(save))
			return
		
		print("Created config at: " + configPath)
	
	else:
		var volume := config.get_value("player", "volume_db", -20)
		music_player.volume_db = volume
		var linear_volume := db_to_linear(volume) * 100
		volume_slider.set_value_no_signal(linear_volume)
		volume_text.text = "Volume: " + str(round(linear_volume)) + "%"
		var last_path := config.get_value("player", "last_song", "")
		if FileAccess.file_exists(last_path):
			_play_new_song(last_path)
		music_player.stream_paused = config.get_value("player", "paused", true)
		isPaused = music_player.stream_paused
		shuffle = config.get_value("player", "shuffle", false)
		shuffle_checkbox.set_pressed_no_signal(shuffle)
		var subfolder := config.get_value("player", "current_playlist", "") 
		if DirAccess.open(subfolder) != null:
			selectedSubfolder = subfolder

func _save() -> void:
	configPath = OS.get_user_data_dir().path_join("Godot Music Player/Config.ini")
	
	var config := ConfigFile.new()
	var config_loaded := config.load(configPath)
	
	config.set_value("player", "volume_db", music_player.volume_db)
	config.set_value("player", "last_song", lastSong)
	config.set_value("player", "current_playlist", selectedSubfolder)
	config.set_value("player", "shuffle", shuffle)
	config.set_value("player", "paused", isPaused)
	
	var save := config.save(configPath)
	
	if save != OK:
		push_error("Failed to save: " + error_string(save))

func _start_new_song(isShuffled : bool):
	if !isShuffled && !currentSongs.is_empty():
		var currentIndex := currentSongs.find(lastSong)
		var newIndexNumber := currentIndex + 1
		
		if newIndexNumber >= currentSongs.size():
			_play_new_song(currentSongs[0])
		else:
			_play_new_song(currentSongs[newIndexNumber])
		
	else:
		if currentSongs.size() <= 2:
			push_warning("Less than 2 songs, setting shuffle to false...")
			shuffle = false
			_start_new_song(false)
			return
		
		var new_song := currentSongs.pick_random()
		while new_song == lastSong:
			new_song = currentSongs.pick_random()
		
		_play_new_song(new_song)

func _on_toggle_music_pressed() -> void:
	isPaused = !music_player.stream_paused
	music_player.stream_paused = isPaused

func _on_stop_music_pressed() -> void:
	music_player.stop()

func _on_change_mode_button_pressed() -> void:
	if main.visible:
		change_mode_button.text = "Main"
	else:
		change_mode_button.text = "Settings"
	
	main.visible = !main.visible
	settings.visible = !settings.visible
	


func _on_volume_slider_value_changed(value: float) -> void:
	var db_value := linear_to_db(value / 100)
	music_player.volume_db = db_value
	volume_text.text = "Volume: " + str(round(value)) + "%"
	_save()


func _on_shuffle_pressed() -> void:
	shuffle = !shuffle
	_save()


func _on_refresh_songs_button_pressed() -> void:
	_scan_for_songs()


func _on_music_player_finished() -> void:
	_start_new_song(shuffle)


func _on_skip_pressed() -> void:
	_start_new_song(shuffle)


func _on_print_song_folder_pressed() -> void:
	print("Songs folder is at: " + path)


func _on_print_config_folder_pressed() -> void:
	print("Config folder is at: " + OS.get_user_data_dir().path_join("Godot Music Player/Config.ini"))


func _on_back_to_root_pressed() -> void:
	selectedSubfolder = ""
	_scan_for_songs()
