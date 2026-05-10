extends CanvasLayer
class_name NPCDataView
## Full-screen NPC directory spreadsheet. Toggled by City.gd on the F key.
##
## Columns: Name | Type | District | Balance | Wage/day | Rent/day | Hunger | State | Behaviour

const HEADERS: Array = [
	"Name", "Type", "District", "Balance", "Wage/day", "Rent/day",
	"Hunger", "State", "Employer", "Home", "Behaviour",
]
const WIDTHS: Array = [170, 108, 135, 82, 80, 80, 70, 112, 145, 145, 155]

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
var _detail_panel: PanelContainer = null
var _detail_body:  VBoxContainer  = null
var _detail_title: Label          = null

# ── Filter state ─────────────────────────────────────────────────────
var _filter_search:   String = ""
var _filter_type:     int    = -1   # -1 = all, else NPC.Type value
var _filter_state:    String = ""
var _filter_district: int    = -1   # -1 = all, else district_id
var _selected_npc:    NPC    = null  # NPC currently shown in the detail panel


func _ready() -> void:
	layer   = 20
	visible = false
	EconomyManager.phase_changed.connect(_on_phase_changed_detail)


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

	# ── Filter bar ───────────────────────────────────────────────────────
	var fbar := HBoxContainer.new()
	fbar.add_theme_constant_override("separation", 8)
	outer.add_child(fbar)

	var search_edit := LineEdit.new()
	search_edit.placeholder_text    = "Search name…"
	search_edit.custom_minimum_size = Vector2(170, 0)
	search_edit.text_changed.connect(func(t: String) -> void:
		_filter_search = t.to_lower()
		_refresh()
	)
	fbar.add_child(search_edit)

	var type_lbl := Label.new()
	type_lbl.text = "Type:"
	type_lbl.add_theme_font_size_override("font_size", 12)
	type_lbl.add_theme_color_override("font_color", C_DIM)
	fbar.add_child(type_lbl)
	var type_opt := OptionButton.new()
	for s: String in ["All", "Civilian", "Tourist", "Police"]:
		type_opt.add_item(s)
	type_opt.item_selected.connect(func(idx: int) -> void:
		match idx:
			0: _filter_type = -1
			1: _filter_type = NPC.Type.CIVILIAN
			2: _filter_type = NPC.Type.TOURIST
			3: _filter_type = NPC.Type.POLICE
		_refresh()
	)
	fbar.add_child(type_opt)

	var state_lbl := Label.new()
	state_lbl.text = "State:"
	state_lbl.add_theme_font_size_override("font_size", 12)
	state_lbl.add_theme_color_override("font_color", C_DIM)
	fbar.add_child(state_lbl)
	var state_opt := OptionButton.new()
	for s: String in ["All", "OK", "Struggling", "Unemployed", "Unhoused"]:
		state_opt.add_item(s)
	state_opt.item_selected.connect(func(idx: int) -> void:
		_filter_state = "" if idx == 0 else state_opt.get_item_text(idx).to_lower()
		_refresh()
	)
	fbar.add_child(state_opt)

	var dist_lbl := Label.new()
	dist_lbl.text = "District:"
	dist_lbl.add_theme_font_size_override("font_size", 12)
	dist_lbl.add_theme_color_override("font_color", C_DIM)
	fbar.add_child(dist_lbl)
	var dist_opt := OptionButton.new()
	dist_opt.add_item("All")
	for i: int in range(_districts.size()):
		dist_opt.add_item(_districts[i]["name"])
	dist_opt.item_selected.connect(func(idx: int) -> void:
		_filter_district = idx - 1
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
		_filter_type     = -1
		_filter_state    = ""
		_filter_district = -1
		search_edit.text = ""
		type_opt.select(0)
		state_opt.select(0)
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

	# ── Scrollable body ───────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.add_child(scroll)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	# ── Detail panel (right-side overlay) ────────────────────────────────
	var dp := PanelContainer.new()
	var dp_sty := StyleBoxFlat.new()
	dp_sty.bg_color = Color(0.03, 0.05, 0.10, 0.98)
	dp_sty.border_color = Color(0.50, 1.00, 0.72, 0.6)
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
	_detail_title.add_theme_color_override("font_color", Color(0.50, 1.00, 0.72))
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

	var visible_count: int = 0
	var row_idx: int = 0
	for npc: NPC in _npcs:
		if not is_instance_valid(npc):
			continue
		# Search filter
		if _filter_search != "" and not npc.display_name.to_lower().contains(_filter_search):
			continue
		# Type filter
		if _filter_type != -1 and npc.npc_type != _filter_type:
			continue
		# District filter
		if _filter_district != -1 and npc.district_id != _filter_district:
			continue
		# State filter (civilians only)
		if _filter_state != "":
			if npc.npc_type != NPC.Type.CIVILIAN:
				continue
			var _matches: bool
			match _filter_state:
				"ok":
					_matches = not npc._is_struggling
				"struggling":
					_matches = npc._is_struggling
				"unemployed":
					_matches = npc.employer_meta.is_empty()
				"unhoused":
					_matches = npc.home_meta.is_empty()
				_:
					_matches = true
			if not _matches:
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
	var type_col: Color
	if npc.npc_type == NPC.Type.POLICE:
		type_str = "Highway Patrol" if npc.is_highway_police else "Police"
		type_col = C_DIM
	elif npc.npc_type == NPC.Type.TOURIST:
		type_str = "Tourist"
		type_col = Color(1.00, 0.82, 0.12)
	else:
		type_str = "Civilian"
		type_col = C_NORM
	row.add_child(_cell(type_str, WIDTHS[1], type_col))

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

	# Employer (idx 8)
	var emp_str: String
	var emp_col: Color
	if npc.npc_type == NPC.Type.TOURIST:
		emp_str = "$%.0f budget" % npc.tourist_budget
		emp_col = Color(1.00, 0.82, 0.12)
	elif is_civ:
		if npc.employer_meta.is_empty():
			emp_str = "Unemployed"
			emp_col = C_WARN
		else:
			emp_str = npc.employer_meta.get("biz_name", "—")
			emp_col = C_NORM
	else:
		emp_str = "—"
		emp_col = C_DIM
	row.add_child(_cell(emp_str, WIDTHS[8], emp_col))

	# Home (idx 9)
	var home_str: String
	var home_col: Color
	if is_civ:
		if npc.home_meta.is_empty():
			home_str = "Unhoused"
			home_col = C_WARN
		else:
			home_str = npc.home_meta.get("biz_name", "—")
			home_col = C_NORM
	else:
		home_str = "—"
		home_col = C_DIM
	row.add_child(_cell(home_str, WIDTHS[9], home_col))

	# Behaviour (idx 10)
	var beh_str: String = "Patrol"
	var beh_col: Color  = C_DIM
	if is_civ:
		if npc._behaviour == NPC.Behaviour.GOING_TO_SHOP and npc._shop_item >= 0:
			beh_str = "→ " + ItemDB.get_item_name(npc._shop_item)
			beh_col = C_OK
		else:
			beh_str = "Wander"
			beh_col = C_NORM
	elif npc.npc_type == NPC.Type.TOURIST:
		beh_str = "Touring"
		beh_col = Color(1.00, 0.82, 0.12)
	row.add_child(_cell(beh_str, WIDTHS[10], beh_col))

	# Click → drill-down
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pc.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var me := event as InputEventMouseButton
			if me.pressed and me.button_index == MOUSE_BUTTON_LEFT:
				_show_npc_detail(npc)
	)

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


