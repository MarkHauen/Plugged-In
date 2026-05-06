extends CharacterBody2D

class_name NPC

enum Type      { CIVILIAN, POLICE }
enum MoveState { IDLE, MOVING }
enum Behaviour { WANDER, GOING_TO_SHOP }

signal npc_clicked(npc: NPC)
signal sale_made(item_name: String, amount: int, shop_pos: Vector2)

# Visual config per type
const TYPE_CONFIG := {
	Type.CIVILIAN: {
		"color":  Color(0.85, 0.85, 0.85, 1.0),  # light gray octagon
		"radius": 12.0,
		"sides":  8,
		"label":  "Civilian",
	},
	Type.POLICE: {
		"color":  Color(0.25, 0.45, 0.90, 1.0),  # blue diamond
		"radius": 13.0,
		"sides":  4,
		"label":  "Police",
	},
}

# Movement config — arrays indexed by Type (CIVILIAN=0, POLICE=1)
const SPEEDS:    Array = [85.0,  110.0]   # px / s
const IDLE_MINS: Array = [5.0,   1.0  ]   # seconds min idle
const IDLE_MAXS: Array = [14.0,  4.0  ]   # seconds max idle
const ARRIVE_DIST := 28.0

# 80% chance a civilian picks from their local (home-district) wander pool
const LOCAL_WANDER_CHANCE  := 0.80
# Flat city-wide chance any shopping trip is for a Flower (no storefront stocks it)
const FLOWER_DEMAND_CHANCE := 0.20

var npc_type:     Type   = Type.CIVILIAN
var display_name: String = ""
var district_id:  int    = -1

# ── Behaviour ─────────────────────────────────────────────────────────────────
var _shop_chance:      float      = 0.15
var _preferred_items:  Array      = []
var _behaviour:        Behaviour  = Behaviour.WANDER
var _shop_item:        int        = -1        # item ID being sought
var _shop_meta:        Dictionary = {}        # live ref to target building meta
var _shop_pos:         Vector2    = Vector2.ZERO
var is_highway_police: bool       = false     # highway patrols roam the whole city

# ── Economy ───────────────────────────────────────────────────────────────────
var balance:        float      = 0.0     # NPC's personal cash
var daily_wage:     float      = 0.0     # received each DAWN tick
var daily_rent:     float      = 0.0     # paid each NIGHT tick
var employer_meta:  Dictionary = {}      # building meta of NPC's employer
var home_meta:      Dictionary = {}      # building meta of NPC's home
var hunger:         float      = 0.0     # 0–1; triggers food trip when > 0.7
const HUNGER_RATE      := 0.30   # hunger added per NIGHT tick
const HUNGER_THRESHOLD := 0.70   # above this → seek food before wants
const STRUGGLING_TINT  := Color(0.90, 0.55, 0.20, 1.0)  # amber — low balance
const NORMAL_TINT      := Color(1.0,  1.0,  1.0,  1.0)  # reset tint
var _is_struggling: bool = false   # true when balance < 0; affects shopping
var _body_poly: Polygon2D = null   # set in _build_visual for tint updates
var _move_state:      MoveState  = MoveState.IDLE
var _path:            Array      = []
var _path_idx:        int        = 0
var _idle_timer:      float      = 0.0
var _road_graph:      Object     = null
var _local_wander_pts: Array     = []   # road nodes near home district
var _roam_wander_pts:  Array     = []   # city-wide road nodes
var _storefront_registry: Array  = []   # shared Array ref from City.gd

var _name_label: Label = null


func _ready() -> void:
	# NPCs are visual movers only — no physics interaction with world or each other
	collision_layer = 0
	collision_mask  = 0
	_build_visual()
	_build_collision()
	# Stagger initial idle so all NPCs don't start moving simultaneously
	_idle_timer = randf_range(0.5, IDLE_MAXS[npc_type])


