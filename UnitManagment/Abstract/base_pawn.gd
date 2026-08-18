extends Node3D
class_name BasePawn

@export_group("Base Stats")
## Team/Faction identifier to distinguish friendly from enemy units.
@export var team_id: int = 0

## Default base Movement Points available to this pawn per turn.
@export var base_mp: int = 3

@export_group("Classification & Tags")
## Tags defining this pawn's characteristics (e.g. ["fast_unit", "cavalry", "armored"]).
@export var tags: Array[String] = []

@export_group("Movement Costs")
## Cost to move 1 tile orthogonally (Up, Down, Left, Right).
@export var orthogonal_cost: int = 1

## Cost to move 1 tile diagonally.
@export var diagonal_cost: int = 1

@export_group("Commander Panel")
## Distance in tiles this unit projects command authority (0 means not a commander).
@export var command_radius: int = 0

## If true, this unit suffers movement penalties when out of allied command range.
@export var can_be_disrupted: bool = true

## Internal toggle for Line of Sight checking during target/move validation.
var _use_los: bool = true

## Current 2D tile position on the board matrix (X, Z).
var grid_pos: Vector2i

## Cached reflection map binding target tags to their respective "get_zoc_" getter methods.
var _zoc_getters_cache: Dictionary = {}

## Cached reflection map binding target tags to their respective "zoc_effect_" reaction methods.
var _zoc_effects_cache: Dictionary = {}


func _ready() -> void:
	if EventBus.has_signal("camera_changed"):
		EventBus.connect("camera_changed", _on_cam_changed)
	_build_zoc_reflection_cache()

## Scans and caches all "get_zoc_" and "zoc_effect_" methods once to eliminate slow runtime reflection.
func _build_zoc_reflection_cache() -> void:
	_zoc_getters_cache.clear()
	_zoc_effects_cache.clear()
	
	for method_info in get_method_list():
		var m_name: String = method_info["name"]
		if m_name.begins_with("get_zoc_"):
			var target_tag = m_name.trim_prefix("get_zoc_")
			_zoc_getters_cache[target_tag] = m_name
		elif m_name.begins_with("zoc_effect_"):
			var target_tag = m_name.trim_prefix("zoc_effect_")
			_zoc_effects_cache[target_tag] = m_name

# ==========================================================
# PUBLIC API
# ==========================================================

## Checks if this pawn possesses a given classification tag.
func has_tag(tag_id: String) -> bool:
	return tags.has(tag_id)

## Returns all tile positions this pawn can legitimately reach this turn, accounting for MP, terrain, and LOS.
func get_valid_moves(board_state: BoardState) -> Array[Vector2i]:
	var valid_moves: Array[Vector2i] = []
	var total_mp = get_effective_mp(board_state)
	
	var reachable_paths = _calculate_reachable_tiles(board_state, total_mp)
	
	for dest in reachable_paths.keys():
		if not _use_los or has_line_of_sight(board_state, grid_pos, dest):
			valid_moves.append(dest)
			
	return valid_moves

## Calculates current available Movement Points, taking disruption penalties into account.
func get_effective_mp(board_state: BoardState) -> int:
	var mp = base_mp
	if board_state.is_unit_disrupted(self):
		mp = max(1, mp / 2)
	return mp

## Checks if a target grid position falls within this commander's authority radius.
func is_in_command_range(target_pos: Vector2i) -> bool:
	if command_radius <= 0:
		return false
	var dist = max(abs(target_pos.x - grid_pos.x), abs(target_pos.y - grid_pos.y))
	return dist <= command_radius

# ==========================================================
# OVERRIDABLE MOVEMENT HOOKS
# ==========================================================

## Returns the directional vectors this pawn is allowed to explore (defaults to 8-way movement).
func _get_allowed_directions() -> Array[Vector2i]:
	return [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]

## Calculates the MP cost to move from one tile to an adjacent tile based on direction and elevation change.
func _calculate_step_cost(_board: BoardState, from: Vector2i, to: Vector2i, curr_h: int, next_h: int, _state: Dictionary) -> int:
	var delta_h = next_h - curr_h
	if delta_h > 1 or delta_h < -2:
		return -1

	var dir = to - from
	var is_diagonal = (abs(dir.x) + abs(dir.y) == 2)
	return diagonal_cost if is_diagonal else orthogonal_cost

## Subclass hook to enforce directional locks, movement path constraints, or mid-movement stops.
func _is_step_allowed(_board: BoardState, _from: Vector2i, _to: Vector2i, _dir: Vector2i, _state: Dictionary) -> bool:
	return true

