extends Node2D

var node_positions: Array = []  # Array of Arrays of Vector2 (local coords)
var connections: Array = []     # Array of [Vector2, Vector2, int, int] (from, to, from_layer, to_layer)
var pulse_time: float = 0.0
var stage_transition_timer: float = 0.0
const STAGE_TRANSITION_DURATION = 1.5
var net_width: float = 180.0
var net_height: float = 140.0

# Per-node highlight system — replaces global flash
var node_highlights: Dictionary = {}  # Vector2 (local pos) -> float (timer remaining)
const NODE_HIGHLIGHT_DURATION = 0.35


func _ready() -> void:
	_generate_network()
	GameData.network_changed.connect(_on_network_changed)


func _process(delta: float) -> void:
	pulse_time += delta

	if stage_transition_timer > 0:
		stage_transition_timer -= delta
		if stage_transition_timer <= 0:
			stage_transition_timer = 0.0

	# Decay node highlights
	for key in node_highlights.keys():
		node_highlights[key] -= delta
		if node_highlights[key] <= 0:
			node_highlights.erase(key)

	queue_redraw()


func _generate_network() -> void:
	node_positions.clear()
	connections.clear()

	var neurons = GameData.neurons_per_layer
	var num_hidden = GameData.num_hidden_layers
	var total_layers = num_hidden + 2  # 1 input + hidden layers + 1 output

	# Scale dimensions with network size
	net_width = maxf(130.0, total_layers * 40.0)
	net_height = maxf(60.0, neurons * 26.0)

	for layer in range(total_layers):
		var layer_nodes: Array = []
		var x = -net_width / 2.0 + (net_width / maxf(total_layers - 1, 1)) * layer

		# Determine node count for this layer
		var count: int
		if layer == 0:
			count = 1  # Single input node
		elif layer == total_layers - 1:
			count = GameData.get_output_count()
		else:
			count = neurons  # Hidden layer

		for node_i in range(count):
			var y: float
			if count == 1:
				y = 0.0
			else:
				y = -net_height / 2.0 + (net_height / maxf(count - 1, 1)) * node_i
			layer_nodes.append(Vector2(x, y))
		node_positions.append(layer_nodes)

	# Connect adjacent layers (store layer indices for accuracy-based lighting)
	for layer in range(total_layers - 1):
		for from_node in node_positions[layer]:
			for to_node in node_positions[layer + 1]:
				connections.append([from_node, to_node, layer, layer + 1])


func get_input_node_world_positions() -> Array:
	var positions: Array = []
	if node_positions.size() > 0:
		for pos in node_positions[0]:
			positions.append(global_position + pos)
	return positions


func get_output_node_world_positions() -> Array:
	var positions: Array = []
	if node_positions.size() > 1:
		var last_layer = node_positions[node_positions.size() - 1]
		for pos in last_layer:
			positions.append(global_position + pos)
	return positions


func get_exclusion_rect() -> Rect2:
	var half_w = net_width / 2.0 + 30.0
	var half_h = net_height / 2.0 + 30.0
	return Rect2(global_position.x - half_w, global_position.y - half_h, half_w * 2, half_h * 2)


# Returns a path of world positions through the network: one random node per layer,
# with the final node matching the data_class index in the output layer
func get_traversal_path(data_class: int) -> Array:
	var path: Array = []
	var last_layer_idx = node_positions.size() - 1
	for i in range(node_positions.size()):
		var layer = node_positions[i]
		if layer.size() == 0:
			continue
		var local_pos: Vector2
		if i == last_layer_idx:
			# Route to the output node matching the data class
			var idx = clampi(data_class, 0, layer.size() - 1)
			local_pos = layer[idx]
		else:
			local_pos = layer[randi() % layer.size()]
		path.append(global_position + local_pos)
	return path


# Highlight a specific node (called when data passes through it)
func highlight_node_at(world_pos: Vector2) -> void:
	var local_pos = world_pos - global_position
	# Find closest node position
	var best_dist = 20.0
	var best_pos: Variant = null
	for layer in node_positions:
		for pos in layer:
			var d = pos.distance_to(local_pos)
			if d < best_dist:
				best_dist = d
				best_pos = pos
	if best_pos != null:
		node_highlights[best_pos] = NODE_HIGHLIGHT_DURATION


