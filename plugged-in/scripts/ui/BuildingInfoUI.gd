extends CanvasLayer

const BTC_RATE := 30000.0   # $ per BTC (in-game)
const ATM_FEE  := 0.01      # 1%
# Bulk buy discount tiers for designated storefronts [x1, x5, x10]
const BULK_QTYS:      Array = [1,    5,    10  ]
const BULK_DISCOUNTS: Array = [0.0,  0.08, 0.15]  # 0% / 8% / 15% off unit price

# =============================================================================
#  BuildingInfoUI — shows property details when a building is clicked.
#  Instantiated and added as a child of City by City.gd.
# =============================================================================

var _panel:        PanelContainer
var _name_lbl:     Label
var _addr_lbl:     Label
var _type_lbl:     Label
var _status_lbl:   Label
var _price_lbl:    Label
var _income_lbl:   Label
var _district_lbl: Label
var _buy_btn:        Button
var _squat_btn:      Button
var _manage_btn:     Button
var _shop_section:         VBoxContainer = null
var _shop_items_container: VBoxContainer = null  # cleared and rebuilt each show_building call
var _atm_section:    VBoxContainer = null
var _atm_result_lbl: Label         = null
var _atm_btns:       Array         = []
signal owner_inspect_requested(owner_id: int)
var _econ_section:   VBoxContainer = null
var _owner_lbl:      Label         = null
var _owner_btn:      Button        = null
var _category_lbl:   Label         = null
var _wages_lbl:      Label         = null
var _rent_lbl:       Label         = null
var _cash_lbl:       Label         = null
var _current_meta:   Dictionary
var _player:         Node = null


