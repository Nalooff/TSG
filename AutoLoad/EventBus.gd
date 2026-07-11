@tool
extends Node

# TO GET THE DEBUG OF SIGNALS, GO TO PROJECT SETTINGS/DEBUG/EVENTBUS

# ==============================================================================
# SIGNALS
# ==============================================================================
signal camera_changed(cam: Camera3D)
signal preview_updated(grid_pos: Vector3i, size: Vector3i, is_valid: bool)
signal block_placed(grid_position: Vector3i, size: Vector3i, is_successful: bool)
signal pawn_moved(pawn: Node, target_tile: Vector2i)
signal game_started(player_count: int)


# ==============================================================================
# EDITOR AUTOMATION
# ==============================================================================
func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_generate_project_settings_checkboxes()
	else:
		_hook_up_debug_listeners()


func _generate_project_settings_checkboxes() -> void:
	var properties_changed = false
	var base_node_signals = ClassDB.class_get_signal_list("Node").map(func(s): return s.name)
	
	for sig_info in get_signal_list():
		var sig_name = sig_info["name"]
		
		if sig_name in base_node_signals or sig_name in ["script_changed", "property_list_changed"]:
			continue
			
		var setting_path = "debug/event_bus/" + sig_name
		
		if not ProjectSettings.has_setting(setting_path):
			ProjectSettings.set_setting(setting_path, false)
			
			var property_info = {
				"name": setting_path,
				"type": TYPE_BOOL,
				"hint": PROPERTY_HINT_NONE
			}
			ProjectSettings.add_property_info(property_info)
			properties_changed = true
			print("EventBus: Automatically created setting for -> ", setting_path)
			
	if properties_changed:
		ProjectSettings.save()


# ==============================================================================
# GAMEPLAY RUNTIME HOOKS
# ==============================================================================
func _hook_up_debug_listeners() -> void:
	var base_node_signals = ClassDB.class_get_signal_list("Node").map(func(s): return s.name)
	
	for sig_info in get_signal_list():
		var sig_name = sig_info["name"]
		
		if sig_name in base_node_signals or sig_name in ["script_changed", "property_list_changed"]: 
			continue
			
		var sig: Signal = get(sig_name)
		var setting_path = "debug/event_bus/" + sig_name
		
		if ProjectSettings.has_setting(setting_path) and ProjectSettings.get_setting(setting_path):
			# Get the exact number of parameters defined for this specific signal
			var expected_arg_count = sig_info["args"].size()
			
			sig.connect(func(arg1=null, arg2=null, arg3=null, arg4=null, arg5=null, arg6=null, arg7=null, arg8=null): 
				var raw_args = [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8]
				
				# Slice the array down to match ONLY the number of arguments the signal actually sent.
				# This prevents accidental deletion of valid 'null' entries!
				var passed_args = raw_args.slice(0, expected_arg_count)
				
				_log_emission(sig, passed_args)
			)

# ==============================================================================
# CRASH-SAFE LOGGING FUNCTION
# ==============================================================================
func _log_emission(sig: Signal, args: Array) -> void:
	var time = Time.get_time_string_from_system()
	var stack = get_stack()
	var real_emitter: String = "Unknown Script"
	
	if stack.size() >= 3:
		var caller_info = stack[2]
		real_emitter = str(caller_info["source"].get_file(), " -> line ", caller_info["line"], " in .", caller_info["function"], "()")
	
	print("\n========== SIGNAL EMITTED ==========")
	print("Signal Name : ", sig.get_name())
	print("Real Emitter: ", real_emitter)
	print("Infos/Args  : ", args)
	print("Time        : ", time)
	
	var connections = sig.get_connections()
	if connections.is_empty():
		print("Receivers   : None (No one is listening!)")
	else:
		print("Receivers")
		for connection in connections:
			var callable: Callable = connection["callable"]
			var receiver = callable.get_object()
			if receiver == self: 
				continue
				
			var receiver_name = receiver.name if (receiver and "name" in receiver) else str(receiver)
			
			if callable.is_custom():
				print("   -> [", receiver_name, "] will run an: [Anonymous Lambda Function]")
			else:
				print("   -> [", receiver_name, "] will run method: .", callable.get_method(), "()")
	print("=======================================\n")
