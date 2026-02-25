extends CharacterBody3D

@onready var camera_3d: Camera3D = %Camera3D
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var head: Node3D = %Head
@onready var nameplate: Label3D = %Nameplate
@onready var body: CollisionShape3D =  %CollisionShape3D

@onready var menu: Control = %Menu
@onready var button_leave: Button = %ButtonLeave

@onready var speed_label: Label = %SpeedLabel
@onready var dash_label: Label = %DashReportLabel
@onready var speed_lines: ColorRect = %SpeedLines

var custom_name: String = ""
var current_player_index: int = 0

# --- VARIABLES PARA EL COLOR ---
var unique_outline_mat: ShaderMaterial
var base_outline_color: Color

var base_material: ShaderMaterial # Material principal del cuerpo
var dash_was_ready: bool = false # Inicializar en false para que flasheen al empezar
var pound_was_ready: bool = false


const PLAYER_COLORS = [
	Color(1.0, 0.0, 0.0), # Jugador 1 - Rojo
	Color(0.0, 0.0, 1.0), # Jugador 2 - Azul
	Color(0.0, 1.0, 0.0), # Jugador 3 - Verde
	Color(1.0, 1.0, 0.0)  # Jugador 4 - Amarillo
]

const START_SPEED = 6.0
const MAX_SPEED_RUN = 10.0
const MAX_SPEED = 15.0
const DECELERATION = 30.0 

var speed = START_SPEED 
var speed_counter: int = 0 
var speed_plus_cooldown = 0.3

const JUMP_VELOCITY = 4.5
const dash_cooldown_ms := 1000 
var last_dash_ms := 0

const pound_cooldown_ms := 1500 
var last_pound_ms := 0

@export var sensitivity: float = 0.002

const DASH_SPEED = 25.0
const DASH_DURATION = 0.2 
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var can_bounce: bool = true
var ctrl_bounce: bool = false


func _enter_tree() -> void:
	set_multiplayer_authority(int(name))

# =========================================================
# --- SISTEMA DE RED A PRUEBA DE FALLOS ---

func _ready():
	add_to_group('Players')
	menu.hide()
	
	if is_multiplayer_authority():
		camera_3d.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		button_leave.pressed.connect(func(): Network.leave_server())
		
		# SOLUCIÓN WARNING: Usamos str(name) para que coincida el tipo String
		var my_name = Network.local_player_name if Network.local_player_name != "" else str(name)
		
		if multiplayer.is_server():
			# El Host ya conoce su ID desde el diccionario de Network y se auto-sincroniza
			var my_id = multiplayer.get_unique_id()
			var my_idx = Network.assigned_indices.get(my_id, 0)
			_server_store_and_sync(my_idx, my_name)
		else:
			# El cliente dueño se presenta y envía su nombre al servidor
			rpc_id(1, "register_player_data", my_name)
			
	else:
		set_process(false)
		set_physics_process(false)
		speed_lines.hide()
		$CanvasLayer.hide()
		
		# Los clones que cargan en tu pantalla le piden al Servidor que los actualice
		rpc_id(1, "request_sync")

# =========================================================
# --- RCP ---
# 1. El cliente le avisa al Servidor su nombre elegido
@rpc("any_peer", "reliable")
func register_player_data(p_name: String):
	if not multiplayer.is_server(): return
	var node_id = int(name) # El nombre del nodo es el peer_id real
	var idx = Network.assigned_indices.get(node_id, 0)
	_server_store_and_sync(idx, p_name)

# 2. El Servidor guarda los datos de este nodo y los transmite a TODOS
func _server_store_and_sync(idx: int, p_name: String):
	current_player_index = idx
	custom_name = p_name
	rpc("sync_player_data", idx, p_name)

# 3. Un clon entra tarde y pide los datos de ESTE nodo al servidor
@rpc("any_peer", "reliable")
func request_sync():
	if not multiplayer.is_server(): return
	var sender = multiplayer.get_remote_sender_id()
	# El servidor le contesta a ese clon con la info que ya tenía guardada
	rpc_id(sender, "sync_player_data", current_player_index, custom_name)

