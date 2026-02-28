extends RigidBody3D

var holding_player: CharacterBody3D = null

func _ready():
	add_to_group(&"Grabbable")

func _process(_delta: float) -> void:
	if holding_player:
		freeze = true 
		var hold_pos = holding_player.get_node("%HoldPosition")
		global_transform = hold_pos.global_transform
