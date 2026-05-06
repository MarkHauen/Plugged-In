extends CanvasLayer

# =============================================================================
#  TransferUI — side-by-side inventory transfer between player and a shop.
#  Open via Player.open_transfer(emp_inv, shop_title).
# =============================================================================

const ROW_COLOR_A  := Color(0.15, 0.15, 0.18, 1.0)
const ROW_COLOR_B  := Color(0.20, 0.20, 0.24, 1.0)
const HEADER_COLOR := Color(0.10, 0.10, 0.13, 1.0)

var _player_inv:     Object = null   # Inventory
var _shop_inv:       Object = null   # Inventory
var _wallet:         Wallet = null
var _shop_title:     String = ""

var _shop_emp:            Object = null   # Employee reference (for cash)
var _panel:               PanelContainer
var _title_lbl:           Label
var _shop_hdr_lbl:        Label
var _left_list:           VBoxContainer
var _right_list:          VBoxContainer
var _player_cash_lbl:     Label
var _shop_cash_lbl:       Label
var _cash_to_shop_btns:   Array = []
var _cash_from_shop_btns: Array = []


func _ready() -> void:
	layer = 11
	_build_ui()
	hide()


# ── Public ────────────────────────────────────────────────────────────────────

func open(player_inv: Object, shop_inv: Object, wallet: Wallet, shop_emp: Object, shop_title: String) -> void:
	_disconnect_all()
	_player_inv = player_inv
	_shop_inv   = shop_inv
	_wallet     = wallet
	_shop_emp   = shop_emp
	_shop_title = shop_title
	if _player_inv != null and not _player_inv.changed.is_connected(_on_inv_changed):
		_player_inv.changed.connect(_on_inv_changed)
	if _shop_inv != null and not _shop_inv.changed.is_connected(_on_inv_changed):
		_shop_inv.changed.connect(_on_inv_changed)
	if _wallet != null and not _wallet.changed.is_connected(_refresh_cash):
		_wallet.changed.connect(_refresh_cash)
	_refresh()
	show()


func close() -> void:
	_disconnect_all()
	hide()


# ── Internal ──────────────────────────────────────────────────────────────────

func _disconnect_all() -> void:
	if _player_inv != null and _player_inv.changed.is_connected(_on_inv_changed):
		_player_inv.changed.disconnect(_on_inv_changed)
	if _shop_inv != null and _shop_inv.changed.is_connected(_on_inv_changed):
		_shop_inv.changed.disconnect(_on_inv_changed)
	if _wallet != null and _wallet.changed.is_connected(_refresh_cash):
		_wallet.changed.disconnect(_refresh_cash)


