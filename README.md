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
| **Interact / Build** | Left Mouse Button | — | Place/remove blocks or select/move units based on state |
| **Switch Build Mode** | <kbd>B</kbd> Key | — | Toggle between **ADD** and **REMOVE** block modes |
| **Toggle Game Mode** | <kbd>V</kbd> Key | — | Switch between **PLAY** and **BUILD** game states |
| **Rotate Camera** | Middle Mouse Button *(Hold & Drag)* | <kbd>Left</kbd> / <kbd>Right</kbd> Arrow Keys | Orbit perspective camera around grid center |
| **Toggle View Mode** | <kbd>Enter</kbd> Key | — | Switch between 3D Perspective and 2D Top-Down View |

---

## 🚀 Key Engine Features

* **Voxel Grid Construction**: Real-time multi-cell block placement and removal with automatic vertical layer stacking.
* **Adaptive Wireframe Preview**: Live dynamic bounding outline that conforms to non-flat terrain surfaces and displays placement validity.
* **Dual-View Camera System**: Seamlessly switch between an interactive 3D perspective camera with smooth orbit rotation and an orthogonal 2D top-down view.
* **Procedural Map Generation**: Map loading supports Simplex noise heightmaps, custom image topology heightmaps, or standard flat ground.
* **Automated Event Bus & Logging**: Global signal dispatcher (`EventBus.gd`) that automatically registers signals to `ProjectSettings` for real-time console debug tracking.
* **Unit Management & Dijkstra Pathfinding**: Entity system featuring Dijkstra-based pathfinding engine with Binary Min-Heap optimization, Zone of Control (ZoC) reflection, line-of-sight (LOS) height checks, and command disruption mechanics.

---
## 📂 Project Architecture

```
├── AutoLoad
│   ├── EventBus.gd
│   ├── GlobalData.gd
│   └── Globals.gd
├── General
│   ├── select_cursor.gd
│   ├── tile_handler.gd
│   ├── world.gd
│   └── world.tscn
├── GridGeneration
│   ├── Abstract
│   │   ├── grid_state.gd
│   │   ├── preview_mesh_builder.gd
│   │   └── tiles.gd
│   ├── block_preview.gd
│   ├── grid.gd
│   ├── grid.tscn
│   ├── map_generator.gd
│   ├── piece_placer.gd
│   └── piece_remover.gd
├── script_templates
│   └── BasePawn
│       └── default pawn.gd
└── UnitManagment
    ├── Abstract
    │   ├── base_pawn.gd
    │   └── base_pawn.tscn
    ├── Pawns
    │   ├── combat_component.gd
    │   ├── movement_component.gd
    │   └── zone_of_control_component.gd
    ├── preview_movement.gd
    ├── select_unit.gd
    ├── unit_manager.gd
    ├── unit_manager.tscn
    └── unit_movement.gd
