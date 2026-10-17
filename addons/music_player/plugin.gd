@tool
extends EditorPlugin

var dock : EditorDock


func _enter_tree() -> void:
	var dockScene = preload("res://addons/music_player/music_player.tscn").instantiate()
	
	dock = EditorDock.new()
	dock.add_child(dockScene)
	
	dock.default_slot = EditorDock.DOCK_SLOT_LEFT_BR
	
	dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	
	add_dock(dock)



func _exit_tree() -> void:
	remove_dock(dock)
	
	dock.queue_free()
