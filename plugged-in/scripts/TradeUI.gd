extends CanvasLayer

const PANEL_COLOR  := Color(0.12, 0.12, 0.16, 0.97)
const BORDER_COLOR := Color(0.95, 0.75, 0.20, 1.0)  # gold — matches Customer color

var _request:   Dictionary = {}
var _inventory: Object     = null
var _player:    Node       = null

var _item_label:  Label
var _stock_label: Label
var _price_label: Label
var _deal_button: Button


func _ready() -> void:
	layer = 11  # above InventoryUI's layer 10
	_build_ui()
	hide()


# ── Public ────────────────────────────────────────────────────────────────────

func open(request: Dictionary, inventory: Object, player: Node) -> void:
	_request   = request
	_inventory = inventory
	_player    = player
	_refresh()
	show()


func close() -> void:
	hide()
	_request = {}


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(340.0, 230.0)
	panel.position            = Vector2(-170.0, -115.0)

	var style := StyleBoxFlat.new()
	style.bg_color            = PANEL_COLOR
	style.border_color        = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "  TRADE REQUEST"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", BORDER_COLOR)
	header.custom_minimum_size.y = 34.0
	header.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	# Item being requested
	_item_label = Label.new()
	_item_label.add_theme_font_size_override("font_size", 14)
	_item_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(_item_label)

	# Player's current stock
	_stock_label = Label.new()
	_stock_label.add_theme_font_size_override("font_size", 13)
	_stock_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
	vbox.add_child(_stock_label)

	# Offered price
	_price_label = Label.new()
	_price_label.add_theme_font_size_override("font_size", 14)
	_price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(_price_label)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4.0
	vbox.add_child(spacer)

	# Buttons
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_deal_button = Button.new()
	_deal_button.text                  = "  [Q] Deal  "
	_deal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deal_button.pressed.connect(_on_deal_pressed)
	hbox.add_child(_deal_button)

	var pass_button := Button.new()
	pass_button.text                  = "  [E] Pass  "
	pass_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pass_button.pressed.connect(close)
	hbox.add_child(pass_button)


func _refresh() -> void:
	if _request.is_empty():
		return

	var item_id:   int    = _request["item_id"]
	var qty:       int    = _request["qty"]
	var price:     int    = _request["price"]
	var item_name: String = ItemDB.get_item_name(item_id)
	var stock:     int    = _inventory.count(item_id)

	_item_label.text  = "  Wants:    %s  x%d" % [item_name, qty]
	_stock_label.text = "  You have: %d in bag" % stock
	_price_label.text = "  Offering: $%d" % price

	var can_deal: bool       = stock >= qty
	_deal_button.disabled    = not can_deal
	_deal_button.modulate    = Color(1, 1, 1, 1) if can_deal else Color(0.5, 0.5, 0.5, 1)


# ── Callbacks ─────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := (event as InputEventKey).keycode
		if key == KEY_Q:
			get_viewport().set_input_as_handled()
			_on_deal_pressed()
		elif key == KEY_E:
			get_viewport().set_input_as_handled()
			close()


func _on_deal_pressed() -> void:
	var item_id: int = _request["item_id"]
	var qty:     int = _request["qty"]
	var price:   int = _request["price"]
	if _inventory.remove(item_id, qty):
		_player.wallet.add(Wallet.Currency.CASH, float(price))
	close()