func setup(type: Type, npc_name: String = "", dist_id: int = -1,
		   shop_chance: float = 0.15, pref_items: Array = [],
		   highway_police: bool = false) -> void:
	npc_type           = type
	display_name       = npc_name if npc_name != "" else TYPE_CONFIG[type]["label"]
	district_id        = dist_id
	_shop_chance       = shop_chance if type == Type.CIVILIAN else 0.0
	_preferred_items   = pref_items
	is_highway_police  = highway_police


## Called by City.gd once the RoadGraph and storefront data are ready.
## local_pts — road nodes near this NPC's spawn (80% of wander picks)
## roam_pts  — city-wide road nodes (20% of picks; occasional long trips)
## registry  — shared Array[{pos, item_id, meta}] of all storefronts
func init_pathfinding(graph: Object, local_pts: Array,
					  roam_pts: Array, registry: Array) -> void:
	_road_graph          = graph
	_local_wander_pts    = local_pts
	_roam_wander_pts     = roam_pts
	_storefront_registry = registry
	# Snap onto the nearest road node so movement never starts off-road
	var snap_idx: int = graph.nearest_node(position)
	if snap_idx >= 0:
		position = graph.nodes[snap_idx]


# ── Per-frame movement ────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	match _move_state:
		MoveState.IDLE:
			if _behaviour == Behaviour.WANDER:
				_idle_timer -= delta
				if _idle_timer <= 0.0:
					_pick_destination()
		MoveState.MOVING:
			_advance_path(delta)


func _pick_destination() -> void:
	if _road_graph == null:
		_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])
		return
	var pool: Array
	if npc_type == Type.POLICE:
		# Police always patrol their assigned area (district or highway).
		# City.gd populates _local_wander_pts with the correct node set.
		if _local_wander_pts.is_empty():
			_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])
			return
		pool = _local_wander_pts
	elif randf() < LOCAL_WANDER_CHANCE and not _local_wander_pts.is_empty():
		pool = _local_wander_pts
	elif not _roam_wander_pts.is_empty():
		pool = _roam_wander_pts
	else:
		_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])
		return
	var dest: Vector2 = pool[randi() % pool.size()]
	_path     = _road_graph.find_path(position, dest)
	_path_idx = 1
	if _path.size() > 1:
		_move_state = MoveState.MOVING
	else:
		_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])


func _advance_path(delta: float) -> void:
	if _path_idx >= _path.size():
		_arrive()
		return
	var target: Vector2 = _path[_path_idx]
	var diff:   Vector2 = target - position
	if diff.length() < ARRIVE_DIST:
		_path_idx += 1
		if _path_idx >= _path.size():
			_arrive()
		return
	position += diff.normalized() * SPEEDS[npc_type] * delta


func _arrive() -> void:
	_move_state = MoveState.IDLE
	_path.clear()
	_path_idx = 0
	if _behaviour == Behaviour.GOING_TO_SHOP:
		_execute_purchase()
		return
	# Normal wander arrival — hunger takes priority over wants
	if npc_type == Type.CIVILIAN:
		if hunger >= HUNGER_THRESHOLD:
			_try_go_shopping_for_food()
			return
		if not _is_struggling and randf() < _shop_chance:
			_try_go_shopping()
			return
	if npc_type == Type.CIVILIAN and _is_struggling and hunger >= HUNGER_THRESHOLD:
		_try_go_shopping_for_food()
		return
	_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])


# ── Shopping behaviour ────────────────────────────────────────────────────────

