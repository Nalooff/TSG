@tool
extends Node

# ==============================================================================
# HOW TO CONFIG THE EVENT BUS VIA PROJECT SETTINGS
# ==============================================================================
# Go to: Project -> Project Settings
# -> debug/event_bus/config/...  (Controls global logger output formatting)
# -> debug/event_bus/signals/... (True = Log this signal to console; False = Mute logs)
#
# HOW TO EMIT A SIGNAL IN YOUR CODE:
#   EventBus.preview_updated.emit(pos, size, true)
#
# HOW TO LISTEN TO A SIGNAL IN YOUR CODE:
#   EventBus.preview_updated.connect(_on_preview_updated)
# ==============================================================================

# ==============================================================================
# MASTER SIGNAL REGISTRY (Arrange these in any order you like!)
# ==============================================================================
signal camera_changed(cam: Camera3D)
signal preview_updated(grid_pos: Vector3i, size: Vector3i, is_valid: bool)
signal placement_requested(grid_2d_pos: Vector2i, size: Vector3i)
signal block_placed(grid_position: Vector3i, size: Vector3i, is_successful: bool)
signal supression_preview(grid_position: Vector3i, size: Vector3i) # <-- Perfectly sorted in-place!
signal suppression_requested(grid_2d_pos: Vector2i, size: Vector3i)
signal block_suppressed(grid_position: Vector3i, size: Vector3i, is_successful: bool)
signal pawn_moved(pawn: Node, target_tile: Vector2i)
signal game_started(player_count: int)


# ==============================================================================
# ENGINE LIFECYCLE & LIVE COMPILATION
# ==============================================================================

## Godot entry point. Runs when the EventBus node enters the scene tree.
func _enter_tree() -> void:
	# If running the actual game, configure runtime signal proxy loggers
	if not Engine.is_editor_hint():
		_run_runtime_setup()


## Native static compiler hook. Runs in the editor whenever this script is modified/saved.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		# Instantiate a transient instance to forcefully regenerate the Project Settings UI layout
		var temp_instance = load("res://AutoLoad/EventBus.gd").new()
		if temp_instance:
			temp_instance._run_editor_setup()
			temp_instance.free()


# ==============================================================================
# EDITOR SETUP AUTOMATION
# ==============================================================================

## Coordinates the editor data sync sequence and commits changes directly to project.godot
func _run_editor_setup() -> void:
	var settings_modified = false
	
	settings_modified = _register_config_settings() or settings_modified
	settings_modified = _sync_signal_toggles() or settings_modified
			
	if settings_modified:
		ProjectSettings.save()
		if ProjectSettings.has_method("notify_property_list_changed"):
			ProjectSettings.notify_property_list_changed()


## Defines default configuration preferences for the logger output format
func _get_config_definitions() -> Dictionary:
	return {
		"debug/event_bus/config/show_argument_names": false,
		"debug/event_bus/config/show_emitter_line_number": true,
		"debug/event_bus/config/show_receiver_line_number": false
	}


## Initializes global event bus logging rules if they do not yet exist
func _register_config_settings() -> bool:
	var modified = false
	var configs = _get_config_definitions()
	
	var index = 0
	for path in configs:
		if not ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, configs[path])
			_add_setting_meta(path, TYPE_BOOL, index)
			modified = true
		index += 1
	return modified


## The Sorting Fix: Erases and sequentially reinstantiates all custom signals 
## to maintain perfect alignment with your script's top-to-bottom layout.
func _sync_signal_toggles() -> bool:
	var valid_signal_paths = _get_valid_custom_signal_paths()
	
	# 1. Back up all currently active toggle states into volatile memory
	var current_values_backup = {}
	for path in valid_signal_paths:
		if ProjectSettings.has_setting(path):
			current_values_backup[path] = ProjectSettings.get_setting(path)
	
	# 2. Completely purge all custom EventBus settings keys from Godot's internal configuration registry.
	# Setting a property to null instructs Godot to forcefully drop its serialization tracking key.
	for prop in ProjectSettings.get_property_list():
		var path: String = prop["name"]
		if path.begins_with("debug/event_bus/signals/"):
			ProjectSettings.set_setting(path, null)
			
	# 3. Re-serialize all active elements down to project.godot sequentially.
	# Because we are appending them from scratch, Godot saves them in this exact order.
	for index in range(valid_signal_paths.size()):
		var setting_path = valid_signal_paths[index]
		
		# Restore the user's previous preference value (Defaults to false if brand new)
		var saved_toggle_state = current_values_backup.get(setting_path, false)
		
		ProjectSettings.set_setting(setting_path, saved_toggle_state)
		_add_setting_meta(setting_path, TYPE_BOOL, index + 100) # Base offset separates them visually
			
	return true


