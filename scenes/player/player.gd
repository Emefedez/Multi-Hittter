extends CharacterBody3D

# --- REFERENCIAS DE NODOS (Caché) ---
@onready var camera_3d: Camera3D = %Camera3D
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var head: Node3D = %Head
@onready var nameplate: Label3D = %Nameplate
@onready var body: CollisionShape3D = %CollisionShape3D
@onready var mesh_instance: MeshInstance3D = %CollisionShape3D.get_node("MeshInstance3D")

@onready var menu: Control = %Menu
@onready var button_leave: Button = %ButtonLeave
@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var interact_text: Control = %InteractText
@onready var hp_label: ProgressBar = %ProgressBar
@onready var speed_label: Label = %SpeedLabel
@onready var dash_label: Label = %DashReportLabel
@onready var speed_lines: ColorRect = %SpeedLines
@onready var speed_lines_material: ShaderMaterial = speed_lines.material

# --- REFERENCIAS DE NODOS PARA AGARRAR ---
@onready var hold_position: Marker3D = %HoldPosition
@onready var pickup_area: Area3D = %PickupArea

var held_ball: RigidBody3D = null

# --- CONSTANTES ---
const PLAYER_COLORS = [
	Color(1.0, 0.0, 0.0), # Rojo
	Color(0.0, 0.0, 1.0), # Azul
	Color(0.0, 1.0, 0.0), # Verde
	Color(1.0, 1.0, 0.0)  # Amarillo
]

const START_SPEED = 6.0
const MAX_SPEED_RUN = 10.0
const MAX_SPEED = 15.0
const DECELERATION = 30.0 
const JUMP_VELOCITY = 4.5
const DASH_SPEED = 25.0
const DASH_DURATION = 0.2 
const DASH_COOLDOWN_MS := 1000 
const POUND_COOLDOWN_MS := 1500 

var max_health: int = 100
var current_health: int = 100

# --- VARIABLES DE ESTADO ---
var speed = START_SPEED 
var speed_counter: int = 0 
var speed_plus_cooldown = 0.3
var last_dash_ms := 0
var last_pound_ms := 0
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var can_bounce: bool = true
var ctrl_bounce: bool = false
var dash_was_ready: bool = false
var pound_was_ready: bool = false
var extra_jump: bool = true
var spent_wall_jump: bool = false
var custom_name: String = ""
var current_player_index: int = 0

var object_in_hand: bool = false

@export var sensitivity: float = 0.002

# --- MATERIALES Y SHADERS ---
var unique_outline_mat: ShaderMaterial
var base_outline_color: Color
var base_material: ShaderMaterial 

# Si al final no la variamos, cacheamos la gravedad para no consultarla al motor en cada frame
var gravity_vec: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector") * ProjectSettings.get_setting("physics/3d/default_gravity")

# --- OPTIMIZACIÓN DE STRINGS ---
# El uso de &"string" (StringName) es más rápido para parámetros de shaders
const SN_FLASH_COLOR = &"flash_color"
const SN_COLOR = &"color"
const SN_LINE_DENSITY = &"line_density"

func _enter_tree() -> void:
	set_multiplayer_authority(int(name))

func _ready():
	add_to_group(&"Players")
	menu.hide()
	interact_text.hide()
	
	if is_multiplayer_authority():
		camera_3d.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		button_leave.pressed.connect(func(): Network.leave_server())
		
		var my_name = Network.local_player_name if Network.local_player_name != "" else str(name)
		
		if multiplayer.is_server():
			var my_id = multiplayer.get_unique_id()
			var my_idx = Network.assigned_indices.get(my_id, 0)
			_server_store_and_sync(my_idx, my_name)
		else:
			rpc_id(1, &"register_player_data", my_name)
	else:
		set_process(false)
		set_physics_process(false)
		speed_lines.hide()
		canvas_layer.hide()
		rpc_id(1, &"request_sync")

# =========================================================
# --- SISTEMA RPC ---

@rpc("any_peer", "reliable")
func register_player_data(p_name: String):
	if not multiplayer.is_server(): return
	var node_id = int(name)
	var idx = Network.assigned_indices.get(node_id, 0)
	_server_store_and_sync(idx, p_name)

