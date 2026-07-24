extends Node3D
class_name BasePawn




# Called when the node enters the scene tree for the first time.
func _ready():
	EventBus.connect("camera_changed", _on_cam_changed)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass


func _on_cam_changed(cam: Camera3D):
	if cam.name == "View2D":
		$Sprite3D.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	else:
		$Sprite3D.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
