# Spearfishing Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current neural-network training game with an oxygen-based spearfishing game, where the player dives from a boat, clicks fish to throw spears, and cashes out at the surface for upgrades.

**Architecture:** Single `main.tscn` with a state machine driving four phases (SURFACE / DIVING / UNDERWATER / RESURFACING). Reuses the current phase-fade framework and upgrade-shop framework, but replaces all gameplay (network, cursor, data points) with diver + spears + fish. `GameData` autoload holds cash, oxygen, and upgrades.

**Tech Stack:** Godot 4.6, GDScript. No external assets — all visuals drawn via `_draw()`.

**Design doc:** [2026-04-24-spearfishing-redesign-design.md](2026-04-24-spearfishing-redesign-design.md)

**Testing approach:** Godot has no unit tests in this project. "Verification" = run the game (press F5 in Godot editor or `godot --headless` is not suitable for visual), observe specific behavior, confirm it matches expected. Each task below lists concrete in-game observations to confirm.

---

## Task 0: Delete old neural-network files

**Files:**
- Delete: `scripts/data_point.gd` + `scripts/data_point.gd.uid`
- Delete: `scripts/data_spawner.gd` + `scripts/data_spawner.gd.uid`
- Delete: `scripts/network.gd` + `scripts/network.gd.uid`
- Delete: `scripts/cursor.gd` + `scripts/cursor.gd.uid`
- Delete: `scenes/data_point.tscn`

**Step 1: Remove files**

```bash
rm scripts/data_point.gd scripts/data_point.gd.uid
rm scripts/data_spawner.gd scripts/data_spawner.gd.uid
rm scripts/network.gd scripts/network.gd.uid
rm scripts/cursor.gd scripts/cursor.gd.uid
rm scenes/data_point.tscn
```

**Step 2: Verify**

- Project will NOT compile/run until Task 1 rewrites `GameData`. That's expected.
- Confirm with `git status` that the five scripts + one scene are deleted.

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove neural-network gameplay files (pre-spearfishing pivot)"
```

---

## Task 1: Rewrite `GameData` autoload

Replace stages/accuracy/combo with cash/oxygen/dive state and the new 8-upgrade table.

**Files:**
- Rewrite: `scripts/game_data.gd`

**Step 1: Replace file contents**

```gdscript
extends Node

# Signals
signal cash_changed(amount: float)
signal oxygen_changed(oxygen: float)
signal dive_state_changed(state: String)  # "surface" | "diving" | "underwater" | "resurfacing"

# Persistent state
var cash: float = 0.0
var dive_number: int = 0

# Per-dive state
var dive_cash: float = 0.0
var oxygen: float = 45.0
var dive_state: String = "surface"

# Upgrade levels
var upgrade_levels: Dictionary = {
	"oxygen": 0,
	"spears": 0,
	"spear_speed": 0,
	"reel_speed": 0,
	"hit_radius": 0,
	"lure": 0,
	"fish_value": 0,
	"trophy_room": 0,
}

# Upgrade definitions
var upgrades: Dictionary = {
	"oxygen": {
		"name": "Oxygen Tank",
		"description": "Longer dive time per tank level",
		"max_level": 5,
		"costs": [20, 50, 120, 300, 800],
	},
	"spears": {
		"name": "Spears",
		"description": "Carry more spears — fire multiple at once",
		"max_level": 4,
		"costs": [100, 300, 900, 2500],
	},
	"spear_speed": {
		"name": "Spear Speed",
		"description": "Spears fly faster",
		"max_level": 4,
		"costs": [30, 90, 250, 700],
	},
	"reel_speed": {
		"name": "Reel Speed",
		"description": "Reel fish in faster",
		"max_level": 4,
		"costs": [40, 120, 350, 900],
	},
	"hit_radius": {
		"name": "Spear Tip",
		"description": "Wider effective hit area",
		"max_level": 3,
		"costs": [50, 180, 500],
	},
	"lure": {
		"name": "Lure",
		"description": "Attract more fish per dive",
		"max_level": 4,
		"costs": [60, 180, 500, 1400],
	},
	"fish_value": {
		"name": "Market Price",
		"description": "All fish sell for more cash",
		"max_level": 5,
		"costs": [80, 220, 600, 1600, 4000],
	},
	"trophy_room": {
		"name": "Trophy Room",
		"description": "Keep a share of dive cash if oxygen runs out",
		"max_level": 3,
		"costs": [200, 600, 1800],
	},
}


# --- Derived getters ---

func get_oxygen_capacity() -> float:
	return 45.0 + upgrade_levels["oxygen"] * 10.0


func get_spear_count() -> int:
	return 1 + upgrade_levels["spears"]


func get_spear_speed() -> float:
	return 800.0 * (1.0 + upgrade_levels["spear_speed"] * 0.2)


func get_reel_speed() -> float:
	return 180.0 * (1.0 + upgrade_levels["reel_speed"] * 0.2)


func get_hit_radius_bonus() -> float:
	return upgrade_levels["hit_radius"] * 8.0


func get_spawn_rate_multiplier() -> float:
	return 1.0 + upgrade_levels["lure"] * 0.25


func get_fish_value_multiplier() -> float:
	return 1.0 + upgrade_levels["fish_value"] * 0.2


func get_trophy_room_percent() -> float:
	return upgrade_levels["trophy_room"] * 0.05


# --- Cash / oxygen mutators ---

func add_dive_cash(amount: float) -> void:
	dive_cash += amount
	cash_changed.emit(cash + dive_cash)


func set_oxygen(value: float) -> void:
	oxygen = clampf(value, 0.0, get_oxygen_capacity())
	oxygen_changed.emit(oxygen)


