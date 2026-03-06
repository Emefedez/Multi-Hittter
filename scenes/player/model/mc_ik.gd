## mc_ik.gd
## Controlador de IK procedural para el modelo de jugador MC.
## Adjunta este script al nodo raíz "PlayerModel" de mc.tscn.
##
## USO DESDE CÓDIGO EXTERNO (p.ej. player.gd):
##   var model: Node3D = $PlayerModel          # instancia del mc.tscn
##   model.look_target     = $Head/SpringArm3D/Camera3D
##   model.right_hand_target = $Head/.../HoldPosition
##   model.left_hand_target  = null  # sin IK de mano izquierda

class_name McIkModel
extends Node3D

# ─────────────────────────────────────────────
# API PÚBLICA – asignar desde el player
# ─────────────────────────────────────────────

## Nodo hacia el que el personaje dirigirá la cabeza/cuello.
## Puede ser la Camera3D del jugador o cualquier Marker3D.
var look_target: Node3D = null

## Nodo hacia el que se moverá la mano derecha (IK de brazo derecho).
## Úsalo cuando el jugador sujeta un objeto (HoldPosition).
var right_hand_target: Node3D = null

## Nodo hacia el que se moverá la mano izquierda (IK de brazo izquierdo).
var left_hand_target: Node3D = null

## Peso del look-at de cabeza (0 = sin efecto, 1 = completamente hacia el objetivo).
@export_range(0.0, 1.0) var head_look_weight: float = 0.55

## Si es false, se desactivan los IK de brazos aunque haya targets.
@export var arm_ik_enabled: bool = true

## Locomoción procedural básica para que el modelo reaccione al movimiento del jugador.
@export var locomotion_enabled: bool = true
@export_range(0.1, 20.0) var locomotion_max_speed: float = 10.0
@export_range(0.1, 20.0) var bob_frequency: float = 7.5
@export_range(0.0, 0.5) var bob_height: float = 0.035
@export_range(0.0, 0.5) var bob_side_amount: float = 0.025
@export_range(0.0, 25.0) var root_tilt_degrees: float = 7.5
@export_range(0.0, 25.0) var spine_tilt_degrees: float = 10.0
@export_range(0.1, 30.0) var locomotion_smoothing: float = 12.0
@export_range(0.1, 30.0) var limb_pose_smoothing: float = 10.0
@export_range(0.0, 60.0) var arm_swing_degrees: float = 22.0
@export_range(0.0, 45.0) var forearm_swing_degrees: float = 16.0
@export_range(0.0, 60.0) var leg_swing_degrees: float = 28.0
@export_range(0.0, 45.0) var calf_swing_degrees: float = 18.0
@export_range(0.0, 90.0) var head_yaw_limit_degrees: float = 65.0
@export_range(0.0, 90.0) var head_pitch_limit_degrees: float = 40.0
@export_range(-45.0, 45.0) var head_pitch_offset_degrees: float = -8.0
@export_range(0.0, 0.5) var jump_stretch_amount: float = 0.12
@export_range(0.0, 0.5) var fall_stretch_amount: float = 0.1
@export_range(0.0, 0.5) var landing_squash_amount: float = 0.16
@export_range(0.1, 30.0) var landing_recover_speed: float = 10.0
@export_range(0.1, 2.0) var hand_target_pull: float = 1.0
@export_range(0.1, 2.0) var hand_max_reach: float = 1.2
@export_range(-0.5, 0.5) var hand_marker_depth_offset: float = -0.04
@export var right_hand_hold_offset: Vector3 = Vector3(-0.06, -0.02, -0.04)
@export var left_hand_hold_offset: Vector3 = Vector3(0.06, -0.02, -0.04)
@export_range(0.0, 90.0) var air_leg_lift_degrees: float = 28.0
@export_range(0.0, 90.0) var air_knee_bend_degrees: float = 42.0
@export_range(0.0, 45.0) var landing_knee_bend_bonus_degrees: float = 14.0
@export_range(0.0, 90.0) var air_arm_lift_degrees: float = 18.0
@export_range(0.0, 90.0) var air_forearm_bend_degrees: float = 26.0
@export_range(0.1, 10.0) var airborne_cycle_speed: float = 2.4

