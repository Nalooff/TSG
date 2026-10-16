extends PawnComponent
class_name MovementComponent

@export_group("Movement Rules")
@export var orthogonal_cost: int = 1
@export var diagonal_cost: int = 1
@export var climb_max: int = 1
@export var descent_max: int = 2
@export var use_los: bool = true

@export_group("Commander & Command Range")
## Distance in tiles this unit projects command authority (0 means not a commander).
@export var command_radius: int = 0

## If true, this unit suffers movement penalties when out of allied command range.
@export var can_be_disrupted: bool = true

# ==========================================================
# PUBLIC API
# ==========================================================

## Calculates available Movement Points, taking disruption penalties into account.
func get_effective_mp(board_state: BoardState) -> int:
	var mp = pawn.base_mp
	if can_be_disrupted and board_state.is_unit_disrupted(pawn):
		@warning_ignore("integer_division")
		mp = max(1, mp / 2)
	return mp

## Checks if a target position falls within this commander's authority radius.
func is_in_command_range(target_pos: Vector2i) -> bool:
	if command_radius <= 0:
		return false
	var dist = max(abs(target_pos.x - pawn.grid_pos.x), abs(target_pos.y - pawn.grid_pos.y))
	return dist <= command_radius

## Checks if there is an unobstructed line of sight between p_start and p_end based on elevation thresholds.
func has_line_of_sight(board_state: BoardState, p_start: Vector2i, p_end: Vector2i) -> bool:
	var D = max(abs(p_end.x - p_start.x), abs(p_end.y - p_start.y))
	if D <= 1:
		return true

	var h_start = board_state.get_height_at(p_start)
	var h_end = board_state.get_height_at(p_end)
	var inv_D = 1.0 / float(D)

	for step in range(1, D):
		var factor = float(step) * inv_D
		var t_i = Vector2i(
			round(lerp(float(p_start.x), float(p_end.x), factor)),
			round(lerp(float(p_start.y), float(p_end.y), factor))
		)
		
		var d_i = max(abs(t_i.x - p_start.x), abs(t_i.y - p_start.y))
		var raw_h_los = float(h_start) + (float(d_i) * inv_D) * float(h_end - h_start)
		
		if board_state.get_height_at(t_i) > round(raw_h_los):
			return false

	return true

func get_reachable_paths(board_state: BoardState) -> Dictionary:
	var total_mp = get_effective_mp(board_state)
	var raw_paths = _calculate_reachable_tiles(board_state, total_mp)
	
	if not use_los:
		return raw_paths
		
	var valid_paths: Dictionary = {}
	for dest in raw_paths.keys():
		if has_line_of_sight(board_state, pawn.grid_pos, dest):
			valid_paths[dest] = raw_paths[dest]
			
	return valid_paths

func get_path_to_tile(board_state: BoardState, destination: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var paths := get_reachable_paths(board_state)
	if paths.has(destination):
		result.assign(paths[destination]["path"])
	return result

func get_valid_moves(board_state: BoardState) -> Array[Vector2i]:
	var paths = get_reachable_paths(board_state)
	var valid_moves: Array[Vector2i] = []
	valid_moves.assign(paths.keys())
	return valid_moves

# ==========================================================
# OVERRIDABLE HOOKS
# ==========================================================

func _get_allowed_directions() -> Array[Vector2i]:
	return [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]

func _calculate_step_cost(_board: BoardState, from_pos: Vector2i, to_pos: Vector2i, curr_h: int, next_h: int, _state: Dictionary) -> int:
	var delta_h = next_h - curr_h
	if delta_h > climb_max or delta_h < -descent_max:
		return -1

	var dir = to_pos - from_pos
	var is_diagonal = (abs(dir.x) + abs(dir.y) == 2)
	return diagonal_cost if is_diagonal else orthogonal_cost

func _is_step_allowed(_board: BoardState, _from: Vector2i, _to: Vector2i, _dir: Vector2i, _state: Dictionary) -> bool:
	return true

func _on_step_entered(_board: BoardState, _pos: Vector2i, _state: Dictionary) -> void:
	pass

# ==========================================================
# DIJKSTRA ENGINE
# ==========================================================

func _calculate_reachable_tiles(board_state: BoardState, start_mp: int) -> Dictionary:
	var visited = {}
	var results = {}   # pos -> { "cost": int, "path": Array }
	var pq = PriorityQueue.new()
	var allowed_directions = _get_allowed_directions()

	var enemy_zocs = board_state.cache_enemy_zocs_for(pawn)

	pq.push({
		"pos": pawn.grid_pos,
		"mp": start_mp,
		"cost": 0,
		"climbs": 0,
		"path": [pawn.grid_pos]
	}, 0)

	while not pq.is_empty():
		var current: Dictionary = pq.pop()
		var curr_pos: Vector2i = current["pos"]
		var curr_cost: int = current["cost"]

		if visited.has(curr_pos) and visited[curr_pos] < curr_cost:
			continue
			
		visited[curr_pos] = curr_cost

		# remember the best path found for this tile
		if not results.has(curr_pos) or curr_cost < results[curr_pos]["cost"]:
			results[curr_pos] = {"cost": curr_cost, "path": current["path"]}

		for dir in allowed_directions:
			var next_pos = curr_pos + dir
			
			if not board_state.is_valid_tile(next_pos):
				continue
				
			if not _is_step_allowed(board_state, curr_pos, next_pos, dir, current):
				continue

			if board_state.is_occupied(next_pos):
				continue
				
			var curr_h = board_state.get_height_at(curr_pos)
			var next_h = board_state.get_height_at(next_pos)
			
			var step_cost = _calculate_step_cost(board_state, curr_pos, next_pos, curr_h, next_h, current)
			if step_cost < 0:
				continue
				
			var next_cost = curr_cost + step_cost
			if next_cost > start_mp:
				continue

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
			board_state.process_cached_zoc_interceptions(pawn, curr_pos, next_pos, next_state, enemy_zocs)
			
			pq.push(next_state, next_cost)

	results.erase(pawn.grid_pos)
	return results


class PriorityQueue:
	var heap: Array = []

	func push(element: Dictionary, priority: int) -> void:
		heap.append({"item": element, "priority": priority})
		_up_heap(heap.size() - 1)

	func pop() -> Dictionary:
		if heap.is_empty():
			return {}
		var top = heap[0]["item"]
		var last = heap.pop_back()
		if not heap.is_empty():
			heap[0] = last
			_down_heap(0)
		return top

	func is_empty() -> bool:
		return heap.is_empty()

	func _up_heap(index: int) -> void:
		while index > 0:
			@warning_ignore("integer_division")
			var parent = (index - 1) / 2
			if heap[index]["priority"] < heap[parent]["priority"]:
				var temp = heap[index]
				heap[index] = heap[parent]
				heap[parent] = temp
				index = parent
			else:
				break

	func _down_heap(index: int) -> void:
		var size = heap.size()
		while true:
			var left = 2 * index + 1
			var right = 2 * index + 2
			var smallest = index

			if left < size and heap[left]["priority"] < heap[smallest]["priority"]:
				smallest = left
			if right < size and heap[right]["priority"] < heap[smallest]["priority"]:
				smallest = right

			if smallest != index:
				var temp = heap[index]
				heap[index] = heap[smallest]
				heap[smallest] = temp
				index = smallest
			else:
				break