func _ready() -> void:
	layer   = 12
	visible = false
	_build_ui()
	EconomyManager.phase_changed.connect(_on_econ_phase_changed)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(310, 0)
	# Anchor to top-right of viewport
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-330, 16)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# ── Header row ────────────────────────────────────────────────────────
	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)

	var title := Label.new()
	title.text = "  PROPERTY DETAILS"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.20))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)

	var close := Button.new()
	close.text = "  ✕  "
	close.pressed.connect(func() -> void: visible = false)
	hdr.add_child(close)

	vbox.add_child(HSeparator.new())

	# ── Info labels ───────────────────────────────────────────────────────
	_name_lbl     = _row(vbox, Color(1.0, 1.0, 1.0), 12)
	_addr_lbl     = _row(vbox, Color(0.80, 0.80, 0.80), 11)
	_district_lbl = _row(vbox, Color(0.70, 0.85, 1.00), 11)
	vbox.add_child(HSeparator.new())
	_type_lbl     = _row(vbox, Color(0.90, 0.75, 0.50), 11)
	_status_lbl   = _row(vbox, Color(0.50, 1.00, 0.50), 11)
	vbox.add_child(HSeparator.new())
	_price_lbl    = _row(vbox, Color(0.50, 1.00, 0.60), 12)
	_income_lbl   = _row(vbox, Color(0.50, 1.00, 0.60), 12)

	# ── Economic details section ─────────────────────────────────
	_econ_section = VBoxContainer.new()
	_econ_section.add_theme_constant_override("separation", 3)
	vbox.add_child(_econ_section)
	_econ_section.add_child(HSeparator.new())
	var _owner_row := HBoxContainer.new()
	_econ_section.add_child(_owner_row)
	_owner_lbl = Label.new()
	_owner_lbl.add_theme_font_size_override("font_size", 11)
	_owner_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 1.00))
	_owner_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owner_row.add_child(_owner_lbl)
	_owner_btn = Button.new()
	_owner_btn.text = "ℹ"
	_owner_btn.custom_minimum_size = Vector2(28, 0)
	_owner_btn.flat    = true
	_owner_btn.visible = false
	_owner_btn.pressed.connect(_on_owner_info_pressed)
	_owner_row.add_child(_owner_btn)
	_category_lbl = _row(_econ_section, Color(0.70, 0.85, 0.70), 11)
	_wages_lbl    = _row(_econ_section, Color(1.00, 0.75, 0.50), 11)
	_rent_lbl     = _row(_econ_section, Color(1.00, 0.65, 0.65), 11)
	_cash_lbl     = _row(_econ_section, Color(0.60, 1.00, 0.70), 11)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	_squat_btn = Button.new()
	_squat_btn.text                  = "  🏖  Squat (Free)  "
	_squat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_squat_btn.visible               = false
	_squat_btn.pressed.connect(_on_squat_pressed)
	btn_row.add_child(_squat_btn)

	_buy_btn = Button.new()
	_buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_btn.visible               = false
	_buy_btn.pressed.connect(_on_buy_pressed)
	btn_row.add_child(_buy_btn)

	_manage_btn = Button.new()
	_manage_btn.text                  = "  📌  Manage Stock  "
	_manage_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_manage_btn.visible               = false
	_manage_btn.pressed.connect(_on_manage_stock_pressed)
	vbox.add_child(_manage_btn)

	# small padding at bottom
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(pad)

	# ── Available goods section — dynamically populated from output_buffer ─────
	_shop_section = VBoxContainer.new()
	_shop_section.add_theme_constant_override("separation", 4)
	_shop_section.visible = false
	vbox.add_child(_shop_section)

	_shop_section.add_child(HSeparator.new())

	var shop_hdr := Label.new()
	shop_hdr.text = "  AVAILABLE GOODS"
	shop_hdr.add_theme_font_size_override("font_size", 11)
	shop_hdr.add_theme_color_override("font_color", Color(0.45, 1.0, 0.72))
	_shop_section.add_child(shop_hdr)

	_shop_items_container = VBoxContainer.new()
	_shop_items_container.add_theme_constant_override("separation", 3)
	_shop_section.add_child(_shop_items_container)

	# ── ATM section (hidden by default) ────────────────────────────────────
	_atm_section = VBoxContainer.new()
	_atm_section.add_theme_constant_override("separation", 4)
	_atm_section.visible = false
	vbox.add_child(_atm_section)

	_atm_section.add_child(HSeparator.new())

	var atm_hdr := Label.new()
	atm_hdr.text = "  \u20bf ATM \u2014 1% fee  (1 BTC \u2248 $" + str(int(BTC_RATE)) + ")"
	atm_hdr.add_theme_font_size_override("font_size", 11)
	atm_hdr.add_theme_color_override("font_color", Color(1.0, 0.82, 0.15))
	_atm_section.add_child(atm_hdr)

	var atm_row := HBoxContainer.new()
	atm_row.add_theme_constant_override("separation", 4)
	_atm_section.add_child(atm_row)
	for amt: int in [10, 50, 100, 500]:
		var b := Button.new()
		b.text = "$" + str(amt)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_atm_convert_pressed.bind(float(amt)))
		atm_row.add_child(b)
		_atm_btns.append(b)

	_atm_result_lbl = Label.new()
	_atm_result_lbl.add_theme_font_size_override("font_size", 11)
	_atm_result_lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	_atm_section.add_child(_atm_result_lbl)


func _row(parent: Control, col: Color, size: int) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)
	parent.add_child(lbl)
	return lbl