var movement_velocity: Vector3 = Vector3.ZERO
var movement_input: Vector2 = Vector2.ZERO
var is_grounded: bool = true

# ─────────────────────────────────────────────
# Referencias internas
# ─────────────────────────────────────────────

@onready var _skeleton: Skeleton3D = $Skeleton3D

# Markers de objetivo para el CCDIK3D configurado en la escena
@onready var _right_hand_ik_marker: Marker3D = $RightHandIKTarget
@onready var _left_hand_ik_marker: Marker3D  = $LeftHandIKTarget
@onready var _head_look_marker: Marker3D     = $HeadLookTarget

# Nodo CCDIK del brazo derecho (ya existente en la escena, renombrado)
@onready var _right_arm_ik: CCDIK3D = $Skeleton3D/RightArmIK
@onready var _left_arm_ik: CCDIK3D  = $Skeleton3D/LeftArmIK

var _body_meshes: Array[MeshInstance3D] = []
var _mesh_base_materials: Dictionary = {}
var _theme_color: Color = Color.WHITE
var _flash_tint: Color = Color(1.0, 1.0, 1.0, 0.0)
var _outline_material: Material = null

# Índices de huesos cacheados
var _head_bone: int = -1
var _neck_bone: int = -1
var _spine2_bone: int = -1
var _left_arm_bone: int = -1
var _right_arm_bone: int = -1
var _left_forearm_bone: int = -1
var _right_forearm_bone: int = -1
var _left_up_leg_bone: int = -1
var _right_up_leg_bone: int = -1
var _left_leg_bone: int = -1
var _right_leg_bone: int = -1

# Rots de reposo cacheadas para restaurar los huesos cuando no hay target
var _head_rest_quat: Quaternion
var _neck_rest_quat: Quaternion
var _spine_rest_quat: Quaternion
var _left_arm_rest_quat: Quaternion
var _right_arm_rest_quat: Quaternion
var _left_forearm_rest_quat: Quaternion
var _right_forearm_rest_quat: Quaternion
var _left_up_leg_rest_quat: Quaternion
var _right_up_leg_rest_quat: Quaternion
var _left_leg_rest_quat: Quaternion
var _right_leg_rest_quat: Quaternion

var _base_transform: Transform3D
var _gait_phase: float = 0.0
var _airborne_time: float = 0.0
var _previous_grounded: bool = true
var _previous_vertical_velocity: float = 0.0
var _landing_squash: float = 0.0

# ─────────────────────────────────────────────
# Ciclo de vida
# ─────────────────────────────────────────────

func _ready() -> void:
	_base_transform = transform
	_cache_body_meshes()
	_cache_bones()
	_init_arm_ik_state()
	_previous_grounded = is_grounded


func _cache_body_meshes() -> void:
	for child in find_children("*", "MeshInstance3D"):
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			_body_meshes.append(mesh_instance)
			var materials: Array[Material] = []
			if mesh_instance.mesh:
				for surface_idx in mesh_instance.mesh.get_surface_count():
					var material := mesh_instance.get_surface_override_material(surface_idx)
					if material == null:
						material = mesh_instance.mesh.surface_get_material(surface_idx)
					materials.append(material)
			_mesh_base_materials[mesh_instance] = materials


func _process(delta: float) -> void:
	_sync_ik_markers()
	_apply_locomotion(delta)
	_apply_head_look()


# ─────────────────────────────────────────────
# Inicialización
# ─────────────────────────────────────────────

