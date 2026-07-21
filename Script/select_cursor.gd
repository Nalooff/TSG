extends Node3D

@onready var grid: Grid = get_parent() as Grid

# Cache the last emitted tile coordinates to prevent unnecessary signal spam
var _last_gx: int = -1
var _last_gz: int = -1

func _process(_delta: float) -> void:
	var tile_info = _get_hovered_tile()
	
	# If ray hits nothing, retain the last valid tile state and do nothing
	if tile_info.is_empty():
		return

	var current_pos: Vector2i = tile_info["grid_pos"]

	# Only emit if we have moved to a DIFFERENT valid tile
	if current_pos.x != _last_gx or current_pos.y != _last_gz:
		_last_gx = current_pos.x
		_last_gz = current_pos.y
		EventBus.tile_hovered.emit(tile_info)

## Performs a mouse raycast and resolves the targeted 1x1 grid cell.
func _get_hovered_tile(max_distance: float = 2000.0) -> Dictionary:
	var cam = get_viewport().get_camera_3d()
	if not cam or not grid: return {}

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = cam.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + cam.project_ray_normal(mouse_pos) * max_distance

	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, GData.TILE.COLLISION_LAYER_BITMASK)
	var hit = grid.get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return {}

	# Small bias using normal to ensure ray inside-surface sampling accuracy
	var sample_pos = hit.position + (hit.normal * (0.1 if hit.normal.y <= 0.5 else -0.1))
	var gx = clampi(int(floor(sample_pos.x / grid.CELL_SIZE)), 0, grid.GRID_WIDTH - 1)
	var gz = clampi(int(floor(sample_pos.z / grid.CELL_SIZE)), 0, grid.GRID_DEPTH - 1)

	return {
		"grid_pos": Vector2i(gx, gz),
		"normal": hit.normal,
		"position": hit.position,
		"collider": hit.collider
	}
