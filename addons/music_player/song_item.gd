@tool
extends Node

var file_path : String

signal song_selected(file_path : String)

func _on_pressed() -> void:
	song_selected.emit(file_path)
