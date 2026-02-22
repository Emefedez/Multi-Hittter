extends MeshInstance3D

@export var camera: Camera3D
@export var distance_from_camera: float = 0.1

func _ready() -> void:
	# Conectamos la señal del viewport para que avise cuando cambie el tamaño de la ventana
	get_viewport().size_changed.connect(_resize_quad)
	
	# Ejecutamos la función una vez al inicio para el tamaño por defecto
	_resize_quad()

func _resize_quad() -> void:
	if not camera:
		return
		
	# Obtenemos el tamaño de la ventana y calculamos la relación de aspecto
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect_ratio := viewport_size.x / viewport_size.y
	
	# Godot usa FOV vertical. Lo convertimos a radianes para la función matemática
	var fov_radians := deg_to_rad(camera.fov)
	
	# Calculamos el tamaño físico del plano en el espacio 3D
	var quad_height := 2.0 * distance_from_camera * tan(fov_radians / 2.0)
	var quad_width := quad_height * aspect_ratio
	
	# Aplicamos las medidas al QuadMesh
	mesh.size = Vector2(quad_width, quad_height)
	
	# Posicionamos el plano exactamente a la distancia requerida frente a la cámara
	position.z = -distance_from_camera