func _cache_bones() -> void:
	_head_bone   = _skeleton.find_bone("mixamorig_Head")
	_neck_bone   = _skeleton.find_bone("mixamorig_Neck")
	_spine2_bone = _skeleton.find_bone("mixamorig_Spine2")
	_left_arm_bone = _skeleton.find_bone("mixamorig_LeftArm")
	_right_arm_bone = _skeleton.find_bone("mixamorig_RightArm")
	_left_forearm_bone = _skeleton.find_bone("mixamorig_LeftForeArm")
	_right_forearm_bone = _skeleton.find_bone("mixamorig_RightForeArm")
	_left_up_leg_bone = _skeleton.find_bone("mixamorig_LeftUpLeg")
	_right_up_leg_bone = _skeleton.find_bone("mixamorig_RightUpLeg")
	_left_leg_bone = _skeleton.find_bone("mixamorig_LeftLeg")
	_right_leg_bone = _skeleton.find_bone("mixamorig_RightLeg")

	if _head_bone >= 0:
		_head_rest_quat = _skeleton.get_bone_rest(_head_bone).basis.get_rotation_quaternion()
	if _neck_bone >= 0:
		_neck_rest_quat = _skeleton.get_bone_rest(_neck_bone).basis.get_rotation_quaternion()
	if _spine2_bone >= 0:
		_spine_rest_quat = _skeleton.get_bone_rest(_spine2_bone).basis.get_rotation_quaternion()
	if _left_arm_bone >= 0:
		_left_arm_rest_quat = _skeleton.get_bone_rest(_left_arm_bone).basis.get_rotation_quaternion()
	if _right_arm_bone >= 0:
		_right_arm_rest_quat = _skeleton.get_bone_rest(_right_arm_bone).basis.get_rotation_quaternion()
	if _left_forearm_bone >= 0:
		_left_forearm_rest_quat = _skeleton.get_bone_rest(_left_forearm_bone).basis.get_rotation_quaternion()
	if _right_forearm_bone >= 0:
		_right_forearm_rest_quat = _skeleton.get_bone_rest(_right_forearm_bone).basis.get_rotation_quaternion()
	if _left_up_leg_bone >= 0:
		_left_up_leg_rest_quat = _skeleton.get_bone_rest(_left_up_leg_bone).basis.get_rotation_quaternion()
	if _right_up_leg_bone >= 0:
		_right_up_leg_rest_quat = _skeleton.get_bone_rest(_right_up_leg_bone).basis.get_rotation_quaternion()
	if _left_leg_bone >= 0:
		_left_leg_rest_quat = _skeleton.get_bone_rest(_left_leg_bone).basis.get_rotation_quaternion()
	if _right_leg_bone >= 0:
		_right_leg_rest_quat = _skeleton.get_bone_rest(_right_leg_bone).basis.get_rotation_quaternion()


func _init_arm_ik_state() -> void:
	# El CCDIK3D se activa/desactiva según arm_ik_enabled y la presencia de targets
	_set_arm_ik_active(false, false)


# ─────────────────────────────────────────────
# Auxiliares de IK de brazos
# ─────────────────────────────────────────────

func _set_arm_ik_active(right_active: bool, left_active: bool) -> void:
	if _right_arm_ik:
		_right_arm_ik.active = right_active
	if _left_arm_ik:
		_left_arm_ik.active  = left_active


## Mueve los Marker3D de objetivo a cada frame para que el CCDIK3D los siga.
func _sync_ik_markers() -> void:
	var use_right := arm_ik_enabled and right_hand_target != null
	var use_left  := arm_ik_enabled and left_hand_target  != null

	_set_arm_ik_active(use_right, use_left)

	if use_right and _right_hand_ik_marker:
		_right_hand_ik_marker.global_position = _get_reachable_hand_target(
			right_hand_target,
			_right_arm_bone,
			right_hand_hold_offset
		)

	if use_left and _left_hand_ik_marker:
		_left_hand_ik_marker.global_position  = _get_reachable_hand_target(
			left_hand_target,
			_left_arm_bone,
			left_hand_hold_offset
		)

	# El HeadLookTarget lo movemos también para que otras herramientas lo vean
	if look_target and _head_look_marker:
		_head_look_marker.global_position = look_target.global_position


