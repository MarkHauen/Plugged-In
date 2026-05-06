extends CanvasLayer

const ROW_COLOR_A  := Color(0.15, 0.15, 0.18, 1.0)
const ROW_COLOR_B  := Color(0.20, 0.20, 0.24, 1.0)
const HEADER_COLOR := Color(0.10, 0.10, 0.13, 1.0)

var _inventory: Object = null  # Inventory instance
var _wallet:    Wallet = null
var _panel: PanelContainer
var _list:  VBoxContainer
var _cash_label:  Label
var _btc_label:   Label
var _title_lbl:   Label


func _ready() -> void:
	layer = 10
	_build_ui()
	hide()


# ── Public ────────────────────────────────────────────────────────────────────

func bind(inventory: Object) -> void:
	if _inventory != null and _inventory.changed.is_connected(_on_inventory_changed):
		_inventory.changed.disconnect(_on_inventory_changed)
	_inventory = inventory
	if _inventory == null:
		return
	_inventory.changed.connect(_on_inventory_changed)
	_refresh()


func toggle() -> void:
	if visible:
		hide()
	else:
		show()
		_refresh()
		_refresh_wallet()


func bind_wallet(wallet: Wallet) -> void:
	if _wallet and _wallet.changed.is_connected(_refresh_wallet):
		_wallet.changed.disconnect(_refresh_wallet)
	_wallet = wallet
	_wallet.changed.connect(_refresh_wallet)
	_refresh_wallet()


func set_title(text: String) -> void:
	_title_lbl.text = "  " + text


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Semi-transparent dark panel centered on screen
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420.0, 480.0)
	_panel.position = Vector2(-210.0, -240.0)
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color            = Color(0.12, 0.12, 0.16, 0.95)
	style.border_color        = Color(0.4, 0.7, 1.0, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_panel.add_child(vbox)

	# ── Title bar ──
	_title_lbl = Label.new()
	_title_lbl.text                  = "  INVENTORY"
	_title_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
	_title_lbl.add_theme_font_size_override("font_size", 18)
	_title_lbl.custom_minimum_size.y = 36.0
	_title_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	var title_bg := _make_bg_panel(HEADER_COLOR)
	_wrap_with_bg(vbox, _title_lbl, title_bg)

	# ── Column headers ──
	var header_row := _make_row_hbox()
	header_row.add_child(_make_label("Item",  Color(0.6, 0.8, 1.0), 250.0, true))
	header_row.add_child(_make_label("Qty",   Color(0.6, 0.8, 1.0),  60.0, true))
	header_row.add_child(_make_label("Value", Color(0.6, 0.8, 1.0),  80.0, true))
	var hdr_bg := _make_bg_panel(HEADER_COLOR)
	_wrap_with_bg(vbox, header_row, hdr_bg)

	# ── Scroll area for item rows ──
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_list)

	# ── Wallet balance row ──
	vbox.add_child(HSeparator.new())
	var wallet_row := HBoxContainer.new()
	wallet_row.custom_minimum_size.y = 32.0
	wallet_row.add_theme_constant_override("separation", 0)

	_cash_label = Label.new()
	_cash_label.text = "  Cash: $0"
	_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cash_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_cash_label.add_theme_font_size_override("font_size", 14)
	_cash_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 1.0))
	wallet_row.add_child(_cash_label)

	_btc_label = Label.new()
	_btc_label.text = "\u20bf0.00000000  "
	_btc_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_btc_label.add_theme_font_size_override("font_size", 14)
	_btc_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1, 1.0))
	wallet_row.add_child(_btc_label)

	var wallet_bg := _make_bg_panel(HEADER_COLOR)
	_wrap_with_bg(vbox, wallet_row, wallet_bg)

	# ── Footer hint ──
	var hint := Label.new()
	hint.text               = "  [Tab] Close"
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 1.0))
	hint.add_theme_font_size_override("font_size", 13)
	hint.custom_minimum_size.y = 28.0
	hint.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	if _inventory == null:
		return

	var items: Array = _inventory.get_items()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "  (empty)"
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
		empty.add_theme_font_size_override("font_size", 14)
		empty.custom_minimum_size.y = 36.0
		empty.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(empty)
		return

	var even := false
	for item: Dictionary in items:
		var row := _make_row_hbox()
		var bg  := _make_bg_panel(ROW_COLOR_A if even else ROW_COLOR_B)
		even = not even

		row.add_child(_make_label(item["name"],              Color(0.9, 0.9, 0.9), 250.0))
		row.add_child(_make_label(str(item["qty"]),          Color(0.8, 1.0, 0.8),  60.0))
		row.add_child(_make_label("$" + str(item["price"]), Color(1.0, 0.85, 0.4),  80.0))

		_wrap_with_bg(_list, row, bg)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _on_inventory_changed() -> void:
	if visible:
		_refresh()


func _refresh_wallet() -> void:
	if _wallet == null or _cash_label == null:
		return
	_cash_label.text = "  Cash: " + _wallet.format(Wallet.Currency.CASH)
	_btc_label.text  = _wallet.format(Wallet.Currency.BITCOIN) + "  "


func _make_row_hbox() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = 36.0
	h.add_theme_constant_override("separation", 0)
	return h


func _make_label(text: String, color: Color, min_width: float, bold: bool = false) -> Label:
	var l := Label.new()
	l.text                      = "  " + text
	l.custom_minimum_size.x     = min_width
	l.size_flags_horizontal     = Control.SIZE_EXPAND_FILL if min_width == 250.0 else Control.SIZE_SHRINK_BEGIN
	l.vertical_alignment        = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 15 if bold else 14)
	return l


func _make_bg_panel(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	return s


func _wrap_with_bg(parent: Control, child: Control, style: StyleBoxFlat) -> void:
	var container := PanelContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_stylebox_override("panel", style)
	container.add_child(child)
	parent.add_child(container)
