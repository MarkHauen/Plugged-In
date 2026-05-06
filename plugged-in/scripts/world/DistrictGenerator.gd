extends RefCounted

# =============================================================================
#  DistrictGenerator — spawns districts, blocks, special blocks, mega blocks,
#  and individual buildings.  Pure world-generation logic; no tick/economy code.
#
#  Usage:
#    var gen := DistrictGenerator.new(scene_root, building_info_ui, landowners,
#                                      all_bldg_metas, all_bldg_pos,
#                                      storefront_registry, npc_init_queue)
#    gen.generate_all_districts()
# =============================================================================

class_name DistrictGenerator

# ── Decoration colours / labels for special block types ───────────────────
const SPECIAL_COLORS: Dictionary = {
	"park":          Color(0.28, 0.68, 0.30),
	"town_square":   Color(0.72, 0.64, 0.48),
	"statue":        Color(0.36, 0.46, 0.62),
	"beach":         Color(0.94, 0.86, 0.60),
	"port":          Color(0.20, 0.30, 0.40),
	"market_square": Color(0.72, 0.58, 0.30),
	"vacant_lot":    Color(0.28, 0.24, 0.18),
}
const SPECIAL_LABELS: Dictionary = {
	"park":          "Park",
	"town_square":   "Town Square",
	"statue":        "The Vertex — Tech Sculpture",
	"beach":         "Beachfront Promenade",
	"port":          "Working Port",
	"market_square": "Market Square",
	"vacant_lot":    "Vacant Lot",
}

# ── Per-type config for mega blocks ───────────────────────────────────────
const MEGA_CONFIGS: Dictionary = {
	"bank":       {"biz": "Bank",          "prop": "Financial",     "tint": Color(0.62, 0.72, 0.90), "pfx": ["Grand", "Central", "Apex", "Meridian"]},
	"law_firm":   {"biz": "Law Firm",      "prop": "Office",        "tint": Color(0.52, 0.58, 0.70), "pfx": ["Premier", "Elite", "Crown", "Pinnacle"]},
	"factory":    {"biz": "Factory",       "prop": "Industrial",    "tint": Color(0.48, 0.42, 0.34), "pfx": ["Iron", "Steel", "Heavy", "Crown"]},
	"warehouse":  {"biz": "Warehouse",     "prop": "Industrial",    "tint": Color(0.40, 0.46, 0.52), "pfx": ["Blue", "Dock", "Port", "Anchor"]},
	"casino":     {"biz": "Casino",        "prop": "Entertainment", "tint": Color(0.80, 0.64, 0.20), "pfx": ["Golden", "Jackpot", "Lucky", "Glitter"]},
	"mega_hotel": {"biz": "Tourist Hotel", "prop": "Hotel",         "tint": Color(0.78, 0.72, 0.54), "pfx": ["Grand", "Lagoon", "Horizon", "Royal", "Palm", "Azure", "Coral", "Surf", "Tropicana", "Blue", "Breeze", "Wave", "Sandy", "Reef", "Sunny"]},
	"tech_campus":{"biz": "R&D Campus",    "prop": "Office",        "tint": Color(0.42, 0.56, 0.72), "pfx": ["Quantum", "Helix", "Neural", "Vertex"]},
	"manor":      {"biz": "Manor House",   "prop": "Residential",   "tint": Color(0.60, 0.50, 0.38), "pfx": ["Royal", "Grand", "Stone", "Ivory"]},
}

# ── Injected references (set via constructor) ──────────────────────────────
var _scene_root:          Node
var _building_info_ui:    CanvasLayer
var _landowners:          Array   # shared ref from City
var _all_bldg_metas:      Array   # shared ref from City
var _all_bldg_pos:        Array   # shared ref from City
var _storefront_registry: Array   # shared ref from City
var _npc_init_queue:      Array   # shared ref from City
var _npc_spawner:         Object  # NPCSpawner instance (set by City after construction)