func start_dive() -> void:
	dive_number += 1
	dive_cash = 0.0
	set_oxygen(get_oxygen_capacity())
	set_dive_state("diving")


func finish_dive(lost_oxygen: bool) -> void:
	# Trophy Room: if oxygen ran out, keep a share of dive cash
	var kept: float = dive_cash
	if lost_oxygen:
		kept = dive_cash * get_trophy_room_percent()
	cash += kept
	dive_cash = 0.0
	cash_changed.emit(cash)
	set_dive_state("surface")


func set_dive_state(state: String) -> void:
	dive_state = state
	dive_state_changed.emit(state)


# --- Shop ---

func can_buy_upgrade(key: String) -> bool:
	var level = upgrade_levels[key]
	var upgrade = upgrades[key]
	if level >= upgrade["max_level"]:
		return false
	return cash >= upgrade["costs"][level]


func buy_upgrade(key: String) -> bool:
	if not can_buy_upgrade(key):
		return false
	var level = upgrade_levels[key]
	cash -= upgrades[key]["costs"][level]
	upgrade_levels[key] += 1
	cash_changed.emit(cash)
	return true


func get_upgrade_cost(key: String) -> int:
	var level = upgrade_levels[key]
	var upgrade = upgrades[key]
	if level >= upgrade["max_level"]:
		return -1
	return upgrade["costs"][level]
```

**Step 2: Verify by static parse**

- Open `project.godot` in Godot editor. GameData should still be registered as autoload and compile.
- Run the project — it will fail because `main.gd` and `hud.gd` reference removed fields. Fine; next tasks fix that.

**Step 3: Commit**

```bash
git add scripts/game_data.gd
git commit -m "feat: rewrite GameData for spearfishing — cash, oxygen, 8 upgrades"
```

---

## Task 2: Restructure `main.tscn` skeleton

Strip neural-network nodes, add Diver + FishSpawner + OxygenTimer placeholders.

**Files:**
- Rewrite: `scenes/main.tscn`

**Step 1: Replace contents**

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1"]
[ext_resource type="Script" path="res://scripts/fish_spawner.gd" id="2"]
[ext_resource type="Script" path="res://scripts/hud.gd" id="3"]
[ext_resource type="Script" path="res://scripts/upgrade_shop.gd" id="4"]

[node name="Main" type="Node2D"]
script = ExtResource("1")

[node name="Diver" type="Node2D" parent="."]
; script assigned via code in Task 5 — diver.tscn will be instanced here

[node name="FishSpawner" type="Node2D" parent="."]
script = ExtResource("2")

[node name="OxygenTimer" type="Timer" parent="."]
wait_time = 1.0
autostart = false

[node name="HUD" type="CanvasLayer" parent="."]
script = ExtResource("3")

[node name="UpgradeShop" type="CanvasLayer" parent="."]
layer = 10
script = ExtResource("4")
```

**Note:** `Diver` is a placeholder `Node2D`. Task 5 will replace it with an instance of `diver.tscn`. `scripts/fish_spawner.gd` doesn't exist yet; the scene file will still parse because Godot resolves ext_resources lazily at load time. If Godot errors, either create empty stub scripts first or defer this scene edit to Task 5/7.

**Fallback if Godot refuses to open the scene:** create empty stub files for `fish_spawner.gd` and `diver.gd` before opening:

```bash
printf "extends Node2D\n" > scripts/fish_spawner.gd
printf "extends Node2D\n" > scripts/diver.gd
```

**Step 2: Verify**

- Open the scene in Godot editor. Confirm node tree shows: Main → Diver, FishSpawner, OxygenTimer, HUD, UpgradeShop.
- Project will still fail to run (main.gd references old API).

**Step 3: Commit**

```bash
git add scenes/main.tscn scripts/fish_spawner.gd scripts/diver.gd
git commit -m "feat: main.tscn skeleton for spearfishing"
```

---

## Task 3: Rewrite `main.gd` state machine

Drive the four states. Oxygen drains during UNDERWATER. Fades between shop ↔ fishing.

**Files:**
- Rewrite: `scripts/main.gd`

**Step 1: Replace contents**

```gdscript
extends Node2D

@onready var diver: Node2D = $Diver
@onready var fish_spawner: Node2D = $FishSpawner
@onready var oxygen_timer: Timer = $OxygenTimer
@onready var hud: CanvasLayer = $HUD
@onready var upgrade_shop: CanvasLayer = $UpgradeShop

# Fade transition
var phase_fade: float = 0.0
const PHASE_FADE_DURATION = 0.4
var pending_state: String = ""

const DIVE_TRAVEL_DURATION = 1.5
const RESURFACE_TRAVEL_DURATION = 1.0
var travel_timer: float = 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.04, 0.08, 0.14))

	upgrade_shop.next_dive_pressed.connect(_on_dive_pressed)
	oxygen_timer.timeout.connect(_on_oxygen_tick)

	# Start on surface with shop open
	GameData.set_dive_state("surface")
	upgrade_shop.show_shop()
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(false)


func _process(delta: float) -> void:
	match GameData.dive_state:
		"diving":
			travel_timer += delta
			# Diver travels from top to center — managed in diver.gd via a t in [0,1]
			if diver.has_method("update_dive_travel"):
				diver.update_dive_travel(clampf(travel_timer / DIVE_TRAVEL_DURATION, 0.0, 1.0))
			if travel_timer >= DIVE_TRAVEL_DURATION:
				_enter_underwater()

		"underwater":
			# Oxygen drains via OxygenTimer (1/sec); nothing to tick here
			pass

		"resurfacing":
			travel_timer += delta
			if diver.has_method("update_resurface_travel"):
				diver.update_resurface_travel(clampf(travel_timer / RESURFACE_TRAVEL_DURATION, 0.0, 1.0))
			if travel_timer >= RESURFACE_TRAVEL_DURATION:
				_enter_surface()


func _on_dive_pressed() -> void:
	GameData.start_dive()
	travel_timer = 0.0
	upgrade_shop.hide_shop()
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(true)


func _enter_underwater() -> void:
	GameData.set_dive_state("underwater")
	oxygen_timer.start()
	if fish_spawner.has_method("start_spawning"):
		fish_spawner.start_spawning()
	if diver.has_method("enable_fishing"):
		diver.enable_fishing(true)


func _on_oxygen_tick() -> void:
	if GameData.dive_state != "underwater":
		return
	GameData.set_oxygen(GameData.oxygen - 1.0)
	if GameData.oxygen <= 0.0:
		_begin_resurface(true)


func begin_manual_resurface() -> void:
	if GameData.dive_state == "underwater":
		_begin_resurface(false)


func _begin_resurface(lost_oxygen: bool) -> void:
	oxygen_timer.stop()
	if fish_spawner.has_method("stop_spawning"):
		fish_spawner.stop_spawning()
	if diver.has_method("enable_fishing"):
		diver.enable_fishing(false)
	GameData.set_dive_state("resurfacing")
	travel_timer = 0.0
	# Cache whether oxygen was lost to be handled in _enter_surface
	set_meta("lost_oxygen", lost_oxygen)


func _enter_surface() -> void:
	var lost_oxygen = get_meta("lost_oxygen", false)
	GameData.finish_dive(lost_oxygen)
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(false)
	upgrade_shop.show_shop()
```