func _server_store_and_sync(idx: int, p_name: String):
	current_player_index = idx
	custom_name = p_name
	rpc(&"sync_player_data", idx, p_name)

@rpc("any_peer", "reliable")
func request_sync():
	if not multiplayer.is_server(): return
	var sender = multiplayer.get_remote_sender_id()
	rpc_id(sender, &"sync_player_data", current_player_index, custom_name)

@rpc("any_peer", "call_local", "reliable")
func sync_player_data(idx: int, p_name: String):
	current_player_index = idx
	custom_name = p_name if p_name != "" else str(name)
	
	_make_outline_unique()
	base_outline_color = PLAYER_COLORS[idx % PLAYER_COLORS.size()]
	
	nameplate.text = str(idx + 1) + ". " + custom_name
	reset_outline_color()

func request_flash(color: Color, intensity: float, time_ms: float):
	rpc(&"remote_flash_model", color, intensity, time_ms)

@rpc("any_peer", "call_local", "reliable")
func remote_flash_model(color: Color, intensity: float, time_ms: float):
	if base_material:
		var tint = Color(color.r, color.g, color.b, intensity)
		base_material.set_shader_parameter(SN_FLASH_COLOR, tint)
		await get_tree().create_timer(time_ms / 1000.0).timeout
		base_material.set_shader_parameter(SN_FLASH_COLOR, Color(1, 1, 1, 0))

@rpc("any_peer", "call_local", "reliable")
func server_pickup(ball_path: NodePath):
	if not multiplayer.is_server(): return
	var ball = get_node_or_null(ball_path)
	if ball and not ball.holding_player:
		ball.holding_player = self
		rpc(&"sync_held_ball", ball_path)

@rpc("any_peer", "call_local", "reliable")
func server_throw(throw_dir: Vector3, player_vel: Vector3):
	if not multiplayer.is_server(): return
	if held_ball:
		held_ball.freeze = false
		var throw_force = 15.0
		held_ball.linear_velocity = player_vel + (throw_dir * throw_force)
		
		held_ball.set("last_thrower", self)
		
		rpc(&"sync_drop_ball")

@rpc("any_peer", "call_local", "reliable")
func sync_held_ball(ball_path: NodePath):
	var ball = get_node_or_null(ball_path)
	if ball:
		held_ball = ball
		object_in_hand = true
		
		# Modificaciones de físicas aplazadas
		held_ball.set_deferred("collision_layer", 0)
		held_ball.set_deferred("collision_mask", 0)
		
		held_ball.set("holding_player", self) 
		
		var sync_node = held_ball.get_node_or_null("MultiplayerSynchronizer")
		if sync_node:
			sync_node.process_mode = Node.PROCESS_MODE_DISABLED

		# --- AÑADIR OUTLINE A LA PELOTA ---
		var meshes = held_ball.find_children("*", "MeshInstance3D")
		for m in meshes:
			m.material_overlay = unique_outline_mat


@rpc("any_peer", "call_local", "reliable")
func sync_drop_ball():
	if held_ball:
		# Modificaciones de físicas aplazadas
		held_ball.call_deferred("add_collision_exception_with", self)
		held_ball.set_deferred("continuous_cd", true) 
		held_ball.set_deferred("collision_layer", 1)
		held_ball.set_deferred("collision_mask", 1)
		
		held_ball.set("holding_player", null)
		
		# --- QUITAR OUTLINE A LA PELOTA ---
		var meshes = held_ball.find_children("*", "MeshInstance3D")
		for m in meshes:
			m.material_overlay = null
			
	held_ball = null
	object_in_hand = false
	
@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: int):
	current_health -= amount
	
	remote_flash_model(Color.RED, 1.0, 300.0)
	print(custom_name + " hit for " + str(amount) + " || " + "HP: " + str(current_health))
	
	if current_health <= 0:
		call_deferred("_die")

# =========================================================
# --- FUNCIONES DE MATERIAL ---

func _make_outline_unique():
	if unique_outline_mat != null: return
	
	var mat_override = mesh_instance.get_surface_override_material(0)
	base_material = mat_override.duplicate()
	unique_outline_mat = base_material.next_pass.duplicate()
	base_material.next_pass = unique_outline_mat
	
	mesh_instance.set_surface_override_material(0, base_material)