## Appends custom UI typing hints and ordering instructions to the project configuration dictionary
func _add_setting_meta(path: String, type_enum: int, order_weight: int) -> void:
	ProjectSettings.add_property_info({
		"name": path,
		"type": type_enum,
		"hint": PROPERTY_HINT_NONE,
		"order": order_weight
	})


## Helper to identify core internal node alerts that should be kept out of our logging dashboard
func _is_ignored_signal(sig_name: String, base_signals: Array) -> bool:
	return sig_name in base_signals or sig_name in ["script_changed", "property_list_changed"]


# ==============================================================================
# RUNTIME HOOKS & PROCESSING
# ==============================================================================

## Discovers custom signals at runtime launch and establishes intercepting proxy closures
func _run_runtime_setup() -> void:
	var base_node_signals = ClassDB.class_get_signal_list("Node").map(func(s): return s.name)
	
	for sig_info in get_signal_list():
		var sig_name = sig_info["name"]
		if _is_ignored_signal(sig_name, base_node_signals):
			continue
			
		_evaluate_and_hook_signal(sig_info)


## Connects an intercepting lambda macro to a signal if its debug toggle is enabled
func _evaluate_and_hook_signal(sig_info: Dictionary) -> void:
	var sig_name = sig_info["name"]
	var setting_path = "debug/event_bus/signals/" + sig_name
	
	var is_enabled = ProjectSettings.get_setting(setting_path) if ProjectSettings.has_setting(setting_path) else false
	if not is_enabled:
		return
		
	var sig: Signal = get(sig_name)
	var expected_arg_count = sig_info["args"].size()
	var arg_names = sig_info["args"].map(func(arg): return arg["name"])
	
	# Binds an 8-parameter anonymous proxy layout to support generic variable payloads cleanly
	sig.connect(func(arg1=null, arg2=null, arg3=null, arg4=null, arg5=null, arg6=null, arg7=null, arg8=null): 
		var raw_args = [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8]
		var passed_args = raw_args.slice(0, expected_arg_count)
		
		_process_signal_log(sig, passed_args, arg_names)
	)


## Unpacks the active system properties to assemble a visual terminal report
func _process_signal_log(sig: Signal, args: Array, arg_names: Array) -> void:
	var time = Time.get_time_string_from_system()
	var emitter_string = _find_caller_source()
	var formatted_arguments = _format_arguments_by_config(args, arg_names)
	
	_print_signal_block(sig.get_name(), emitter_string, formatted_arguments, time, sig.get_connections())


## Walks up the active engine engine call stack to locate exactly who fired the signal
func _find_caller_source() -> String:
	var stack = get_stack()
	# Index 3 isolates the source node that called .emit() on our global Bus instance
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


## Maps raw signal argument values to their script parameter names if configured to do so
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

## Outputs a comprehensive, stylized diagnostic report block directly into the Godot Output console
func _print_signal_block(sig_name: String, emitter: String, args: Variant, time: String, connections: Array) -> void:
	print("\n========== SIGNAL EMITTED ==========")
	print("Signal Name : ", sig_name)
	print("Real Emitter: ", emitter)
	print("Infos/Args  : ", args)
	print("Time        : ", time)
	
	_print_receivers(connections)
	print("=======================================\n")


## Lists every object currently listening to this signal, along with their connected target method names
func _print_receivers(connections: Array) -> void:
	# Filter out our internal logging interceptors to keep the receiver printout pristine
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
# DELEGATED STRUCTURAL SUB-FUNCTIONS
# ==============================================================================

## Sweeps the custom class definitions to dynamically build the absolute configuration paths for settings menu generation
func _get_valid_custom_signal_paths() -> Array:
	var paths = []
	var base_node_signals = ClassDB.class_get_signal_list("Node").map(func(s): return s.name)
	for sig_info in get_signal_list():
		var sig_name = sig_info["name"]
		if not _is_ignored_signal(sig_name, base_node_signals):
			paths.append("debug/event_bus/signals/" + sig_name)
	return paths


## Inspects a target callable reference to safely extract its executable label format string
func _get_callable_action_text(callable: Callable) -> String:
	if callable.is_custom():
		return "will run an: [Anonymous Lambda Function]"
	return str("will run method: .", callable.get_method(), "()")


## Locates the script location path and filename associated with a target listener object
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


## Parses reflection arrays or raw source lines to pinpoint exactly what line a callback method starts on
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
