extends Node3D
class_name BasePawn

@export_group("Base Stats")
@export var team_id: int = 0
@export var base_mp: int = 3

@export_group("Classification & Tags")
## Tags defining this pawn's characteristics (e.g. ["fast_unit", "cavalry", "armored"])
@export var tags: Array[String] = []

@export_group("Movement Costs")
## Cost to move 1 tile orthogonally (Up, Down, Left, Right)
@export var orthogonal_cost: int = 1
## Cost to move 1 tile diagonally
@export var diagonal_cost: int = 1

@export_group("Commander Panel")
@export var command_radius: int = 0 # 0 means not a commander
@export var can_be_disrupted: bool = true

var _use_los: bool = true

var grid_pos: Vector2i

func _ready():
	EventBus.camera_changed.connect(_on_cam_changed)

# ==========================================================
# PUBLIC API
# ==========================================================

## Helper to check if this pawn contains a specific classification tag.
func has_tag(tag_id: String) -> bool:
	return tags.has(tag_id)

## Returns all tiles this pawn can legitimately reach this turn.
func get_valid_moves(board_state: BoardState) -> Array[Vector2i]:
	var valid_moves: Array[Vector2i] = []
	var total_mp = get_effective_mp(board_state)
	
	# 1. Dijkstra Pathfinding driven by subclass rules
	var reachable_paths = _calculate_reachable_tiles(board_state, total_mp)
	
	# 2. Filter destinations against Line of Sight (LOS) Rule
	for dest in reachable_paths.keys():
		if not _use_los or has_line_of_sight(board_state, grid_pos, dest):
			valid_moves.append(dest)
	
	return valid_moves

## Standard Disruption penalty check (Chapter VI). Override in subclass for extra turn-start penalties.
func get_effective_mp(board_state: BoardState) -> int:
	var mp = base_mp
	if board_state.is_unit_disrupted(self):
		mp = max(1, mp / 2) # Halved, rounded down, min 1
	return mp

func is_in_command_range(target_pos: Vector2i) -> bool:
	if command_radius <= 0:
		return false
	var dist = max(abs(target_pos.x - grid_pos.x), abs(target_pos.y - grid_pos.y))
	return dist <= command_radius

# ==========================================================
# OVERRIDABLE MOVEMENT HOOKS (FOR SUBCLASSES)
# ==========================================================

## Subclasses specify which directions they can test (default: 8-directional).
func _get_allowed_directions() -> Array[Vector2i]:
	return [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]

## Calculates step MP cost based on direction and terrain elevation.
func _calculate_step_cost(_board: BoardState, from: Vector2i, to: Vector2i, curr_h: int, next_h: int, _state: Dictionary) -> int:
	var delta_h = next_h - curr_h
	if delta_h > 1 or delta_h < -2:
		return -1 # Invalid default step height

	var dir = to - from
	var is_diagonal = (abs(dir.x) + abs(dir.y) == 2)

	return diagonal_cost if is_diagonal else orthogonal_cost

## Subclasses override this to enforce direction locks (e.g. Artillery straight line lock), path constraints, or mid-movement stops.
func _is_step_allowed(_board: BoardState, _from: Vector2i, _to: Vector2i, _dir: Vector2i, _state: Dictionary) -> bool:
	return true

## Hook called when entering a step. Allows subclasses to modify state (e.g., zero remaining MP on interception).
func _on_step_entered(_board: BoardState, _pos: Vector2i, _state: Dictionary) -> void:
	pass

# ==========================================================
# DYNAMIC ZONE OF CONTROL (ZOC) REFLECTION REFLEXES
# ==========================================================

## Evaluates all methods matching "get_zoc_<tag>" that match the asking_unit's tags.
## Returns a Dictionary mapping tag -> { "team_id": int, "source_unit": BasePawn, "tiles": Array[Vector2i] }
func get_zones_of_control(board_state: BoardState, asking_unit: BasePawn) -> Dictionary:
	var result = {}
	if asking_unit == null or asking_unit == self:
		return result

	# Scan all functions on this instance
	for method_info in get_method_list():
		var m_name: String = method_info["name"]
		if m_name.begins_with("get_zoc_"):
			var target_tag = m_name.trim_prefix("get_zoc_")
			
			# If the asking unit carries the matching tag, run the function
			if asking_unit.has_tag(target_tag):
				var tiles = call(m_name, board_state, asking_unit)
				if tiles is Array and tiles.size() > 0:
					var typed_tiles: Array[Vector2i] = []
					for t in tiles:
						if t is Vector2i:
							typed_tiles.append(t)
					
					# Store team ownership and source unit alongside the tile list
					result[target_tag] = {
						"team_id": team_id,
						"source_unit": self,
						"tiles": typed_tiles
					}

	return result

