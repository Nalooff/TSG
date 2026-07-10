extends Node3D
class_name BlockPreview

# Set this to change cursor layout dynamically (e.g., Vector3i(1,1,1), Vector3i(2,2,2), Vector3i(3,3,3))
@export var preview_size: Vector3i = Vector3i(1, 1, 1):
	set(value):
		preview_size = value
		_update_preview_mesh_dimensions()

@onready var grid: Grid = get_parent()

var current_cam: Camera3D
var preview_instance: MeshInstance3D
var valid_mat: StandardMaterial3D
var invalid_mat: StandardMaterial3D

func _ready() -> void:
	EventBus.connect("camera_changed", func(cam): current_cam = cam)
	_setup_materials()
	_build_preview_node()

func _setup_materials() -> void:
	valid_mat = StandardMaterial3D.new()
	valid_mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)
	valid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	invalid_mat = StandardMaterial3D.new()
	invalid_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.4)
	invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _build_preview_node() -> void:
	preview_instance = MeshInstance3D.new()
	preview_instance.mesh = BoxMesh.new()
	_update_preview_mesh_dimensions()
	add_child(preview_instance)

func _update_preview_mesh_dimensions() -> void:
	if not preview_instance: return
	(preview_instance.mesh as BoxMesh).size = Vector3(preview_size) * grid.CELL_SIZE

func _process(_delta: float) -> void:
	if not current_cam or not preview_instance: return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var drop_plane = Plane(Vector3.UP, 0.0)
	var ray_origin = current_cam.project_ray_origin(mouse_pos)
	var ray_dir = current_cam.project_ray_normal(mouse_pos)
	var hit = drop_plane.intersects_ray(ray_origin, ray_dir)
	
	if hit:
		var gx = clampi(int(floor(hit.x / grid.CELL_SIZE)), 0, grid.GRID_WIDTH - 1)
		var gz = clampi(int(floor(hit.z / grid.CELL_SIZE)), 0, grid.GRID_DEPTH - 1)
		
		# Offset center point calculation relative to multiblock sizes
		var offset_x = (preview_size.x * grid.CELL_SIZE) / 2.0
		var offset_z = (preview_size.z * grid.CELL_SIZE) / 2.0
		
		# Read directly from database matrix to snap visual preview accurately on top of hills
		var terrain_height = grid.get_height_at(gx, gz)
		var py = ((terrain_height + 1) * grid.CELL_SIZE) + ((preview_size.y * grid.CELL_SIZE) / 2.0)
		
		preview_instance.global_position = Vector3(
			(gx * grid.CELL_SIZE) + offset_x,
			py,
			(gz * grid.CELL_SIZE) + offset_z
		)
		
		# Boundary alignment validation
		var is_valid = (gx + preview_size.x <= grid.GRID_WIDTH) and (gz + preview_size.z <= grid.GRID_DEPTH)
		preview_instance.material_override = valid_mat if is_valid else invalid_mat