# 4. Todos ejecutan esto para aplicar el texto y el color final
@rpc("any_peer", "call_local", "reliable")
func sync_player_data(idx: int, p_name: String):
	current_player_index = idx
	custom_name = p_name
	
	# Fallback por si acaso
	if custom_name == "":
		custom_name = str(name)
		
	_make_outline_unique()
	base_outline_color = PLAYER_COLORS[idx % PLAYER_COLORS.size()]
	
	nameplate.text = str(idx + 1) + ". " + custom_name
	reset_outline_color()
	
		# =====================================
		#  --- FUNCIONES MATERIAL ALBEDO ---

# 5. Esta función es la que "ordena" a los demás que flasheen
func request_flash(color: Color, intensity: float, time_ms: float):
	# Ejecutamos localmente y enviamos a los demás
	rpc("remote_flash_model", color, intensity, time_ms)

# 6. Esta es la que realmente cambia el material en cada PC
@rpc("any_peer", "call_local", "reliable")
func remote_flash_model(color: Color, intensity: float, time_ms: float):
	if base_material:
		var tint = Color(color.r, color.g, color.b, intensity)
		base_material.set_shader_parameter("flash_color", tint)
		
		await get_tree().create_timer(time_ms / 1000.0).timeout
		base_material.set_shader_parameter("flash_color", Color(1, 1, 1, 0))

# =========================================================
# --- FUNCIONES MODULARES DEL OUTLINE ---

func _make_outline_unique():
	if unique_outline_mat != null: return
	
	var mesh = %CollisionShape3D.get_node("MeshInstance3D")
	var mat_override = mesh.get_surface_override_material(0)
	
	# Duplicamos el material base para que el flash no afecte a otros jugadores
	base_material = mat_override.duplicate()
	unique_outline_mat = base_material.next_pass.duplicate()
	base_material.next_pass = unique_outline_mat
	
	mesh.set_surface_override_material(0, base_material)

func set_outline_color(new_color: Color, time_ms: float = 0.0):
	if unique_outline_mat:
		unique_outline_mat.set_shader_parameter("color", new_color)
		if time_ms > 0.0:
			print("[DEBUG] Temporary outline: ", new_color, " in node ", name, " for ", time_ms, "ms")
			await get_tree().create_timer(time_ms / 1000.0).timeout
			reset_outline_color()
	else:
		print("[ERROR] Trying to change color without unique material in: ", name)

func reset_outline_color():
	if base_outline_color:
		set_outline_color(base_outline_color)
	else:
		# Fallback si el color base aún no se ha sincronizado
		set_outline_color(Color.WHITE)

# =========================================================

func _push_away_rigid_bodies():
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		var collider = c.get_collider()
		
		if collider is RigidBody3D:
			var normal = c.get_normal()
			
			if velocity.y < 0 and normal.y > 0.5:
				var forward_dir = -transform.basis.z
				var bounce_dir = (forward_dir + Vector3(0, 0.8, 0)).normalized()
				var bounce_force = collider.mass * 6.0 
				collider.apply_central_impulse(bounce_dir * bounce_force)
				
				velocity.y = 3.0 
				continue 
			
			var push_dir = -normal
			push_dir.y = 0
			
			if push_dir.length() > 0.01:
				push_dir = push_dir.normalized()
				var player_v = velocity.dot(push_dir)
				var rb_v = collider.linear_velocity.dot(push_dir)
				var velocity_diff = player_v - rb_v
				
				if velocity_diff > 0:
					var push_force = velocity_diff * collider.mass * 0.2
					collider.apply_central_impulse(push_dir * push_force)

func dash_possible() -> bool:
	return Time.get_ticks_msec() - last_dash_ms > dash_cooldown_ms

func pound_possible() -> bool:
	return Time.get_ticks_msec() - last_pound_ms > pound_cooldown_ms

