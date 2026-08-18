extends Node3D
class_name BasePawn

@export_group("Base Stats")
@export var team_id: int = 0
@export var base_mp: int = 3

var grid_pos: Vector2i

func _ready():
	if EventBus.has_signal("camera_changed"):
		EventBus.connect("camera_changed", _on_cam_changed)

# ==========================================================
# PUBLIC API
# ==========================================================

## Returns all tiles this pawn can legitimately reach this turn.
func get_valid_moves(board_state: BoardState) -> Array[Vector2i]:
	var valid_moves: Array[Vector2i] = []
	var total_mp = get_effective_mp(board_state)
	
	# 1. Dijkstra Pathfinding driven by subclass rules
	var reachable_paths = _calculate_reachable_tiles(board_state, total_mp)
	
	# 2. Filter destinations against Chapter I Line of Sight (LOS) Rule
	for dest in reachable_paths.keys():
		if has_line_of_sight(board_state, grid_pos, dest):
			valid_moves.append(dest)
			
	return valid_moves

## Standard Disruption penalty check (Chapter VI). Override in subclass for extra turn-start penalties.
func get_effective_mp(board_state: BoardState) -> int:
	var mp = base_mp
	if board_state.is_unit_disrupted(self):
		mp = max(1, mp / 2) # Halved, rounded down, min 1
	return mp

# ==========================================================
# OVERRIDABLE MOVEMENT HOOKS (FOR SUBCLASSES)
# ==========================================================

## Subclasses specify which directions they can test (default: 8-directional).
func _get_allowed_directions() -> Array[Vector2i]:
	return [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]

## Subclasses calculate step MP cost. Return -1 if the step is illegal (e.g., wall too high).
func _calculate_step_cost(_board: BoardState, _from: Vector2i, _to: Vector2i, curr_h: int, next_h: int, _state: Dictionary) -> int:
	var delta_h = next_h - curr_h
	if delta_h > 1 or delta_h < -2:
		return -1 # Invalid default step height
	return 1

## Subclasses override this to enforce direction locks, path constraints, or mid-movement stops.
func _is_step_allowed(_board: BoardState, _from: Vector2i, _to: Vector2i, _dir: Vector2i, _state: Dictionary) -> bool:
	return true

## Hook called when entering a step. Allows subclasses to modify state (e.g., zero remaining MP on interception).
func _on_step_entered(_board: BoardState, _pos: Vector2i, _state: Dictionary) -> void:
	pass

# ==========================================================
# CORE DIJKSTRA PATHFINDING ENGINE
# ==========================================================

func _calculate_reachable_tiles(board_state: BoardState, start_mp: int) -> Dictionary:
	# Dictionary mapping destination (Vector2i) -> minimum MP remaining
	var visited = {}
	
	# Open set elements track: pos, remaining MP, climbs count, and path history
	var queue: Array[Dictionary] = []
	queue.append({
		"pos": grid_pos,
		"mp": start_mp,
		"climbs": 0,
		"path": [grid_pos]
	})
	
	var allowed_directions = _get_allowed_directions()

	while queue.size() > 0:
		# Process node with the most remaining MP first
		queue.sort_custom(func(a, b): return a["mp"] > b["mp"])
		var current = queue.pop_front()
		
		var curr_pos: Vector2i = current["pos"]
		var curr_mp: int = current["mp"]

		if visited.has(curr_pos) and visited[curr_pos] >= curr_mp:
			continue
			
		visited[curr_pos] = curr_mp

		# Stop exploring outward from this tile if MP is exhausted
		if curr_mp <= 0:
			continue

		for dir in allowed_directions:
			var next_pos = curr_pos + dir
			
			if not board_state.is_valid_tile(next_pos):
				continue
				
			# Check custom movement constraints (e.g., straight-line lock)
			if not _is_step_allowed(board_state, curr_pos, next_pos, dir, current):
				continue

			var occupant = board_state.get_unit_at(next_pos)
			if occupant != null:
				continue # Occupied tiles block movement
				
			var curr_h = board_state.get_height_at(curr_pos)
			var next_h = board_state.get_height_at(next_pos)
			
			# Calculate step cost via subclass rules
			var step_cost = _calculate_step_cost(board_state, curr_pos, next_pos, curr_h, next_h, current)
			if step_cost < 0 or curr_mp < step_cost:
				continue # Step impossible or not enough MP
				
			# Construct next search state
			var next_path = current["path"].duplicate()
			next_path.append(next_pos)
			
			var next_state = {
				"pos": next_pos,
				"mp": curr_mp - step_cost,
				"climbs": current["climbs"] + (1 if next_h > curr_h else 0),
				"path": next_path
			}

			# Allow subclass to alter state upon entering tile (e.g. Spikeman Interception)
			_on_step_entered(board_state, next_pos, next_state)

			queue.append(next_state)

	visited.erase(grid_pos) # Starting tile is not a valid movement target
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