## Seek only food items (STREET_FOOD, COFFEE, ICE_CREAM, BEER) when hungry.
## Skips the Flower / district preference logic — pure survival need.
func _try_go_shopping_for_food() -> void:
	const FOOD_IDS: Array = [1, 0, 3, 2]  # STREET_FOOD, COFFEE, ICE_CREAM, BEER
	var shuffled: Array = FOOD_IDS.duplicate()
	shuffled.shuffle()
	for food_id: int in shuffled:
		var best_entry: Dictionary = {}
		var best_dist:  float      = INF
		for entry: Dictionary in _storefront_registry:
			if entry["item_id"] == food_id:
				var d: float = (entry["pos"] as Vector2).distance_to(position)
				if d < best_dist:
					best_dist  = d
					best_entry = entry
		if not best_entry.is_empty():
			_shop_item = food_id
			_shop_meta = best_entry["meta"]
			_shop_pos  = best_entry["pos"]
			_path      = _road_graph.find_path(position, _shop_pos)
			_path_idx  = 1
			if _path.size() > 1:
				_behaviour  = Behaviour.GOING_TO_SHOP
				_move_state = MoveState.MOVING
				_update_label()
				return
	_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])


## Pick an item to buy and pathfind to the nearest storefront that stocks it.
func _try_go_shopping() -> void:
	if _storefront_registry.is_empty() or _road_graph == null:
		_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])
		return
	# Universal demand — Flower is desirable city-wide and only the player stocks it.
	# Check this first so it can fire regardless of district preferences.
	var item_id: int
	if randf() < FLOWER_DEMAND_CHANCE:
		item_id = ItemDB.ID.FLOWER
	elif _preferred_items.size() > 0 and randf() < 0.75:
		# 75% of remaining trips want something from the home-district pool
		item_id = _preferred_items[randi() % _preferred_items.size()]
	else:
		var ids: Array = ItemDB.retail_ids()
		item_id = ids[randi() % ids.size()]
	# Find the nearest storefront stocking this item
	var best_entry: Dictionary = {}
	var best_dist:  float      = INF
	for entry: Dictionary in _storefront_registry:
		if entry["item_id"] == item_id:
			var d: float = (entry["pos"] as Vector2).distance_to(position)
			if d < best_dist:
				best_dist  = d
				best_entry = entry
	if best_entry.is_empty():
		_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])
		return
	_shop_item = item_id
	_shop_meta = best_entry["meta"]
	_shop_pos  = best_entry["pos"]
	_path      = _road_graph.find_path(position, _shop_pos)
	_path_idx  = 1
	if _path.size() > 1:
		_behaviour  = Behaviour.GOING_TO_SHOP
		_move_state = MoveState.MOVING
		_update_label()
	else:
		_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])


## Attempt a purchase at the building we navigated to.
## A sale only executes when the shop is player-owned and the employee has stock.
func _execute_purchase() -> void:
	if _shop_meta.get("storefront", false) \
			and _shop_meta.get("status", "") == "player_owned" \
			and _shop_meta.get("sells_item_id", -1) == _shop_item:
		var emp: Variant = _shop_meta.get("_employee", null)
		if emp != null and is_instance_valid(emp):
			var inv: Variant = emp.inventory
			if inv != null and (inv as Object).count(_shop_item) > 0:
				var price: int = _shop_meta.get("sell_price", ItemDB.get_base_price(_shop_item))
				(inv as Object).remove(_shop_item, 1)
				emp.cash += float(price)
				balance  -= float(price)
				sale_made.emit(ItemDB.get_item_name(_shop_item), price, _shop_pos)
				# Eating food reduces hunger
				if _shop_item in [0, 1, 2, 3]:   # COFFEE, STREET_FOOD, BEER, ICE_CREAM
					hunger = maxf(0.0, hunger - 0.50)
				_update_struggling_tint()
	# Always return to wandering after the attempt
	_shop_item = -1
	_shop_meta = {}
	_behaviour = Behaviour.WANDER
	_update_label()
	_idle_timer = randf_range(IDLE_MINS[npc_type], IDLE_MAXS[npc_type])


func _update_label() -> void:
	if _name_label == null:
		return
	if _behaviour == Behaviour.GOING_TO_SHOP and _shop_item >= 0:
		_name_label.text = "%s → %s" % [display_name, ItemDB.get_item_name(_shop_item)]
	else:
		_name_label.text = display_name


