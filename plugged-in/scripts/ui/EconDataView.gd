extends CanvasLayer
class_name EconDataView
## Full-screen economic data spreadsheet. Toggled by City.gd on the G key.
##
## Columns: Biz Name | District | Type | Category | Owner | Status |
##          Cash | Wages/day | Rent/day | In Buffer | Out Buffer

const HEADERS: Array = [
	"Biz Name", "District", "Type", "Category",
	"Owner", "Status", "Cash", "Wages/day", "Rent/day",
	"Staff", "Tenants", "In Buffer", "Out Buffer",
]
const WIDTHS: Array = [155, 112, 138, 108, 138, 92, 82, 78, 78, 65, 65, 128, 128]

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
var _detail_panel: PanelContainer = null
var _detail_body:  VBoxContainer  = null
var _detail_title: Label          = null

# ── Filter state ─────────────────────────────────────────────────────
var _filter_search:   String = ""
var _filter_status:   String = ""
var _filter_category: String = ""
var _filter_district: String = ""


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

	# ── Filter bar ───────────────────────────────────────────────────────
	var fbar := HBoxContainer.new()
	fbar.add_theme_constant_override("separation", 8)
	fbar.add_theme_constant_override("margin_top", 2)
	outer.add_child(fbar)

	var search_edit := LineEdit.new()
	search_edit.placeholder_text    = "Search name…"
	search_edit.custom_minimum_size = Vector2(170, 0)
	search_edit.text_changed.connect(func(t: String) -> void:
		_filter_search = t.to_lower()
		_refresh()
	)
	fbar.add_child(search_edit)

	var status_lbl := Label.new()
	status_lbl.text = "Status:"
	status_lbl.add_theme_font_size_override("font_size", 12)
	status_lbl.add_theme_color_override("font_color", C_DIM)
	fbar.add_child(status_lbl)
	var status_opt := OptionButton.new()
	for s: String in ["All", "Operating", "Suspended", "Abandoned"]:
		status_opt.add_item(s)
	status_opt.item_selected.connect(func(idx: int) -> void:
		_filter_status = "" if idx == 0 else status_opt.get_item_text(idx).to_lower()
		_refresh()
	)
	fbar.add_child(status_opt)

	var cat_lbl := Label.new()
	cat_lbl.text = "Category:"
	cat_lbl.add_theme_font_size_override("font_size", 12)
	cat_lbl.add_theme_color_override("font_color", C_DIM)
	fbar.add_child(cat_lbl)
	var cat_opt := OptionButton.new()
	cat_opt.add_item("All")
	var _seen_cats: Array = []
	for meta: Dictionary in _buildings:
		var cat: String = meta.get("biz_category", "")
		if cat != "" and cat not in _seen_cats:
			_seen_cats.append(cat)
	_seen_cats.sort()
	for cat: String in _seen_cats:
		cat_opt.add_item(cat.capitalize())
	cat_opt.item_selected.connect(func(idx: int) -> void:
		_filter_category = "" if idx == 0 else cat_opt.get_item_text(idx).to_lower()
		_refresh()
	)
	fbar.add_child(cat_opt)

	var dist_lbl := Label.new()
	dist_lbl.text = "District:"
	dist_lbl.add_theme_font_size_override("font_size", 12)
	dist_lbl.add_theme_color_override("font_color", C_DIM)
	fbar.add_child(dist_lbl)
	var dist_opt := OptionButton.new()
	dist_opt.add_item("All")
	var _seen_dists: Array = []
	for meta: Dictionary in _buildings:
		var d: String = meta.get("district", "")
		if d != "" and d not in _seen_dists:
			_seen_dists.append(d)
	_seen_dists.sort()
	for d: String in _seen_dists:
		dist_opt.add_item(d)
	dist_opt.item_selected.connect(func(idx: int) -> void:
		_filter_district = "" if idx == 0 else dist_opt.get_item_text(idx)
		_refresh()
	)
	fbar.add_child(dist_opt)

	var fspacer := Control.new()
	fspacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fbar.add_child(fspacer)
	var clear_btn := Button.new()
	clear_btn.text = "Clear Filters"
	clear_btn.pressed.connect(func() -> void:
		_filter_search   = ""
		_filter_status   = ""
		_filter_category = ""
		_filter_district = ""
		search_edit.text = ""
		status_opt.select(0)
		cat_opt.select(0)
		dist_opt.select(0)
		_refresh()
	)
	fbar.add_child(clear_btn)

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

	# ── Detail panel (right-side overlay) ────────────────────────────────
	var dp := PanelContainer.new()
	var dp_sty := StyleBoxFlat.new()
	dp_sty.bg_color = Color(0.04, 0.06, 0.10, 0.98)
	dp_sty.border_color = Color(1.00, 0.85, 0.38, 0.6)
	dp_sty.border_width_left = 2
	dp_sty.set_corner_radius_all(4)
	dp.add_theme_stylebox_override("panel", dp_sty)
	dp.mouse_filter = Control.MOUSE_FILTER_STOP
	dp.anchor_left   = 1.0
	dp.anchor_right  = 1.0
	dp.anchor_top    = 0.0
	dp.anchor_bottom = 1.0
	dp.offset_left   = -380.0
	dp.offset_right  = -18.0
	dp.offset_top    = 18.0
	dp.offset_bottom = -18.0
	dp.visible = false
	add_child(dp)
	_detail_panel = dp

	var dmc := MarginContainer.new()
	dmc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dmc.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	dmc.add_theme_constant_override("margin_top",    10)
	dmc.add_theme_constant_override("margin_bottom", 10)
	dmc.add_theme_constant_override("margin_left",   12)
	dmc.add_theme_constant_override("margin_right",  12)
	dp.add_child(dmc)

	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	dmc.add_child(dv)

	var dtr := HBoxContainer.new()
	dv.add_child(dtr)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 13)
	_detail_title.add_theme_color_override("font_color", Color(1.00, 0.85, 0.38))
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dtr.add_child(_detail_title)

	var dcl := Button.new()
	dcl.text = "  ✕  "
	dcl.pressed.connect(func() -> void: _detail_panel.visible = false)
	dtr.add_child(dcl)

	dv.add_child(HSeparator.new())

	var ds := ScrollContainer.new()
	ds.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ds.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dv.add_child(ds)

	_detail_body = VBoxContainer.new()
	_detail_body.add_theme_constant_override("separation", 3)
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.add_child(_detail_body)


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
		# Search filter
		if _filter_search != "" and not (meta.get("biz_name", "") as String).to_lower().contains(_filter_search):
			continue
		# Status filter
		if _filter_status != "":
			var _st: String = meta.get("status", "occupied")
			var _st_key: String
			if _st == "abandoned":
				_st_key = "abandoned"
			elif meta.get("operational", false):
				_st_key = "operating"
			else:
				_st_key = "suspended"
			if _st_key != _filter_status:
				continue
		# Category filter
		if _filter_category != "" and (meta.get("biz_category", "") as String).to_lower() != _filter_category:
			continue
		# District filter
		if _filter_district != "" and meta.get("district", "") != _filter_district:
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

	# Staff (idx 9)
	var staff_str: String = str(int(meta.get("_employee_count", 0))) if meta.has("_employee_count") else "—"
	row.add_child(_cell(staff_str, WIDTHS[9], C_NORM))

	# Tenants (idx 10)
	var tenant_str: String = str(int(meta.get("_tenant_count", 0))) if meta.has("_tenant_count") else "—"
	row.add_child(_cell(tenant_str, WIDTHS[10], C_NORM))

	# Input buffer (idx 11)
	var ibuf: Dictionary = meta["input_buffer"] as Dictionary if meta.has("input_buffer") else {}
	row.add_child(_cell(_buf_str(ibuf), WIDTHS[11], C_NORM))

	# Output buffer (idx 12)
	var obuf: Dictionary = meta["output_buffer"] as Dictionary if meta.has("output_buffer") else {}
	row.add_child(_cell(_buf_str(obuf), WIDTHS[12], C_OK if not obuf.is_empty() else C_DIM))

	# Click → drill-down
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pc.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var me := event as InputEventMouseButton
			if me.pressed and me.button_index == MOUSE_BUTTON_LEFT:
				_show_biz_detail(meta)
	)

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