func set_outline_color(new_color: Color, time_ms: float = 0.0):
	if unique_outline_mat:
		unique_outline_mat.set_shader_parameter(SN_COLOR, new_color)
		if time_ms > 0.0:
			await get_tree().create_timer(time_ms / 1000.0).timeout
			reset_outline_color()

func reset_outline_color():
	set_outline_color(base_outline_color if base_outline_color else Color.WHITE)

# =========================================================
# --- FÍSICA Y MOVIMIENTO ---

func _push_away_rigid_bodies(pre_vel: Vector3):
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		var collider = c.get_collider()
		
		if collider is RigidBody3D:
			var normal = c.get_normal()
			# Rebote desde arriba (usamos pre_vel en vez de velocity para evaluar la caída)
			if pre_vel.y < 0 and normal.y > 0.5:
				var bounce_dir = (-transform.basis.z + Vector3(0, 0.8, 0)).normalized()
				collider.apply_central_impulse(bounce_dir * (collider.mass * 6.0))
				velocity.y = 3.0 
				continue 
			# Empuje lateral
			var push_dir = Vector3(-normal.x, 0, -normal.z)
			if push_dir.length_squared() > 0.0001:
				push_dir = push_dir.normalized()
				
				var velocity_diff = pre_vel.dot(push_dir) - collider.linear_velocity.dot(push_dir)
				
				if velocity_diff > 0:
					collider.apply_central_impulse(push_dir * (velocity_diff * collider.mass * 0.2))
					
					
func dash_possible() -> bool:
	return (Time.get_ticks_msec() - last_dash_ms) > DASH_COOLDOWN_MS

func pound_possible() -> bool:
	return (Time.get_ticks_msec() - last_pound_ms) > POUND_COOLDOWN_MS