func show_building(meta: Dictionary) -> void:
	visible = true
	_current_meta = meta

	_name_lbl.text     = "  " + meta.get("biz_name", "Unknown Building")
	_addr_lbl.text     = "  " + meta.get("address", "")
	_district_lbl.text = "  District: " + meta.get("district", "")

	var prop: String = meta.get("property_type", "Property")
	var btype: String = meta.get("biz_type", "Building")
	_type_lbl.text = "  " + prop + "  ·  " + btype

	var status: String = meta.get("status", "occupied")
	match status:
		"abandoned":
			_status_lbl.text = "  ⚠  ABANDONED"
			_status_lbl.add_theme_color_override("font_color", Color(0.90, 0.55, 0.20))
		"for_sale":
			_status_lbl.text = "  🏷  FOR SALE"
			_status_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 1.00))
		"player_owned":
			_status_lbl.text = "  🏠  OWNED BY YOU"
			_status_lbl.add_theme_color_override("font_color", Color(1.00, 0.85, 0.20))
		"squatting":
			_status_lbl.text = "  ⛺  SQUATTING HERE"
			_status_lbl.add_theme_color_override("font_color", Color(0.60, 1.00, 0.70))
		_:
			_status_lbl.text = "  ✔  Occupied"
			_status_lbl.add_theme_color_override("font_color", Color(0.40, 1.00, 0.50))

	var price: int = meta.get("price", 0)
	_price_lbl.text = "  Market Value:  $" + _fmt(price)

	if status == "abandoned" or status == "squatting":
		_income_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		if status == "squatting":
			_income_lbl.text = "  Selling from your inventory"
		else:
			_income_lbl.text = "  Daily Income:  —"
	else:
		var recipe: Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var out_items: Dictionary = recipe.get("outputs", {}) as Dictionary
		if not out_items.is_empty():
			var rev: int = 0
			for iid: int in out_items.keys():
				rev += int(out_items[iid]) * ItemDB.get_base_price(iid)
			_income_lbl.text = "  Est. Revenue:  $" + _fmt(rev) + " / cycle"
			_income_lbl.add_theme_color_override("font_color", Color(0.50, 1.00, 0.60))
		else:
			var rent: float = float(meta.get("rent_per_day", 0.0))
			if rent > 0.0:
				_income_lbl.text = "  Rent income:  $" + _fmt(int(rent)) + " / day"
				_income_lbl.add_theme_color_override("font_color", Color(0.50, 1.00, 0.60))
			else:
				_income_lbl.text = "  Daily Revenue:  —"
				_income_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))

	# ── Economic details ─────────────────────────────────────────
	if _econ_section != null:
		var owner_name: String = meta.get("owner_name", "City")
		if meta.get("status", "") == "player_owned":
			owner_name = "You"
		_owner_lbl.text    = "  Owner:  " + owner_name
		_owner_btn.visible = int(_current_meta.get("owner_id", -1)) >= 0
		var cat: String    = (meta.get("biz_category", meta.get("property_type", "commercial")) as String).capitalize()
		_category_lbl.text = "  Category:  " + cat
		var wages: float   = float(meta.get("wages_per_day", 0.0))
		_wages_lbl.text    = ("  Wages/day:  $" + _fmt(int(wages))) if wages > 0.0 else "  Wages/day:  —"
		var rent: float    = float(meta.get("rent_per_day", 0.0))
		_rent_lbl.text     = ("  Rent/day:  $"  + _fmt(int(rent)))  if rent  > 0.0 else "  Rent/day:  —"
		var reserves: float = float(meta.get("cash_reserves", 0.0))
		var is_op: bool     = meta.get("operational", true)
		_cash_lbl.text = "  Cash reserves:  $" + _fmt(int(reserves))
		_cash_lbl.add_theme_color_override("font_color",
			Color(0.60, 1.00, 0.70) if is_op else Color(1.00, 0.40, 0.40))

	# Action buttons
	_manage_btn.visible = false
	if status == "player_owned" or _player == null:
		_squat_btn.visible = false
		_buy_btn.visible   = false
		_manage_btn.visible = _current_meta.has("_employee")
	elif status == "squatting":
		_squat_btn.visible  = false
		_manage_btn.visible = true
		var can_afford: bool = _player.wallet.get_balance(Wallet.Currency.CASH) >= float(price)
		_buy_btn.text     = "  🏠  Legitimise — Buy $" + _fmt(price) + "  "
		_buy_btn.disabled  = not can_afford
		_buy_btn.modulate  = Color(1.0, 1.0, 1.0, 1.0) if can_afford else Color(0.5, 0.5, 0.5, 1.0)
		_buy_btn.visible   = true
	elif status == "abandoned":
		var free_count: int = _player.available_employees().size()
		_squat_btn.visible  = true
		_squat_btn.disabled = free_count == 0
		_squat_btn.modulate = Color(1.0, 1.0, 1.0, 1.0) if free_count > 0 else Color(0.5, 0.5, 0.5, 1.0)
		_squat_btn.text     = "  ⛺  Squat (Free)  " if free_count > 0 else "  ⛺  Squat — No free employees  "
		var can_afford: bool = _player.wallet.get_balance(Wallet.Currency.CASH) >= float(price)
		_buy_btn.text     = "  🏠  Buy $" + _fmt(price) + "  "
		_buy_btn.disabled  = not can_afford
		_buy_btn.modulate  = Color(1.0, 1.0, 1.0, 1.0) if can_afford else Color(0.5, 0.5, 0.5, 1.0)
		_buy_btn.visible   = true
	else:
		_squat_btn.visible = false
		var can_afford: bool = _player.wallet.get_balance(Wallet.Currency.CASH) >= float(price)
		_buy_btn.text     = "  🏠  Buy $" + _fmt(price) + "  "
		_buy_btn.disabled  = not can_afford
		_buy_btn.modulate  = Color(1.0, 1.0, 1.0, 1.0) if can_afford else Color(0.5, 0.5, 0.5, 1.0)
		_buy_btn.visible   = true

	# ── Available goods section ─────────────────────────────────────────────────
	# Shown for any non-residential building with goods in its output_buffer.
	# Player-owned shops use the Manage Stock / employee flow instead.
	if _shop_section != null:
		if _player != null and status != "abandoned" and status != "player_owned" \
				and meta.get("property_type", "") != "Residential":
			var obuf: Dictionary = meta.get("output_buffer", {}) as Dictionary
			var available: Dictionary = {}
			for iid: int in obuf.keys():
				if int(obuf.get(iid, 0)) > 0:
					available[iid] = int(obuf[iid])
			if not available.is_empty():
				_shop_section.visible = true
				for child: Node in _shop_items_container.get_children():
					child.queue_free()
				var cash:       float = _player.wallet.get_balance(Wallet.Currency.CASH)
				var sf_item_id: int   = int(meta.get("sells_item_id", -1))
				var sf_price:   int   = int(meta.get("sell_price",   0))
				for iid: int in available.keys():
					var qty_avail:  int    = available[iid]
					var unit_price: int = sf_price \
							if (sf_item_id == iid and sf_price > 0) \
							else ItemDB.get_base_price(iid)
					var info_row := HBoxContainer.new()
					_shop_items_container.add_child(info_row)
					var name_lbl := Label.new()
					name_lbl.text = "  " + ItemDB.get_item_name(iid) + "  —  $" + str(unit_price)
					name_lbl.add_theme_font_size_override("font_size", 11)
					name_lbl.add_theme_color_override("font_color", Color(0.90, 0.90, 0.90))
					name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					info_row.add_child(name_lbl)
					var stock_lbl := Label.new()
					stock_lbl.text = str(qty_avail) + " left  "
					stock_lbl.add_theme_font_size_override("font_size", 10)
					stock_lbl.add_theme_color_override("font_color",
							Color(0.50, 1.00, 0.60) if qty_avail > 3 else Color(1.00, 0.75, 0.30))
					info_row.add_child(stock_lbl)
					# Storefronts get bulk tiers for their primary item; all others get ×1 only.
					var tiers: Array = BULK_QTYS if sf_item_id == iid else [1]
					var btn_row := HBoxContainer.new()
					btn_row.add_theme_constant_override("separation", 3)
					_shop_items_container.add_child(btn_row)
					for tier_qty: int in tiers:
						var disc: float = BULK_DISCOUNTS[BULK_QTYS.find(tier_qty)] \
											if sf_item_id == iid else 0.0
						var tier_unit:  int = int(ceil(float(unit_price) * (1.0 - disc)))
						var tier_total: int = tier_unit * tier_qty
						var btn := Button.new()
						btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						btn.text = ("×%d  $%d (-%d%%)" % [tier_qty, tier_total, int(disc * 100)]) \
									if disc > 0.0 else ("×%d  $%d" % [tier_qty, tier_total])
						btn.disabled = cash < float(tier_total) or qty_avail < tier_qty
						btn.pressed.connect(_on_buy_output_item.bind(iid, tier_qty, tier_unit))
						btn_row.add_child(btn)
			else:
				_shop_section.visible = false
		else:
			_shop_section.visible = false

	# ── ATM section ───────────────────────────────────────────────────
	if _atm_section != null:
		if meta.has("atm") and _player != null:
			_atm_section.visible = true
			_atm_result_lbl.text = ""
			var atm_amts: Array = [10.0, 50.0, 100.0, 500.0]
			for j: int in range(_atm_btns.size()):
				_atm_btns[j].disabled = _player.wallet.get_balance(Wallet.Currency.CASH) < atm_amts[j]
		else:
			_atm_section.visible = false