func set_locomotion_state(world_velocity: Vector3, grounded: bool, input_axis: Vector2 = Vector2.ZERO) -> void:
	if not _previous_grounded and grounded and _previous_vertical_velocity < -4.0:
		_landing_squash = clampf(abs(_previous_vertical_velocity) / 20.0, 0.0, landing_squash_amount)

	_previous_grounded = grounded
	_previous_vertical_velocity = world_velocity.y
	movement_velocity = world_velocity
	is_grounded = grounded
	movement_input = input_axis


func _apply_locomotion(delta: float) -> void:
	if not locomotion_enabled:
		transform = _base_transform
		_restore_spine_pose()
		_restore_limb_pose()
		return

	var planar_velocity := movement_velocity
	planar_velocity.y = 0.0
	var speed := planar_velocity.length()
	var speed_ratio := clampf(speed / maxf(locomotion_max_speed, 0.001), 0.0, 1.0)
	_landing_squash = move_toward(_landing_squash, 0.0, delta * landing_recover_speed)

	var parent_node := get_parent_node_3d()
	var parent_basis := parent_node.global_transform.basis if parent_node else Basis.IDENTITY
	var local_velocity := parent_basis.inverse() * planar_velocity

	if is_grounded and speed_ratio > 0.05:
		_gait_phase += delta * bob_frequency * lerp(0.8, 1.8, speed_ratio)
	if not is_grounded:
		_airborne_time += delta * airborne_cycle_speed
		_gait_phase += delta * bob_frequency * 0.22
	else:
		_airborne_time = 0.0

	var bob_vertical := 0.0
	var bob_side := 0.0
	if is_grounded:
		bob_vertical = sin(_gait_phase) * bob_height * speed_ratio
		bob_side = sin(_gait_phase * 2.0) * bob_side_amount * speed_ratio
		bob_side += clampf(local_velocity.x / maxf(locomotion_max_speed, 0.001), -1.0, 1.0) * bob_side_amount * 0.35

	var pitch := deg_to_rad(root_tilt_degrees) * clampf(local_velocity.z / maxf(locomotion_max_speed, 0.001), -1.0, 1.0)
	var strafe_roll := deg_to_rad(root_tilt_degrees) * clampf(-movement_input.x, -1.0, 1.0) * 0.65
	var gait_roll := deg_to_rad(root_tilt_degrees * 0.35) * sin(_gait_phase * 2.0) * speed_ratio
	var roll := strafe_roll + gait_roll
	if not is_grounded:
		pitch += deg_to_rad(4.0) * clampf(-movement_velocity.y / 8.0, -1.0, 1.0)

	var stretch_y := 1.0
	if movement_velocity.y > 0.1:
		stretch_y += clampf(movement_velocity.y / 12.0, 0.0, jump_stretch_amount)
	elif movement_velocity.y < -0.1:
		stretch_y += clampf(abs(movement_velocity.y) / 16.0, 0.0, fall_stretch_amount)
	stretch_y -= _landing_squash
	stretch_y = maxf(stretch_y, 0.72)
	var stretch_xz := 1.0 + ((1.0 - stretch_y) * 0.5)

	var target_basis := (_base_transform.basis * Basis.from_euler(Vector3(pitch, 0.0, roll))).scaled(Vector3(stretch_xz, stretch_y, stretch_xz))
	var target_origin := _base_transform.origin + Vector3(bob_side, bob_vertical, 0.0)
	transform = transform.interpolate_with(
		Transform3D(target_basis, target_origin),
		clampf(delta * locomotion_smoothing, 0.0, 1.0)
	)

	_apply_spine_locomotion(local_velocity, speed_ratio, delta)
	_apply_limb_locomotion(local_velocity, speed_ratio, delta)


