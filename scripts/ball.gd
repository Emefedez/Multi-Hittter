extends RigidBody3D

var holding_player: CharacterBody3D = null

func _ready():
	add_to_group(&"Grabbable")

func _physics_process(_delta: float) -> void:
	# Solo el servidor dicta la posición cuando la pelota está agarrada
	if multiplayer.is_server() and holding_player:
		# Anulamos la física para poder moverla manualmente sin tirones
		freeze = true 
		var hold_pos = holding_player.get_node("%HoldPosition")
		global_transform = hold_pos.global_transform
