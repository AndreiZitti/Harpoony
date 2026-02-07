extends Node2D

var node_positions: Array = []  # Array of Arrays of Vector2
var connections: Array = []     # Array of [Vector2, Vector2, int, int] (from, to, from_layer, to_layer)
var pulse_time: float = 0.0
var flash_timer: float = 0.0
var net_width: float = 180.0
var net_height: float = 140.0


func _ready() -> void:
	_generate_network()
	GameData.network_changed.connect(_on_network_changed)


func _process(delta: float) -> void:
	pulse_time += delta

	if flash_timer > 0:
		flash_timer -= delta
		if flash_timer <= 0:
			flash_timer = 0.0

	queue_redraw()


func _generate_network() -> void:
	node_positions.clear()
	connections.clear()

	var neurons = GameData.neurons_per_layer
	var num_hidden = GameData.num_hidden_layers
	var total_layers = num_hidden + 2  # 1 input + hidden layers + 1 output

	# Scale dimensions with network size
	net_width = maxf(180.0, total_layers * 55.0)
	net_height = maxf(80.0, neurons * 35.0)

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
	var half_w = net_width / 2.0 + 40.0
	var half_h = net_height / 2.0 + 40.0
	return Rect2(global_position.x - half_w, global_position.y - half_h, half_w * 2, half_h * 2)


func trigger_forward_pass() -> void:
	flash_timer = 0.4


func _on_network_changed() -> void:
	_generate_network()


func on_stage_changed() -> void:
	_generate_network()  # output count may change between stages


func _draw() -> void:
	var stage_color: Color = GameData.get_stage()["color"]
	var pulse = (sin(pulse_time * 2.0) + 1.0) / 2.0
	var accuracy_pct = GameData.get_accuracy_percent() / 100.0  # 0.0 to 1.0
	var total_layers = node_positions.size()

	# Dim base color — the "unlearned" look
	var dim_color = Color(0.2, 0.2, 0.3)

	# Draw connections
	for conn in connections:
		var from_pos = conn[0]
		var to_pos = conn[1]
		var from_layer: int = conn[2]
		var to_layer: int = conn[3]

		# How "lit" is this connection based on accuracy?
		# Connections light up left-to-right as accuracy grows
		var conn_threshold = float(to_layer) / maxf(total_layers - 1, 1)
		var conn_lit = clampf((accuracy_pct - conn_threshold * 0.7) / 0.3, 0.0, 1.0)

		var base_alpha = 0.08 + conn_lit * 0.2 + pulse * 0.05
		if flash_timer > 0:
			base_alpha += 0.3 * (flash_timer / 0.4)

		var line_color = dim_color.lerp(stage_color, conn_lit)
		line_color.a = base_alpha
		draw_line(from_pos, to_pos, line_color, 1.5)

		# Glow on lit connections
		if conn_lit > 0.3:
			var glow_alpha = conn_lit * (0.04 + pulse * 0.03)
			draw_line(from_pos, to_pos, Color(stage_color.r, stage_color.g, stage_color.b, glow_alpha), 4.0)

	# Draw nodes
	for layer_idx in range(total_layers):
		var layer_threshold = float(layer_idx) / maxf(total_layers - 1, 1)
		var layer_lit = clampf((accuracy_pct - layer_threshold * 0.7) / 0.3, 0.0, 1.0)

		for node_pos in node_positions[layer_idx]:
			var radius = 6.0
			var brightness = 0.2 + layer_lit * 0.5 + pulse * 0.1
			var node_color = dim_color.lerp(stage_color, layer_lit) * brightness
			node_color.a = 1.0

			if layer_idx == 0 or layer_idx == total_layers - 1:
				radius = 8.0

			# Flash on forward pass
			if flash_timer > 0:
				var layer_progress = 1.0 - (flash_timer / 0.4)
				var flash_threshold = float(layer_idx) / maxf(total_layers - 1, 1)
				if layer_progress >= flash_threshold:
					node_color = Color.WHITE
					radius += 2.0

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
			var outline_alpha = 0.15 + layer_lit * 0.4
			var outline_color = dim_color.lerp(stage_color, layer_lit).lightened(0.3)
			outline_color.a = outline_alpha
			draw_arc(node_pos, radius + 1, 0, TAU, 16, outline_color, 1.0)

	# Accuracy label below the network
	var font = ThemeDB.fallback_font
	var acc_text = "Accuracy: %.0f%%" % GameData.get_accuracy_percent()
	var text_size = font.get_string_size(acc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var text_pos = Vector2(-text_size.x / 2.0, net_height / 2.0 + 35)
	var text_color = dim_color.lerp(stage_color, accuracy_pct)
	text_color.a = 0.5 + accuracy_pct * 0.5
	draw_string(font, text_pos, acc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, text_color)

	# Stage name below accuracy
	var stage_name = GameData.get_stage()["name"]
	var stage_text_size = font.get_string_size(stage_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var stage_pos = Vector2(-stage_text_size.x / 2.0, net_height / 2.0 + 52)
	draw_string(font, stage_pos, stage_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.6, 0.7))

	# Outer glow — grows with accuracy
	var glow_radius = maxf(net_width, net_height) / 2.0 + 20.0 + pulse * 5.0 + accuracy_pct * 15.0
	var glow_intensity = 0.02 + accuracy_pct * 0.04 + pulse * 0.02
	var glow_color = Color(stage_color.r, stage_color.g, stage_color.b, glow_intensity)
	draw_arc(Vector2.ZERO, glow_radius, 0, TAU, 64, glow_color, 2.0)