func _init(scene_root: Node,
		   building_info_ui: CanvasLayer,
		   landowners: Array,
		   all_bldg_metas: Array,
		   all_bldg_pos: Array,
		   storefront_registry: Array,
		   npc_init_queue: Array) -> void:
	_scene_root          = scene_root
	_building_info_ui    = building_info_ui
	_landowners          = landowners
	_all_bldg_metas      = all_bldg_metas
	_all_bldg_pos        = all_bldg_pos
	_storefront_registry = storefront_registry
	_npc_init_queue      = npc_init_queue


## Generate every district in WorldData.DISTRICTS.
func generate_all_districts() -> void:
	for d: Dictionary in WorldData.DISTRICTS:
		_generate_district(d)


# =============================================================================
#  DISTRICT — floor, roads, per-block dispatch
# =============================================================================
func _generate_district(d: Dictionary) -> void:
	var cols: int   = d["cols"]
	var rows: int   = d["rows"]
	var ox:   float = float(d["ox"])
	var oy:   float = float(d["oy"])
	var dw:   float = cols * WorldData.CELL_W + WorldData.ROAD_W
	var dh:   float = rows * WorldData.CELL_H + WorldData.ROAD_W

	WorldRenderer.fill_rect(ox, oy, dw, dh, d["floor"], -2, _scene_root)
	for row: int in range(rows + 1):
		WorldRenderer.fill_rect(ox, oy + row * WorldData.CELL_H, dw, WorldData.ROAD_W, WorldData.ROAD_COLOR, -1, _scene_root)
	for col: int in range(cols + 1):
		WorldRenderer.fill_rect(ox + col * WorldData.CELL_W, oy, WorldData.ROAD_W, dh, WorldData.ROAD_COLOR, -1, _scene_root)

	var did:  int    = d["id"]
	var bc:   Color  = d["bldg"]
	var pref: Array  = d["pref"]
	var pw:   float  = d["police_w"]
	var cw:   float  = d["civilian_w"]
	var kw:   float  = d["customer_w"]
	var stn:  String = d["st_name"]

	# Build fast lookup sets for special and mega blocks (keyed "col,row")
	var special_set: Dictionary = {}
	for sb: Dictionary in d.get("special_blocks", []):
		special_set[str(int(sb["col"])) + "," + str(int(sb["row"]))] = sb["type"]
	var mega_set: Dictionary = {}
	for mb: Dictionary in d.get("mega_blocks", []):
		mega_set[str(int(mb["col"])) + "," + str(int(mb["row"]))] = mb["type"]

	for row: int in range(rows):
		for col: int in range(cols):
			var bx:  float  = ox + col * WorldData.CELL_W + WorldData.ROAD_W
			var by_: float  = oy + row * WorldData.CELL_H + WorldData.ROAD_W
			var key: String = str(col) + "," + str(row)
			if special_set.has(key):
				_spawn_special_block(bx, by_, did, bc, d["name"], d["floor"], special_set[key], pw, cw)
			elif mega_set.has(key):
				_spawn_mega_block(bx, by_, did, bc, d["name"], stn, row + 1, col + 1, mega_set[key], pw, cw)
			else:
				_spawn_block(bx, by_, did, bc, d["name"], row + 1, col + 1, stn, pref, pw, cw, kw)