func _apply_spine_locomotion(local_velocity: Vector3, speed_ratio: float, delta: float) -> void:
	if _spine2_bone < 0:
		return

	var pitch := deg_to_rad(spine_tilt_degrees) * clampf(local_velocity.z / maxf(locomotion_max_speed, 0.001), -1.0, 1.0)
	var roll := deg_to_rad(spine_tilt_degrees) * clampf(-local_velocity.x / maxf(locomotion_max_speed, 0.001), -1.0, 1.0)
	var twist := deg_to_rad(spine_tilt_degrees * 0.35) * clampf(-movement_input.x, -1.0, 1.0)
	var locomotion_quat := Quaternion.from_euler(Vector3(pitch * 0.45, twist * speed_ratio, roll * 0.75))
	_blend_bone_pose_rotation(
		_spine2_bone,
		_spine_rest_quat.slerp(_spine_rest_quat * locomotion_quat, speed_ratio),
		delta
	)


func _restore_spine_pose() -> void:
	if _spine2_bone >= 0:
		_skeleton.set_bone_pose_rotation(_spine2_bone, _spine_rest_quat)


func _apply_limb_locomotion(_local_velocity: Vector3, speed_ratio: float, delta: float) -> void:
	var stride := sin(_gait_phase)
	var stride_opposite := sin(_gait_phase + PI)
	var leg_amount := speed_ratio if is_grounded else 0.15
	var arm_amount := speed_ratio if is_grounded else 0.1
	if not is_grounded:
		var jump_ratio := clampf(movement_velocity.y / 8.0, 0.0, 1.0)
		var fall_ratio := clampf(abs(minf(movement_velocity.y, 0.0)) / 14.0, 0.0, 1.0)
		var air_amount := clampf(0.55 + (jump_ratio * 0.25) + (fall_ratio * 0.35), 0.0, 1.0)
		var air_phase := sin(_airborne_time)
		var air_opposite_phase := sin(_airborne_time + PI * 0.55)
		var landing_ratio := 0.0
		if landing_squash_amount > 0.0:
			landing_ratio = clampf(_landing_squash / landing_squash_amount, 0.0, 1.0)
		var landing_bend := landing_ratio * landing_knee_bend_bonus_degrees

		_apply_bone_swing(_left_up_leg_bone, _left_up_leg_rest_quat, 0.7 + (air_phase * 0.2), air_leg_lift_degrees + landing_bend, air_amount, Vector3.RIGHT, delta)
		_apply_bone_swing(_right_up_leg_bone, _right_up_leg_rest_quat, 0.7 + (air_opposite_phase * 0.2), air_leg_lift_degrees + landing_bend, air_amount, Vector3.RIGHT, delta)
		_apply_bone_swing(_left_leg_bone, _left_leg_rest_quat, 0.85 + (jump_ratio * 0.1), air_knee_bend_degrees + landing_bend, air_amount, Vector3.RIGHT, delta)
		_apply_bone_swing(_right_leg_bone, _right_leg_rest_quat, 0.85 + (fall_ratio * 0.1), air_knee_bend_degrees + landing_bend, air_amount, Vector3.RIGHT, delta)

		if not _left_arm_ik.active:
			_apply_bone_swing(_left_arm_bone, _left_arm_rest_quat, 0.5 + (air_opposite_phase * 0.25), air_arm_lift_degrees, 0.55, Vector3.FORWARD, delta)
			_apply_bone_swing(_left_forearm_bone, _left_forearm_rest_quat, 0.45 + (fall_ratio * 0.25), air_forearm_bend_degrees, 0.45, Vector3.FORWARD, delta)
		if not _right_arm_ik.active:
			_apply_bone_swing(_right_arm_bone, _right_arm_rest_quat, 0.5 + (air_phase * 0.25), air_arm_lift_degrees, 0.55, Vector3.FORWARD, delta)
			_apply_bone_swing(_right_forearm_bone, _right_forearm_rest_quat, 0.45 + (fall_ratio * 0.25), air_forearm_bend_degrees, 0.45, Vector3.FORWARD, delta)
		return

	_apply_bone_swing(_left_up_leg_bone, _left_up_leg_rest_quat, stride, leg_swing_degrees, leg_amount, Vector3.RIGHT, delta)
	_apply_bone_swing(_right_up_leg_bone, _right_up_leg_rest_quat, stride_opposite, leg_swing_degrees, leg_amount, Vector3.RIGHT, delta)
	_apply_bone_swing(_left_leg_bone, _left_leg_rest_quat, maxf(0.0, -stride), calf_swing_degrees, leg_amount, Vector3.RIGHT, delta)
	_apply_bone_swing(_right_leg_bone, _right_leg_rest_quat, maxf(0.0, -stride_opposite), calf_swing_degrees, leg_amount, Vector3.RIGHT, delta)

	if not _left_arm_ik.active:
		_apply_bone_swing(_left_arm_bone, _left_arm_rest_quat, stride_opposite, arm_swing_degrees, arm_amount, Vector3.FORWARD, delta)
		_apply_bone_swing(_left_forearm_bone, _left_forearm_rest_quat, maxf(0.0, -stride_opposite), forearm_swing_degrees, arm_amount, Vector3.FORWARD, delta)
	if not _right_arm_ik.active:
		_apply_bone_swing(_right_arm_bone, _right_arm_rest_quat, stride, arm_swing_degrees, arm_amount, Vector3.FORWARD, delta)
		_apply_bone_swing(_right_forearm_bone, _right_forearm_rest_quat, maxf(0.0, -stride), forearm_swing_degrees, arm_amount, Vector3.FORWARD, delta)

	if speed_ratio <= 0.05 and is_grounded:
		_restore_limb_pose(false, delta)


