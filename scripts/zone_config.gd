class_name ZoneConfig
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var depth_meters: int = 0
@export var unlock_cost: int = 0

@export_group("Palette")
@export var water_top: Color = Color(0.08, 0.2, 0.4)
@export var water_bottom: Color = Color(0.02, 0.05, 0.12)
@export var ambient_tint: Color = Color(1, 1, 1)
@export var background_texture: Texture2D = null

@export_group("Spawning")
@export var spawn_weights: Dictionary = {"sardine": 1.0, "grouper": 0.0, "tuna": 0.0}