func _update_struggling_tint() -> void:
	var struggling_now: bool = balance < 0.0
	if struggling_now == _is_struggling:
		return
	_is_struggling = struggling_now
	if _body_poly == null:
		return
	_body_poly.modulate = STRUGGLING_TINT if _is_struggling else NORMAL_TINT


# ── Economic tick callbacks (called by City.gd) ───────────────────────

## DAWN: employer pays the NPC's wage into their balance.
func receive_wage() -> void:
	if npc_type != Type.CIVILIAN or daily_wage <= 0.0:
		return
	balance += daily_wage
	_update_struggling_tint()


## NIGHT: NPC pays rent to their home building's landowner.
## If they can't afford it, balance goes negative and they become struggling.
func pay_rent() -> void:
	if daily_rent <= 0.0:
		return
	balance -= daily_rent
	if not home_meta.is_empty():
		# Forward rent to the building so it can be collected by the landlord
		home_meta["cash_reserves"] = float(home_meta.get("cash_reserves", 0.0)) + daily_rent
	_update_struggling_tint()


## NIGHT: advance hunger; struggling NPCs get hungrier faster.
func tick_hunger() -> void:
	if npc_type != Type.CIVILIAN:
		return
	var rate: float = HUNGER_RATE * (1.5 if _is_struggling else 1.0)
	hunger = minf(1.0, hunger + rate)


# ── Visual ────────────────────────────────────────────────────────────────────

func _build_visual() -> void:
	var cfg: Dictionary = TYPE_CONFIG[npc_type]
	var color  := cfg["color"] as Color
	var radius := cfg["radius"] as float
	var sides  := cfg["sides"] as int

	var outline := Polygon2D.new()
	outline.polygon = _regular_polygon(sides, radius + 2.0)
	outline.color   = Color(0.0, 0.0, 0.0, 0.6)
	outline.z_index = 0
	add_child(outline)

	var poly   := Polygon2D.new()
	poly.polygon = _regular_polygon(sides, radius)
	poly.color   = color
	poly.z_index = 1
	add_child(poly)
	_body_poly = poly   # keep ref for struggling tint

	# Name label — updated when shopping state changes
	_name_label = Label.new()
	_name_label.text = display_name
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	_name_label.position = Vector2(-40.0, -(radius + 18.0))
	_name_label.custom_minimum_size.x = 80.0
	_name_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.z_index = 2
	add_child(_name_label)


func _build_collision() -> void:
	var cfg: Dictionary = TYPE_CONFIG[npc_type]
	var radius := cfg["radius"] as float
	var shape  := CircleShape2D.new()
	shape.radius = radius
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	# Separate Area2D for mouse-click detection (independent of physics layers)
	var click_area := Area2D.new()
	click_area.input_pickable = true
	var click_shape := CircleShape2D.new()
	click_shape.radius = radius + 4.0
	var click_col := CollisionShape2D.new()
	click_col.shape = click_shape
	click_area.add_child(click_col)
	click_area.input_event.connect(
		func(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
			if event is InputEventMouseButton:
				var mb := event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					npc_clicked.emit(self)
	)
	add_child(click_area)


# ── Helpers ───────────────────────────────────────────────────────────────────

## Build a regular polygon with `sides` vertices inscribed in a circle of `r`.
## Triangles start with a flat base; all others start pointing up.
func _regular_polygon(sides: int, r: float) -> PackedVector2Array:
	var pts    := PackedVector2Array()
	# Rotate so triangles point up and squares stand as diamonds
	var offset := -PI / 2.0
	if sides == 4:
		offset = -PI / 4.0  # diamond orientation
	for i: int in range(sides):
		var angle := offset + (2.0 * PI * i) / float(sides)
		pts.append(Vector2(cos(angle) * r, sin(angle) * r))
	return pts
