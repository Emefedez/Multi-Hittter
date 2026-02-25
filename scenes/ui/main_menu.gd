extends CanvasLayer
@onready var button_join: Button = %ButtonJoin
@onready var button_quit: Button = %ButtonQuit

const WORLD_FOREST = preload("uid://dpbxeeslo572q")
const PLAYER = preload("uid://k6mcorwk6nxq")
@onready var line_edit: LineEdit = %LineEdit


func _ready() -> void:
	if (line_edit.has_focus() && Input.is_action_just_pressed("enter")):
		on_join()
		
	button_join.pressed.connect(on_join)
	button_quit.pressed.connect(func(): get_tree().quit())
	
	if OS.has_feature('server'):
		print("Server flag is enabled for this instance: ", name, "\n")
		Network.start_server()
		add_world()
		hide()

	
	
func on_join():
	Network.local_player_name = %LineEdit.text
	Network.join_server()
	add_world()
	print("Joined correcly\nAs auth?: ", (true == is_multiplayer_authority()), "\n")
	hide()
	
	
func add_world():
	var new_world = WORLD_FOREST.instantiate()
	get_tree().current_scene.add_child.call_deferred(new_world)
	
	