**Step 2: Verify**

- This will still fail to run because `hud.gd`, `upgrade_shop.gd`, and `diver` are not compatible yet.
- Don't try to run yet — next tasks fix each.

**Step 3: Commit**

```bash
git add scripts/main.gd
git commit -m "feat: main.gd state machine — surface/diving/underwater/resurfacing"
```

---

## Task 4: Rewrite HUD

Oxygen bar, dive cash, total cash, spear inventory row, resurface button.

**Files:**
- Rewrite: `scripts/hud.gd`

**Step 1: Replace contents**

```gdscript
extends CanvasLayer

var oxygen_bar: ProgressBar
var oxygen_label: Label
var dive_cash_label: Label
var total_cash_label: Label
var spear_row: HBoxContainer
var resurface_button: Button
var _spear_count_cache: int = -1


func _ready() -> void:
	_build_ui()
	GameData.cash_changed.connect(_on_cash_changed)
	GameData.oxygen_changed.connect(_on_oxygen_changed)
	GameData.dive_state_changed.connect(_on_dive_state_changed)
	_refresh()


func _build_ui() -> void:
	# Top bar
	var top = MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 80
	top.add_theme_constant_override("margin_left", 20)
	top.add_theme_constant_override("margin_right", 20)
	top.add_theme_constant_override("margin_top", 15)
	add_child(top)

	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 30)
	top.add_child(top_hbox)

	# Total cash (left)
	total_cash_label = Label.new()
	total_cash_label.text = "$0"
	total_cash_label.add_theme_font_size_override("font_size", 22)
	total_cash_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	total_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(total_cash_label)

	# Oxygen bar (center)
	var oxy_vbox = VBoxContainer.new()
	oxy_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oxy_vbox.custom_minimum_size = Vector2(300, 0)
	top_hbox.add_child(oxy_vbox)

	oxygen_label = Label.new()
	oxygen_label.text = "OXYGEN 45s"
	oxygen_label.add_theme_font_size_override("font_size", 12)
	oxygen_label.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	oxygen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	oxy_vbox.add_child(oxygen_label)

	oxygen_bar = ProgressBar.new()
	oxygen_bar.min_value = 0.0
	oxygen_bar.max_value = 45.0
	oxygen_bar.value = 45.0
	oxygen_bar.show_percentage = false
	oxygen_bar.custom_minimum_size = Vector2(300, 18)
	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.12, 0.2)
	bar_bg.set_corner_radius_all(6)
	oxygen_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fg = StyleBoxFlat.new()
	bar_fg.bg_color = Color(0.3, 0.7, 1.0)
	bar_fg.set_corner_radius_all(6)
	oxygen_bar.add_theme_stylebox_override("fill", bar_fg)
	oxy_vbox.add_child(oxygen_bar)

	# Dive cash (right)
	dive_cash_label = Label.new()
	dive_cash_label.text = ""
	dive_cash_label.add_theme_font_size_override("font_size", 22)
	dive_cash_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	dive_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dive_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(dive_cash_label)

	# Spear inventory (bottom-center)
	var bottom = MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -70
	bottom.add_theme_constant_override("margin_bottom", 16)
	add_child(bottom)

	spear_row = HBoxContainer.new()
	spear_row.alignment = BoxContainer.ALIGNMENT_CENTER
	spear_row.add_theme_constant_override("separation", 8)
	bottom.add_child(spear_row)

	# Resurface button (bottom-right)
	var btn_margin = MarginContainer.new()
	btn_margin.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn_margin.offset_left = -200
	btn_margin.offset_top = -70
	btn_margin.add_theme_constant_override("margin_right", 30)
	btn_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(btn_margin)

	resurface_button = Button.new()
	resurface_button.text = "RESURFACE"
	resurface_button.custom_minimum_size = Vector2(160, 40)
	resurface_button.pressed.connect(_on_resurface_pressed)
	btn_margin.add_child(resurface_button)


func _refresh() -> void:
	_on_cash_changed(GameData.cash)
	_on_oxygen_changed(GameData.oxygen)
	_on_dive_state_changed(GameData.dive_state)
	_rebuild_spear_row()


func _on_cash_changed(_amount: float) -> void:
	total_cash_label.text = "$%d" % int(GameData.cash)
	if GameData.dive_state == "underwater":
		dive_cash_label.text = "+$%d" % int(GameData.dive_cash)
	else:
		dive_cash_label.text = ""


func _on_oxygen_changed(value: float) -> void:
	oxygen_bar.max_value = GameData.get_oxygen_capacity()
	oxygen_bar.value = value
	oxygen_label.text = "OXYGEN %.0fs" % value
	# Color shifts as oxygen empties
	var ratio = value / GameData.get_oxygen_capacity()
	var bar_fg = StyleBoxFlat.new()
	bar_fg.bg_color = Color(1.0, 0.3, 0.3).lerp(Color(0.3, 0.7, 1.0), ratio)
	bar_fg.set_corner_radius_all(6)
	oxygen_bar.add_theme_stylebox_override("fill", bar_fg)


func _on_dive_state_changed(state: String) -> void:
	var underwater = state == "underwater"
	resurface_button.visible = underwater
	spear_row.visible = underwater or state == "diving" or state == "resurfacing"
	if state == "underwater":
		_rebuild_spear_row()
	_on_cash_changed(0.0)


func _rebuild_spear_row() -> void:
	for child in spear_row.get_children():
		child.queue_free()
	var count = GameData.get_spear_count()
	for i in count:
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = Color(0.7, 0.85, 1.0)
		dot.name = "Spear%d" % i
		spear_row.add_child(dot)


func update_spear_state(index: int, state: String) -> void:
	# state: "ready" | "flying" | "reeling"
	if index < 0 or index >= spear_row.get_child_count():
		return
	var dot = spear_row.get_child(index) as ColorRect
	if dot == null:
		return
	match state:
		"ready":
			dot.color = Color(0.7, 0.85, 1.0)
		"flying":
			dot.color = Color(1.0, 0.85, 0.3)
		"reeling":
			dot.color = Color(0.4, 0.6, 1.0)


func _on_resurface_pressed() -> void:
	var main = get_tree().current_scene
	if main and main.has_method("begin_manual_resurface"):
		main.begin_manual_resurface()
```