# =============================================================================
#  STANDARD BLOCK — 2×2 sub-buildings + 1 NPC
# =============================================================================
func _spawn_block(bx: float, by_: float,
				  did: int, bc: Color, d_name: String,
				  st_num: int, ave_num: int, stn: String,
				  pref: Array, pw: float, cw: float, kw: float) -> void:
	var hw: float = (WorldData.BLOCK_W - WorldData.ALLEY) * 0.5
	var hh: float = (WorldData.BLOCK_H - WorldData.ALLEY) * 0.5

	var offsets: Array = [
		Vector2(0.0, 0.0),
		Vector2(hw + WorldData.ALLEY, 0.0),
		Vector2(0.0, hh + WorldData.ALLEY),
		Vector2(hw + WorldData.ALLEY, hh + WorldData.ALLEY),
	]

	var ordinal: String = WorldData.ORDINALS[st_num - 1] if st_num <= WorldData.ORDINALS.size() else str(st_num) + "th"
	var cfg: Dictionary = WorldData.DISTRICT_BLDG_CONFIG[did]
	var sz_lo: float    = float(cfg["bldg_size_lo"])
	var sz_hi: float    = float(cfg["bldg_size_hi"])

	# ── One storefront per block; one ATM per block in eligible districts ──
	var sf_idx:   int    = randi() % 4
	var sf_pool:  Array  = WorldData.DISTRICT_STOREFRONT_ITEMS[did]
	var sf_item:  int    = sf_pool[randi() % sf_pool.size()]
	var sf_price: int    = ItemDB.get_base_price(sf_item)
	var sf_iname: String = ItemDB.get_item_name(sf_item)
	var sf_btype: String = WorldData.ITEM_SHOP_TYPES[sf_item]

	var atm_idx: int = -1
	if (did in WorldData.ATM_DISTRICT_IDS) and randf() < 0.22:
		atm_idx = (sf_idx + 1 + randi() % 3) % 4

	for i: int in range(4):
		var sx: float = bx + offsets[i].x
		var sy: float = by_ + offsets[i].y
		var is_storefront: bool = (i == sf_idx)
		var is_atm:        bool = (i == atm_idx)

		var sw: float
		var sh: float
		if is_atm:
			sw = hw * 0.28
			sh = hh * 0.28
		else:
			sw = randf_range(hw * sz_lo, hw * sz_hi)
			sh = randf_range(hh * sz_lo, hh * sz_hi)
		var pad_x: float = randf() * max(0.0, hw - sw)
		var pad_y: float = randf() * max(0.0, hh - sh)

		var bnum:    int    = ave_num * 100 + i * 2 + 1
		var address: String = str(bnum) + " " + ordinal + " " + stn

		var biz_type:  String
		var prop_type: String
		var biz_name:  String
		if is_atm:
			biz_type  = "Bitcoin ATM"
			prop_type = "Financial"
			biz_name  = "BTC ATM"
		elif is_storefront:
			biz_type  = sf_btype
			prop_type = "Retail"
			var pfx_pool: Array = cfg["prefixes"]
			biz_name = pfx_pool[randi() % pfx_pool.size()] + " " + sf_btype
		else:
			var pool_size: int = (cfg["biz_types"] as Array).size()
			var pool_idx:  int = randi() % pool_size
			biz_type  = (cfg["biz_types"] as Array)[pool_idx]
			prop_type = (cfg["prop_types"] as Array)[pool_idx]
			var pfx_pool: Array = cfg["prefixes"]
			biz_name = pfx_pool[randi() % pfx_pool.size()] + " " + biz_type

		var price:  int = randi_range(cfg["price_lo"],  cfg["price_hi"])
		var income: int = randi_range(cfg["income_lo"], cfg["income_hi"])

		var status:      String = "occupied"
		var draw_col:    Color  = bc
		var orig_income: int    = income
		if not is_atm and not is_storefront and randf() < float(cfg["abandon_chance"]):
			status   = "abandoned"
			draw_col = WorldData.ABANDONED_COLOR
			income   = 0

		if is_atm:
			draw_col = WorldData.ATM_COLOR
		elif is_storefront:
			draw_col = draw_col.lerp(WorldData.STOREFRONT_TINT, 0.45)

		var meta: Dictionary = {
			"biz_name": biz_name, "address": address, "district": d_name,
			"biz_type": biz_type, "property_type": prop_type,
			"price": price, "income": income, "status": status,
			"_orig_income": orig_income, "_base_color": bc,
		}
		if is_storefront:
			meta["storefront"]      = true
			meta["sells_item_id"]   = sf_item
			meta["sells_item_name"] = sf_iname
			meta["sell_price"]      = sf_price
		if is_atm:
			meta["atm"] = true

		_apply_econ_fields(meta, biz_type, prop_type, did)
		_spawn_building(sx + pad_x + sw * 0.5, sy + pad_y + sh * 0.5, sw, sh, draw_col, meta)

	_npc_spawner.spawn_npc_at(
		bx + WorldData.BLOCK_W * 0.5 + randf_range(-40, 40),
		by_ + WorldData.BLOCK_H * 0.5 + randf_range(-30, 30),
		did, pref, pw, cw, kw * 0.4)


