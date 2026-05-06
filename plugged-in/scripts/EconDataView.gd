extends CanvasLayer
class_name EconDataView
## Full-screen economic data spreadsheet. Toggled by City.gd on the G key.
##
## Columns: Biz Name | District | Type | Category | Owner | Status |
##          Cash | Wages/day | Rent/day | In Buffer | Out Buffer

const HEADERS: Array = [
	"Biz Name", "District", "Type", "Category",
	"Owner", "Status", "Cash", "Wages/day", "Rent/day",
	"In Buffer", "Out Buffer",
]
const WIDTHS: Array = [155, 112, 138, 108, 138, 92, 82, 78, 78, 128, 128]

const C_HDR  := Color(0.55, 0.85, 1.00)
const C_NORM := Color(0.82, 0.82, 0.82)
const C_DIM  := Color(0.46, 0.46, 0.56)
const C_OK   := Color(0.38, 1.00, 0.55)
const C_WARN := Color(1.00, 0.68, 0.22)
const C_CRIT := Color(1.00, 0.30, 0.30)
const R_EVEN := Color(0.04, 0.07, 0.12, 1.0)
const R_ODD  := Color(0.07, 0.10, 0.17, 1.0)

var _buildings: Array         = []
var _body:      VBoxContainer = null
var _count_lbl: Label         = null


func _ready() -> void:
	layer   = 21
	visible = false


## Called by City.gd after the building meta array is populated.
func setup(buildings: Array) -> void:
	_buildings = buildings


## Toggle visibility; lazily builds UI on first open and refreshes data.
func toggle() -> void:
	visible = not visible
	if visible:
		if _body == null:
			_build_ui()
		_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.04, 0.07, 0.95)
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
	ttl.text = "  ECONOMIC DATA"
	ttl.add_theme_font_size_override("font_size", 15)
	ttl.add_theme_color_override("font_color", Color(1.00, 0.85, 0.38))
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(ttl)

	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 12)
	_count_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	_count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_count_lbl)

	var close_btn := Button.new()
	close_btn.text = "  ✕  Close  [G]  "
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

	# ── Scrollable body ────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
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

	var row_idx: int = 0
	for meta: Dictionary in _buildings:
		if meta.is_empty():
			continue
		_body.add_child(_make_row(meta, row_idx))
		row_idx += 1

	if _count_lbl != null:
		_count_lbl.text = "%d buildings" % row_idx


func _make_row(meta: Dictionary, idx: int) -> PanelContainer:
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

	var is_op:    bool   = meta.get("operational", false)
	var status:   String = meta.get("status", "occupied")
	var is_aband: bool   = (status == "abandoned")

	# Biz Name
	row.add_child(_cell(meta.get("biz_name", "?"), WIDTHS[0], C_DIM if is_aband else C_NORM))

	# District
	row.add_child(_cell(meta.get("district", "?"), WIDTHS[1], C_NORM))

	# Biz Type
	row.add_child(_cell(meta.get("biz_type", "?"), WIDTHS[2], C_NORM))

	# Category
	row.add_child(_cell((meta.get("biz_category", "?") as String).capitalize(), WIDTHS[3], C_NORM))

	# Owner
	var owner_str: String = meta.get("owner_name", "City")
	if status == "player_owned":
		owner_str = "You"
	row.add_child(_cell(owner_str, WIDTHS[4], Color(0.80, 0.90, 1.00) if owner_str == "You" else C_NORM))

	# Status
	var status_disp: String
	var status_col:  Color
	if is_aband:
		status_disp = "Abandoned"
		status_col  = C_DIM
	elif is_op:
		status_disp = "● Operating"
		status_col  = C_OK
	else:
		status_disp = "✕ Suspended"
		status_col  = C_CRIT
	row.add_child(_cell(status_disp, WIDTHS[5], status_col))

	# Cash reserves — warn when negative or near-zero
	var cash: float = float(meta.get("cash_reserves", 0.0))
	var cash_col: Color = C_CRIT if cash < 0.0 else (C_WARN if cash < 50.0 else C_NORM)
	row.add_child(_cell("$%.0f" % cash, WIDTHS[6], cash_col))

	# Wages/day
	var wages: float = float(meta.get("wages_per_day", 0.0))
	row.add_child(_cell(("$%.0f" % wages) if wages > 0.0 else "—", WIDTHS[7], C_NORM))

	# Rent/day
	var rent: float = float(meta.get("rent_per_day", 0.0))
	row.add_child(_cell(("$%.0f" % rent) if rent > 0.0 else "—", WIDTHS[8], C_NORM))

	# Input buffer
	var ibuf: Dictionary = meta["input_buffer"] as Dictionary if meta.has("input_buffer") else {}
	row.add_child(_cell(_buf_str(ibuf), WIDTHS[9], C_NORM))

	# Output buffer
	var obuf: Dictionary = meta["output_buffer"] as Dictionary if meta.has("output_buffer") else {}
	row.add_child(_cell(_buf_str(obuf), WIDTHS[10], C_OK if not obuf.is_empty() else C_DIM))

	return pc


## Summarises a buffer dictionary as "Name×qty, …" (item names truncated to 8 chars).
func _buf_str(buf: Dictionary) -> String:
	if buf.is_empty():
		return "—"
	var parts: PackedStringArray = []
	for item_id: int in buf.keys():
		var qty: int = int(buf[item_id])
		if qty > 0:
			parts.append(ItemDB.get_item_name(item_id).left(8) + "×" + str(qty))
	return ", ".join(parts) if not parts.is_empty() else "—"


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
