class_name SpearType
extends Resource

@export_group("Identity")
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var color: Color = Color(0.85, 0.85, 0.9)
@export var icon_glyph: String = "│"

@export_group("Economy")
@export var unlock_cost: int = 0

@export_group("Behavior — Base")
@export_range(0.5, 3.0, 0.05) var speed_mult: float = 1.0
@export_range(0.5, 3.0, 0.05) var reel_speed_mult: float = 1.0
@export_range(0.0, 32.0, 1.0) var hit_radius_bonus: float = 0.0
@export_range(0.5, 3.0, 0.05) var value_bonus: float = 1.0
@export var bypasses_defenses: bool = false  # if true, fish.deflects_spear is ignored

@export_group("Behavior — Pierce")
@export_range(1, 10, 1) var pierce_count: int = 1

@export_group("Behavior — Net")
@export_range(0.0, 200.0, 1.0) var net_radius: float = 0.0
@export_range(1, 12, 1) var net_max_catch: int = 1
@export var catch_size_classes: Array[StringName] = [&"small", &"medium", &"large", &"trophy"]

@export_group("Upgrades")
# Each entry: { "key": { "name", "description", "max_level", "costs": Array[int], "field": String, "step": float } }
# field is the SpearType property to add (level * step) onto when computing effective stats.
@export var upgrades: Dictionary = {}
