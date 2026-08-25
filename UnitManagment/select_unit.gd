extends Node
class_name SelectUnit

@export var unit_manager: UnitManager

var _hovered_pawn: BasePawn = null

func _ready() -> void:
	# Fallback setup for UnitManager reference
	if not unit_manager:
		unit_manager = get_parent() as UnitManager
		
	if not unit_manager:
		push_error("SelectUnit: Missing 'unit_manager' assignment and parent '%s' is not a UnitManager." % get_parent().name)
		return

	# Listen for hovered pawn updates from the hover detector
	EventBus.pawn_hovered.connect(_on_pawn_hovered)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return

	if Global.current_mode != GData.GameMode.PLAY and Global.current_play_mode != GData.PlayMode.SELECT:
		return

	# Perform Unit Selection / Deselection
	if is_instance_valid(_hovered_pawn):
		unit_manager.select_pawn(_hovered_pawn)
	else:
		unit_manager.clear_selection()

func _on_pawn_hovered(pawn: BasePawn) -> void:
	_hovered_pawn = pawn
