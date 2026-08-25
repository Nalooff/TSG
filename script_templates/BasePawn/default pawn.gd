# meta-default: true
# meta-name: Base Pawn
# meta-description: Template for pawns with overridable hooks and ZoC reflection methods
# meta-space-indent: 4
extends _BASE_


# ==========================================================
# MOVEMENT HOOKS (Uncomment to override)
# ==========================================================

#func _get_allowed_directions() -> Array[Vector2i]:
#	return [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

#func _calculate_step_cost(board: BoardState, from: Vector2i, to: Vector2i, curr_h: int, next_h: int, state: Dictionary) -> int:
#	return super._calculate_step_cost(board, from, to, curr_h, next_h, state)

#func _is_step_allowed(board: BoardState, from: Vector2i, to: Vector2i, dir: Vector2i, state: Dictionary) -> bool:
#	return true

#func _on_step_entered(board: BoardState, pos: Vector2i, state: Dictionary) -> void:
#	pass

# ==========================================================
# ZONE OF CONTROL (ZOC) HOOKS
# Format: get_zoc_<tag_id>(board_state, asking_unit) -> Array[Vector2i]
# Format: zoc_effect_<tag_id>(moving_unit, from_pos, to_pos, state) -> void
# ==========================================================


#func get_zoc_<tag>(board_state: BoardState, asking_unit: BasePawn) -> Array[Vector2i]:
#	return [grid_pos + Vector2i.UP, grid_pos + Vector2i.DOWN]

#func zoc_effect_<tag>(moving_unit: BasePawn, from_pos: Vector2i, to_pos: Vector2i, state: Dictionary) -> void:
#	state["cost"] = base_mp # Stop movement