**Step 2: Verify**

- Save, reload project in Godot editor. Should compile.
- Still can't run — upgrade_shop.gd still references the old `next_epoch_pressed` signal and stage system.

**Step 3: Commit**

```bash
git add scripts/hud.gd
git commit -m "feat: HUD — oxygen bar, dive/total cash, spear inventory, resurface button"
```

---

## Task 5: Diver scene + script

Owns spear inventory and handles click-to-throw. Surfaces/submerges via travel-progress methods called from main.gd.

**Files:**
- Create: `scenes/diver.tscn`
- Rewrite: `scripts/diver.gd` (stub was created in Task 2)

**Step 1: Write diver.gd**

```gdscript
extends Node2D

const Spear = preload("res://scenes/spear.tscn")

var spears: Array = []  # Array of Spear nodes
var fishing_enabled: bool = false
var surface_y: float = 100.0
var underwater_y: float = 400.0
var in_water: bool = false


func _ready() -> void:
	var viewport = get_viewport_rect().size
	surface_y = 100.0
	underwater_y = viewport.y * 0.5
	position = Vector2(viewport.x * 0.5, surface_y)
	_rebuild_spears()


func set_visible_in_water(flag: bool) -> void:
	in_water = flag
	visible = flag
	if not flag:
		# Recall all spears instantly on surfacing
		for s in spears:
			if is_instance_valid(s):
				s.recall_instant()


func update_dive_travel(t: float) -> void:
	# Interpolate from above-water to underwater mid-screen
	position.y = lerp(surface_y, underwater_y, t)
	queue_redraw()


func update_resurface_travel(t: float) -> void:
	position.y = lerp(underwater_y, surface_y, t)
	queue_redraw()


func enable_fishing(flag: bool) -> void:
	fishing_enabled = flag
	_ensure_spear_count()


func _ensure_spear_count() -> void:
	var target = GameData.get_spear_count()
	if spears.size() != target:
		_rebuild_spears()


func _rebuild_spears() -> void:
	for s in spears:
		if is_instance_valid(s):
			s.queue_free()
	spears.clear()
	var count = GameData.get_spear_count()
	for i in count:
		var spear = Spear.instantiate()
		spear.spear_index = i
		spear.diver_node = self
		add_child(spear)
		spears.append(spear)


func _unhandled_input(event: InputEvent) -> void:
	if not fishing_enabled:
		return
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_throw(get_viewport().get_mouse_position())


func _try_throw(world_target: Vector2) -> void:
	for s in spears:
		if is_instance_valid(s) and s.is_ready():
			s.throw_at(world_target)
			return


func _draw() -> void:
	# Simple diver silhouette — circle head + rectangle body
	if not visible:
		return
	draw_circle(Vector2(0, -12), 10, Color(0.9, 0.85, 0.6))   # head
	draw_rect(Rect2(-8, -2, 16, 24), Color(0.2, 0.3, 0.5))    # body
	draw_circle(Vector2(-4, -12), 3, Color(0.2, 0.6, 1.0, 0.6))  # mask
```

**Step 2: Create diver.tscn**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/diver.gd" id="1"]

[node name="Diver" type="Node2D"]
script = ExtResource("1")
```

**Step 3: Update main.tscn to instance diver**

Edit `scenes/main.tscn` — replace the placeholder `Diver` node with an instance:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1"]
[ext_resource type="Script" path="res://scripts/fish_spawner.gd" id="2"]
[ext_resource type="Script" path="res://scripts/hud.gd" id="3"]
[ext_resource type="Script" path="res://scripts/upgrade_shop.gd" id="4"]
[ext_resource type="PackedScene" path="res://scenes/diver.tscn" id="5"]

[node name="Main" type="Node2D"]
script = ExtResource("1")

[node name="Diver" parent="." instance=ExtResource("5")]

[node name="FishSpawner" type="Node2D" parent="."]
script = ExtResource("2")

[node name="OxygenTimer" type="Timer" parent="."]
wait_time = 1.0
autostart = false

[node name="HUD" type="CanvasLayer" parent="."]
script = ExtResource("3")

[node name="UpgradeShop" type="CanvasLayer" parent="."]
layer = 10
script = ExtResource("4")
```