func set_player(p: Node) -> void:
	_player = p


func _on_squat_pressed() -> void:
	if _current_meta.is_empty() or _player == null:
		return
	var free_emps: Array = _player.available_employees()
	if free_emps.is_empty():
		return
	var emp: Employee = free_emps[0] as Employee
	emp.assign_to_building(_current_meta.get("_world_pos", Vector2.ZERO))
	_current_meta["status"]    = "squatting"
	_current_meta["_employee"] = emp
	show_building(_current_meta)


func _on_manage_stock_pressed() -> void:
	if _current_meta.is_empty() or _player == null:
		return
	var emp: Variant = _current_meta.get("_employee", null)
	if emp == null or not is_instance_valid(emp as Object):
		return
	var emp_obj := emp as Employee
	if emp_obj == null:
		return
	var emp_inv: Object = emp_obj.inventory
	if emp_inv == null:
		return
	visible = false
	_player.open_transfer(emp_inv, emp_obj, emp_obj.display_name + " — " + _current_meta.get("biz_name", "Shop"))


func _on_buy_output_item(item_id: int, qty: int, unit_price: int) -> void:
	if _player == null or _current_meta.is_empty():
		return
	var total: float = float(unit_price * qty)
	var obuf:  Dictionary = _current_meta.get("output_buffer", {}) as Dictionary
	var stock: int        = int(obuf.get(item_id, 0))
	if stock < qty:
		return
	if not _player.wallet.remove(Wallet.Currency.CASH, total):
		return
	if stock - qty <= 0:
		obuf.erase(item_id)
	else:
		obuf[item_id] = stock - qty
	_current_meta["cash_reserves"] = float(_current_meta.get("cash_reserves", 0.0)) + total
	_player.inventory.add(item_id, qty)
	show_building(_current_meta)


