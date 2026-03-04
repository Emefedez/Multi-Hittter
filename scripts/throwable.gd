extends RigidBody3D

@export var max_health: int = 0 ## 0 significa indestructible (vida infinita)
@export var damage_multiply: int = 1 ## Multiplicador de daño al golpear jugadores u otras cosas

var cooldown: int = 0 #cooldown until damage can happen to the item
var cooldown_wait: int = 50 #miliseconds


var current_health: int
var holding_player: Node3D = null # Se asigna desde player.gd [cite: 17]
var last_thrower: Node3D = null # Se asigna desde player.gd [cite: 17]

func _ready() -> void:
	add_to_group("Grabbable")
	current_health = max_health
	
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	# Si un jugador lo tiene en la mano, congelamos físicas y lo pegamos a su posición
	if holding_player != null and is_instance_valid(holding_player):
		freeze = true
		global_transform = holding_player.hold_position.global_transform
		
func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server(): return

	var impact_force = linear_velocity.length()
	
	if body is RigidBody3D:
		impact_force += body.linear_velocity.length()
		cooldown = Time.get_ticks_msec()
	elif body is CharacterBody3D:
		impact_force += body.velocity.length()

	# Ignoramos golpes muy suaves
	if impact_force > 2.0:
		if body.has_method("receive_damage") and body != holding_player and (Time.get_ticks_msec() > cooldown + cooldown_wait):
			var final_damage = int(impact_force * damage_multiply)
			# Como receive_damage es un RPC, lo llamamos a través de la red
			body.rpc("receive_damage", final_damage)
			print("[DAMAGE DEALT TO PLAYER]: ", final_damage)

		# 2. RECIBIR DAÑO EL PROPIO OBJETO (Solo si no es indestructible)
		if max_health > 0:
			_take_damage(int(impact_force))
			print("[TAKEN DAMAGE]: ", impact_force)

func _take_damage(amount: int) -> void:
	current_health -= amount
	
	if current_health <= 0:
		rpc("destroy_object")

@rpc("call_local", "reliable")
func destroy_object() -> void:
	if multiplayer.is_server():
		Network.destroyed_objects.append(get_path())
	queue_free()
