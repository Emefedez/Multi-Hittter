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
@export var sensitivity: float = 0.002

const DASH_SPEED = 25.0
const DASH_DURATION = 0.2 # Segundos que dura el dash (y el tiempo que flotas)
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var can_bounce: bool = true

func _enter_tree() -> void:
	set_multiplayer_authority(int(name))

############################################################################
func dash_possible() -> bool:
	return Time.get_ticks_msec() - last_dash_ms > dash_cooldown_ms

func _attempt_dash() -> void:
	if not dash_possible():
		return

	print("Dash attempted")
	last_dash_ms = Time.get_ticks_msec()
	
	can_bounce = true
	dash_timer = DASH_DURATION
	
	# Guardamos la dirección en la que vamos a hacer el dash
	var input_dir := Input.get_vector("down", "up", "left", "right")
	dash_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Si estamos quietos y hacemos dash, lo hacemos hacia adelante
	if dash_direction == Vector3.ZERO:
		dash_direction = -transform.basis.z
		
	# Cancelamos cualquier inercia de caída o salto para quedarnos suspendidos
	velocity.y = 0.0
############################################################################

func _ready():
	add_to_group('Players')
	nameplate.text = name
	menu.hide()
	
	if is_multiplayer_authority():
		camera_3d.current = true
		print(name, " is auth\n")
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		button_leave.pressed.connect(func(): Network.leave_server())

	else:
		set_process(false)
		set_physics_process(false)
		print(name, " is not auth\n")
		speed_lines.hide()
		$CanvasLayer.hide()
		return
	
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
		
	# Aumentamos un poco el multiplicador para que las líneas sean más intensas
	var density = velocity.length() * 0.025 
	
	if speed_lines.material:
		speed_lines.material.set_shader_parameter("line_density", density)
		
	# Ocultamos el nodo gráficamente si vamos muy lento para ahorrar recursos,
	# y lo mostramos automáticamente en cuanto empezamos a ganar velocidad.
	if velocity.length() < 12.0:
		speed_lines.hide()
	else:
		speed_lines.show()

	if Input.is_action_just_pressed("dash"):
		_attempt_dash()

		
	if dash_timer > 0:
		# when dashing
		dash_timer -= delta
		
		# Solo reflejamos si no hemos rebotado aún en este ciclo aéreo 
		if is_on_wall() and can_bounce:
			dash_direction = -dash_direction
			can_bounce = false # Bloquear más rebotes hasta tocar el suelo
		
		velocity.x = dash_direction.x * DASH_SPEED
		velocity.z = dash_direction.z * DASH_SPEED
		velocity.y = 0 
	else:
		if is_on_floor():
			can_bounce = true
			
		if not is_on_floor():
			velocity += get_gravity() * delta

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

		var input_dir := Input.get_vector("down", "up", "left", "right")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		if direction:
			# Aceleración lógica
			if speed < MAX_SPEED_RUN and (Time.get_ticks_msec() - speed_counter) > int(speed_plus_cooldown * 1000):
				speed = min(speed * 1.2, MAX_SPEED_RUN) 
				speed_counter = Time.get_ticks_msec() 
			
			# CAMBIO CLAVE: move_toward en lugar de "=" 
			# Esto hace que si vienes de un dash (25), baje a "speed" (10) poco a poco
			velocity.x = move_toward(velocity.x, direction.x * speed, DECELERATION * delta)
			velocity.z = move_toward(velocity.z, direction.z * speed, DECELERATION * delta)
		else:
			speed = START_SPEED
			speed_counter = Time.get_ticks_msec()
			
			velocity.x = move_toward(velocity.x, 0, DECELERATION * delta)
			velocity.z = move_toward(velocity.z, 0, DECELERATION * delta)

	# UI y Movimiento
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	speed_label.text = "Speed: " + str(snapped(horizontal_speed, 0.1))
	dash_label.text = "CAN DASH" if dash_possible() else "NO DASH"

	move_and_slide()
	
