extends Node3D

@onready var grid: Grid = get_parent() as Grid

var _last_gx: int = -1
var _last_gz: int = -1
var _last_hovered_pawn: BasePawn = null

func _process(_delta: float) -> void:
	# Guard: Only process during active gameplay or build modes
	if Global.current_mode == GData.GameMode.MENU or Global.current_mode == GData.GameMode.NONE:
		return
	
	_update_hover_state()

func _update_hover_state() -> void:
	var cam = get_viewport().get_camera_3d()
	if not cam or not grid: return

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = cam.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + cam.project_ray_normal(mouse_pos) * 2000.0

	# 1. Determine Raycast Mask based on active sub-mode
	var mask: int = 0
	
	if Global.current_mode == GData.GameMode.BUILD or (Global.current_mode == GData.GameMode.PLAY and Global.current_play_mode == GData.PlayMode.MOVE):
		# Tile-only raycast (movement destination or building map)
		mask = GData.TILE.COLLISION_LAYER_BITMASK
	elif Global.current_mode == GData.GameMode.PLAY and Global.current_play_mode == GData.PlayMode.SELECT:
		# Unit selection: Pawns + Tiles (so elevated walls block units behind them)
		mask = GData.PAWN.COLLISION_LAYER_BITMASK | GData.TILE.COLLISION_LAYER_BITMASK

	if mask == 0:
		_clear_hover_states()
		return

	# 2. Perform Raycast
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, mask)
	query.collide_with_areas = true
	var hit = grid.get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return
	
	var hit_type : CollisionObject3D = hit.collider
	
	# 3. Process Raycast Result
	if hit_type.owner is BasePawn:
		_notify_pawn_hover(hit_type.owner as BasePawn)
		_clear_tile_hover()
	else:
		_notify_tile_hover(hit)
		_clear_pawn_hover()

# --- Helper State Broadcasters ---

func _notify_pawn_hover(pawn: BasePawn) -> void:
	if pawn != _last_hovered_pawn:
		_last_hovered_pawn = pawn
		EventBus.pawn_hovered.emit(pawn)

func _notify_tile_hover(hit: Dictionary) -> void:
	var sample_pos = hit.position + (hit.normal * (0.1 if hit.normal.y <= 0.5 else -0.1))
	var grid_coord = Global.board.world_to_grid_2d(sample_pos)
	
	# Clamp to board dimensions safely
	var gx = clampi(grid_coord.x, 0, Global.board.width - 1)
	var gz = clampi(grid_coord.y, 0, Global.board.depth - 1)

	if gx != _last_gx or gz != _last_gz:
		_last_gx = gx
		_last_gz = gz
		EventBus.tile_hovered.emit({
			"grid_pos": Vector2i(gx, gz),
			"normal": hit.normal,
			"position": hit.position,
			"collider": hit.collider
		})

func _clear_pawn_hover() -> void:
	if _last_hovered_pawn != null:
		_last_hovered_pawn = null
		EventBus.pawn_hovered.emit(null)

func _clear_tile_hover() -> void:
	_last_gx = -1
	_last_gz = -1

func _clear_hover_states() -> void:
	_clear_pawn_hover()
	_clear_tile_hover()