func _show_biz_detail(meta: Dictionary) -> void:
	if _detail_panel == null:
		return
	_detail_title.text = "◀  " + meta.get("biz_name", "Building")
	for ch: Node in _detail_body.get_children():
		_detail_body.remove_child(ch)
		ch.queue_free()

	# ── Core fields ─────────────────────────────────────────────────
	var curated: Array = [
		["Biz Name",   meta.get("biz_name",    "—")],
		["Type",       meta.get("biz_type",    "—")],
		["Category",   (meta.get("biz_category", "—") as String).capitalize()],
		["District",   meta.get("district",    "—")],
		["Owner",      meta.get("owner_name",  "City")],
		["Status",     meta.get("status",      "—")],
		["Operational","Yes" if meta.get("operational", false) else "No"],
		["Cash",       "$%.2f" % float(meta.get("cash_reserves", 0.0))],
		["Wages/day",  "$%.2f" % float(meta.get("wages_per_day", 0.0))],
		["Rent/day",   "$%.2f" % float(meta.get("rent_per_day",  0.0))],
		["Price",      "$%.0f" % float(meta.get("price",         0.0))],
		["Sell Price", "$%.0f" % float(meta.get("sell_price",    0.0))],
		["Staff",      str(int(meta.get("_employee_count", 0))) if meta.has("_employee_count") else "—"],
		["Tenants",    str(int(meta.get("_tenant_count",   0))) if meta.has("_tenant_count")   else "—"],
	]
	for kv: Array in curated:
		_detail_body.add_child(_detail_row(kv[0], kv[1]))

	# ── Inventory buffers ─────────────────────────────────────────
	var ibuf: Dictionary = meta.get("input_buffer",  {})
	var obuf: Dictionary = meta.get("output_buffer", {})
	if not ibuf.is_empty() or not obuf.is_empty():
		_detail_body.add_child(HSeparator.new())
	if not ibuf.is_empty():
		_detail_body.add_child(_detail_row("Input Buffer",  _buf_str(ibuf)))
	if not obuf.is_empty():
		_detail_body.add_child(_detail_row("Output Buffer", _buf_str(obuf)))

	# ── Any extra keys not already shown ───────────────────────────
	var shown: Array = ["biz_name","biz_type","biz_category","district","owner_name",
		"status","operational","cash_reserves","wages_per_day","rent_per_day",
		"price","sell_price","_employee_count","_tenant_count",
		"input_buffer","output_buffer","_world_pos"]
	var extras: Array = []
	for key: String in meta.keys():
		if key in shown:
			continue
		var val: Variant = meta[key]
		if val is Dictionary or val is Array or val is Vector2:
			continue
		extras.append([key, str(val)])
	if not extras.is_empty():
		_detail_body.add_child(HSeparator.new())
		for kv: Array in extras:
			_detail_body.add_child(_detail_row(kv[0], kv[1]))

	_detail_panel.visible = true


func _detail_row(key: String, value: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var k := Label.new()
	k.text = key
	k.custom_minimum_size       = Vector2(140, 18)
	k.size_flags_horizontal     = Control.SIZE_SHRINK_BEGIN
	k.add_theme_font_size_override("font_size", 11)
	k.add_theme_color_override("font_color", Color(1.00, 0.85, 0.38))
	hb.add_child(k)
	var v := Label.new()
	v.text = value
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode         = TextServer.AUTOWRAP_WORD
	v.add_theme_font_size_override("font_size", 11)
	v.add_theme_color_override("font_color", C_NORM)
	hb.add_child(v)
	return hb