func _apply_bone_swing(bone_idx: int, rest_quat: Quaternion, phase_value: float, degrees_amount: float, weight: float, axis: Vector3, delta: float) -> void:
	if bone_idx < 0:
		return

	var swing_quat := Quaternion(axis.normalized(), deg_to_rad(degrees_amount) * phase_value)
	var target_rotation := rest_quat.slerp(rest_quat * swing_quat, clampf(weight, 0.0, 1.0))
	_blend_bone_pose_rotation(bone_idx, target_rotation, delta)


func _restore_limb_pose(force_arms: bool = true, delta: float = 1.0) -> void:
	if force_arms or not _left_arm_ik.active:
		_restore_bone_pose(_left_arm_bone, _left_arm_rest_quat, delta)
		_restore_bone_pose(_left_forearm_bone, _left_forearm_rest_quat, delta)
	if force_arms or not _right_arm_ik.active:
		_restore_bone_pose(_right_arm_bone, _right_arm_rest_quat, delta)
		_restore_bone_pose(_right_forearm_bone, _right_forearm_rest_quat, delta)
	_restore_bone_pose(_left_up_leg_bone, _left_up_leg_rest_quat, delta)
	_restore_bone_pose(_right_up_leg_bone, _right_up_leg_rest_quat, delta)
	_restore_bone_pose(_left_leg_bone, _left_leg_rest_quat, delta)
	_restore_bone_pose(_right_leg_bone, _right_leg_rest_quat, delta)


