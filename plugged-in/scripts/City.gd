extends Node2D

const FLOOR_COLOR    := Color(0.35, 0.45, 0.30, 1.0)  # muted green ground
const BUILDING_COLOR := Color(0.55, 0.45, 0.40, 1.0)  # brownish-gray blocks

const MAP_W := 1600.0
const MAP_H := 1200.0

# Each entry: [center_x, center_y, width, height]
const BUILDINGS: Array = [
	[150.0,  125.0,  200.0, 150.0],
	[1450.0, 125.0,  200.0, 150.0],
	[150.0,  1075.0, 200.0, 150.0],
	[1450.0, 1075.0, 200.0, 150.0],
	[800.0,  125.0,  400.0, 150.0],
	[150.0,  600.0,  200.0, 300.0],
	[1450.0, 600.0,  200.0, 300.0],
	[320.0,  720.0,  220.0, 180.0],
	[1100.0, 420.0,  220.0, 180.0],
]


func _ready() -> void:
	_create_floor()
	_create_boundary_walls()
	for b: Array in BUILDINGS:
		_create_building(b[0], b[1], b[2], b[3])
	# Draw player on top of all world geometry
	$Player.z_index = 1


# ── Floor ──────────────────────────────────────────────────────────────────────

func _create_floor() -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0.0,   0.0),
		Vector2(MAP_W, 0.0),
		Vector2(MAP_W, MAP_H),
		Vector2(0.0,   MAP_H),
	])
	poly.color   = FLOOR_COLOR
	poly.z_index = -1
	add_child(poly)


# ── Boundary walls (invisible collision, keeps player inside the map) ──────────

func _create_boundary_walls() -> void:
	var walls: Array = [
		[MAP_W / 2.0,        -50.0,           MAP_W + 200.0, 100.0],
		[MAP_W / 2.0,        MAP_H + 50.0,    MAP_W + 200.0, 100.0],
		[-50.0,              MAP_H / 2.0,     100.0,         MAP_H + 200.0],
		[MAP_W + 50.0,       MAP_H / 2.0,     100.0,         MAP_H + 200.0],
	]
	for w: Array in walls:
		_make_static_body(w[0], w[1], w[2], w[3], false)


# ── Buildings ─────────────────────────────────────────────────────────────────

func _create_building(cx: float, cy: float, w: float, h: float) -> void:
	var body := _make_static_body(cx, cy, w, h, false)

	var hw  := w / 2.0
	var hh  := h / 2.0
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-hw, -hh),
		Vector2( hw, -hh),
		Vector2( hw,  hh),
		Vector2(-hw,  hh),
	])
	vis.color = BUILDING_COLOR
	body.add_child(vis)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_static_body(cx: float, cy: float, w: float, h: float, _unused: bool) -> StaticBody2D:
	var body  := StaticBody2D.new()
	body.position = Vector2(cx, cy)
	add_child(body)

	var shape     := RectangleShape2D.new()
	shape.size    = Vector2(w, h)
	var col       := CollisionShape2D.new()
	col.shape     = shape
	body.add_child(col)

	return body
