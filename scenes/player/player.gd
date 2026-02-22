extends CharacterBody3D



@onready var camera_3d: Camera3D = %Camera3D
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var head: Node3D = %Head
@onready var nameplate: Label3D = %Nameplate
@onready var body: CollisionShape3D =  %CollisionShape3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
@export var sensitivity: float = 0.002


func _enter_tree() -> void:
	set_multiplayer_authority(int(name))



func _ready():
	add_to_group('Players')
	nameplate.text = name
	if is_multiplayer_authority():
		camera_3d.current = true
		print(name, " is auth\n")
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		print(name, " is not auth\n")
	
	
	
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	if event is InputEventMouseMotion:
		# Rotación horizontal aplicada a la cabeza y al modelo
		rotate_y(-event.relative.x * sensitivity)
		# Rotación vertical aplicada al brazo que sostiene la cámara
		spring_arm.rotation.x -= event.relative.y * sensitivity
		# Limitar la rotación vertical para no dar volteretas
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-90), deg_to_rad(90))


func _physics_process(delta: float) -> void:
	# Si este cliente no es el dueño de este personaje, no ejecuta físicas
	if not is_multiplayer_authority():
		return
		
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("down", "up", "left", "right")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
