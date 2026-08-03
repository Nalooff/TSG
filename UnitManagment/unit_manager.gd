extends Node3D
class_name UnitManager

const PAWNS_NODE_NAME = "Pawns"

# State
var pawn_container: Node3D
var selected_pawn: BasePawn


func _ready() -> void:
	_initialize_connection()
	_initialize_containers()


## Prepares a dedicated scene node for child pawns to prevent hierarchy clutter.
func _initialize_containers() -> void:
	if has_node(PAWNS_NODE_NAME):
		var old_container = get_node(PAWNS_NODE_NAME)
		remove_child(old_container)
		old_container.queue_free()
	
	pawn_container = Node3D.new()
	pawn_container.name = PAWNS_NODE_NAME
	add_child(pawn_container)

func _initialize_connection():
	EventBus.pawn_move_requested.connect(_on_pawn_move_requested)
# ===============================================
# SELECTION MANAGEMENT
# ===============================================

## Selects a given pawn and broadcasts the change.
func select_pawn(pawn: BasePawn) -> void:
	if not is_instance_valid(pawn):
		clear_selection()
		return

	# Avoid redundant selection events
	if selected_pawn == pawn:
		return

	selected_pawn = pawn
	EventBus.pawn_selected.emit(selected_pawn)


## Clears the current pawn selection.
func clear_selection() -> void:
	if selected_pawn == null:
		return

	selected_pawn = null
	EventBus.pawn_deselected.emit()

func _on_pawn_move_requested(pawn, pos):
	pass

# ===============================================
# PAWN SPANNING & LIFECYCLE
# ===============================================

## Spawns a pawn scene under the managed Pawns container.
func spawn_pawn(pawn_scene: PackedScene, grid_pos: Vector2i) -> BasePawn:
	if not pawn_scene:
		push_error("UnitManager: Cannot spawn pawn from null PackedScene.")
		return null

	var pawn_instance = pawn_scene.instantiate() as BasePawn
	if not pawn_instance:
		push_error("UnitManager: Instantiated scene is not a BasePawn.")
		return null

	pawn_container.add_child(pawn_instance)
	
	# Set initial position based on grid cell size
	var world_x = grid_pos.x * GData.CELL_SIZE + (GData.CELL_SIZE / 2.0)
	var world_z = grid_pos.y * GData.CELL_SIZE + (GData.CELL_SIZE / 2.0)
	pawn_instance.global_position = Vector3(world_x, 0.0, world_z)

	EventBus.pawn_registered.emit(pawn_instance)
	return pawn_instance


## Removes a pawn from the board and handles cleanup if it was selected.
func despawn_pawn(pawn: BasePawn = selected_pawn) -> void:
	if not is_instance_valid(pawn):
		return

	if selected_pawn == pawn:
		clear_selection()

	EventBus.pawn_unregistered.emit(pawn)
	pawn.queue_free()


# ===============================================
# QUERY HELPERS
# ===============================================

## Returns an Array of all currently active pawns under management.
func get_all_pawns() -> Array[BasePawn]:
	var list: Array[BasePawn] = []
	if not is_instance_valid(pawn_container):
		return list

	for child in pawn_container.get_children():
		if child is BasePawn:
			list.append(child as BasePawn)
			
	return list


## Finds a pawn occupying a specific grid coordinate, if any.
func get_pawn_at_grid_pos(grid_pos: Vector2i) -> BasePawn:
	for pawn in get_all_pawns():
		if "grid_pos" in pawn and pawn.grid_pos == grid_pos:
			return pawn
	return null