**Step 4: Verify**

- Game still won't run end-to-end because spear.tscn/gd don't exist yet.
- But syntax-check in Godot should pass for diver.gd.

**Step 5: Commit**

```bash
git add scenes/diver.tscn scripts/diver.gd scenes/main.tscn
git commit -m "feat: diver scene + script — spear inventory, click-to-throw"
```

---

## Task 6: Spear scene + state machine (throw/return, no fish yet)

Implement the full READY → FLYING → (HIT|MISS) → REELING state machine. Hit detection stubs for fish come in Task 8.

**Files:**
- Create: `scripts/spear.gd`
- Create: `scenes/spear.tscn`

**Step 1: Write spear.gd**

```gdscript
extends Node2D

enum State { READY, FLYING, REELING_MISS, REELING_HIT }

var state: int = State.READY
var spear_index: int = 0
var diver_node: Node2D = null
var attached_fish: Node2D = null

# Movement
var flight_dir: Vector2 = Vector2.ZERO
var flight_target: Vector2 = Vector2.ZERO
var flight_distance_remaining: float = 0.0
const MISS_OVERSHOOT = 80.0


func is_ready() -> bool:
	return state == State.READY


func _ready() -> void:
	_sync_hud()


func throw_at(world_target: Vector2) -> void:
	if state != State.READY:
		return
	# Diver is at own global position; spear starts there too
	global_position = diver_node.global_position
	flight_target = world_target
	flight_dir = (world_target - global_position).normalized()
	flight_distance_remaining = global_position.distance_to(world_target)
	state = State.FLYING
	_sync_hud()
	queue_redraw()


func attach_to_fish(fish: Node2D) -> void:
	if state != State.FLYING:
		return
	attached_fish = fish
	if fish.has_method("on_speared"):
		fish.on_speared(self)
	state = State.REELING_HIT
	_sync_hud()


func recall_instant() -> void:
	state = State.READY
	attached_fish = null
	if diver_node:
		global_position = diver_node.global_position
	_sync_hud()
	queue_redraw()


func _process(delta: float) -> void:
	match state:
		State.READY:
			# Sit on diver
			if diver_node:
				global_position = diver_node.global_position
		State.FLYING:
			var speed = GameData.get_spear_speed()
			var step = speed * delta
			global_position += flight_dir * step
			flight_distance_remaining -= step
			if flight_distance_remaining <= -MISS_OVERSHOOT:
				# Miss — begin fast reel
				state = State.REELING_MISS
				_sync_hud()
		State.REELING_MISS:
			var speed = GameData.get_spear_speed()  # Miss recalls at spear speed (fast)
			_reel_toward_diver(speed, delta)
		State.REELING_HIT:
			var speed = GameData.get_reel_speed()  # Hit reels slower
			_reel_toward_diver(speed, delta)
			if attached_fish and is_instance_valid(attached_fish):
				attached_fish.global_position = global_position
	queue_redraw()


func _reel_toward_diver(speed: float, delta: float) -> void:
	if not diver_node:
		return
	var to_diver = diver_node.global_position - global_position
	var dist = to_diver.length()
	if dist < 8.0:
		_arrive()
		return
	global_position += to_diver.normalized() * speed * delta


func _arrive() -> void:
	if state == State.REELING_HIT and attached_fish and is_instance_valid(attached_fish):
		var value = attached_fish.get_cash_value() if attached_fish.has_method("get_cash_value") else 0
		GameData.add_dive_cash(value)
		attached_fish.queue_free()
		attached_fish = null
	state = State.READY
	_sync_hud()


func _sync_hud() -> void:
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("update_spear_state"):
		var hud_state = "ready"
		match state:
			State.FLYING:
				hud_state = "flying"
			State.REELING_MISS, State.REELING_HIT:
				hud_state = "reeling"
		hud.update_spear_state(spear_index, hud_state)


func _draw() -> void:
	if state == State.READY:
		return
	# Taut line from diver to spear
	if diver_node:
		var local_diver = to_local(diver_node.global_position)
		draw_line(Vector2.ZERO, local_diver, Color(0.9, 0.9, 0.95, 0.6), 1.5)
	# Spear body
	var length = 20.0
	var width = 3.0
	var angle = flight_dir.angle() if state == State.FLYING else (diver_node.global_position - global_position).angle() + PI
	draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
	draw_rect(Rect2(-length / 2, -width / 2, length, width), Color(0.85, 0.85, 0.9))
	# Tip triangle
	var tip_a = Vector2(length / 2, 0)
	var tip_b = Vector2(length / 2 - 6, -4)
	var tip_c = Vector2(length / 2 - 6, 4)
	draw_polygon(PackedVector2Array([tip_a, tip_b, tip_c]), PackedColorArray([Color(0.95, 0.9, 0.6)]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
```

**Step 2: Create spear.tscn**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/spear.gd" id="1"]