func _get_reachable_hand_target(target_node: Node3D, arm_bone_idx: int, hold_offset: Vector3) -> Vector3:
	if target_node == null:
		return Vector3.ZERO
	if arm_bone_idx < 0:
		return target_node.global_position

	var shoulder_world := _get_bone_world_position(arm_bone_idx)
	var target_basis := target_node.global_transform.basis.orthonormalized()
	var adjusted_offset := hold_offset
	adjusted_offset.z = hand_marker_depth_offset
	var desired_target := target_node.global_position + (target_basis * adjusted_offset)
	var adjusted_target := shoulder_world.lerp(desired_target, clampf(hand_target_pull, 0.0, 1.0))

	var to_target := adjusted_target - shoulder_world
	if to_target.length() > hand_max_reach:
		adjusted_target = shoulder_world + to_target.normalized() * hand_max_reach

	return adjusted_target


func _get_bone_world_position(bone_idx: int) -> Vector3:
	var bone_pose := _skeleton.get_bone_global_pose(bone_idx)
	return _skeleton.global_transform * bone_pose.origin


func _restore_bone_pose(bone_idx: int, rest_quat: Quaternion, delta: float = 1.0) -> void:
	if bone_idx >= 0:
		_blend_bone_pose_rotation(bone_idx, rest_quat, delta)


func _blend_bone_pose_rotation(bone_idx: int, target_rotation: Quaternion, delta: float) -> void:
	if bone_idx < 0:
		return
	var current_rotation := _skeleton.get_bone_pose_rotation(bone_idx)
	var blend_weight := clampf(delta * limb_pose_smoothing, 0.0, 1.0)
	_skeleton.set_bone_pose_rotation(bone_idx, current_rotation.slerp(target_rotation, blend_weight))


func apply_theme(theme_color: Color, outline_material: Material = null) -> void:
	_theme_color = theme_color
	_flash_tint = Color(1.0, 1.0, 1.0, 0.0)
	_outline_material = outline_material
	_refresh_themed_materials()


func set_outline_material(outline_material: Material) -> void:
	_outline_material = outline_material
	for mesh_instance in _body_meshes:
		mesh_instance.material_overlay = _outline_material


func set_outline_color(outline_color: Color) -> void:
	if _outline_material is ShaderMaterial:
		(_outline_material as ShaderMaterial).set_shader_parameter("color", outline_color)
	for mesh_instance in _body_meshes:
		mesh_instance.material_overlay = _outline_material


func flash_theme(color: Color, intensity: float, time_ms: float) -> void:
	_flash_tint = Color(color.r, color.g, color.b, clampf(intensity, 0.0, 1.0))
	_refresh_themed_materials()
	await get_tree().create_timer(time_ms / 1000.0).timeout
	_flash_tint = Color(1.0, 1.0, 1.0, 0.0)
	_refresh_themed_materials()


func _refresh_themed_materials() -> void:
	for mesh_instance in _body_meshes:
		var base_materials: Array = _mesh_base_materials.get(mesh_instance, [])
		for surface_idx in range(base_materials.size()):
			var base_material = base_materials[surface_idx]
			if base_material is StandardMaterial3D:
				var source_material := base_material as StandardMaterial3D
				var themed_material := source_material.duplicate() as StandardMaterial3D
				var tinted_albedo := source_material.albedo_color.lerp(_theme_color, 0.72)
				if _flash_tint.a > 0.0:
					tinted_albedo = tinted_albedo.lerp(Color(_flash_tint.r, _flash_tint.g, _flash_tint.b, 1.0), _flash_tint.a)
				themed_material.albedo_color = tinted_albedo
				themed_material.emission_enabled = true
				themed_material.emission = _theme_color.lerp(Color(_flash_tint.r, _flash_tint.g, _flash_tint.b, 1.0), minf(_flash_tint.a, 1.0))
				themed_material.emission_energy_multiplier = 0.2 + (_flash_tint.a * 0.9)
				themed_material.vertex_color_use_as_albedo = true
				mesh_instance.set_surface_override_material(surface_idx, themed_material)
		mesh_instance.material_overlay = _outline_material


# ─────────────────────────────────────────────
# IK de cabeza / cuello (procedural, sin nodo extra)
# ─────────────────────────────────────────────

