@tool
extends Node

# TO CONFIG THE EVENT BUS, GO TO PROJECT SETTINGS:
# -> debug/event_bus/config/...  (Global logger behavior)
# -> debug/event_bus/signals/... (Toggles for individual signals)

# ==============================================================================
# SIGNALS
# ==============================================================================
signal camera_changed(cam: Camera3D)
signal preview_updated(grid_pos: Vector3i, size: Vector3i, is_valid: bool)
signal block_placed(grid_position: Vector3i, size: Vector3i, is_successful: bool)
signal placement_requested(grid_pos: Vector2i, size: Vector3i)
signal pawn_moved(pawn: Node, target_tile: Vector2i)
signal game_started(player_count: int)


# ==============================================================================
# ENGINE LIFECYCLE & LIVE COMPILATION DETECTOR
# ==============================================================================
func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		_run_runtime_setup()


static func _static_init() -> void:
	if Engine.is_editor_hint():
		var temp_instance = load("res://AutoLoad/EventBus.gd").new()
		if temp_instance:
			temp_instance._run_editor_setup()
			temp_instance.free()


# ==============================================================================
# EDITOR SETUP AUTOMATION
# ==============================================================================
func _run_editor_setup() -> void:
	var settings_modified = false
	
	settings_modified = _register_config_settings() or settings_modified
	settings_modified = _sync_signal_toggles() or settings_modified
			
	if settings_modified:
		ProjectSettings.save()
		if ProjectSettings.has_method("notify_property_list_changed"):
			ProjectSettings.notify_property_list_changed()


func _get_config_definitions() -> Dictionary:
	return {
		"debug/event_bus/config/show_argument_names": false,
		"debug/event_bus/config/show_emitter_line_number": true,
		"debug/event_bus/config/show_receiver_line_number": false
	}


func _register_config_settings() -> bool:
	var modified = false
	var configs = _get_config_definitions()
	
	for path in configs:
		if not ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, configs[path])
			_add_setting_meta(path, TYPE_BOOL)
			modified = true
	return modified


func _sync_signal_toggles() -> bool:
	var modified = false
	var valid_signal_settings = _get_valid_custom_signal_paths()
	
	modified = _register_new_signals(valid_signal_settings) or modified
	modified = _purge_dead_signals(valid_signal_settings) or modified
			
	return modified


func _add_setting_meta(path: String, type_enum: int) -> void:
	ProjectSettings.add_property_info({
		"name": path,
		"type": type_enum,
		"hint": PROPERTY_HINT_NONE
	})
	print("EventBus Automation: Synchronized -> ", path)


func _is_ignored_signal(sig_name: String, base_signals: Array) -> bool:
	return sig_name in base_signals or sig_name in ["script_changed", "property_list_changed"]


# ==============================================================================
# RUNTIME HOOKS & PROCESSING
# ==============================================================================
func _run_runtime_setup() -> void:
	var base_node_signals = ClassDB.class_get_signal_list("Node").map(func(s): return s.name)
	
	for sig_info in get_signal_list():
		var sig_name = sig_info["name"]
		if _is_ignored_signal(sig_name, base_node_signals):
			continue
			
		_evaluate_and_hook_signal(sig_info)


func _evaluate_and_hook_signal(sig_info: Dictionary) -> void:
	var sig_name = sig_info["name"]
	var setting_path = "debug/event_bus/signals/" + sig_name
	
	var is_enabled = ProjectSettings.get_setting(setting_path) if ProjectSettings.has_setting(setting_path) else false
	if not is_enabled:
		return
		
	var sig: Signal = get(sig_name)
	var expected_arg_count = sig_info["args"].size()
	var arg_names = sig_info["args"].map(func(arg): return arg["name"])
	
	sig.connect(func(arg1=null, arg2=null, arg3=null, arg4=null, arg5=null, arg6=null, arg7=null, arg8=null): 
		var raw_args = [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8]
		var passed_args = raw_args.slice(0, expected_arg_count)
		
		_process_signal_log(sig, passed_args, arg_names)
	)


func _process_signal_log(sig: Signal, args: Array, arg_names: Array) -> void:
	var time = Time.get_time_string_from_system()
	var emitter_string = _find_caller_source()
	var formatted_arguments = _format_arguments_by_config(args, arg_names)
	
	_print_signal_block(sig.get_name(), emitter_string, formatted_arguments, time, sig.get_connections())


func _find_caller_source() -> String:
	var stack = get_stack()
	if stack.size() >= 4:
		var caller_info = stack[3]
		var file_name: String = caller_info["source"].get_file()
		
		var config_path = "debug/event_bus/config/show_emitter_line_number"
		var show_line = ProjectSettings.get_setting(config_path) if ProjectSettings.has_setting(config_path) else true
		
		if show_line:
			return str(file_name, " -> line ", caller_info["line"], " in .", caller_info["function"], "()")
		else:
			return str(file_name, " in .", caller_info["function"], "()")
			
	return "Unknown Script Source"


