extends RefCounted
class_name BoardState

var width: int
var depth: int
var cell_size: float

## 2D Matrix storing heights (-1 for empty, 0+ for block height levels)
var matrix: Array[Array] = []

## Dictionary mapping Vector2i grid position to BasePawn references
var unit_matrix: Dictionary = {}

func _init(p_width: int, p_depth: int, p_cell_size: float) -> void:
	width = p_width
	depth = p_depth
	cell_size = p_cell_size
	
	matrix.clear()
	for x in range(width):
		var row: Array[int] = []
		row.resize(depth)
		row.fill(-1)
		matrix.append(row)

# ==========================================================
# GRID & HEIGHT QUERIES
# ==========================================================

## Returns true if the coordinates fall within map bounds and contain ground.
func is_valid_tile(coord: Vector2i) -> bool:
	if coord.x >= 0 and coord.x < width and coord.y >= 0 and coord.y < depth:
		return matrix[coord.x][coord.y] != -1
	return false

## Returns the top height level at coordinates, or -1 if empty/out of bounds.
func get_height_at(coord: Vector2i) -> int:
	if is_valid_tile(coord):
		return matrix[coord.x][coord.y]
	return -1

## Directly updates the data matrix layer height value using a Vector2i grid position.
func set_height_at(coord: Vector2i, height: int) -> void:
	if coord.x >= 0 and coord.x < width and coord.y >= 0 and coord.y < depth:
		matrix[coord.x][coord.y] = height

# ==========================================================
# UNIT MANAGEMENT & OCCUPANCY
# ==========================================================

func set_unit_at(coord: Vector2i, pawn: BasePawn) -> void:
	if pawn == null:
		unit_matrix.erase(coord)
	else:
		unit_matrix[coord] = pawn

func get_unit_at(coord: Vector2i) -> BasePawn:
	return unit_matrix.get(coord, null)

func is_occupied(coord: Vector2i) -> bool:
	return unit_matrix.has(coord)

# ==========================================================
# INTERCEPTION & REACTION PROCESSOR
# ==========================================================

## Evaluates reactive threat zones projected by enemy pawns for a step target tile.
func process_zoc_interceptions(moving_unit: BasePawn, from_pos: Vector2i, to_pos: Vector2i, state: Dictionary) -> void:
	for pos in unit_matrix:
		var enemy = unit_matrix[pos]
		if enemy == null or enemy == moving_unit:
			continue
			
		var zoc_dict: Dictionary = enemy.get_zones_of_control(self, moving_unit)
		
		for tag in zoc_dict.keys():
			var payload: Dictionary = zoc_dict[tag]
			var zoc_team_id: int = payload["team_id"]
			var zoc_tiles: Array = payload["tiles"]
			
			# Only trigger if the moving unit belongs to an opposing team
			if zoc_team_id != moving_unit.team_id:
				if to_pos in zoc_tiles:
					enemy.trigger_zoc_effect(tag, moving_unit, from_pos, to_pos, state)

## Returns a list of all active ZoC threat payloads covering a specific tile.
## Useful for threat overlays, AI evaluation, or hazard checks.
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

# Checks if a unit is Disrupted (out of command range of all allied Commanders).
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

## Returns all active commanders belonging to a given team.
func get_all_commanders_for_team(team_id: int) -> Array[BasePawn]:
	var commanders: Array[BasePawn] = []
	for pos in unit_matrix:
		var pawn = unit_matrix[pos]
		if pawn != null and pawn.team_id == team_id and pawn.command_radius > 0:
			commanders.append(pawn)
	return commanders

## Returns all pawns within a Chebyshev distance of `radius` from center.
## filter_enemies = true returns enemies, false returns team members, null returns all pawns.
func get_adjacent_pawns(center: Vector2i, radius: int = 1, team_id: int = -1, filter_enemies: Variant = null) -> Array[BasePawn]:
	var results: Array[BasePawn] = []
	
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx == 0 and dz == 0:
				continue # Skip center tile
				
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
					results.append(unit) # No team filter applied
	return results

# ==========================================================
# COORDINATE CONVERSIONS & CLONING
# ==========================================================

## Helper to convert grid coordinates + height level directly into 3D world space.
func grid_to_world(x: int, height_level: int, z: int, atop: bool = false) -> Vector3:
	var offset = cell_size / 2.0
	var y_pos = (height_level + 1.0) * cell_size if atop else (height_level * cell_size) + offset
	return Vector3((x * cell_size) + offset, y_pos, (z * cell_size) + offset)

## Converts a 3D world position back into integer grid coordinates (X, Height Level, Z).
func world_to_grid(world_pos: Vector3) -> Vector3i:
	var x = floori(world_pos.x / cell_size)
	var height_level = floori(world_pos.y / cell_size)
	var z = floori(world_pos.z / cell_size)
	return Vector3i(x, height_level, z)

## Converts a 3D world position back into 2D grid coordinates (X, Z).
func world_to_grid_2d(world_pos: Vector3) -> Vector2i:
	var x = floori(world_pos.x / cell_size)
	var z = floori(world_pos.z / cell_size)
	return Vector2i(x, z)

## Performs a deep copy of the board state for pawn pathfinding & AI projections.
func clone() -> BoardState:
	var copy = BoardState.new(width, depth, cell_size)
	for x in range(width):
		for z in range(depth):
			copy.matrix[x][z] = matrix[x][z]
	for key in unit_matrix:
		copy.unit_matrix[key] = unit_matrix[key]
	return copy