## Rota el cuello y la cabeza para que el personaje mire hacia `look_target`.
## Se hace de forma procedural manipulando las poses de los huesos directamente,
## lo que permite controlar el peso de mezcla con precisión.
func _apply_head_look() -> void:
	if _head_bone < 0 or _neck_bone < 0:
		return

	# Sin objetivo → restaurar poses de reposo
	if look_target == null:
		_skeleton.set_bone_pose_rotation(_head_bone, _head_rest_quat)
		_skeleton.set_bone_pose_rotation(_neck_bone, _neck_rest_quat)
		return

	var head_global_pose: Transform3D = _skeleton.get_bone_global_pose(_head_bone)
	var target_in_skeleton: Vector3 = _skeleton.to_local(look_target.global_position)
	var dir_local: Vector3 = (target_in_skeleton - head_global_pose.origin).normalized()

	if dir_local.length_squared() < 0.0001:
		return

	var yaw := clampf(atan2(dir_local.x, -dir_local.z), -deg_to_rad(head_yaw_limit_degrees), deg_to_rad(head_yaw_limit_degrees))
	var horizontal_len := maxf(Vector2(dir_local.x, dir_local.z).length(), 0.001)
	var pitch := clampf(
		atan2(dir_local.y, horizontal_len) + deg_to_rad(head_pitch_offset_degrees),
		-deg_to_rad(head_pitch_limit_degrees),
		deg_to_rad(head_pitch_limit_degrees)
	)

	var head_delta := Quaternion.from_euler(Vector3(-pitch, yaw, 0.0))
	var neck_delta := Quaternion.from_euler(Vector3(-pitch * 0.45, yaw * 0.45, 0.0))

	# Mezclamos con la pose de reposo
	var final_quat: Quaternion = _head_rest_quat.slerp(_head_rest_quat * head_delta, head_look_weight)
	_skeleton.set_bone_pose_rotation(_head_bone, final_quat)

	# Cuello: gira la mitad para un movimiento más natural
	if _neck_bone >= 0:
		_skeleton.set_bone_pose_rotation(
			_neck_bone,
			_neck_rest_quat.slerp(_neck_rest_quat * neck_delta, head_look_weight * 0.45)
		)

## Devuelve la pose global del padre de un hueso (en espacio del esqueleto).
func _get_bone_parent_global_pose(bone_idx: int) -> Transform3D:
	var parent: int = _skeleton.get_bone_parent(bone_idx)
	if parent < 0:
		return Transform3D.IDENTITY
	return _skeleton.get_bone_global_pose(parent)


# ─────────────────────────────────────────────
# API de conveniencia para player.gd
# ─────────────────────────────────────────────

## Apunta la cabeza hacia una posición global (sin nodo). Crea un helper temporal.
func look_at_position(world_pos: Vector3) -> void:
	if _head_look_marker:
		_head_look_marker.global_position = world_pos
		look_target = _head_look_marker


## Activa el IK del brazo derecho y mueve el target a `world_pos`.
func move_right_hand_to(world_pos: Vector3) -> void:
	if _right_hand_ik_marker:
		_right_hand_ik_marker.global_position = world_pos
		right_hand_target = _right_hand_ik_marker


## Activa el IK del brazo izquierdo y mueve el target a `world_pos`.
func move_left_hand_to(world_pos: Vector3) -> void:
	if _left_hand_ik_marker:
		_left_hand_ik_marker.global_position = world_pos
		left_hand_target = _left_hand_ik_marker


## Desactiva todos los IK y restaura poses de reposo.
func reset_ik() -> void:
	look_target       = null
	right_hand_target = null
	left_hand_target  = null
	movement_velocity = Vector3.ZERO
	movement_input = Vector2.ZERO
	_apply_head_look()
	_restore_spine_pose()
	_restore_limb_pose()
	_set_arm_ik_active(false, false)
