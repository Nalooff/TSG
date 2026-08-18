extends RefCounted
class_name BoardState

## Width dimension of the grid (number of columns along X).
var width: int

## Depth dimension of the grid (number of rows along Z).
var depth: int

## World size scale factor for each tile cell.
var cell_size: float

## Flattened 1D array storing grid cell heights (-1 for void/unreachable, 0+ for ground levels).
var matrix: PackedInt32Array = PackedInt32Array()

## Spatial lookup dictionary mapping Vector2i coordinates to BasePawn instances.
var unit_matrix: Dictionary = {}

## Initializes grid dimensions and allocates memory for the height matrix.
func _init(p_width: int, p_depth: int, p_cell_size: float) -> void:
	width = p_width
	depth = p_depth
	cell_size = p_cell_size
	
	matrix.resize(width * depth)
	matrix.fill(-1)

# ==========================================================
# FAST GRID QUERIES
# ==========================================================

## Returns true if coordinates are within map bounds and point to traversable ground.
func is_valid_tile(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.x < width and coord.y >= 0 and coord.y < depth and matrix[coord.x + coord.y * width] != -1

## Returns ground height at given coordinates, or -1 if out of bounds/void.
func get_height_at(coord: Vector2i) -> int:
	if coord.x >= 0 and coord.x < width and coord.y >= 0 and coord.y < depth:
		return matrix[coord.x + coord.y * width]
	return -1

## Sets ground height value at target grid coordinates.
func set_height_at(coord: Vector2i, height: int) -> void:
	if coord.x >= 0 and coord.x < width and coord.y >= 0 and coord.y < depth:
		matrix[coord.x + coord.y * width] = height

# ==========================================================
# UNIT MANAGEMENT
# ==========================================================

## Registers or removes a pawn at target grid coordinates.
func set_unit_at(coord: Vector2i, pawn: BasePawn) -> void:
	if pawn == null:
		unit_matrix.erase(coord)
	else:
		unit_matrix[coord] = pawn

## Retrieves the pawn located at given coordinates, or null if empty.
func get_unit_at(coord: Vector2i) -> BasePawn:
	return unit_matrix.get(coord, null)

## Returns true if a pawn currently occupies target coordinates.
func is_occupied(coord: Vector2i) -> bool:
	return unit_matrix.has(coord)

# ==========================================================
# FAST ZOC INTERCEPTION CACHE
# ==========================================================

## Pre-calculates and caches all enemy Zone of Control threat regions before running pathfinding.
func cache_enemy_zocs_for(moving_unit: BasePawn) -> Array[Dictionary]:
	var zoc_cache: Array[Dictionary] = []
	
	for pos in unit_matrix:
		var enemy: BasePawn = unit_matrix[pos]
		if enemy == null or enemy == moving_unit or enemy.team_id == moving_unit.team_id:
			continue
			
		var zoc_dict: Dictionary = enemy.get_zones_of_control(self, moving_unit)
		for tag in zoc_dict.keys():
			var payload: Dictionary = zoc_dict[tag]
			zoc_cache.append({
				"enemy": enemy,
				"tag": tag,
				"tiles": payload["tiles"]
			})
			
	return zoc_cache

## Checks pre-calculated enemy ZoC coverage and triggers reaction callbacks if entered.
func process_cached_zoc_interceptions(moving_unit: BasePawn, from_pos: Vector2i, to_pos: Vector2i, state: Dictionary, zoc_cache: Array[Dictionary]) -> void:
	for entry in zoc_cache:
		var zoc_tiles: Array = entry["tiles"]
		if to_pos in zoc_tiles:
			var enemy: BasePawn = entry["enemy"]
			var tag: String = entry["tag"]
			enemy.trigger_zoc_effect(tag, moving_unit, from_pos, to_pos, state)

## Returns a list of all active threat payloads covering target coordinates for UI or AI checks.
func get_zoc_threats_at(target_pos: Vector2i, asking_unit: BasePawn) -> Array[Dictionary]:
	var active_threats: Array[Dictionary] = []
	
	for pos in unit_matrix:
		var pawn = unit_matrix[pos]
		if pawn == null or pawn == asking_unit or pawn.team_id == asking_unit.team_id:
			continue
			
		var zoc_dict = pawn.get_zones_of_control(self, asking_unit)
		for tag in zoc_dict.keys():
			var payload = zoc_dict[tag]
			if target_pos in payload["tiles"]:
				active_threats.append({
					"tag": tag,
					"team_id": payload["team_id"],
					"source_unit": payload["source_unit"]
				})
				
	return active_threats

# ==========================================================
# RULES & DISRUPTION HELPERS
# ==========================================================

## Returns true if a pawn is out of range of all allied commanders and susceptible to disruption penalties.
func is_unit_disrupted(pawn: BasePawn) -> bool:
	if not pawn.can_be_disrupted:
		return false

	var commanders = get_all_commanders_for_team(pawn.team_id)
	if pawn in commanders:
		return false

	for commander in commanders:
		if commander.is_in_command_range(pawn.grid_pos):
			return false

	return true

## Collects and returns all active commander pawns belonging to a specific team.
func get_all_commanders_for_team(team_id: int) -> Array[BasePawn]:
	var commanders: Array[BasePawn] = []
	for pos in unit_matrix:
		var pawn = unit_matrix[pos]
		if pawn != null and pawn.team_id == team_id and pawn.command_radius > 0:
			commanders.append(pawn)
	return commanders

## Returns all pawns within a Chebyshev distance radius from center, optionally filtered by team.
func get_adjacent_pawns(center: Vector2i, radius: int = 1, team_id: int = -1, filter_enemies: Variant = null) -> Array[BasePawn]:
	var results: Array[BasePawn] = []
	
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx == 0 and dz == 0:
				continue
				
			var check_pos = center + Vector2i(dx, dz)
			var unit = get_unit_at(check_pos)
			
			if unit != null:
				if filter_enemies == true:
					if unit.team_id != team_id:
						results.append(unit)
				elif filter_enemies == false:
					if unit.team_id == team_id:
						results.append(unit)
				else:
					results.append(unit)
	return results

# ==========================================================
# COORDINATE CONVERSIONS & CLONING
# ==========================================================

## Converts 2D grid coordinates and elevation level into 3D world space position.
func grid_to_world(x: int, height_level: int, z: int, atop: bool = false) -> Vector3:
	var offset = cell_size * 0.5
	var y_pos = (height_level + 1.0) * cell_size if atop else (height_level * cell_size) + offset
	return Vector3((x * cell_size) + offset, y_pos, (z * cell_size) + offset)

## Converts 3D world coordinates into integer grid coordinates (X, Height, Z).
func world_to_grid(world_pos: Vector3) -> Vector3i:
	var inv_cell = 1.0 / cell_size
	return Vector3i(
		floori(world_pos.x * inv_cell),
		floori(world_pos.y * inv_cell),
		floori(world_pos.z * inv_cell)
	)

## Converts 3D world coordinates into 2D grid coordinates (X, Z).
func world_to_grid_2d(world_pos: Vector3) -> Vector2i:
	var inv_cell = 1.0 / cell_size
	return Vector2i(
		floori(world_pos.x * inv_cell),
		floori(world_pos.z * inv_cell)
	)

## Performs a deep copy of the board state for pathfinding simulation and AI evaluation.
func clone() -> BoardState:
	var copy = BoardState.new(width, depth, cell_size)
	copy.matrix = matrix.duplicate()
	for key in unit_matrix:
		copy.unit_matrix[key] = unit_matrix[key]
	return copy