[node name="Spear" type="Node2D"]
script = ExtResource("1")
```

**Step 3: Verify by running**

- Launch project (F5 in Godot editor).
- Expected sequence:
  1. Opens on surface with shop overlay + oxygen bar full.
  2. Press the "DIVE" button (requires Task 9 for the shop to send the new signal — **skip to step 5 if shop still emits old signal**).
  3. Diver travels from top to middle of screen.
  4. Click anywhere — spear flies from diver to click point, overshoots slightly, then flies back.
  5. Click again — spear flies again (same behavior).
- If the shop still fails: comment out the shop's `show_shop()` in `main.gd._ready()` temporarily and hardcode a test `_on_dive_pressed()` call 1 second after start to verify the dive/spear loop. Revert after Task 9.

**Step 4: Commit**

```bash
git add scripts/spear.gd scenes/spear.tscn
git commit -m "feat: spear scene + throw/return state machine"
```

---

## Task 7: Fish scene + FishSpawner (no collision yet)

Fish drift across screen. Spawner runs during UNDERWATER.

**Files:**
- Create: `scripts/fish.gd`
- Create: `scenes/fish.tscn`
- Rewrite: `scripts/fish_spawner.gd` (stub was created in Task 2)

**Step 1: Write fish.gd**

```gdscript
extends Node2D

var species: String = "sardine"
var base_value: int = 2
var hit_radius: float = 10.0
var speed: float = 120.0
var velocity: Vector2 = Vector2.ZERO
var wave_amplitude: float = 20.0
var wave_frequency: float = 2.0
var wave_phase: float = 0.0
var age: float = 0.0
var speared: bool = false
var color: Color = Color(0.7, 0.8, 0.9)


func setup(s: String, start_pos: Vector2, direction_right: bool) -> void:
	species = s
	match species:
		"sardine":
			base_value = 2
			hit_radius = 10.0
			speed = 160.0
			color = Color(0.75, 0.85, 0.95)
		"grouper":
			base_value = 10
			hit_radius = 18.0
			speed = 80.0
			color = Color(0.8, 0.6, 0.3)
		"tuna":
			base_value = 40
			hit_radius = 24.0
			speed = 120.0
			color = Color(0.4, 0.5, 0.7)
	velocity = Vector2(speed if direction_right else -speed, 0)
	global_position = start_pos
	wave_phase = randf() * TAU


func _process(delta: float) -> void:
	if speared:
		return
	age += delta
	var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
	global_position += velocity * delta + Vector2(0, wave_y)
	# Despawn when fully off-screen
	var viewport = get_viewport_rect().size
	var margin = 60.0
	if global_position.x < -margin or global_position.x > viewport.x + margin:
		queue_free()
		return
	queue_redraw()


func on_speared(_spear: Node2D) -> void:
	speared = true


func get_cash_value() -> int:
	return int(base_value * GameData.get_fish_value_multiplier())


func get_effective_hit_radius() -> float:
	return hit_radius + GameData.get_hit_radius_bonus()


func _draw() -> void:
	var facing_right = velocity.x >= 0
	var dir = 1.0 if facing_right else -1.0
	# Body ellipse (approximate via scaled circle)
	var body_len = hit_radius * 1.8
	var body_h = hit_radius * 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Body
	var pts = PackedVector2Array()
	var n = 16
	for i in n:
		var a = float(i) / n * TAU
		pts.append(Vector2(cos(a) * body_len * 0.5, sin(a) * body_h * 0.5))
	draw_colored_polygon(pts, color)
	# Tail triangle
	var tx = -body_len * 0.5 * dir
	draw_polygon(
		PackedVector2Array([
			Vector2(tx, 0),
			Vector2(tx - 8 * dir, -6),
			Vector2(tx - 8 * dir, 6),
		]),
		PackedColorArray([color.darkened(0.15)])
	)
	# Eye
	draw_circle(Vector2(body_len * 0.3 * dir, -body_h * 0.2), 1.6, Color.BLACK)
```

**Step 2: Write fish_spawner.gd**

```gdscript
extends Node2D

const Fish = preload("res://scenes/fish.tscn")

var spawn_timer: float = 0.0
var active: bool = false

const BASE_SPAWN_INTERVAL = 1.2
const SPECIES_WEIGHTS = {
	"sardine": 0.6,
	"grouper": 0.3,
	"tuna": 0.1,
}


func start_spawning() -> void:
	active = true
	spawn_timer = 0.5  # First spawn quickly


func stop_spawning() -> void:
	active = false
	# Clear any still-swimming fish (speared ones are owned by spears — leave them)
	for child in get_tree().get_nodes_in_group("fish"):
		if is_instance_valid(child) and not child.speared:
			child.queue_free()


func _process(delta: float) -> void:
	if not active:
		return
	spawn_timer -= delta * GameData.get_spawn_rate_multiplier()
	if spawn_timer <= 0.0:
		spawn_timer = BASE_SPAWN_INTERVAL * randf_range(0.7, 1.3)
		_spawn_one()


func _spawn_one() -> void:
	var species = _pick_species()
	var viewport = get_viewport_rect().size
	var from_right = randf() < 0.5
	var x = viewport.x + 40.0 if from_right else -40.0
	var y = randf_range(viewport.y * 0.25, viewport.y * 0.85)
	var fish = Fish.instantiate()
	fish.add_to_group("fish")
	get_tree().current_scene.add_child(fish)
	fish.setup(species, Vector2(x, y), not from_right)


func _pick_species() -> String:
	var total = 0.0
	for w in SPECIES_WEIGHTS.values():
		total += w
	var r = randf() * total
	var acc = 0.0
	for key in SPECIES_WEIGHTS.keys():
		acc += SPECIES_WEIGHTS[key]
		if r <= acc:
			return key
	return "sardine"
```

**Step 3: Create fish.tscn**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/fish.gd" id="1"]

[node name="Fish" type="Node2D"]
script = ExtResource("1")
```

**Step 4: Verify by running**

- Launch. After diving, fish should spawn from edges and swim across.
- Spears still fly through fish (no collision). Fish despawn at opposite edge.

**Step 5: Commit**

