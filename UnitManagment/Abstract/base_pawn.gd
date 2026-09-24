extends Node3D
class_name BasePawn

const NODES_NAMES = GData.PAWN.NODES_NAMES

# Structural Nodes
@onready var area_3d: Area3D = get_node_or_null(NODES_NAMES[GData.PawnNode.AREA_3D]) as Area3D
@onready var sprite_3d: Sprite3D = get_node_or_null(NODES_NAMES[GData.PawnNode.SPRITE_3D]) as Sprite3D

@export_group("Components")
@export var movement: MovementComponent
@export var zoc: ZoCComponent
@export var combat: CombatComponent

@export_group("Base Stats")
@export var team_id: int = 0
@export var base_mp: int = 3

@export_group("Classification & Tags")
@export var tags: Array[StringName] = [&"global"]

var grid_pos: Vector2i


func _ready() -> void:
	EventBus.camera_changed.connect(_on_cam_changed)

## Checks if this pawn possesses a given classification tag.
func has_tag(tag_id: StringName) -> bool:
	return tags.has(tag_id)


# --- ENGINE HELPERS ---

func _on_cam_changed(cam: Camera3D) -> void:
	if sprite_3d != null:
		sprite_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED if cam.name == "View2D" else BaseMaterial3D.BILLBOARD_FIXED_Y

static func spawn(pawn_scene: PackedScene) -> BasePawn:
	return pawn_scene.instantiate() as BasePawn
