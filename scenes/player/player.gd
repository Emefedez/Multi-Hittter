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

# --- NUEVO: Cooldown para el Ctrl (Ground Pound) ---
const pound_cooldown_ms := 1500 # 1.5 segundos de espera
var last_pound_ms := 0
# ---------------------------------------------------

@export var sensitivity: float = 0.002

const DASH_SPEED = 25.0
const DASH_DURATION = 0.2 
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var can_bounce: bool = true
var ctrl_bounce: bool = false


func _enter_tree() -> void:
	set_multiplayer_authority(int(name))
###########################################################################
func _set_outline_color():
	var node_peer_id = int(name)
	
	# Obtenemos todos los peers conectados (excluye el local)
	var all_peers = multiplayer.get_peers()
	
	# Añadimos nuestro propio ID para tener el panorama completo
	all_peers.append(multiplayer.get_unique_id())
	
	# Ordenamos para que todos los clientes tengan la lista en el mismo orden
	all_peers.sort()
	
	# Buscamos la posición del ID de ESTE nodo específico
	var player_index = all_peers.find(node_peer_id)
	
	# Fallback de seguridad en caso de desincronización
	if player_index == -1:
		player_index = 0
		
	var chosen_color = PLAYER_COLORS[player_index % PLAYER_COLORS.size() - 1]
	
	var mesh = %CollisionShape3D.get_node("MeshInstance3D")
	var base_mat = mesh.get_surface_override_material(0)
	
	var unique_mat = base_mat.duplicate()
	var unique_outline = unique_mat.next_pass.duplicate()
	unique_mat.next_pass = unique_outline
	
	unique_outline.set_shader_parameter("color", chosen_color)
	mesh.set_surface_override_material(0, unique_mat)
	return player_index
##########################################################################
@rpc("any_peer", "call_local", "reliable")
func update_nameplate(new_name: String):
	custom_name = new_name
	var p_index = _set_outline_color()
	nameplate.text = str(p_index) + ". " + custom_name

@rpc("any_peer", "reliable")
func request_name():
	var sender_id = multiplayer.get_remote_sender_id()
	# Le respondemos exclusivamente a quien nos lo preguntó enviándole nuestro nombre
	rpc_id(sender_id, "update_nameplate", custom_name)
##########################################################################

func _push_away_rigid_bodies():
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		var collider = c.get_collider()
		
		if collider is RigidBody3D:
			var normal = c.get_normal()
			
			# 1. SI ESTAMOS CAYENDO SOBRE LA PELOTA (El jugador cae hacia abajo y toca la parte superior)
			if velocity.y < 0 and normal.y > 0.5:
				# Obtenemos hacia donde mira el jugador (-Z es el frente en Godot)
				var forward_dir = -transform.basis.z
				
				# Creamos un vector que apunte al frente y ligeramente hacia arriba para que la pelota bote
				var bounce_dir = (forward_dir + Vector3(0, 0.8, 0)).normalized()
				
				# Aplicamos el impulso para que la pelota salga disparada
				var bounce_force = collider.mass * 6.0 
				collider.apply_central_impulse(bounce_dir * bounce_force)
				
				# Hacemos que el jugador rebote un poco hacia arriba al pisarla
				velocity.y = 3.0 
				continue # Terminamos aquí este frame para no mezclar fuerzas
			
			# 2. EMPUJE HORIZONTAL NORMAL (Caminando o haciendo Dash)
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
			
############################################################################
func dash_possible() -> bool:
	return Time.get_ticks_msec() - last_dash_ms > dash_cooldown_ms

# --- NUEVO: Función para chequear el cooldown del Ctrl ---
func pound_possible() -> bool:
	return Time.get_ticks_msec() - last_pound_ms > pound_cooldown_ms
# ---------------------------------------------------------

func _attempt_dash() -> void:
	if not dash_possible():
		return

	print("Dash attempted")
	last_dash_ms = Time.get_ticks_msec()
	
	can_bounce = true
	dash_timer = DASH_DURATION
	
	var input_dir := Input.get_vector("down", "up", "left", "right")
	dash_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if dash_direction == Vector3.ZERO:
		dash_direction = transform.basis.x
		
	velocity.y = 0.0
############################################################################

func _ready():
	add_to_group('Players')
	menu.hide()
	
	if is_multiplayer_authority():
		camera_3d.current = true
		print(name, " is auth\n")
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		button_leave.pressed.connect(func(): Network.leave_server())
		
		# Leemos el nombre que guardamos en la pantalla de inicio
		var my_name = Network.local_player_name
		if my_name == "":
			my_name = name # Nombre por defecto si lo dejan vacío
			
		# Nos lo asignamos localmente y lo enviamos al resto por la red
		rpc("update_nameplate", my_name)
		
	else:
		set_process(false)
		set_physics_process(false)
		print(name, " is not auth\n")
		speed_lines.hide()
		$CanvasLayer.hide()
		
		# Si somos un "clon" en la pantalla de otro, le preguntamos al dueño original cuál es su nombre
		rpc_id(int(name), "request_name")
	
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
	
	# --- MODIFICADO: Ahora chequeamos el cooldown ---
	if Input.is_action_just_pressed("ctrl"):
		if pound_possible():
			ctrl_bounce = true
			last_pound_ms = Time.get_ticks_msec() # Reseteamos el cooldown
	# ------------------------------------------------

	if Input.is_action_just_pressed("dash"):
		_attempt_dash()

	if dash_timer > 0:
		# ESTADO: DASHING
		dash_timer -= delta
		
		if is_on_wall() and can_bounce:
			var valid_wall_normal = Vector3.ZERO
			var found_valid_wall = false
			
			# Revisamos las colisiones del último frame para encontrar la pared real, ignorando la pelota
			for i in get_slide_collision_count():
				var collision = get_slide_collision(i)
				var collider = collision.get_collider()
				
				# Filtramos cualquier RigidBody3D (como la pelota)
				if not collider is RigidBody3D:
					var n = collision.get_normal()
					# Comprobamos que la superficie sea vertical (pared). 
					# Un valor absoluto de 'y' menor a 0.7 equivale aprox. a ángulos mayores de 45 grados.
					if abs(n.y) < 0.7: 
						valid_wall_normal = n
						found_valid_wall = true
						break
			
			# Si realmente chocamos contra una pared válida, aplicamos el rebote matemático
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
			
		# Gravedad Normal
		if not is_on_floor() && ctrl_bounce == false:
			velocity += get_gravity() * delta
			
		# Caída Rápida (Ground Pound)
		if ctrl_bounce == true:
			velocity += (get_gravity() * delta) * 10
			
			if is_on_floor():
				velocity.y =  speed # Rebote hacia arriba al tocar suelo
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
	
	move_and_slide()
	_push_away_rigid_bodies()
	
	
