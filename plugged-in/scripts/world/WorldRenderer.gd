extends RefCounted

# =============================================================================
#  WorldRenderer — draws water, island, highways, and debug grid.
#  All drawing is done by appending Polygon2D nodes to the scene tree.
#  Call each draw_* function with the target parent Node.
# =============================================================================

class_name WorldRenderer


## Draw the ocean background filling the full map rectangle.
static func draw_water(parent: Node) -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(WorldData.MAP_W, 0.0),
		Vector2(WorldData.MAP_W, WorldData.MAP_H), Vector2(0.0, WorldData.MAP_H),
	])
	poly.color    = WorldData.WATER_COLOR
	poly.z_index  = -4
	poly.material = _make_water_material()
	parent.add_child(poly)


## Draw the island landmass polygon.
static func draw_island(parent: Node) -> void:
	var poly := Polygon2D.new()
	poly.polygon = WorldData.ISLAND_POLY
	poly.color    = WorldData.ISLAND_BASE
	poly.z_index  = -3
	poly.material = _make_grass_material()
	parent.add_child(poly)


## Draw production highway rectangles into highway_layer.
static func draw_highways(highway_layer: Node) -> void:
	for seg: Dictionary in WorldData.HIGHWAYS:
		var hx: float = float(seg["x"])
		var hy: float = float(seg["y"])
		var hw: float = float(seg["w"])
		var hh: float = float(seg["h"])
		fill_rect(hx, hy, hw, hh, WorldData.HIGHWAY_COLOR, -2, highway_layer)
		if hh > hw:
			fill_rect(hx + (hw - 6.0) * 0.5, hy, 6.0, hh, WorldData.CENTRE_LINE, -1, highway_layer)
		else:
			fill_rect(hx, hy + (hh - 6.0) * 0.5, hw, 6.0, WorldData.CENTRE_LINE, -1, highway_layer)


## Draw tinted highway rects + name labels into debug_layer.
static func draw_highway_debug_labels(debug_layer: Node) -> void:
	for seg: Dictionary in WorldData.HIGHWAYS:
		var hx: float = float(seg["x"])
		var hy: float = float(seg["y"])
		var hw: float = float(seg["w"])
		var hh: float = float(seg["h"])
		var cx: float = hx + hw * 0.5
		var cy: float = hy + hh * 0.5
		fill_rect(hx, hy, hw, hh, Color(0.90, 0.30, 0.10, 0.35), 5, debug_layer)
		var lbl := Label.new()
		lbl.text     = "%s\n%d × %d" % [seg["name"], int(hw), int(hh)]
		lbl.position = Vector2(cx, cy - 18.0)
		lbl.z_index  = 10
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.20))
		debug_layer.add_child(lbl)


## Draw a faint 1000 px coordinate grid with labels every 1000 px into debug_layer.
static func draw_debug_grid(debug_layer: Node) -> void:
	var step:     float = 1000.0
	var line_col: Color = Color(1.0, 1.0, 1.0, 0.08)
	var lbl_col:  Color = Color(0.55, 0.85, 1.0, 0.55)
	var gx: float = 0.0
	while gx <= WorldData.MAP_W:
		fill_rect(gx, 0.0, 2.0, WorldData.MAP_H, line_col, 4, debug_layer)
		gx += step
	var gy: float = 0.0
	while gy <= WorldData.MAP_H:
		fill_rect(0.0, gy, WorldData.MAP_W, 2.0, line_col, 4, debug_layer)
		gy += step
	gx = 0.0
	while gx <= WorldData.MAP_W:
		gy = 0.0
		while gy <= WorldData.MAP_H:
			var lbl := Label.new()
			lbl.text     = "%d,%d" % [int(gx), int(gy)]
			lbl.position = Vector2(gx + 4.0, gy + 2.0)
			lbl.z_index  = 9
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", lbl_col)
			debug_layer.add_child(lbl)
			gy += step
		gx += step


## Draw a cyan dot at every road-graph node into debug_layer.
static func draw_road_nodes(road_graph: Object, debug_layer: Node) -> void:
	if road_graph == null:
		return
	for n_pos: Vector2 in road_graph.nodes:
		var dot  := Polygon2D.new()
		var pts  := PackedVector2Array()
		for i: int in range(6):
			var angle := (2.0 * PI * i) / 6.0
			pts.append(Vector2(cos(angle) * 5.0, sin(angle) * 5.0))
		dot.polygon  = pts
		dot.color    = Color(0.0, 0.95, 0.85, 0.80)
		dot.position = n_pos
		dot.z_index  = 15
		debug_layer.add_child(dot)

		var lbl := Label.new()
		lbl.text = "(%d,%d)" % [int(n_pos.x), int(n_pos.y)]
		lbl.position = Vector2(7.0, -14.0)
		lbl.z_index  = 15
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.0, 0.95, 0.85, 0.90))
		dot.add_child(lbl)


