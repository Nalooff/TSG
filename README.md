
# TSG - Tactical Strategy Game

TSG is a turn-based 3D/2D strategy game built in Godot 4.x. Command your army of pawns led by vital Commanders across dynamically generated voxel terrain. Use height advantages, tactical placement, and Risk-style contested dice rolls to eliminate your opponent's forces and secure victory.

---

## 🎯 Gameplay & Victory Conditions

* **Army Composition**: Each player commands a custom pool of Pawns overseen by 3 key Commanders.
* **Winning & Losing**: You lose instantly if **all 3 Commanders are slain** or **all Pawns are wiped out**.
* **Combat System**: Capturing opposing units is resolved through contested dice rolls (inspired by *Risk*).
* **Dice Modifiers**: Your combat dice pools expand based on unit properties, Commander proximity coverage, type matchups, and elevation advantages.

---

## 🕹️ Controls

| Action | Primary Input | Secondary Input | Description |
| :--- | :--- | :--- | :--- |
| **Interact / Build** | Left Mouse Button | — | Place or remove terrain blocks at target cursor |
| **Switch Build Mode** | <kbd>B</kbd> Key | — | Toggle between **ADD** and **REMOVE** block modes |
| **Rotate Camera** | Right Mouse Button *(Hold & Drag)* | <kbd>Left</kbd> / <kbd>Right</kbd> Arrow Keys | Orbit perspective camera around grid center |
| **Toggle View Mode** | <kbd>Enter</kbd> Key | — | Switch between 3D Perspective and 2D Top-Down |

---

## 🚀 Key Engine Features

* **Voxel Grid Construction**: Real-time multi-cell block placement and removal with automatic vertical layer stacking.
* **Adaptive Wireframe Preview**: Live dynamic bounding outline that conforms to non-flat terrain surfaces and displays placement validity.
* **Dual-View Camera System**: Seamlessly switch between an interactive 3D perspective camera with smooth orbit rotation and a top-down 2D view.
* **Procedural Map Generation**: Map loading supports Simplex noise heightmaps, custom image topology height maps, or standard flat ground.
* **Automated Event Bus**: Global signal dispatcher that automatically registers signals to `ProjectSettings` for real-time console debug tracking.

---

## 📂 Project Architecture

```
├── AutoLoad/
│   ├── EventBus.gd       # Centralized signal broker with auto-debug logging
│   └── GlobalData.gd     # Core game parameters, collision layers, and constants
├── GridGeneration/
│   ├── BaseScript/       # Abstract handlers & wireframe builders
│   ├── block_preview.gd  # Placement preview & terrain conformity algorithms
│   ├── grid.gd           # Core voxel grid matrix & mesh rendering logic
│   └── map_generator.gd  # Procedural Simplex & topology map generators
└── Script/
    ├── world.gd          # Dual camera controller & rotation system
    ├── select_cursor.gd   # 3D grid raycasting system
    └── base_pawn.gd       # Pawn entity behavior & camera-facing billboard logic
