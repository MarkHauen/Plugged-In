extends CanvasLayer
class_name NPCDataView
## Full-screen NPC directory spreadsheet. Toggled by City.gd on the F key.
##
## Columns: Name | Type | District | Balance | Wage/day | Rent/day | Hunger | State | Behaviour

const HEADERS: Array = [
	"Name", "Type", "District", "Balance", "Wage/day", "Rent/day", "Hunger", "State", "Behaviour",
]
const WIDTHS: Array = [170, 108, 135, 82, 80, 80, 70, 112, 155]

const C_HDR  := Color(0.55, 0.85, 1.00)
const C_NORM := Color(0.82, 0.82, 0.82)
const C_DIM  := Color(0.46, 0.46, 0.56)
const C_OK   := Color(0.38, 1.00, 0.55)
const C_WARN := Color(1.00, 0.68, 0.22)
const C_CRIT := Color(1.00, 0.30, 0.30)
const R_EVEN := Color(0.04, 0.07, 0.12, 1.0)
const R_ODD  := Color(0.07, 0.10, 0.17, 1.0)

var _npcs:      Array         = []
var _districts: Array         = []
var _body:      VBoxContainer = null
var _count_lbl: Label         = null


func _ready() -> void:
	layer   = 20
	visible = false


## Called by City.gd after NPC and district arrays are populated.
func setup(npcs: Array, districts: Array) -> void:
	_npcs      = npcs
	_districts = districts


## Toggle visibility; lazily builds UI on first open and refreshes data.
func toggle() -> void:
	visible = not visible
	if visible:
		if _body == null:
			_build_ui()
		_refresh()


func _build_ui() -> void:
	# Full-screen dark backdrop — eats pointer events so the world doesn't react
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.07, 0.95)
	add_child(bg)

	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_top",    18)
	mc.add_theme_constant_override("margin_bottom", 18)
	mc.add_theme_constant_override("margin_left",   18)
	mc.add_theme_constant_override("margin_right",  18)
	bg.add_child(mc)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	mc.add_child(outer)

	# ── Title bar ────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)

	var ttl := Label.new()
	ttl.text = "  NPC DIRECTORY"
	ttl.add_theme_font_size_override("font_size", 15)
	ttl.add_theme_color_override("font_color", Color(0.50, 1.00, 0.72))
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(ttl)

	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 12)
	_count_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	_count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_count_lbl)

	var close_btn := Button.new()
	close_btn.text = "  ✕  Close  [F]  "
	close_btn.pressed.connect(func() -> void: visible = false)
	title_row.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# ── Fixed header row ─────────────────────────────────────────────────
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 2)
	outer.add_child(hrow)
	for i: int in range(HEADERS.size()):
		hrow.add_child(_cell(HEADERS[i], WIDTHS[i], C_HDR))

	outer.add_child(HSeparator.new())

	# ── Scrollable body ───────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.add_child(scroll)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


func _refresh() -> void:
	if _body == null:
		return

	for ch: Node in _body.get_children():
		_body.remove_child(ch)
		ch.queue_free()

	var visible_count: int = 0
	var row_idx: int = 0
	for npc: NPC in _npcs:
		if not is_instance_valid(npc):
			continue
		_body.add_child(_make_row(npc, row_idx))
		row_idx += 1
		visible_count += 1

	if _count_lbl != null:
		_count_lbl.text = "%d NPCs" % visible_count


func _make_row(npc: NPC, idx: int) -> PanelContainer:
	var sty := StyleBoxFlat.new()
	sty.bg_color = R_EVEN if idx % 2 == 0 else R_ODD
	sty.content_margin_left   = 2.0
	sty.content_margin_right  = 2.0
	sty.content_margin_top    = 1.0
	sty.content_margin_bottom = 1.0
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sty)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	pc.add_child(row)

	var is_civ: bool = npc.npc_type == NPC.Type.CIVILIAN

	# Name
	row.add_child(_cell(npc.display_name, WIDTHS[0], C_NORM))

	# Type
	var type_str: String
	if npc.npc_type == NPC.Type.POLICE:
		type_str = "Highway Patrol" if npc.is_highway_police else "Police"
	else:
		type_str = "Civilian"
	row.add_child(_cell(type_str, WIDTHS[1], C_DIM if npc.npc_type == NPC.Type.POLICE else C_NORM))

	# District
	var d_str: String = "All Districts"
	if npc.district_id >= 0 and npc.district_id < _districts.size():
		d_str = _districts[npc.district_id]["name"]
	row.add_child(_cell(d_str, WIDTHS[2], C_NORM))

	# Balance — warn if less than 2 days' rent
	var bal_col: Color = C_NORM
	if is_civ and npc.balance < npc.daily_rent * 2.0:
		bal_col = C_WARN
	row.add_child(_cell("$%.0f" % npc.balance if is_civ else "—", WIDTHS[3], bal_col))

	# Wage/day
	row.add_child(_cell("$%.0f" % npc.daily_wage if is_civ else "—", WIDTHS[4], C_NORM))

	# Rent/day
	row.add_child(_cell("$%.0f" % npc.daily_rent if is_civ else "—", WIDTHS[5], C_NORM))

	# Hunger — colour-coded green/amber/red
	var h_col: Color = C_OK
	if is_civ:
		if npc.hunger >= NPC.HUNGER_THRESHOLD:
			h_col = C_CRIT
		elif npc.hunger >= 0.40:
			h_col = C_WARN
	row.add_child(_cell("%.0f%%" % (npc.hunger * 100.0) if is_civ else "—", WIDTHS[6], h_col))

	# State
	var state_str: String
	var state_col: Color
	if is_civ:
		state_str = "⚠ Struggling" if npc._is_struggling else "OK"
		state_col  = C_WARN if npc._is_struggling else C_OK
	else:
		state_str = "—"
		state_col  = C_DIM
	row.add_child(_cell(state_str, WIDTHS[7], state_col))

	# Behaviour
	var beh_str: String = "Patrol"
	var beh_col: Color  = C_DIM
	if is_civ:
		if npc._behaviour == NPC.Behaviour.GOING_TO_SHOP and npc._shop_item >= 0:
			beh_str = "→ " + ItemDB.get_item_name(npc._shop_item)
			beh_col = C_OK
		else:
			beh_str = "Wander"
			beh_col = C_NORM
	row.add_child(_cell(beh_str, WIDTHS[8], beh_col))

	return pc


## Returns a Label sized to the given column width.
func _cell(text: String, w: int, col: Color = Color(0.82, 0.82, 0.82)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size      = Vector2(w, 20)
	lbl.size_flags_horizontal    = Control.SIZE_SHRINK_BEGIN
	lbl.clip_text                = true
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", col)
	return lbl