## Triggers matching "zoc_effect_<tag>" method when an enemy enters a targeted ZoC tile.
func trigger_zoc_effect(tag: String, moving_unit: BasePawn, from_pos: Vector2i, to_pos: Vector2i, state: Dictionary) -> void:
	var func_name = "zoc_effect_" + tag
	if has_method(func_name):
		call(func_name, moving_unit, from_pos, to_pos, state)

# ==========================================================
# CORE DIJKSTRA PATHFINDING ENGINE
# ==========================================================

func _calculate_reachable_tiles(board_state: BoardState, start_mp: int) -> Dictionary:
	# Tracks pos -> lowest cost recorded to reach it
	var visited = {}
	
	var queue: Array[Dictionary] = []
	queue.append({
		"pos": grid_pos,
		"mp": start_mp,
		"cost": 0,
		"climbs": 0,
		"path": [grid_pos]
	})
	
	var allowed_directions = _get_allowed_directions()

	while queue.size() > 0:
		# Process node with lowest accumulated cost first (Dijkstra)
		queue.sort_custom(func(a, b): return a["cost"] < b["cost"])
		var current = queue.pop_front()
		
		var curr_pos: Vector2i = current["pos"]
		var curr_cost: int = current["cost"]

		# If we've already settled this tile at a lower or equal cost, skip expansion
		if visited.has(curr_pos) and visited[curr_pos] < curr_cost:
			continue
			
		visited[curr_pos] = curr_cost

		for dir in allowed_directions:
			var next_pos = curr_pos + dir
			
			if not board_state.is_valid_tile(next_pos):
				continue
				
			if not _is_step_allowed(board_state, curr_pos, next_pos, dir, current):
				continue

			var occupant = board_state.get_unit_at(next_pos)
			if occupant != null:
				continue # Occupied tiles block movement
				
			var curr_h = board_state.get_height_at(curr_pos)
			var next_h = board_state.get_height_at(next_pos)
			
			var step_cost = _calculate_step_cost(board_state, curr_pos, next_pos, curr_h, next_h, current)
			if step_cost < 0:
				continue # Invalid step height/terrain
				
			var next_cost = curr_cost + step_cost
			if next_cost > start_mp:
				continue # Exceeds available MP

			# Don't add to queue if we already have a cheaper route to next_pos
			if visited.has(next_pos) and visited[next_pos] <= next_cost:
				continue

			var next_path = current["path"].duplicate()
			next_path.append(next_pos)
			
			var next_state = {
				"pos": next_pos,
				"mp": start_mp - next_cost,
				"cost": next_cost,
				"climbs": current["climbs"] + (1 if next_h > curr_h else 0),
				"path": next_path
			}

			_on_step_entered(board_state, next_pos, next_state)
			board_state.process_zoc_interceptions(self, curr_pos, next_pos, next_state)
			queue.append(next_state)

	visited.erase(grid_pos) # Starting tile is not a valid movement destination
	return visited

# ==========================================================
# CHAPTER I: LINE OF SIGHT (LOS) ENGINE
# ==========================================================

func has_line_of_sight(board_state: BoardState, p_start: Vector2i, p_end: Vector2i) -> bool:
	var D = max(abs(p_end.x - p_start.x), abs(p_end.y - p_start.y))
	if D <= 1:
		return true # Adjacent tiles always have LOS

	var h_start = board_state.get_height_at(p_start)
	var h_end = board_state.get_height_at(p_end)

	for step in range(1, D):
		var t_i = Vector2i(
			round(lerp(float(p_start.x), float(p_end.x), float(step) / D)),
			round(lerp(float(p_start.y), float(p_end.y), float(step) / D))
		)
		
		var d_i = max(abs(t_i.x - p_start.x), abs(t_i.y - p_start.y))
		var raw_h_los = float(h_start) + (float(d_i) / float(D)) * float(h_end - h_start)
		var h_los_threshold = round(raw_h_los)
		
		if board_state.get_height_at(t_i) > h_los_threshold:
			return false

	return true

# ==========================================================
# CAMERA HANDLING
# ==========================================================

func _on_cam_changed(cam: Camera3D):
	if has_node("Sprite3D"):
		$Sprite3D.billboard = BaseMaterial3D.BILLBOARD_ENABLED if cam.name == "View2D" else BaseMaterial3D.BILLBOARD_FIXED_Y
