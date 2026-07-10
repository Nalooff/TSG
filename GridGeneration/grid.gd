extends Node3D
class_name Grid

# Grid Configuration
const GRID_WIDTH: int = 15
const GRID_DEPTH: int = 15
const CELL_SIZE: float = 2.0

# Layer Colors for Placed Blocks (0 = Dark, 3 = White)
const LAYER_COLORS = [
	Color8(64, 64, 64),     # Layer 0: Dark Grey
	Color8(127, 127, 127),   # Layer 1: Grey
	Color8(192, 192, 192),   # Layer 2: Light Grey
	Color8(255, 255, 255)    # Layer 3: White
]

# Shared center point for cameras to focus on
var center: Vector3 = Vector3(GRID_WIDTH, 0, GRID_DEPTH) * CELL_SIZE / 2.0

# Master data tracking structure populated with Vector3i(x, height, z)
var grid_matrix: Array[Vector3i] = []

## Instantly get the height layer (0-3) at a specific coordinate
func get_height_at(x: int, z: int) -> int:
	for cell in grid_matrix:
		if cell.x == x and cell.z == z:
			return cell.y
	return 0

## Overwrite or append a height value inside our database
func set_height_at(x: int, z: int, new_height: int) -> void:
	for i in range(grid_matrix.size()):
		if grid_matrix[i].x == x and grid_matrix[i].z == z:
			grid_matrix[i].y = new_height
			return
	grid_matrix.append(Vector3i(x, new_height, z))