# =============================================================================
#  SPECIAL BLOCK — decorative, no buildings; one ambient NPC
# =============================================================================
func _spawn_special_block(bx: float, by_: float,
						  did: int, _bc: Color, _d_name: String, floor_col: Color,
						  spec_type: String, pw: float, cw: float) -> void:
	var fill_col: Color  = SPECIAL_COLORS.get(spec_type, floor_col.lightened(0.12))
	var label:    String = SPECIAL_LABELS.get(spec_type, spec_type.capitalize())

	WorldRenderer.fill_rect(bx, by_, WorldData.BLOCK_W, WorldData.BLOCK_H, fill_col, 0, _scene_root)
	_draw_special_details(bx, by_, spec_type)

	var name_lbl := Label.new()
	name_lbl.text     = label
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.70))
	name_lbl.position = Vector2(bx + WorldData.BLOCK_W * 0.5 - 60, by_ + WorldData.BLOCK_H * 0.5 - 8)
	name_lbl.z_index  = 3
	_scene_root.add_child(name_lbl)

	var pref: Array = []
	_npc_spawner.spawn_npc_at(bx + WorldData.BLOCK_W * 0.5, by_ + WorldData.BLOCK_H * 0.5,
							  did, pref, pw * 0.3, cw, 0.0)


func _draw_special_details(bx: float, by_: float, spec_type: String) -> void:
	match spec_type:
		"park":
			var tree_col := Color(0.16, 0.52, 0.20, 0.85)
			for tx: int in range(2):
				for ty: int in range(2):
					var tcx: float = bx + tx * WorldData.BLOCK_W * 0.5 + WorldData.BLOCK_W * 0.25
					var tcy: float = by_ + ty * WorldData.BLOCK_H * 0.5 + WorldData.BLOCK_H * 0.25
					WorldRenderer.fill_rect(tcx - 36, tcy - 36, 72, 72, tree_col, 1, _scene_root)
			WorldRenderer.fill_rect(bx + WorldData.BLOCK_W * 0.5 - 8, by_, 16, WorldData.BLOCK_H,
									Color(0.65, 0.58, 0.42, 0.70), 1, _scene_root)
			WorldRenderer.fill_rect(bx, by_ + WorldData.BLOCK_H * 0.5 - 8, WorldData.BLOCK_W, 16,
									Color(0.65, 0.58, 0.42, 0.70), 1, _scene_root)
		"town_square":
			WorldRenderer.fill_rect(bx + WorldData.BLOCK_W * 0.5 - 50, by_ + WorldData.BLOCK_H * 0.5 - 50, 100, 100,
									Color(0.55, 0.70, 0.82, 0.90), 1, _scene_root)
			WorldRenderer.fill_rect(bx + WorldData.BLOCK_W * 0.5 - 12, by_ + WorldData.BLOCK_H * 0.5 - 12, 24, 24,
									Color(0.80, 0.88, 0.96, 1.0), 1, _scene_root)
		"statue":
			WorldRenderer.fill_rect(bx + WorldData.BLOCK_W * 0.5 - 55, by_ + WorldData.BLOCK_H * 0.5 - 55, 110, 110,
									Color(0.22, 0.30, 0.42), 1, _scene_root)
			WorldRenderer.fill_rect(bx + WorldData.BLOCK_W * 0.5 - 22, by_ + WorldData.BLOCK_H * 0.5 - 22, 44, 44,
									Color(0.40, 0.82, 1.00, 0.95), 1, _scene_root)
			for ang: int in range(8):
				var rad: float = ang * PI / 4.0
				var ex: float  = bx + WorldData.BLOCK_W * 0.5 + cos(rad) * 90.0
				var ey: float  = by_ + WorldData.BLOCK_H * 0.5 + sin(rad) * 90.0
				WorldRenderer.fill_rect(
					minf(bx + WorldData.BLOCK_W * 0.5, ex),
					minf(by_ + WorldData.BLOCK_H * 0.5, ey),
					maxf(abs(ex - (bx + WorldData.BLOCK_W * 0.5)), 4.0),
					maxf(abs(ey - (by_ + WorldData.BLOCK_H * 0.5)), 4.0),
					Color(0.40, 0.82, 1.00, 0.30), 1, _scene_root)
		"beach":
			WorldRenderer.fill_rect(bx, by_ + WorldData.BLOCK_H * 0.78, WorldData.BLOCK_W, WorldData.BLOCK_H * 0.22,
									Color(0.36, 0.62, 0.82, 0.60), 1, _scene_root)
			WorldRenderer.fill_rect(bx, by_ + WorldData.BLOCK_H * 0.75, WorldData.BLOCK_W, 8,
									Color(0.88, 0.96, 1.00, 0.80), 1, _scene_root)
		"port":
			WorldRenderer.fill_rect(bx, by_, WorldData.BLOCK_W, WorldData.BLOCK_H, Color(0.12, 0.20, 0.30), 0, _scene_root)
			for pi_: int in range(4):
				var px: float = bx + pi_ * WorldData.BLOCK_W * 0.25 + 20
				WorldRenderer.fill_rect(px, by_, 14, WorldData.BLOCK_H, Color(0.22, 0.32, 0.44), 1, _scene_root)
			WorldRenderer.fill_rect(bx + WorldData.BLOCK_W * 0.6, by_ + 10, 12, WorldData.BLOCK_H * 0.55,
									Color(0.55, 0.52, 0.42), 2, _scene_root)
			WorldRenderer.fill_rect(bx + WorldData.BLOCK_W * 0.3, by_ + 10, WorldData.BLOCK_W * 0.32, 12,
									Color(0.55, 0.52, 0.42), 2, _scene_root)
		"market_square":
			for si: int in range(6):
				var stripe_col: Color = Color(0.85, 0.42, 0.18, 0.55) if si % 2 == 0 else Color(0.92, 0.78, 0.28, 0.55)
				WorldRenderer.fill_rect(bx + si * WorldData.BLOCK_W / 6.0, by_, WorldData.BLOCK_W / 6.0, WorldData.BLOCK_H,
										stripe_col, 1, _scene_root)
			WorldRenderer.fill_rect(bx + WorldData.BLOCK_W * 0.5 - 30, by_ + WorldData.BLOCK_H * 0.5 - 30, 60, 60,
									Color(0.90, 0.70, 0.20, 0.90), 2, _scene_root)
		"vacant_lot":
			for _ri: int in range(12):
				var rx: float = bx + randf() * WorldData.BLOCK_W
				var ry: float = by_ + randf() * WorldData.BLOCK_H
				WorldRenderer.fill_rect(rx, ry, randf_range(8, 22), randf_range(8, 16),
										Color(0.38, 0.32, 0.24, 0.80), 1, _scene_root)