```bash
git add scripts/fish.gd scenes/fish.tscn scripts/fish_spawner.gd
git commit -m "feat: fish + spawner — 3 species swim across screen"
```

---

## Task 8: Spear–fish collision and cash payout

During FLYING, check every fish for distance-to-spear-tip ≤ fish.hit_radius. On hit, attach and begin REELING_HIT.

**Files:**
- Modify: `scripts/spear.gd` — add per-frame hit check inside `State.FLYING` branch

**Step 1: Modify spear.gd `_process` FLYING branch**

Find the `State.FLYING` branch in `_process` and change it to:

```gdscript
State.FLYING:
    var speed = GameData.get_spear_speed()
    var step = speed * delta
    global_position += flight_dir * step
    flight_distance_remaining -= step

    # Hit check against fish group
    for fish in get_tree().get_nodes_in_group("fish"):
        if not is_instance_valid(fish) or fish.speared:
            continue
        var r = fish.get_effective_hit_radius() if fish.has_method("get_effective_hit_radius") else 12.0
        if global_position.distance_to(fish.global_position) <= r:
            attach_to_fish(fish)
            return

    if flight_distance_remaining <= -MISS_OVERSHOOT:
        state = State.REELING_MISS
        _sync_hud()
```

**Step 2: Verify by running**

- Dive, click a fish while it swims. Expected:
  - Spear flies, hits the fish, line goes taut back to diver.
  - Fish follows spear position back to diver at `reel_speed`.
  - On arrival: fish disappears, dive cash ticks up.
  - Spear dot in HUD turns blue (reeling) → white (ready).
- Click a blank area — spear overshoots and returns without carrying a fish.
- Throw multiple times (after spear upgrade) — multiple spears can be in flight simultaneously.

**Step 3: Commit**

```bash
git add scripts/spear.gd
git commit -m "feat: spear-fish collision, reel-back with cash payout"
```

---

## Task 9: Strip and rewrite `upgrade_shop.gd` for new upgrades

The current shop draws a complex neural-network tree. For MVP, replace with a simple vertical list of upgrade buttons. Keep the `show_shop`/`hide_shop` API intact. Rename signal from `next_epoch_pressed` to `next_dive_pressed`.

**Files:**
- Rewrite: `scripts/upgrade_shop.gd`

**Step 1: Replace contents**

```gdscript
extends CanvasLayer

signal next_dive_pressed

var root_control: Control
var cash_label: Label
var list_vbox: VBoxContainer
var dive_button: Button
var upgrade_buttons: Dictionary = {}


func _ready() -> void:
	_build_ui()
	hide_shop()
	GameData.cash_changed.connect(_on_cash_changed)


func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.85)
	root_control.add_child(overlay)

	# Centered panel
	var panel_margin = MarginContainer.new()
	panel_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_margin.add_theme_constant_override("margin_left", 120)
	panel_margin.add_theme_constant_override("margin_right", 120)
	panel_margin.add_theme_constant_override("margin_top", 60)
	panel_margin.add_theme_constant_override("margin_bottom", 60)
	root_control.add_child(panel_margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel_margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "⛵ ABOARD THE BOAT"
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	cash_label = Label.new()
	cash_label.add_theme_font_size_override("font_size", 20)
	cash_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cash_label)

	# Upgrade list
	list_vbox = VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(list_vbox)

	for key in GameData.upgrades.keys():
		var btn = _build_upgrade_row(key)
		list_vbox.add_child(btn)
		upgrade_buttons[key] = btn

	# Dive button
	dive_button = Button.new()
	dive_button.text = "🐟  DIVE"
	dive_button.custom_minimum_size = Vector2(260, 52)
	dive_button.add_theme_font_size_override("font_size", 20)
	dive_button.pressed.connect(_on_dive_pressed)
	var dive_s = StyleBoxFlat.new()
	dive_s.bg_color = Color(0.12, 0.35, 0.75)
	dive_s.set_corner_radius_all(10)
	dive_s.set_content_margin_all(10)
	dive_button.add_theme_stylebox_override("normal", dive_s)
	var dive_wrap = CenterContainer.new()
	dive_wrap.add_child(dive_button)
	vbox.add_child(dive_wrap)


func _build_upgrade_row(key: String) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_on_upgrade_pressed.bind(key))
	return btn


func _refresh_rows() -> void:
	for key in upgrade_buttons.keys():
		var btn: Button = upgrade_buttons[key]
		var upgrade = GameData.upgrades[key]
		var level = GameData.upgrade_levels[key]
		var max_level = upgrade["max_level"]
		var maxed = level >= max_level
		var cost_str = "MAX" if maxed else "$%d" % upgrade["costs"][level]
		btn.text = "%s  (Lv %d/%d)   %s   —   %s" % [upgrade["name"], level, max_level, upgrade["description"], cost_str]
		btn.disabled = maxed or not GameData.can_buy_upgrade(key)


func _on_upgrade_pressed(key: String) -> void:
	if GameData.buy_upgrade(key):
		_refresh_rows()
		_update_cash()


func _on_dive_pressed() -> void:
	hide_shop()
	next_dive_pressed.emit()


func _on_cash_changed(_amount: float) -> void:
	_update_cash()
	_refresh_rows()


func _update_cash() -> void:
	cash_label.text = "Wallet: $%d" % int(GameData.cash)


func show_shop() -> void:
	root_control.visible = true
	_update_cash()
	_refresh_rows()


func hide_shop() -> void:
	root_control.visible = false
```

**Step 2: Verify by running**