func _on_atm_convert_pressed(cash_amount: float) -> void:
	if _player == null:
		return
	if not _player.wallet.remove(Wallet.Currency.CASH, cash_amount):
		_atm_result_lbl.text = "  \u2717  Insufficient cash"
		_atm_result_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		return
	var received: float = (cash_amount * (1.0 - ATM_FEE)) / BTC_RATE
	_player.wallet.add(Wallet.Currency.BITCOIN, received)
	_atm_result_lbl.text = "  \u2714  Received \u20bf%.8f" % received
	_atm_result_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	show_building(_current_meta)


func _on_buy_pressed() -> void:
	if _current_meta.is_empty() or _player == null:
		return
	var price: int = _current_meta.get("price", 0)
	if not _player.wallet.remove(Wallet.Currency.CASH, float(price)):
		return
	_claim_building()


func _claim_building() -> void:
	_current_meta["status"]     = "player_owned"
	_current_meta["owner_name"] = "Player"
	# Restore income if it was zeroed by abandonment
	if _current_meta.has("_orig_income"):
		_current_meta["income"] = _current_meta["_orig_income"]
	# Restore the building's original district colour
	var base_col: Color   = _current_meta.get("_base_color", Color(0.5, 0.5, 0.5))
	var vis:      Variant = _current_meta.get("_vis",     null)
	var roof:     Variant = _current_meta.get("_roof",    null)
	var overlay:  Variant = _current_meta.get("_overlay", null)
	if vis  != null: (vis  as Polygon2D).color = base_col
	if roof != null: (roof as Polygon2D).color = Color(base_col.r * 0.70, base_col.g * 0.70, base_col.b * 0.70)
	if overlay != null:
		(overlay as Polygon2D).queue_free()
		_current_meta.erase("_overlay")
	show_building(_current_meta)


func _on_econ_phase_changed(_phase: int) -> void:
	if visible and not _current_meta.is_empty():
		show_building(_current_meta)


func _on_owner_info_pressed() -> void:
	var oid: int = int(_current_meta.get("owner_id", -1))
	if oid >= 0:
		owner_inspect_requested.emit(oid)


# Formats an integer with comma separators.
func _fmt(n: int) -> String:
	var s      := str(n)
	var result := ""
	var count  := 0
	for i: int in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