# =============================================================================
#  MEGA BLOCK — single oversized building filling most of the block footprint
# =============================================================================
func _spawn_mega_block(bx: float, by_: float,
					   did: int, _bc: Color, d_name: String, stn: String,
					   st_num: int, ave_num: int,
					   mega_type: String, pw: float, cw: float) -> void:
	var cfg_m: Dictionary = MEGA_CONFIGS.get(mega_type,
		{"biz": "Office Tower", "prop": "Office", "tint": Color(0.5, 0.5, 0.6), "pfx": ["Grand"]})
	var biz_type:  String = cfg_m["biz"]
	var prop_type: String = cfg_m["prop"]
	var tint:      Color  = cfg_m["tint"]
	var pfx_pool:  Array  = cfg_m["pfx"]
	var dcfg:      Dictionary = WorldData.DISTRICT_BLDG_CONFIG[did]

	var pfx:      String = pfx_pool[randi() % pfx_pool.size()]
	var biz_name: String = pfx + " " + biz_type
	var ordinal:  String = WorldData.ORDINALS[st_num - 1] if st_num <= WorldData.ORDINALS.size() else str(st_num) + "th"
	var address:  String = str(ave_num * 100 + 1) + " " + ordinal + " " + stn

	var margin_x: float = WorldData.BLOCK_W * randf_range(0.02, 0.06)
	var margin_y: float = WorldData.BLOCK_H * randf_range(0.02, 0.06)
	var sw: float = WorldData.BLOCK_W - margin_x * 2.0
	var sh: float = WorldData.BLOCK_H - margin_y * 2.0
	var cx: float = bx + WorldData.BLOCK_W * 0.5
	var cy: float = by_ + WorldData.BLOCK_H * 0.5

	var price:  int = randi_range(int(dcfg["price_hi"]) * 2, int(dcfg["price_hi"]) * 5)
	var income: int = randi_range(int(dcfg["income_hi"]) * 2, int(dcfg["income_hi"]) * 4)

	var meta: Dictionary = {
		"biz_name": biz_name, "address": address, "district": d_name,
		"biz_type": biz_type, "property_type": prop_type,
		"price": price, "income": income, "status": "occupied",
		"_orig_income": income, "_base_color": tint, "mega": true,
	}
	_apply_econ_fields_mega(meta, biz_type, prop_type, did)
	_spawn_building(cx, cy, sw, sh, tint, meta)

	var pref: Array = []
	_npc_spawner.spawn_npc_at(bx + WorldData.BLOCK_W * 0.5, by_ + WorldData.BLOCK_H * 0.5,
							  did, pref, pw * 0.5, cw, 0.15)