func _attempt_dash() -> void:
	if not dash_possible(): return

	spent_wall_jump = false
	last_dash_ms = Time.get_ticks_msec()
	can_bounce = true
	dash_timer = DASH_DURATION
	set_outline_color(Color.ORANGE, 500)
	
	var input_dir := Input.get_vector(&"down", &"up", &"left", &"right")
	dash_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if dash_direction == Vector3.ZERO:
		dash_direction = transform.basis.x
		
	velocity.y = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
		
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x - event.relative.y * sensitivity, -1.57, 1.57)
		
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"menu"):
		if menu.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			menu.hide()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			menu.show()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	
	# Guardamos el tiempo actual una sola vez para todas las comparaciones
	var current_time = Time.get_ticks_msec()
	var vel_len = velocity.length()
	
	# Optimización de Speed Lines
	if speed_lines_material:
		speed_lines_material.set_shader_parameter(SN_LINE_DENSITY, vel_len * 0.025)
	speed_lines.visible = vel_len >= 12.0
	
	if pickup_area:
		interact_text.show()
		
		
	
	if Input.is_action_just_pressed(&"ctrl"):
		velocity += gravity_vec * delta
		if pound_possible():
			ctrl_bounce = true
			last_pound_ms = current_time
			extra_jump = true

	if Input.is_action_just_pressed(&"dash"):
		_attempt_dash()

	if dash_timer > 0:
		dash_timer -= delta
		if is_on_wall() and can_bounce:
			for i in get_slide_collision_count():
				var collision = get_slide_collision(i)
				var n = collision.get_normal()
				if abs(n.y) < 0.7 and not collision.get_collider() is RigidBody3D:
					dash_direction = dash_direction.bounce(n)
					dash_direction.y = 0 
					dash_direction = dash_direction.normalized()
					if speed >= 25: can_bounce = false
					break
		
		velocity.x = dash_direction.x * DASH_SPEED
		velocity.z = dash_direction.z * DASH_SPEED
		velocity.y = 0 
	else:
		if is_on_floor():
			spent_wall_jump = false
			can_bounce = true
			extra_jump = true
			if ctrl_bounce:
				velocity.y = speed 
				ctrl_bounce = false
		elif not ctrl_bounce:
			velocity += gravity_vec * delta
		else:
			velocity += (gravity_vec * delta) * 10
			set_outline_color(Color.AQUA, 500)

	if Input.is_action_just_pressed(&"jump"):
		if is_on_floor():
			# 1. Salto normal desde el suelo
			velocity.y = JUMP_VELOCITY
			
		elif is_on_wall_only() and not spent_wall_jump:
			# 2. Intento de Wall Jump: Verificamos que la pared NO sea un RigidBody3D
			var can_wall_jump = false
			var wall_normal = Vector3.ZERO
			
			for i in get_slide_collision_count():
				var collision = get_slide_collision(i)
				if not collision.get_collider() is RigidBody3D:
					can_wall_jump = true
					wall_normal = collision.get_normal()
					break
			
			if can_wall_jump:
				# Es una pared real
				spent_wall_jump = true
				extra_jump = true # Resetea el doble salto para usarlo tras el rebote
				
				var jump_dir = (wall_normal + Vector3.UP).normalized()
				velocity = jump_dir * JUMP_VELOCITY * 1.5 
				set_outline_color(Color.GRAY,250)
			elif extra_jump:
				# Si era una pelota, ignoramos el wall jump y usamos el salto extra
				velocity.y = JUMP_VELOCITY
				extra_jump = false
				set_outline_color(Color.GRAY,250)
				
		elif extra_jump:
			# 3. Doble salto estándar en el aire (sin tocar nada)
			velocity.y = JUMP_VELOCITY
			extra_jump = false
			set_outline_color(Color.GRAY,250)

	var input_dir := Input.get_vector(&"down", &"up", &"left", &"right")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
	if direction:
		if speed < MAX_SPEED_RUN and (current_time - speed_counter) > (speed_plus_cooldown * 1000):
			speed = min(speed * 1.2, MAX_SPEED_RUN) 
			speed_counter = current_time
		velocity.x = move_toward(velocity.x, direction.x * speed, DECELERATION * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, DECELERATION * delta)
	else:
		speed = START_SPEED
		speed_counter = current_time
		velocity.x = move_toward(velocity.x, 0, DECELERATION * delta)
		velocity.z = move_toward(velocity.z, 0, DECELERATION * delta)
		
	if Input.is_action_just_pressed(&"interact"):
		if held_ball == null:
			_try_pickup()
		else:
			_throw_ball()

	# Actualización de UI
	speed_label.text = "Speed: " + str(snapped(Vector2(velocity.x, velocity.z).length(), 0.1))
	hp_label.value = current_health
	
	var can_dash_now = dash_possible()
	var can_pound_now = pound_possible()
	
	dash_label.text = "CAN DASH" if can_dash_now else "NO DASH"
	
	if can_dash_now and not dash_was_ready:
		request_flash(Color.ORANGE, 1.0, 200.0)
	dash_was_ready = can_dash_now

	if can_pound_now and not pound_was_ready:
		request_flash(Color.CYAN, 1.0, 200.0)
	pound_was_ready = can_pound_now
		
	var pre_velocity = velocity	
	move_and_slide()
	_push_away_rigid_bodies(pre_velocity)

#####################################


func _try_pickup():
	var bodies = pickup_area.get_overlapping_bodies()
	for b in bodies:
		if b is RigidBody3D and b.is_in_group("Grabbable") and not b.get("holding_player"):
			rpc_id(1, &"server_pickup", b.get_path())
			interact_text.hide()
			break
			
func _throw_ball():
	if held_ball == null: return
	var throw_dir = -camera_3d.global_transform.basis.z.normalized()
	rpc_id(1, &"server_throw", throw_dir, velocity)
	
func _die():
	if not is_multiplayer_authority(): return
	
	if held_ball:
		_throw_ball()
		
	camera_3d.current = true
	
	# 2. Desactivar físicas y control del jugador
	hide() # Hacer invisible al jugador localmente
	set_physics_process(false)
	set_process_unhandled_input(false)
	
	# 3. Mostrar Menú y liberar el ratón
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	menu.show()
	
	# 4. Esperar 3 segundos (Tiempo de la Death Cam)
	await get_tree().create_timer(3.0).timeout

	
	
	
