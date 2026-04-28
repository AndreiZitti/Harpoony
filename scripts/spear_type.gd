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
@export var twin_shot: int = 0  # if > 0, fire an additional spear per click (TODO wiring in diver._try_fire)

@export_group("Behavior — Pierce")
@export_range(1, 10, 1) var pierce_count: int = 1
@export_range(0.0, 1.0, 0.05) var crit_chance: float = 0.0      # legacy — unused after redesign, kept for save-compat
@export var perfect_strike: int = 0       # legacy — unused after redesign
@export var sonic_boom: int = 0           # legacy — unused after redesign

@export_group("Behavior — Normal")
@export_range(0.0, 5.0, 0.05) var bullseye_bonus: float = 0.0  # per-level bonus added on dead-center hits

@export_group("Behavior — Heavy")
@export var penetration_depth: int = 0   # how many extra small/med fish Heavy can pass through before reeling
@export var black_hole_tip: int = 0      # keystone: pulls small/med fish to impact and insta-catches them
@export var seismic_roar: int = 0        # keystone: defended fish lose defenses for 10s after a Heavy hit
@export var whale_sonar: int = 0         # keystone: each dive force-spawns a trophy with a HUD marker

@export_group("Behavior — Net")
@export_range(0.0, 200.0, 1.0) var net_radius: float = 0.0
@export_range(1, 12, 1) var net_max_catch: int = 1
@export var catch_size_classes: Array[StringName] = [&"small", &"medium", &"large", &"trophy"]
@export var catches_medium: int = 0   # legacy — kept so existing saves don't break; replaced by net_max_catch+keystones
@export var lure_net: int = 0         # legacy — replaced by lure_pulse
@export var lure_pulse: int = 0       # ramp: post-cast 1s pull on small fish toward net center
@export var standing_wave: int = 0    # keystone: net stays open as a 3s trap
@export var tagging_net: int = 0      # keystone: escaped fish are tagged for 2x cash on next catch
@export var schooling_bonus: int = 0  # keystone: 5+ fish in a single cast → each worth 2x

@export_group("Upgrades")
# Each entry: { "key": { "name", "description", "max_level", "costs": Array[int], "field": String, "step": float } }
# field is the SpearType property to add (level * step) onto when computing effective stats.
@export var upgrades: Dictionary = {}
