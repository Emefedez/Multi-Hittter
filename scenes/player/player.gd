extends CharacterBody3D

@onready var camera_3d: Camera3D = %Camera3D
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var head: Node3D = %Head
@onready var nameplate: Label3D = %Nameplate
# Eliminamos la referencia a body para las colisiones, usaremos self

@onready var menu: Control = %Menu
@onready var button_leave: Button = %ButtonLeave

@onready var speed_label: Label = %SpeedLabel
@onready var dash_label: Label = %DashReportLabel

const START_SPEED = 6.0
const MAX_SPEED_RUN = 10.0
const DECELERATION = 30.0 
const DASH_DECEL = 15.0 # Deceleración específica para el post-dash (más suave)

var speed = START_SPEED 
var speed_counter: int = 0 
var speed_plus_cooldown = 0.3

const JUMP_VELOCITY = 4.5
const dash_cooldown_ms := 1000 
var last_dash_ms := 0
@export var sensitivity: float = 0.002

# --- VARIABLES DE DASH ---
const DASH_SPEED = 25.0
const DASH_DURATION = 0.2 
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

func _enter_tree() -> void:
	set_multiplayer_authority(int(name)) 

func dash_possible() -> bool:
	return Time.get_ticks_msec() - last_dash_ms > dash_cooldown_ms

func _attempt_dash() -> void:
	if not dash_possible():
		return

	last_dash_ms = Time.get_ticks_msec()
	dash_timer = DASH_DURATION
	
	var input_dir := Input.get_vector("down", "up", "left", "right")
	dash_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if dash_direction == Vector3.ZERO:
		dash_direction = -transform.basis.z
		
	velocity.y = 0.0

func _ready():
	add_to_group('Players')
	nameplate.text = name
	menu.hide()
	
	if is_multiplayer_authority():
		camera_3d.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		button_leave.pressed.connect(func(): Network.leave_server()) [cite: 10, 24]
	else:
		set_process(false)
		set_physics_process(false)
		return

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
		
	if Input.is_action_just_pressed("dash"):
		_attempt_dash()
		
	# === LÓGICA DE ESTADOS ===
	if dash_timer > 0:
		dash_timer -= delta
		
		# REBOTE: Si tocamos pared, invertimos la dirección usando la normal del impacto
		if is_on_wall():
			var wall_normal = get_wall_normal()
			dash_direction = dash_direction.bounce(wall_normal)
			# Opcional: reducimos el tiempo de dash al chocar para que no rebote infinitamente
			dash_timer -= delta * 2 
		
		velocity.x = dash_direction.x * DASH_SPEED
		velocity.z = dash_direction.z * DASH_SPEED
		velocity.y = 0 # Mantiene el vuelo
		
	else:
		# === MOVIMIENTO NORMAL ===
		if not is_on_floor():
			velocity += get_gravity() * delta

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

		var input_dir := Input.get_vector("down", "up", "left", "right")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		if direction:
			if speed < MAX_SPEED_RUN and (Time.get_ticks_msec() - speed_counter) > int(speed_plus_cooldown * 1000):
				speed = min(speed * 1.2, MAX_SPEED_RUN) 
				speed_counter = Time.get_ticks_msec() 
			
			# DECELERACIÓN POST-DASH:
			# Si la velocidad actual es mayor que la velocidad de carrera (por el dash),
			# usamos move_toward para bajarla poco a poco en lugar de cortarla en seco.
			var target_vel_x = direction.x * speed
			var target_vel_z = direction.z * speed
			
			velocity.x = move_toward(velocity.x, target_vel_x, DASH_DECEL * delta)
			velocity.z = move_toward(velocity.z, target_vel_z, DASH_DECEL * delta)
		else:
			speed = START_SPEED
			speed_counter = Time.get_ticks_msec()
			
			# Frenado total cuando no hay input
			velocity.x = move_toward(velocity.x, 0, DECELERATION * delta)
			velocity.z = move_toward(velocity.z, 0, DECELERATION * delta)

	# UI y Movimiento
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	speed_label.text = "Speed: " + str(snapped(horizontal_speed, 0.1))
	dash_label.text = "CAN DASH" if dash_possible() else "NO DASH"

	move_and_slide()
