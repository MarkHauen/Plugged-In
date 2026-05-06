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
	poly.color   = WorldData.WATER_COLOR
	poly.z_index = -4
	parent.add_child(poly)


## Draw the island landmass polygon.
static func draw_island(parent: Node) -> void:
	var poly := Polygon2D.new()
	poly.polygon = WorldData.ISLAND_POLY
	poly.color   = WorldData.ISLAND_BASE
	poly.z_index = -3
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
