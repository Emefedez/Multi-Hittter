extends RigidBody3D

@export var max_health: int = 0 ## 0 significa indestructible (vida infinita)
@export var damage_multiply: int = 1 ## Multiplicador de daño al golpear jugadores u otras cosas

@onready var grip_point: Marker3D = %GripPoint
@onready var model: MeshInstance3D = %Model

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
		
		if grip_point:
			# Hace que el punto exacto del grip_node coincida con la mano
			global_transform = holding_player.hold_position.global_transform * grip_point.transform.affine_inverse()
		else:
			# Si te olvidas de asignar el nodo, usa el centro por defecto
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
	_spawn_physical_debris()
	if multiplayer.is_server():
		Network.destroyed_objects.append(get_path())
	queue_free()
	



func _spawn_physical_debris() -> void:
	var num_chunks = randi_range(4, 7)
	
	# Extraemos el material antes del bucle para no calcularlo 7 veces
	var chunk_material: Material = null
	if model:
		if model.material_override:
			chunk_material = model.material_override
		elif model.mesh and model.mesh.get_surface_count() > 0:
			chunk_material = model.mesh.surface_get_material(0)
	
	for i in range(num_chunks):
		var chunk = RigidBody3D.new()
		var mesh_inst = MeshInstance3D.new()
		var col_shape = CollisionShape3D.new()
		
		var box = BoxMesh.new() #Create box
		var s = randf_range(0.1, 0.3) #Random size
		box.size = Vector3(s, s, s)
		mesh_inst.mesh = box
		
		# Aplicamos el material extraído al pedazo (mesh_inst)
		if chunk_material:
			mesh_inst.material_override = chunk_material
		
		
		chunk.add_child(mesh_inst)
		chunk.add_child(col_shape)
		
		# 3. Añadir el pedazo al mundo
		get_tree().current_scene.add_child(chunk)
		
		# 4. Posicionar y lanzar
		var random_offset = Vector3(randf_range(-0.3, 0.3), randf_range(0.1, 0.5), randf_range(-0.3, 0.3))
		chunk.global_position = global_position + random_offset
		
		var random_dir = Vector3(randf_range(-1, 1), randf_range(0.5, 2.0), randf_range(-1, 1)).normalized()
		chunk.apply_impulse(random_dir * randf_range(2.0, 6.0))
		chunk.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		
		# 5. Limpieza
		get_tree().create_timer(3.0).timeout.connect(chunk.queue_free)