## Draw numbered handles on every ISLAND_POLY vertex into debug_layer.
## Each vertex shows:  [index]  Vector2(x, y)
## The boundary edge is also drawn as a coloured polyline so the outline is
## visible against any terrain.  Handles are large enough to read at any zoom.
static func draw_island_vertex_handles(debug_layer: Node) -> void:
	var pts := WorldData.ISLAND_POLY
	var n   := pts.size()

	# ── Edge outline ──────────────────────────────────────────────────────────
	# Draw each edge as a flat rectangle (Line2D not available in pure-code
	# scene trees without a Node2D parent that autodraws, so we use thin polys).
	for i: int in range(n):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var line := Line2D.new()
		line.add_point(a)
		line.add_point(b)
		line.width         = 6.0
		line.default_color = Color(1.0, 0.55, 0.10, 0.70)  # orange
		line.z_index       = 20
		debug_layer.add_child(line)

	# ── Per-vertex handles ────────────────────────────────────────────────────
	for i: int in range(n):
		var pt: Vector2 = pts[i]

		# Diamond marker
		var dot := Polygon2D.new()
		dot.polygon = PackedVector2Array([
			Vector2(0.0, -18.0), Vector2(18.0, 0.0),
			Vector2(0.0,  18.0), Vector2(-18.0, 0.0),
		])
		dot.color    = Color(1.0, 0.92, 0.10, 0.90)   # yellow
		dot.position = pt
		dot.z_index  = 22
		debug_layer.add_child(dot)

		# Dark outline ring so the dot pops against bright ground
		var outline := Polygon2D.new()
		outline.polygon = PackedVector2Array([
			Vector2(0.0, -22.0), Vector2(22.0, 0.0),
			Vector2(0.0,  22.0), Vector2(-22.0, 0.0),
		])
		outline.color    = Color(0.0, 0.0, 0.0, 0.55)
		outline.position = pt
		outline.z_index  = 21
		debug_layer.add_child(outline)

		# Label:  [i]  (x, y)
		var lbl := Label.new()
		lbl.text     = "[%d]  Vector2(%d, %d)" % [i, int(pt.x), int(pt.y)]
		lbl.position = pt + Vector2(26.0, -14.0)
		lbl.z_index  = 23
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color",        Color(1.0,  0.95, 0.20))
		lbl.add_theme_color_override("font_shadow_color", Color(0.0,  0.0,  0.0, 0.80))
		lbl.add_theme_constant_override("shadow_offset_x", 2)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
		debug_layer.add_child(lbl)


## Build invisible StaticBody2D collision segments along the island boundary.
static func build_island_boundary(parent: Node) -> void:
	var pts := WorldData.ISLAND_POLY
	var n   := pts.size()
	for i: int in range(n):
		var a    := pts[i]
		var b    := pts[(i + 1) % n]
		var mid  := (a + b) * 0.5
		var diff := b - a
		var body := StaticBody2D.new()
		body.position = mid
		body.rotation = diff.angle()
		parent.add_child(body)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(diff.length(), 36.0)
		var col := CollisionShape2D.new()
		col.shape = shape
		body.add_child(col)


# ── Shader material factories ────────────────────────────────────────────────

## Animated ripple effect for the ocean surface.
## World-space coordinates are passed via a varying so the pattern is stable
## as the camera moves; TIME drives the wave animation.
static func _make_water_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec2  p = world_pos * 0.00045;
	float t = TIME * 0.35;
	float w = sin(p.x * 7.0 + t)                    * 0.50
	        + sin(p.x * 4.3 - t * 0.80 + p.y * 2.5) * 0.30
	        + sin(p.y * 5.5 + t * 1.10)              * 0.20;
	w = w * 0.5 + 0.5;
	vec4 deep    = vec4(0.06, 0.16, 0.42, 1.0);
	vec4 shallow = vec4(0.15, 0.31, 0.58, 1.0);
	vec4 sparkle = vec4(0.62, 0.84, 0.97, 1.0);
	vec4 base  = mix(deep, shallow, w);
	float spark = smoothstep(0.84, 1.0, w);
	COLOR = mix(base, sparkle, spark * 0.45);
}"""
	var m := ShaderMaterial.new()
	m.shader = s
	return m


## Subtle multi-tone variation for the island grass.
## Uses layered sine harmonics in world space so patches stay fixed.
static func _make_grass_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec2  p = world_pos * 0.004;
	float n = sin(p.x * 5.3 + p.y * 3.7) * 0.50 + 0.50;
	n += (sin(p.x * 11.9 - p.y * 8.1)    * 0.50 + 0.50) * 0.45;
	n /= 1.45;
	vec4 dark  = vec4(0.27, 0.39, 0.19, 1.0);
	vec4 light = vec4(0.47, 0.59, 0.35, 1.0);
	COLOR = mix(dark, light, n);
}"""
	var m := ShaderMaterial.new()
	m.shader = s
	return m


## Shared helper — creates a Polygon2D rectangle at world position (x, y) with
## the given width, height, colour, and z_index; appended to parent.
static func fill_rect(x: float, y: float, w: float, h: float,
					  col: Color, z: int, parent: Node) -> void:
	var poly := Polygon2D.new()
	var hw: float = w * 0.5
	var hh: float = h * 0.5
	poly.position = Vector2(x + hw, y + hh)
	poly.polygon = PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh),
		Vector2(hw, hh), Vector2(-hw, hh),
	])
	poly.color   = col
	poly.z_index = z
	parent.add_child(poly)