func _show_npc_detail(npc: NPC) -> void:
	if _detail_panel == null:
		return
	_selected_npc = npc
	_detail_title.text = "◀  " + npc.display_name
	for ch: Node in _detail_body.get_children():
		_detail_body.remove_child(ch)
		ch.queue_free()

	var is_civ:     bool = npc.npc_type == NPC.Type.CIVILIAN
	var is_tourist: bool = npc.npc_type == NPC.Type.TOURIST

	var type_str: String = "Civilian"
	if npc.npc_type == NPC.Type.POLICE:
		type_str = "Highway Patrol" if npc.is_highway_police else "Police"
	elif is_tourist:
		type_str = "Tourist"

	var d_str: String = "—"
	if npc.district_id >= 0 and npc.district_id < _districts.size():
		d_str = _districts[npc.district_id]["name"]

	_detail_body.add_child(_detail_row("Type",     type_str))
	_detail_body.add_child(_detail_row("District", d_str))
	_detail_body.add_child(_detail_row("Balance",  "$%.2f" % npc.balance))

	if is_tourist:
		_detail_body.add_child(_detail_row("Budget",       "$%.2f" % npc.tourist_budget))
		_detail_body.add_child(_detail_row("Spent",        "$%.2f" % maxf(0.0, npc.tourist_budget - npc.balance)))
		_detail_body.add_child(_detail_row("Days in City", str(npc.days_in_city)))
	elif is_civ:
		_detail_body.add_child(_detail_row("Daily Wage",      "$%.2f" % npc.daily_wage))
		_detail_body.add_child(_detail_row("Daily Rent",      "$%.2f" % npc.daily_rent))
		_detail_body.add_child(_detail_row("Hunger",          "%.1f%%" % (npc.hunger * 100.0)))
		_detail_body.add_child(_detail_row("Struggling",      "Yes" if npc._is_struggling else "No"))
		_detail_body.add_child(_detail_row("Days Unemployed", str(npc.days_unemployed)))
		_detail_body.add_child(_detail_row("Days Unhoused",   str(npc.days_unhoused)))
		_detail_body.add_child(HSeparator.new())
		var emp_name: String = npc.employer_meta.get("biz_name", "") if not npc.employer_meta.is_empty() else ""
		_detail_body.add_child(_detail_row("Employer", emp_name if emp_name != "" else "Unemployed"))
		if not npc.employer_meta.is_empty():
			_detail_body.add_child(_detail_row("  Type",     npc.employer_meta.get("biz_type",     "—")))
			_detail_body.add_child(_detail_row("  District", npc.employer_meta.get("district",     "—")))
			_detail_body.add_child(_detail_row("  Cash",     "$%.0f" % float(npc.employer_meta.get("cash_reserves", 0.0))))
			_detail_body.add_child(_detail_row("  Open",     "Yes" if npc.employer_meta.get("operational", false) else "No"))
		_detail_body.add_child(HSeparator.new())
		var home_name: String = npc.home_meta.get("biz_name", "") if not npc.home_meta.is_empty() else ""
		_detail_body.add_child(_detail_row("Home", home_name if home_name != "" else "Unhoused"))
		if not npc.home_meta.is_empty():
			_detail_body.add_child(_detail_row("  Type",     npc.home_meta.get("biz_type",  "—")))
			_detail_body.add_child(_detail_row("  District", npc.home_meta.get("district",  "—")))
			_detail_body.add_child(_detail_row("  Rent/day", "$%.2f" % npc.daily_rent))
			_detail_body.add_child(_detail_row("  Tenants",  str(npc.home_meta.get("_tenant_count", 0))))

	# ── Balance sparkline ────────────────────────────────────────────────
	if npc.npc_type == NPC.Type.CIVILIAN and not npc.balance_history.is_empty():
		_detail_body.add_child(HSeparator.new())
		var spark_hdr := Label.new()
		spark_hdr.text = "Balance History (%d days)" % npc.balance_history.size()
		spark_hdr.add_theme_font_size_override("font_size", 11)
		spark_hdr.add_theme_color_override("font_color", Color(0.55, 0.75, 1.00))
		_detail_body.add_child(spark_hdr)
		var spark := _BalanceSparkline.new()
		spark._data = npc.balance_history.duplicate()
		spark.custom_minimum_size        = Vector2(0, 58)
		spark.size_flags_horizontal      = Control.SIZE_EXPAND_FILL
		_detail_body.add_child(spark)

	# ── Life log ──────────────────────────────────────────────────────────
	if npc.npc_type == NPC.Type.CIVILIAN and not npc.life_log.is_empty():
		_detail_body.add_child(HSeparator.new())
		var log_hdr := Label.new()
		log_hdr.text = "Life Log  (newest first)"
		log_hdr.add_theme_font_size_override("font_size", 11)
		log_hdr.add_theme_color_override("font_color", Color(0.55, 0.75, 1.00))
		_detail_body.add_child(log_hdr)
		var log_lbl := RichTextLabel.new()
		log_lbl.bbcode_enabled    = false
		log_lbl.fit_content       = true
		log_lbl.scroll_active     = false
		log_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		log_lbl.add_theme_font_size_override("normal_font_size", 10)
		log_lbl.add_theme_color_override("default_color", C_NORM)
		var shown: Array = npc.life_log.slice(maxi(0, npc.life_log.size() - 40))
		shown.reverse()
		log_lbl.text = "\n".join(shown)
		_detail_body.add_child(log_lbl)

	_detail_panel.visible = true


