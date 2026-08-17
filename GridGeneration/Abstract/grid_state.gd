extends RefCounted
class_name BoardState

var width: int
var depth: int
var cell_size: float
## 2D Matrix storing heights (-1 for empty, 0+ for block height levels)
var matrix: Array[Array] = []

## 2D Matrix storing BasePawn references (or null)
var unit_matrix: Dictionary = {} # Key: Vector2i, Value: BasePawn


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

## Returns the top height level at coordinates, or -1 if empty/out of bounds.
func get_height_at(x: int, z: int) -> int:
	if x >= 0 and x < width and z >= 0 and z < depth:
		return matrix[x][z]
	return -1

## Directly updates the data matrix layer height value.
func set_height_at(x: int, z: int, height: int) -> void:
	if x >= 0 and x < width and z >= 0 and z < depth:
		matrix[x][z] = height

##
func set_unit_at(coord: Vector2i, pawn: BasePawn) -> void:
	if pawn == null:
		unit_matrix.erase(coord)
	else:
		unit_matrix[coord] = pawn

##
func get_unit_at(coord: Vector2i) -> BasePawn:
	return unit_matrix.get(coord, null)

##
func is_occupied(coord: Vector2i) -> bool:
	return unit_matrix.has(coord)

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
	return copy
