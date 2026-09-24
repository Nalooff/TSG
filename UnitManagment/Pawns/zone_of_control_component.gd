extends PawnComponent
class_name ZoCComponent

var _zoc_getters_cache: Dictionary = {}
var _zoc_effects_cache: Dictionary = {}


func _ready() -> void:
	super._ready()
	_build_zoc_reflection_cache()

func _build_zoc_reflection_cache() -> void:
	_zoc_getters_cache.clear()
	_zoc_effects_cache.clear()
	
	if pawn == null:
		return

	for method_info in pawn.get_method_list():
		var m_name: String = method_info["name"]
		if m_name.begins_with("get_zoc_"):
			var target_tag = m_name.trim_prefix("get_zoc_")
			_zoc_getters_cache[target_tag] = m_name
		elif m_name.begins_with("zoc_effect_"):
			var target_tag = m_name.trim_prefix("zoc_effect_")
			_zoc_effects_cache[target_tag] = m_name

func get_zones_of_control(board_state: BoardState, asking_unit: BasePawn) -> Dictionary:
	var result = {}
	if asking_unit == null or asking_unit == pawn:
		return result

	for target_tag in _zoc_getters_cache:
		if asking_unit.has_tag(target_tag):
			var m_name: String = _zoc_getters_cache[target_tag]
			var tiles = pawn.call(m_name, board_state, asking_unit)
			if tiles is Array and tiles.size() > 0:
				var typed_tiles: Array[Vector2i] = []
				for t in tiles:
					if t is Vector2i:
						typed_tiles.append(t)
				
				result[target_tag] = {
					"team_id": pawn.team_id,
					"source_unit": pawn,
					"tiles": typed_tiles
				}

	return result

func trigger_zoc_effect(tag: String, moving_unit: BasePawn, from_pos: Vector2i, to_pos: Vector2i, state: Dictionary) -> void:
	if _zoc_effects_cache.has(tag):
		pawn.call(_zoc_effects_cache[tag], moving_unit, from_pos, to_pos, state)