func _detail_row(key: String, value: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var k := Label.new()
	k.text = key
	k.custom_minimum_size       = Vector2(140, 18)
	k.size_flags_horizontal     = Control.SIZE_SHRINK_BEGIN
	k.add_theme_font_size_override("font_size", 11)
	k.add_theme_color_override("font_color", Color(0.55, 0.75, 1.00))
	hb.add_child(k)
	var v := Label.new()
	v.text = value
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode         = TextServer.AUTOWRAP_WORD
	v.add_theme_font_size_override("font_size", 11)
	v.add_theme_color_override("font_color", C_NORM)
	hb.add_child(v)
	return hb


## Refresh detail panel automatically when the economy ticks.
func _on_phase_changed_detail(_phase: int) -> void:
	if _detail_panel != null and _detail_panel.visible \
			and _selected_npc != null and is_instance_valid(_selected_npc):
		_show_npc_detail(_selected_npc)


## Mini line-graph drawn inline in the detail panel.
class _BalanceSparkline extends Control:
	var _data: Array = []

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if _data.size() < 2 or w == 0 or h == 0:
			return
		# Background
		draw_rect(Rect2(0.0, 0.0, w, h), Color(0.06, 0.08, 0.14, 0.85))
		# Find range
		var lo: float = float(_data.min())
		var hi: float = float(_data.max())
		if hi <= lo:
			hi = lo + 1.0
		# Draw zero-line if negative values present
		if lo < 0.0:
			var zy := h - (-lo / (hi - lo)) * h
			draw_line(Vector2(0.0, zy), Vector2(w, zy), Color(0.8, 0.3, 0.3, 0.4), 1.0)
		# Draw sparkline
		var n := _data.size()
		for i: int in range(1, n):
			var x0 := float(i - 1) / float(n - 1) * w
			var x1 := float(i)     / float(n - 1) * w
			var y0 := h - (float(_data[i - 1]) - lo) / (hi - lo) * h
			var y1 := h - (float(_data[i])     - lo) / (hi - lo) * h
			draw_line(Vector2(x0, y0), Vector2(x1, y1), Color(0.35, 0.90, 1.00), 1.5)
		# Labels: min, max, latest
		var fnt := ThemeDB.fallback_font
		draw_string(fnt, Vector2(2.0, 11.0), "$%.0f" % hi,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.75, 1.00, 0.70))
		draw_string(fnt, Vector2(2.0, h - 2.0), "$%.0f" % lo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.75, 1.00, 0.70))
		var last := float(_data.back())
		draw_string(fnt, Vector2(w - 60.0, 11.0), "now $%.0f" % last,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.90, 1.00))
