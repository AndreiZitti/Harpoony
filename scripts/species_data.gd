class_name SpeciesData
extends Resource

# Single source of truth for a fish species — name, lore, stats, recommended
# spear, zone hint. Loaded by GameData at startup from data/species/*.tres so
# fish.gd, hud.gd, dive_summary.gd, and the bestiary all read from one place.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var base_value: int = 0
@export var size_class: StringName = &"medium"  # small / medium / large / trophy
@export var hit_radius: float = 12.0
@export var color: Color = Color.WHITE

# Where the player will first encounter this species — used in the locked
# silhouette hint ("Found in the Surface Reef"). String, matching ZoneConfig.id.
@export var found_in_zone: StringName = &"reef"

# Recommended spear (display hint only — gameplay still allows any). Values:
# &"normal" / &"net" / &"heavy".
@export var recommended_spear: StringName = &"normal"

# Behavior flavor — short paragraph shown in the detail panel after the
# description, e.g. "Inflates when threatened — only catchable while deflated."
@export_multiline var behavior_notes: String = ""