- Full loop should now work end-to-end:
  1. Boot → boat shop appears with 8 upgrades listed.
  2. Buttons disabled if unaffordable. Click DIVE → dive transition plays.
  3. Fishing: spawn fish, click to throw, catch, cash accumulates.
  4. Oxygen drains (1/sec). When it hits 0 → auto-resurface. Cash adds to wallet.
  5. Shop reopens with new cash. Can buy upgrades (e.g., oxygen tank).
  6. Dive again; oxygen now longer.

**Step 3: Commit**

```bash
git add scripts/upgrade_shop.gd
git commit -m "feat: simple list-style upgrade shop for spearfishing upgrades"
```

---

## Task 10: Verify each upgrade actually affects gameplay

Hand-test each upgrade by buying it and observing the effect. This is a validation-only task — no code changes unless something is broken.

**Verification matrix:**

| Upgrade | How to test |
|---|---|
| `oxygen` | Buy Lv 1 — oxygen bar should start at 55s instead of 45s on next dive |
| `spears` | Buy Lv 1 — spear row in HUD shows 2 dots; can fire 2 spears simultaneously |
| `spear_speed` | Buy Lv 1 — spears visibly fly faster when thrown |
| `reel_speed` | Spear a fish, buy `reel_speed` on next dive — hooked fish returns noticeably faster |
| `hit_radius` | Click slightly off-fish — with Lv 1 the spear connects; without, it would miss |
| `lure` | Buy Lv 1 — more fish visible on screen (spawn interval shorter) |
| `fish_value` | Buy Lv 1 — sardine shows $2.40 rounded to $2, but grouper goes from $10 to $12 per catch |
| `trophy_room` | Deplete oxygen while carrying dive cash — with Lv 1 you keep 5% of what was accumulated |

**If any upgrade doesn't have its effect wired:** trace through `GameData.get_*` getter and confirm it's being called at the right spot in `spear.gd`, `fish.gd`, `diver.gd`, or `fish_spawner.gd`.

**Step 1: Playtest each upgrade.**

Commit any fixes as separate commits, e.g. `fix: apply spear_speed multiplier in spear._process`.

---

## Task 11: Polish — surface visuals + dive transition + resurface animation

Visual polish. All optional but desired: boat silhouette on surface, water surface line, bubbles during dive, sun rays.

**Files:**
- Modify: `scripts/main.gd` — add `_draw()` for the backdrop
- Optional: `scripts/main.gd` add a Node2D child that draws boat/surface

**Step 1: Add backdrop drawing**

Add to the bottom of `main.gd`:

```gdscript
func _process_draw() -> void:
	queue_redraw()


func _draw() -> void:
	var viewport = get_viewport_rect().size
	var water_surface_y = 140.0

	# Sky gradient (top)
	for i in 8:
		var t = i / 8.0
		var y = t * water_surface_y
		var band_h = water_surface_y / 8.0
		var c = Color(0.4, 0.6, 0.85).lerp(Color(0.1, 0.3, 0.55), t)
		draw_rect(Rect2(0, y, viewport.x, band_h + 1), c)

	# Water (below surface)
	for i in 12:
		var t = i / 12.0
		var y = water_surface_y + t * (viewport.y - water_surface_y)
		var band_h = (viewport.y - water_surface_y) / 12.0
		var c = Color(0.08, 0.2, 0.4).lerp(Color(0.02, 0.05, 0.12), t)
		draw_rect(Rect2(0, y, viewport.x, band_h + 1), c)

	# Water surface line
	draw_line(Vector2(0, water_surface_y), Vector2(viewport.x, water_surface_y), Color(0.6, 0.8, 1.0, 0.4), 1.5)

	# Boat silhouette (only visible when surface or transitioning)
	if GameData.dive_state in ["surface", "diving", "resurfacing"]:
		var boat_x = viewport.x * 0.5
		var boat_y = water_surface_y
		var boat_w = 180.0
		draw_polygon(
			PackedVector2Array([
				Vector2(boat_x - boat_w * 0.5, boat_y),
				Vector2(boat_x - boat_w * 0.3, boat_y - 25),
				Vector2(boat_x + boat_w * 0.3, boat_y - 25),
				Vector2(boat_x + boat_w * 0.5, boat_y),
			]),
			PackedColorArray([Color(0.2, 0.15, 0.12)])
		)
		# Mast
		draw_line(Vector2(boat_x, boat_y - 25), Vector2(boat_x, boat_y - 90), Color(0.3, 0.25, 0.2), 3.0)
```

Add to `_ready`: `set_process(true)` (already true by default) and in `_process` add `queue_redraw()` so the backdrop refreshes with state changes. Simplest: call `queue_redraw()` inside the existing `_process(delta)` body.

**Step 2: Verify**

- Launch. On boat phase, a water line + boat silhouette + sky is visible. Shop overlay sits on top.
- Dive: diver drops from boat down into water.
- Underwater: diver mid-screen, dark blue, fish swimming.
- Resurface: diver rises back to boat.

**Step 3: Commit**

```bash
git add scripts/main.gd
git commit -m "feat: sky/water/boat backdrop for all phases"
```

---

## Out of scope for this plan (tracked but not built)

- Shark species + harpoon upgrade (designed but not MVP).
- Depth zones with zone-specific fish.
- Sound effects (splash, spear swish, catch).
- Save/load persistence between runs.
- Manual aim preview (line indicator while holding click).

## Final verification

After Task 11, the full game loop should be:

1. Start on boat. 8 upgrades visible. Wallet: $0.
2. Click DIVE. Diver descends.
3. Fish spawn. Click a fish — spear throws, hits, reels back. Dive cash ticks up.
4. Click empty water — spear overshoots, returns empty. No penalty beyond time.
5. Oxygen reaches 0 (or press RESURFACE). Diver ascends.
6. On boat: dive cash adds to wallet. Shop reopens. Buy upgrades.
7. Dive again. Notice upgrades took effect.

Plan complete.