func _on_inv_changed() -> void:
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(880.0, 500.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-440.0, -250.0)
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color         = Color(0.11, 0.12, 0.16, 0.97)
	style.border_color     = Color(0.35, 0.80, 0.50, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 0)
	_panel.add_child(root_vbox)

	# ── Title bar ──────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	title_row.custom_minimum_size.y = 40.0
	title_row.add_theme_constant_override("separation", 0)

	var title_style := StyleBoxFlat.new()
	title_style.bg_color = HEADER_COLOR
	var title_pc := PanelContainer.new()
	title_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_pc.add_theme_stylebox_override("panel", title_style)
	title_pc.add_child(title_row)
	root_vbox.add_child(title_pc)

	_title_lbl = Label.new()
	_title_lbl.text                  = "  TRANSFER INVENTORY"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 16)
	_title_lbl.add_theme_color_override("font_color", Color(0.45, 1.0, 0.60, 1.0))
	title_row.add_child(_title_lbl)

	var close_btn := Button.new()
	close_btn.text = "  ✕  "
	close_btn.pressed.connect(close)
	title_row.add_child(close_btn)

	root_vbox.add_child(HSeparator.new())

	# ── Column headers ──────────────────────────────────────────────────────
	var col_hdrs := HBoxContainer.new()
	col_hdrs.custom_minimum_size.y = 28.0
	col_hdrs.add_theme_constant_override("separation", 0)

	var hdr_style := StyleBoxFlat.new()
	hdr_style.bg_color = HEADER_COLOR
	var hdr_pc := PanelContainer.new()
	hdr_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_pc.add_theme_stylebox_override("panel", hdr_style)
	hdr_pc.add_child(col_hdrs)
	root_vbox.add_child(hdr_pc)

	var left_hdr := Label.new()
	left_hdr.text                  = "  YOUR INVENTORY"
	left_hdr.custom_minimum_size.x = 440.0
	left_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_hdr.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	left_hdr.add_theme_font_size_override("font_size", 12)
	left_hdr.add_theme_color_override("font_color", Color(0.60, 0.80, 1.0, 1.0))
	col_hdrs.add_child(left_hdr)

	_shop_hdr_lbl = Label.new()
	_shop_hdr_lbl.text                = "SHOP STOCK  "
	_shop_hdr_lbl.custom_minimum_size.x = 440.0
	_shop_hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_hdr_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_shop_hdr_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_shop_hdr_lbl.add_theme_font_size_override("font_size", 12)
	_shop_hdr_lbl.add_theme_color_override("font_color", Color(1.0, 0.80, 0.40, 1.0))
	col_hdrs.add_child(_shop_hdr_lbl)

	root_vbox.add_child(HSeparator.new())

	# ── Cash transfer row ──────────────────────────────────────────────────
	var cash_style := StyleBoxFlat.new()
	cash_style.bg_color = Color(0.08, 0.14, 0.10, 1.0)
	var cash_pc := PanelContainer.new()
	cash_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash_pc.add_theme_stylebox_override("panel", cash_style)
	root_vbox.add_child(cash_pc)

	var cash_row := HBoxContainer.new()
	cash_row.custom_minimum_size.y = 40.0
	cash_row.add_theme_constant_override("separation", 4)
	cash_pc.add_child(cash_row)

	_player_cash_lbl = Label.new()
	_player_cash_lbl.text               = "  Cash: $0"
	_player_cash_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_cash_lbl.add_theme_font_size_override("font_size", 13)
	_player_cash_lbl.add_theme_color_override("font_color", Color(0.30, 1.0, 0.40, 1.0))
	cash_row.add_child(_player_cash_lbl)

	_cash_to_shop_btns.clear()
	for amt: int in [10, 50, 100]:
		var b := Button.new()
		b.text = "$%d→" % amt
		b.custom_minimum_size = Vector2(52.0, 0.0)
		b.pressed.connect(_transfer_cash.bind(float(amt), true))
		cash_row.add_child(b)
		_cash_to_shop_btns.append(b)

	var cash_spacer := Control.new()
	cash_spacer.custom_minimum_size.x = 10.0
	cash_row.add_child(cash_spacer)

	_cash_from_shop_btns.clear()
	for amt: int in [10, 50, 100]:
		var b := Button.new()
		b.text = "←$%d" % amt
		b.custom_minimum_size = Vector2(52.0, 0.0)
		b.pressed.connect(_transfer_cash.bind(float(amt), false))
		cash_row.add_child(b)
		_cash_from_shop_btns.append(b)

	_shop_cash_lbl = Label.new()
	_shop_cash_lbl.text                 = "Shop: $0  "
	_shop_cash_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_cash_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_shop_cash_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_shop_cash_lbl.add_theme_font_size_override("font_size", 13)
	_shop_cash_lbl.add_theme_color_override("font_color", Color(1.0, 0.80, 0.30, 1.0))
	cash_row.add_child(_shop_cash_lbl)

	root_vbox.add_child(HSeparator.new())

	# ── Main two-column area ────────────────────────────────────────────────
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 0)
	root_vbox.add_child(hbox)

	# Left scroll
	var lscroll := ScrollContainer.new()
	lscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	hbox.add_child(lscroll)

	_left_list = VBoxContainer.new()
	_left_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_list.add_theme_constant_override("separation", 0)
	lscroll.add_child(_left_list)

	hbox.add_child(VSeparator.new())

	# Right scroll
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	hbox.add_child(rscroll)

	_right_list = VBoxContainer.new()
	_right_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_list.add_theme_constant_override("separation", 0)
	rscroll.add_child(_right_list)

	# ── Footer ──────────────────────────────────────────────────────────────
	root_vbox.add_child(HSeparator.new())

	var footer_style := StyleBoxFlat.new()
	footer_style.bg_color = HEADER_COLOR
	var footer_pc := PanelContainer.new()
	footer_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_pc.add_theme_stylebox_override("panel", footer_style)
	root_vbox.add_child(footer_pc)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 34.0
	footer.add_theme_constant_override("separation", 0)
	footer_pc.add_child(footer)

	var hint := Label.new()
	hint.text                  = "  [Esc] Close"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 1.0))
	footer.add_child(hint)


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	_title_lbl.text    = "  TRANSFER — " + _shop_title
	_shop_hdr_lbl.text = _shop_title + "  "
	_refresh_cash()
	_populate_list(_left_list,  _player_inv, true)
	_populate_list(_right_list, _shop_inv,   false)


