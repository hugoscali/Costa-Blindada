@tool
extends Node

var folder_path : String

signal folder_selected(folder_path : String)

func _on_pressed() -> void:
	folder_selected.emit(folder_path)
