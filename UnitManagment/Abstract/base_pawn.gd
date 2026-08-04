extends Node3D
class_name BasePawn

enum MoveType { STEP, SLIDE, JUMP }

@export_group("Base Stats")
@export var team_id: int = 0
@export var move_range: int = 3
@export var attack_range: int = 1

@export_group("Elevation Rules")
@export var max_step_up: int = 1     ## Max height difference the pawn can climb up in 1 step
@export var max_step_down: int = 2   ## Max height difference the pawn can drop down in 1 step

var grid_pos: Vector2i



# Called when the node enters the scene tree for the first time.
func _ready():
	EventBus.connect("camera_changed", _on_cam_changed)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass


# ==========================================================
# PUBLIC API
# ==========================================================

## Called by UI / Preview system. Calculates all reachable tiles.
func get_valid_moves(board_state: BoardState) -> Array[Vector2i]:
	var valid: Array[Vector2i] = []
	var rules = _get_movement_rules()
	
	for rule in rules:
		valid.append_array(_evaluate_rule(board_state, rule))
		
	# Allow subclasses to inject/filter moves directly
	_custom_movement_rules(board_state, valid)
	
	return valid


# ==========================================================
# OVERRIDABLE HOOKS FOR SUBCLASSES
# ==========================================================

## Subclasses return their directions, move types, and max range here.
func _get_movement_rules() -> Array[Dictionary]:
	# Default Pawn: 4 cardinal directions, step-by-step walking up to move_range
	return [{
		"directions": [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT],
		"type": MoveType.STEP,
		"range": move_range
	}]

## Subclasses can override this for special conditions (e.g. conditional moves, passives).
func _custom_movement_rules(_board_state: BoardState, _out_moves: Array[Vector2i]) -> void:
	pass


# ==========================================================
# CORE EVALUATION ENGINE
# ==========================================================

func _evaluate_rule(board_state: BoardState, rule: Dictionary) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	var dirs: Array = rule.get("directions", [])
	var move_type: MoveType = rule.get("type", MoveType.STEP)
	var max_steps: int = rule.get("range", 1)
	
	for dir in dirs:
		var curr_pos = grid_pos
		var curr_height = board_state.get_height_at(curr_pos.x, curr_pos.y)
		
		for step in range(1, max_steps + 1):
			var next_pos = curr_pos + dir
			var next_height = board_state.get_height_at(next_pos.x, next_pos.y)
			
			# 1. Ground existence check
			if next_height == -1:
				break
				
			# 2. Elevation check (unless jumping)
			if move_type != MoveType.JUMP:
				var height_diff = next_height - curr_height
				if height_diff > max_step_up or height_diff < -max_step_down:
					break # Wall too high or drop too steep
			
			# 3. Occupancy check
			var occupant = board_state.get_unit_at(next_pos)
			
			if move_type == MoveType.JUMP:
				# Jumper only evaluates destination at max step
				if step == max_steps:
					if occupant == null or occupant.team_id != self.team_id:
						results.append(next_pos)
			else:
				# Walkers / Sliders check every tile along the way
				if occupant != null:
					# Friendly unit blocks movement; enemy unit might be attackable depending on game design
					break
				results.append(next_pos)
			
			curr_pos = next_pos
			curr_height = next_height
			
	return results

# ==========================================================
# CAMERA HANDLING
# ==========================================================

func _on_cam_changed(cam: Camera3D):
	if cam.name == "View2D":
		$Sprite3D.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	else:
		$Sprite3D.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