## Subclass hook executed when entering a step (e.g., zeroing remaining MP upon interception).
func _on_step_entered(_board: BoardState, _pos: Vector2i, _state: Dictionary) -> void:
	pass

# ==========================================================
# FAST ZONE OF CONTROL (ZOC) REFLECTION
# ==========================================================

## Evaluates cached "get_zoc_<tag>" methods matching the asking unit's tags to return active ZoC coverage.
func get_zones_of_control(board_state: BoardState, asking_unit: BasePawn) -> Dictionary:
	var result = {}
	if asking_unit == null or asking_unit == self:
		return result

	for target_tag in _zoc_getters_cache:
		if asking_unit.has_tag(target_tag):
			var m_name: String = _zoc_getters_cache[target_tag]
			var tiles = call(m_name, board_state, asking_unit)
			if tiles is Array and tiles.size() > 0:
				var typed_tiles: Array[Vector2i] = []
				for t in tiles:
					if t is Vector2i:
						typed_tiles.append(t)
				
				result[target_tag] = {
					"team_id": team_id,
					"source_unit": self,
					"tiles": typed_tiles
				}

	return result

## Triggers the corresponding "zoc_effect_<tag>" callback when an enemy enters a controlled tile.
func trigger_zoc_effect(tag: String, moving_unit: BasePawn, from_pos: Vector2i, to_pos: Vector2i, state: Dictionary) -> void:
	if _zoc_effects_cache.has(tag):
		call(_zoc_effects_cache[tag], moving_unit, from_pos, to_pos, state)

# ==========================================================
# OPTIMIZED DIJKSTRA PATHFINDING ENGINE
# ==========================================================

## Dijkstra flood-fill algorithm using a binary min-heap priority queue to compute all reachable tiles within MP limit.
func _calculate_reachable_tiles(board_state: BoardState, start_mp: int) -> Dictionary:
	var visited = {}
	var pq = PriorityQueue.new()
	var allowed_directions = _get_allowed_directions()

	var enemy_zocs = board_state.cache_enemy_zocs_for(self)

	pq.push({
		"pos": grid_pos,
		"mp": start_mp,
		"cost": 0,
		"climbs": 0,
		"path": [grid_pos]
	}, 0)

	while not pq.is_empty():
		var current: Dictionary = pq.pop()
		var curr_pos: Vector2i = current["pos"]
		var curr_cost: int = current["cost"]

		if visited.has(curr_pos) and visited[curr_pos] < curr_cost:
			continue
			
		visited[curr_pos] = curr_cost

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
			board_state.process_cached_zoc_interceptions(self, curr_pos, next_pos, next_state, enemy_zocs)
			
			pq.push(next_state, next_cost)

	visited.erase(grid_pos)
	return visited

# ==========================================================
# LINE OF SIGHT (LOS)
# ==========================================================

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

## Signal callback adapting 2D billboard presentation according to camera view type.
func _on_cam_changed(cam: Camera3D):
	if has_node("Sprite3D"):
		$Sprite3D.billboard = BaseMaterial3D.BILLBOARD_ENABLED if cam.name == "View2D" else BaseMaterial3D.BILLBOARD_FIXED_Y

# ==========================================================
# HELPER BINARY MIN-HEAP (PRIORITY QUEUE)
# ==========================================================

## High-performance Binary Min-Heap Priority Queue used to speed up Dijkstra pathfinding.
class PriorityQueue:
	## Internal element storage array holding dictionary objects with priority values.
	var heap: Array = []

	## Inserts an element into the priority queue and reorganizes the heap tree upwards.
	func push(element: Dictionary, priority: int) -> void:
		heap.append({"item": element, "priority": priority})
		_up_heap(heap.size() - 1)

	## Removes and returns the element with the lowest priority value (top of heap).
	func pop() -> Dictionary:
		if heap.is_empty():
			return {}
		var top = heap[0]["item"]
		var last = heap.pop_back()
		if not heap.is_empty():
			heap[0] = last
			_down_heap(0)
		return top

	## Returns true if the queue contains no elements.
	func is_empty() -> bool:
		return heap.is_empty()

	## Bubbles an element up the tree to maintain min-heap ordering.
	func _up_heap(index: int) -> void:
		while index > 0:
			var parent = (index - 1) / 2
			if heap[index]["priority"] < heap[parent]["priority"]:
				var temp = heap[index]
				heap[index] = heap[parent]
				heap[parent] = temp
				index = parent
			else:
				break

	## Sinks an element down the tree to maintain min-heap ordering.
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