func _format_arguments_by_config(args: Array, arg_names: Array) -> Variant:
	var config_path = "debug/event_bus/config/show_argument_names"
	var show_names = ProjectSettings.get_setting(config_path) if ProjectSettings.has_setting(config_path) else false
	
	if not show_names or arg_names.is_empty():
		return args
		
	var named_args_dict = {}
	for i in range(args.size()):
		var key = arg_names[i] if i < arg_names.size() else "param_" + str(i)
		named_args_dict[key] = args[i]
	return named_args_dict


# ==============================================================================
# CLEAN PRINT FORMATTER
# ==============================================================================
func _print_signal_block(sig_name: String, emitter: String, args: Variant, time: String, connections: Array) -> void:
	print("\n========== SIGNAL EMITTED ==========")
	print("Signal Name : ", sig_name)
	print("Real Emitter: ", emitter)
	print("Infos/Args  : ", args)
	print("Time        : ", time)
	
	_print_receivers(connections)
	print("=======================================\n")


func _print_receivers(connections: Array) -> void:
	var active_listeners = connections.filter(func(c): return c["callable"].get_object() != self)
	
	if active_listeners.is_empty():
		print("Receivers   : None (No one is listening!)")
		return
		
	var config_path = "debug/event_bus/config/show_receiver_line_number"
	var show_line = ProjectSettings.get_setting(config_path) if ProjectSettings.has_setting(config_path) else false
	
	print("Receivers")
	for connection in active_listeners:
		var callable: Callable = connection["callable"]
		var receiver = callable.get_object()
		var receiver_name = receiver.name if (receiver and "name" in receiver) else str(receiver)
		
		var action_text = _get_callable_action_text(callable)
		var script_info = _get_receiver_script_info(receiver, callable, show_line)

		print("   -> [", receiver_name, "] (", script_info, ") ", action_text)


# ==============================================================================
# DELEGATED STRUCTURAL SUB-FUNCTIONS (The Cleanups!)
# ==============================================================================

# Helper for _sync_signal_toggles()
func _get_valid_custom_signal_paths() -> Array:
	var paths = []
	var base_node_signals = ClassDB.class_get_signal_list("Node").map(func(s): return s.name)
	for sig_info in get_signal_list():
		var sig_name = sig_info["name"]
		if not _is_ignored_signal(sig_name, base_node_signals):
			paths.append("debug/event_bus/signals/" + sig_name)
	return paths


# Helper for _sync_signal_toggles()
func _register_new_signals(valid_paths: Array) -> bool:
	var modified = false
	for setting_path in valid_paths:
		if not ProjectSettings.has_setting(setting_path):
			ProjectSettings.set_setting(setting_path, false)
			_add_setting_meta(setting_path, TYPE_BOOL)
			modified = true
	return modified


# Helper for _sync_signal_toggles()
func _purge_dead_signals(valid_paths: Array) -> bool:
	var modified = false
	for prop in ProjectSettings.get_property_list():
		var path: String = prop["name"]
		if path.begins_with("debug/event_bus/signals/") and not (path in valid_paths):
			ProjectSettings.set_setting(path, null)
			print("EventBus Automation: Purged Dead Setting -> ", path)
			modified = true
	return modified

# Helper for _print_receivers()
func _get_callable_action_text(callable: Callable) -> String:
	if callable.is_custom():
		return "will run an: [Anonymous Lambda Function]"
	return str("will run method: .", callable.get_method(), "()")


# Helper for _print_receivers()
func _get_receiver_script_info(receiver: Object, callable: Callable, show_line: bool) -> String:
	if not receiver or not receiver.has_method("get_script"):
		return "Unknown Script"
		
	var script = receiver.get_script()
	if not (script is Script):
		return "Unknown Script"
		
	var script_path = script.resource_path.get_file()
	
	if callable.is_custom():
		return script_path
		
	if show_line:
		var line_num = _find_method_line_in_script(script, callable.get_method())
		if line_num > 0:
			return str(script_path, " -> line ", line_num)
			
	return script_path


func _find_method_line_in_script(script: Script, method_name: String) -> int:
	for source_loc in script.get_script_method_list():
		if source_loc.name == method_name and source_loc.has("line"):
			return source_loc["line"]
				
	var source_code = script.source_code
	if not source_code.is_empty():
		var lines = source_code.split("\n")
		var target_pattern = "func " + method_name
		for i in range(lines.size()):
			if lines[i].contains(target_pattern):
				return i + 1
	return -1