# =============================================================================
#  BUILDING — creates scene node + click handler; populates shared arrays
# =============================================================================
func _spawn_building(cx: float, cy: float, w: float, h: float,
					 col: Color, meta: Dictionary) -> void:
	meta["_world_pos"] = Vector2(cx, cy)
	_all_bldg_pos.append(Vector2(cx, cy))
	_all_bldg_metas.append(meta)
	if meta.get("storefront", false):
		_storefront_registry.append({"pos": Vector2(cx, cy), "item_id": meta["sells_item_id"], "meta": meta})

	var body := StaticBody2D.new()
	body.position      = Vector2(cx, cy)
	body.z_index       = 1
	body.input_pickable = true
	_scene_root.add_child(body)

	var shape  := RectangleShape2D.new()
	shape.size = Vector2(w, h)
	var cshape := CollisionShape2D.new()
	cshape.shape = shape
	body.add_child(cshape)

	var hw: float = w * 0.5
	var hh: float = h * 0.5

	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh),
		Vector2(hw, hh), Vector2(-hw, hh),
	])
	vis.color = col
	body.add_child(vis)
	meta["_vis"] = vis

	var rh:   float    = hh * 0.6
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh),
		Vector2(hw, -hh + rh), Vector2(-hw, -hh + rh),
	])
	roof.color = Color(col.r * 0.70, col.g * 0.70, col.b * 0.70)
	body.add_child(roof)
	meta["_roof"] = roof

	if meta.get("status") == "abandoned":
		var overlay := Polygon2D.new()
		overlay.polygon = PackedVector2Array([
			Vector2(-hw, -hh), Vector2(hw, -hh),
			Vector2(hw, hh), Vector2(-hw, hh),
		])
		overlay.color = Color(0.0, 0.0, 0.0, 0.30)
		body.add_child(overlay)
		meta["_overlay"] = overlay

	var lbl := Label.new()
	lbl.text = meta.get("address", "")
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color",
		Color(0.70, 0.65, 0.60) if meta.get("status") == "abandoned"
		else Color(1.0, 1.0, 1.0, 0.80))
	lbl.position = Vector2(-hw + 2.0, -hh + 2.0)
	lbl.z_index  = 2
	body.add_child(lbl)

	var captured_meta:     Dictionary = meta
	var captured_binfo_ui: CanvasLayer = _building_info_ui
	body.input_event.connect(
		func(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
			if event is InputEventMouseButton:
				var mb := event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					captured_binfo_ui.show_building(captured_meta)
	)


# =============================================================================
#  HELPERS — apply economic fields to building metadata
# =============================================================================
func _apply_econ_fields(meta: Dictionary, biz_type: String, prop_type: String, did: int) -> void:
	var econ_recipe: Dictionary = BusinessDB.get_recipe(biz_type)
	meta["biz_category"]  = econ_recipe.get("category", "commercial")
	meta["input_buffer"]  = {}
	meta["output_buffer"] = {}
	meta["cash_reserves"] = float(randi_range(50, 500))
	meta["wages_per_day"] = BusinessDB.wages_for(meta)
	meta["rent_per_day"]  = BusinessDB.rent_for(meta)
	meta["operational"]   = (meta.get("status", "") == "occupied")
	meta["debt"]          = 0.0
	var owner_id: int     = _assign_owner(prop_type, did)
	meta["owner_id"]      = owner_id
	meta["owner_name"]    = _landowners[owner_id]["name"] if owner_id >= 0 else "City (For Sale)"
	if owner_id >= 0:
		(_landowners[owner_id]["owned_buildings"] as Array).append(meta)


func _apply_econ_fields_mega(meta: Dictionary, biz_type: String, prop_type: String, did: int) -> void:
	var econ_recipe: Dictionary = BusinessDB.get_recipe(biz_type)
	meta["biz_category"]  = econ_recipe.get("category", "commercial")
	meta["input_buffer"]  = {}
	meta["output_buffer"] = {}
	meta["cash_reserves"] = float(randi_range(2000, 20000))
	meta["wages_per_day"] = BusinessDB.wages_for(meta) * 3.0
	meta["rent_per_day"]  = BusinessDB.rent_for(meta) * 2.5
	meta["operational"]   = true
	meta["debt"]          = 0.0
	var owner_id: int     = _assign_owner(prop_type, did)
	meta["owner_id"]      = owner_id
	meta["owner_name"]    = _landowners[owner_id]["name"] if owner_id >= 0 else "City (For Sale)"
	if owner_id >= 0:
		(_landowners[owner_id]["owned_buildings"] as Array).append(meta)


## Returns a _landowners index for a newly-spawned building; -1 = city-owned.
func _assign_owner(prop_type: String, did: int) -> int:
	if prop_type == "Government":
		return 0
	if did == 5 and prop_type == "Residential" and randf() < 0.30:
		return 0
	var roll: float = randf()
	if roll < 0.20:
		return 1 + randi() % WorldData.BIG_OWNER_NAMES.size()
	elif roll < 0.55:
		var candidates: Array = []
		for owner: Dictionary in _landowners:
			if owner["type"] == "small" and (owner["district_focus"] == did or owner["district_focus"] == -1):
				candidates.append(owner["id"])
		if candidates.is_empty():
			for owner: Dictionary in _landowners:
				if owner["type"] == "small":
					candidates.append(owner["id"])
		if candidates.is_empty():
			return -1
		return candidates[randi() % candidates.size()]
	return -1
