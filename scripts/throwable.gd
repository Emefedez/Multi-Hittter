extends RigidBody3D

var holding_player: CharacterBody3D = null

@export var damage_multiply: int = 10

func _ready():
	add_to_group(&"Grabbable")
	# Activamos la detección de contactos por código para asegurarnos de que no se nos olvida en el editor
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)

func _process(_delta: float) -> void:
	if holding_player:
		freeze = true 
		var hold_pos = holding_player.get_node("%HoldPosition")
		global_transform = hold_pos.global_transform

func _on_body_entered(body: Node) -> void:
	# Solo el servidor procesa el daño
	if not multiplayer.is_server(): return
	
	if body is CharacterBody3D and body.is_in_group(&"Players"):
		if linear_velocity.length() >= 2.0:
			body.rpc(&"receive_damage", linear_velocity.length()*damage_multiply)
