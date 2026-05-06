extends CharacterBody2D

class_name Employee

# =============================================================================
#  Employee — follows the player when free; stays at an assigned building
#  when deployed as a shop-keeper.  Each employee has their own Inventory.
# =============================================================================

const FOLLOW_SPEED := 180.0
const FOLLOW_DIST  := 80.0            # stop when within this many px of player
const FREE_COLOR   := Color(0.40, 0.90, 0.55, 1.0)   # green pentagon
const BUSY_COLOR   := Color(0.90, 0.65, 0.20, 1.0)   # amber pentagon

enum State { FOLLOWING, ASSIGNED }

var state:        State  = State.FOLLOWING
var display_name: String = "Employee"
var inventory:    Object = null       # Inventory instance (set in init)
var cash:         float  = 0.0        # Cash float stored at this shop

var _target: Node       = null        # player node
var _poly:   Polygon2D  = null
var _label:  Label      = null


# Call BEFORE add_child so _ready picks up the correct name and target.
func init(emp_name: String, player: Node) -> void:
	display_name = emp_name
	_target      = player
	var Inv   := load("res://scripts/economy/Inventory.gd")
	inventory  = Inv.new()


func _ready() -> void:
	if inventory == null:
		var Inv   := load("res://scripts/economy/Inventory.gd")
		inventory  = Inv.new()
	_build_visual()


# ── State transitions ─────────────────────────────────────────────────────────

func assign_to_building(world_pos: Vector2) -> void:
	state    = State.ASSIGNED
	position = world_pos
	if _poly  != null: _poly.color = BUSY_COLOR
	if _label != null: _label.text = display_name + "\n[Shop]"


func recall() -> void:
	state = State.FOLLOWING
	if _poly  != null: _poly.color = FREE_COLOR
	if _label != null: _label.text = display_name


func is_free() -> bool:
	return state == State.FOLLOWING


# ── Movement ──────────────────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	if state != State.FOLLOWING or _target == null:
		velocity = Vector2.ZERO
		return
	var diff: Vector2 = _target.position - position
	if diff.length() <= FOLLOW_DIST:
		velocity = Vector2.ZERO
	else:
		velocity = diff.normalized() * FOLLOW_SPEED
	move_and_slide()


# ── Visual construction ───────────────────────────────────────────────────────

func _build_visual() -> void:
	# Pentagon — visually distinct from NPC shapes (tri/square/octagon)
	var outline := Polygon2D.new()
	outline.polygon = _ngon(5, 14.0)
	outline.color   = Color(0.0, 0.0, 0.0, 0.55)
	outline.z_index = 0
	add_child(outline)

	_poly         = Polygon2D.new()
	_poly.polygon = _ngon(5, 12.0)
	_poly.color   = BUSY_COLOR if state == State.ASSIGNED else FREE_COLOR
	_poly.z_index = 1
	add_child(_poly)

	_label = Label.new()
	_label.text = display_name + ("\n[Shop]" if state == State.ASSIGNED else "")
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.90))
	_label.position                = Vector2(-40.0, -32.0)
	_label.custom_minimum_size.x   = 80.0
	_label.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	_label.z_index = 2
	add_child(_label)

	var col_shape   := CollisionShape2D.new()
	var circle      := CircleShape2D.new()
	circle.radius   = 12.0
	col_shape.shape = circle
	add_child(col_shape)


func _ngon(sides: int, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(sides):
		var angle: float = -PI * 0.5 + float(i) * TAU / float(sides)
		pts.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return pts