func _attempt_dash() -> void:
	if not dash_possible():
		return

	last_dash_ms = Time.get_ticks_msec()
	can_bounce = true
	dash_timer = DASH_DURATION
	
	set_outline_color(Color.ORANGE, 500)
	
	var input_dir := Input.get_vector("down", "up", "left", "right")
	dash_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if dash_direction == Vector3.ZERO:
		dash_direction = transform.basis.x
		
	velocity.y = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		spring_arm.rotation.x -= event.relative.y * sensitivity
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-90), deg_to_rad(90))
		
func _process(_delta:float) -> void:
	if Input.is_action_just_pressed('menu') and menu.visible == false:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		menu.show()
	elif Input.is_action_just_pressed('menu') and menu.visible == true:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		menu.hide()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
		
	var density = velocity.length() * 0.025 
	
	if speed_lines.material:
		speed_lines.material.set_shader_parameter("line_density", density)
		
	if velocity.length() < 12.0:
		speed_lines.hide()
	else:
		speed_lines.show()
	
	if Input.is_action_just_pressed("ctrl"):
		if pound_possible():
			ctrl_bounce = true
			last_pound_ms = Time.get_ticks_msec()
			

	if Input.is_action_just_pressed("dash"):
		_attempt_dash()

	if dash_timer > 0:
		dash_timer -= delta
		
		if is_on_wall() and can_bounce:
			var valid_wall_normal = Vector3.ZERO
			var found_valid_wall = false
			
			for i in get_slide_collision_count():
				var collision = get_slide_collision(i)
				var collider = collision.get_collider()
				
				if not collider is RigidBody3D:
					var n = collision.get_normal()
					if abs(n.y) < 0.7: 
						valid_wall_normal = n
						found_valid_wall = true
						break
			
			if found_valid_wall:
				dash_direction = dash_direction.bounce(valid_wall_normal)
				dash_direction.y = 0 
				dash_direction = dash_direction.normalized()
				
				if speed >= 25:
					can_bounce = false
		
		velocity.x = dash_direction.x * DASH_SPEED
		velocity.z = dash_direction.z * DASH_SPEED
		velocity.y = 0 
	else:
		if is_on_floor():
			can_bounce = true
			
		if not is_on_floor() && ctrl_bounce == false:
			velocity += get_gravity() * delta
			
		if ctrl_bounce == true:
			velocity += (get_gravity() * delta) * 10
			set_outline_color(Color.AQUA,500)
			
			if is_on_floor():
				velocity.y =  speed 
				ctrl_bounce = false

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

		var input_dir := Input.get_vector("down", "up", "left", "right")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		if direction:
			if speed < MAX_SPEED_RUN and (Time.get_ticks_msec() - speed_counter) > int(speed_plus_cooldown * 1000):
				speed = min(speed * 1.2, MAX_SPEED_RUN) 
				speed_counter = Time.get_ticks_msec() 
			
			velocity.x = move_toward(velocity.x, direction.x * speed, DECELERATION * delta)
			velocity.z = move_toward(velocity.z, direction.z * speed, DECELERATION * delta)
		else:
			speed = START_SPEED
			speed_counter = Time.get_ticks_msec()
			
			velocity.x = move_toward(velocity.x, 0, DECELERATION * delta)
			velocity.z = move_toward(velocity.z, 0, DECELERATION * delta)

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	speed_label.text = "Speed: " + str(snapped(horizontal_speed, 0.1))
	dash_label.text = "CAN DASH" if dash_possible() else "NO DASH"
	
	var current_dash_ready = dash_possible()
	var current_pound_ready = pound_possible()
	
	if current_dash_ready and not dash_was_ready:
		request_flash(Color.ORANGE, 1.0, 200.0)
		print("Dash listo")
	dash_was_ready = current_dash_ready

	# Flash para el Pound
	if current_pound_ready and not pound_was_ready:
		request_flash(Color.CYAN, 1.0, 200.0)
		print("Pound listo")
	pound_was_ready = current_pound_ready
		

	
	move_and_slide()
	_push_away_rigid_bodies()