func _refresh_cash() -> void:
	if _player_cash_lbl == null:
		return
	var player_cash: float = _wallet.get_balance(Wallet.Currency.CASH) if _wallet != null else 0.0
	var shop_cash:   float = (_shop_emp.cash if _shop_emp != null else 0.0)
	_player_cash_lbl.text = "  Cash: $%d" % int(player_cash)
	_shop_cash_lbl.text   = "Shop: $%d  " % int(shop_cash)
	var amounts: Array = [10.0, 50.0, 100.0]
	for i: int in range(3):
		_cash_to_shop_btns[i].disabled   = player_cash < amounts[i]
		_cash_from_shop_btns[i].disabled = shop_cash   < amounts[i]


func _transfer_cash(amount: float, to_shop: bool) -> void:
	if _wallet == null or _shop_emp == null:
		return
	if to_shop:
		if _wallet.remove(Wallet.Currency.CASH, amount):
			_shop_emp.cash += amount
			_refresh_cash()
	else:
		if _shop_emp.cash >= amount:
			_shop_emp.cash -= amount
			_wallet.add(Wallet.Currency.CASH, amount)
			_refresh_cash()


func _populate_list(list: VBoxContainer, inv: Object, is_player_side: bool) -> void:
	for child in list.get_children():
		child.queue_free()

	if inv == null:
		return

	var items: Array = inv.get_items()
	if items.is_empty():
		var lbl := Label.new()
		lbl.text               = "  (empty)"
		lbl.custom_minimum_size.y = 36.0
		lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
		list.add_child(lbl)
		return

	var even := false
	for item: Dictionary in items:
		var item_id:   int    = item["id"]
		var item_name: String = item["name"]
		var qty:       int    = item["qty"]

		var bg := StyleBoxFlat.new()
		bg.bg_color = ROW_COLOR_A if even else ROW_COLOR_B
		even = not even

		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.add_theme_stylebox_override("panel", bg)

		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 36.0
		row.add_theme_constant_override("separation", 4)
		pc.add_child(row)

		if is_player_side:
			var name_lbl := _make_item_label(item_name, Color(0.9, 0.9, 0.9, 1.0))
			var qty_lbl  := _make_qty_label("x" + str(qty), Color(0.7, 1.0, 0.7, 1.0))
			var btn      := _make_transfer_btn("→", item_id, _player_inv, _shop_inv)
			row.add_child(name_lbl)
			row.add_child(qty_lbl)
			row.add_child(btn)
		else:
			var btn      := _make_transfer_btn("←", item_id, _shop_inv, _player_inv)
			var name_lbl := _make_item_label(item_name, Color(0.9, 0.9, 0.9, 1.0))
			var qty_lbl  := _make_qty_label("x" + str(qty), Color(1.0, 0.85, 0.50, 1.0))
			row.add_child(btn)
			row.add_child(name_lbl)
			row.add_child(qty_lbl)

		list.add_child(pc)


func _make_item_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text                  = "  " + text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	return l


func _make_qty_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text + "  "
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	return l


func _make_transfer_btn(label: String, item_id: int, from_inv: Object, to_inv: Object) -> Button:
	var btn := Button.new()
	btn.text = " " + label + " "
	btn.custom_minimum_size = Vector2(40.0, 0.0)
	btn.pressed.connect(_transfer_item.bind(item_id, from_inv, to_inv))
	return btn


# ── Transfer logic ────────────────────────────────────────────────────────────

func _transfer_item(item_id: int, from_inv: Object, to_inv: Object) -> void:
	if from_inv == null or to_inv == null:
		return
	if from_inv.remove(item_id, 1):
		to_inv.add(item_id, 1)
