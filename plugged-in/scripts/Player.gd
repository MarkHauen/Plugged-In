extends CharacterBody2D

const SPEED          := 2000.0
const ZOOM_MIN       := 0.2500
const ZOOM_MAX       := 10.0
const ZOOM_STEP      := 0.15
const EMPLOYEE_SCENE := preload("res://scenes/npc/Employee.tscn")

var inventory: Object  # Inventory instance
var wallet:    Wallet
var employees: Array = []   # Array[Employee]

@onready var _inventory_ui: CanvasLayer = $InventoryUI
@onready var _trade_ui:     CanvasLayer = $TradeUI
@onready var _transfer_ui:  CanvasLayer = $TransferUI
@onready var _camera:       Camera2D    = $Camera2D


func _ready() -> void:
	add_to_group("player")
	var Inventory := load("res://scripts/Inventory.gd")
	inventory = Inventory.new()

	wallet = Wallet.new()
	wallet.add(Wallet.Currency.CASH,    100.0)
	wallet.add(Wallet.Currency.BITCOIN, 0.0025)

	# Seed the player with starter items for testing.
	inventory.add(ItemDB.ID.COFFEE,      3)
	inventory.add(ItemDB.ID.USB_CABLE,   1)
	inventory.add(ItemDB.ID.HEADPHONES,  2)
	inventory.add(ItemDB.ID.PHONE_CASE,  6)
	inventory.add(ItemDB.ID.CHARGER,     4)
	inventory.add(ItemDB.ID.STREETWEAR,  2)
	inventory.add(ItemDB.ID.FAKE_ID,     1)
	inventory.add(ItemDB.ID.FLOWER,      5)

	_inventory_ui.bind(inventory)
	_inventory_ui.bind_wallet(wallet)

	# Start the player with one free employee.
	hire_employee()


func hire_employee() -> void:
	var emp: Employee = EMPLOYEE_SCENE.instantiate()
	emp.init("Employee " + str(employees.size() + 1), self)
	get_parent().add_child(emp)
	emp.position = position + Vector2(40.0, 20.0)
	employees.append(emp)


func available_employees() -> Array:
	var free: Array = []
	for emp in employees:
		if (emp as Employee).is_free():
			free.append(emp)
	return free


func open_inventory_for(inv: Object, title: String) -> void:
	_inventory_ui.bind(inv)
	_inventory_ui.set_title(title)
	_inventory_ui.show()
	_inventory_ui.visibility_changed.connect(_on_employee_inv_closed, CONNECT_ONE_SHOT)


func open_transfer(emp_inv: Object, emp_obj: Object, shop_title: String) -> void:
	_transfer_ui.open(inventory, emp_inv, wallet, emp_obj, shop_title)


func _on_employee_inv_closed() -> void:
	if not _inventory_ui.visible:
		_inventory_ui.bind(inventory)
		_inventory_ui.set_title("INVENTORY")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		_inventory_ui.toggle()
		get_viewport().set_input_as_handled()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var current_zoom: float = _camera.zoom.x
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_camera.zoom = Vector2.ONE * clampf(current_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_camera.zoom = Vector2.ONE * clampf(current_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				get_viewport().set_input_as_handled()


func open_trade(request: Dictionary) -> void:
	_trade_ui.open(request, inventory, self)


func close_trade() -> void:
	_trade_ui.close()


func _physics_process(_delta: float) -> void:
	# Freeze movement while any UI panel is open.
	if _inventory_ui.visible or _transfer_ui.visible:
		velocity = Vector2.ZERO
		return

	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0

	velocity = direction.normalized() * SPEED if direction != Vector2.ZERO else Vector2.ZERO
	move_and_slide()