func _on_network_changed() -> void:
	_generate_network()


func _get_output_label(index: int) -> String:
	match GameData.current_stage:
		0:
			return str(index)
		1:
			return str(index)
		2:
			var math_labels = ["Num", "Sign", "Eq"]
			return math_labels[index % math_labels.size()]
		3:
			return "F" + str(index)
		_:
			return str(index)


func on_stage_changed() -> void:
	stage_transition_timer = STAGE_TRANSITION_DURATION
	_generate_network()


func _draw() -> void:
	var stage_color: Color = GameData.get_stage()["color"]
	var pulse = (sin(pulse_time * 2.0) + 1.0) / 2.0
	var accuracy_pct = GameData.get_accuracy_percent() / 100.0  # 0.0 to 1.0
	var total_layers = node_positions.size()

	# Dim base color — the "unlearned" look (visible from the start)
	var dim_color = Color(0.25, 0.28, 0.4)

	# Draw connections
	for conn in connections:
		var from_pos: Vector2 = conn[0]
		var to_pos: Vector2 = conn[1]
		var from_layer: int = conn[2]
		var to_layer: int = conn[3]

		# How "lit" is this connection based on accuracy?
		var conn_threshold = float(to_layer) / maxf(total_layers - 1, 1)
		var conn_lit = clampf((accuracy_pct - conn_threshold * 0.7) / 0.3, 0.0, 1.0)

		var base_alpha = 0.22 + conn_lit * 0.2 + pulse * 0.04

		# Per-node highlight: brighten connections adjacent to highlighted nodes
		var from_hl = node_highlights.get(from_pos, 0.0) / NODE_HIGHLIGHT_DURATION
		var to_hl = node_highlights.get(to_pos, 0.0) / NODE_HIGHLIGHT_DURATION
		var conn_highlight = maxf(from_hl, to_hl)
		if conn_highlight > 0.0:
			base_alpha += conn_highlight * 0.35

		var line_color = dim_color.lerp(stage_color, conn_lit)
		if conn_highlight > 0.0:
			line_color = line_color.lerp(stage_color, conn_highlight * 0.6)
		line_color.a = base_alpha
		draw_line(from_pos, to_pos, line_color, 1.5)

		# Glow on lit connections
		if conn_lit > 0.3 or conn_highlight > 0.2:
			var glow_val = maxf(conn_lit, conn_highlight)
			var glow_alpha = glow_val * (0.04 + pulse * 0.03)
			draw_line(from_pos, to_pos, Color(stage_color.r, stage_color.g, stage_color.b, glow_alpha), 4.0)

	# Draw nodes
	for layer_idx in range(total_layers):
		var layer_threshold = float(layer_idx) / maxf(total_layers - 1, 1)
		var layer_lit = clampf((accuracy_pct - layer_threshold * 0.7) / 0.3, 0.0, 1.0)

		for node_pos in node_positions[layer_idx]:
			var radius = 6.0
			var brightness = 0.45 + layer_lit * 0.35 + pulse * 0.08
			var node_color = dim_color.lerp(stage_color, layer_lit) * brightness
			node_color.a = 1.0

			if layer_idx == 0 or layer_idx == total_layers - 1:
				radius = 8.0

			# Animate output nodes expanding during stage transition
			if layer_idx == total_layers - 1 and stage_transition_timer > 0:
				var progress = 1.0 - (stage_transition_timer / STAGE_TRANSITION_DURATION)
				radius *= clampf(progress * 2.0, 0.0, 1.0)

			# Per-node highlight (data passing through)
			var highlight = 0.0
			if node_pos in node_highlights:
				highlight = node_highlights[node_pos] / NODE_HIGHLIGHT_DURATION
			if highlight > 0.0:
				node_color = node_color.lerp(stage_color, highlight)
				node_color = node_color.lightened(highlight * 0.4)
				node_color.a = 1.0
				radius += highlight * 3.0

			# Activation function visuals (hidden layers only)
			var is_hidden = layer_idx > 0 and layer_idx < total_layers - 1
			var act_level = GameData.upgrade_levels["activation_func"] if is_hidden else 0

			if act_level >= 2:
				# Level 2: Pulsing size (apply before drawing)
				radius += sin(pulse_time * 3.0 + float(layer_idx)) * 2.0

			if act_level >= 1:
				# Level 1: Glow halo (draw behind the node)
				var glow_alpha = 0.15 + pulse * 0.1
				draw_circle(node_pos, radius + 4, Color(stage_color.r, stage_color.g, stage_color.b, glow_alpha))

			if act_level >= 3:
				# Level 3: Square shape instead of circle
				var half = radius
				var square_rect = Rect2(node_pos - Vector2(half, half), Vector2(half * 2, half * 2))
				draw_rect(square_rect, node_color, true)
			else:
				# Normal circle
				draw_circle(node_pos, radius, node_color)

			if act_level >= 4:
				# Level 4: Energy arcs
				for arc_i in range(3):
					var arc_offset = pulse_time * 2.0 + arc_i * TAU / 3.0
					draw_arc(node_pos, radius + 6, arc_offset, arc_offset + 0.8, 8, Color(stage_color.r, stage_color.g, stage_color.b, 0.4 + pulse * 0.2), 1.5)

			# Outline glow
			var outline_alpha = 0.35 + layer_lit * 0.3 + highlight * 0.25
			var outline_color = dim_color.lerp(stage_color, maxf(layer_lit, highlight)).lightened(0.3)
			outline_color.a = outline_alpha
			draw_arc(node_pos, radius + 1, 0, TAU, 16, outline_color, 1.0)

	# Draw output node class labels
	if total_layers > 0:
		var output_layer = node_positions[total_layers - 1]
		var out_font = ThemeDB.fallback_font
		var output_lit = clampf((accuracy_pct - 0.7) / 0.3, 0.0, 1.0)
		for node_i in range(output_layer.size()):
			var npos = output_layer[node_i]
			var label_text = _get_output_label(node_i)
			var label_alpha = 0.3 + output_lit * 0.4
			# Check if this output node is highlighted
			if npos in node_highlights:
				label_alpha = 0.9
			var label_color = Color(stage_color.r, stage_color.g, stage_color.b, label_alpha)
			draw_string(out_font, Vector2(npos.x + 12, npos.y + 4), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_color)

		# Shiny glow for Equations output node (Stage 2)
		if GameData.current_stage == 2 and output_layer.size() > 2:
			var eq_pos = output_layer[2]
			var eq_glow_alpha = 0.12 + pulse * 0.08
			draw_circle(eq_pos, 14.0 + pulse * 2.0, Color(0.7, 0.3, 1.0, eq_glow_alpha))
			draw_circle(eq_pos, 9.0, Color(0.8, 0.5, 1.0, 0.08 + pulse * 0.04))

	# Accuracy label below the network
	var font = ThemeDB.fallback_font
	var acc_text = "Accuracy: %.0f%%" % GameData.get_accuracy_percent()
	var text_size = font.get_string_size(acc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var text_pos = Vector2(-text_size.x / 2.0, net_height / 2.0 + 28)
	var text_color = dim_color.lerp(stage_color, accuracy_pct)
	text_color.a = 0.6 + accuracy_pct * 0.4
	draw_string(font, text_pos, acc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)

	# Stage name below accuracy
	var stage_name = GameData.get_stage()["name"]
	var stage_text_size = font.get_string_size(stage_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var stage_pos = Vector2(-stage_text_size.x / 2.0, net_height / 2.0 + 43)
	draw_string(font, stage_pos, stage_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.6, 0.7))

	# Outer glow — centered on visual midpoint (accounting for text below)
	var glow_center = Vector2(0.0, 14.0)
	var glow_radius = maxf(net_width, net_height) / 2.0 + 18.0 + pulse * 4.0 + accuracy_pct * 12.0
	var glow_intensity = 0.03 + accuracy_pct * 0.04 + pulse * 0.02
	var glow_color = Color(stage_color.r, stage_color.g, stage_color.b, glow_intensity)
	draw_arc(glow_center, glow_radius, 0, TAU, 64, glow_color, 2.0)
