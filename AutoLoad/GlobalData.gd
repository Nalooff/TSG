extends Node

# ===============================================
# CAMERAS
# ===============================================
const CAMERA_2D_LAYER = 20
const CAMERA_2D_LAYER_BITMASK = 1<<19

# ===============================================
# GRID RULES
# ===============================================
const GRID_WIDTH: int = 15
const GRID_DEPTH: int = 15
const GRID_HEIGHT: int = 4
const GRID_CENTER: Vector3 = Vector3(GRID_WIDTH, 0, GRID_DEPTH) * CELL_SIZE / 2.0
const CELL_SIZE: float = 2.0

const GRID_LAYER_COLORS = [
	Color8(64, 64, 64),    # Layer 0: Dark Grey
	Color8(127, 127, 127),  # Layer 1: Grey
	Color8(192, 192, 192),  # Layer 2: Light Grey
	Color8(255, 255, 255)   # Layer 3: White
]

# ===============================================
# OBJECT TYPE
# ===============================================
const TILE = {
	COLLISION_LAYER : 1,
	COLLISION_LAYER_BITMASK : 1 << 0,
	COLLISION_MASK : 0,
	COLLISION_MASK_BITMASK : 0,
	OCCUPIES_CELL : true,
}

const PAWN = {
	COLLISION_LAYER : 2,
	COLLISION_LAYER_BITMASK : 1 << 1,
	COLLISION_MASK : 0,
	COLLISION_MASK_BITMASK : 0,
	OCCUPIES_CELL : false,
}

# ===============================================
# GAME STATES / MODES
# ===============================================
enum GameMode {
	PLAY,    # Normal gameplay: selecting units, moving, attacking
	BUILD,   # Map editing: adding/removing tiles using BuildMode
	MENU,  # Game menu / paused state: ignores board clicks entirely
	NONE     # Neutral state (e.g., cutscenes, transitions)
}

# Sub-mode for BUILD state
enum BuildMode { ADD, REMOVE }

# Sub-mode for PLAY state
enum PlayMode {MOVE, SELECT, INTERACT}

# ===============================================
# PARAMETERS NAME
# ===============================================
const COLLISION_LAYER : String = "COLLISION_LAYER"
const COLLISION_LAYER_BITMASK : String = "COLLISION_LAYER_BITMASK"
const COLLISION_MASK : String = "COLLISION_MASK"
const COLLISION_MASK_BITMASK : String = "COLLISION_MASK_BITMASK"
const OCCUPIES_CELL : String = "OCCUPIES_CELL"
