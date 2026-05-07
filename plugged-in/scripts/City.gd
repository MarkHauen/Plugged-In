extends Node2D

# =============================================================================
#  City.gd — thin orchestrator.
#  Owns shared runtime state arrays; delegates all heavy work to focused modules.
# =============================================================================

const NPC_SCENE := preload("res://scenes/npc/NPC.tscn")
const BUILDING_INFO_UI_S := preload("res://scripts/ui/BuildingInfoUI.gd")
const RoadGraphScript := preload("res://scripts/world/RoadGraph.gd")
const NPCDataViewScript := preload("res://scripts/ui/NPCDataView.gd")
const EconDataViewScript := preload("res://scripts/ui/EconDataView.gd")
const DistrictGeneratorScript := preload("res://scripts/world/DistrictGenerator.gd")
const LandownerSystemScript := preload("res://scripts/world/LandownerSystem.gd")
const NPCSpawnerScript := preload("res://scripts/npc/NPCSpawner.gd")
const EconomyTickerScript := preload("res://scripts/economy/EconomyTicker.gd")
const JobMarketScript := preload("res://scripts/economy/JobMarket.gd")
const DebugOverlayScript := preload("res://scripts/ui/DebugOverlay.gd")


# -- Shared runtime state ----------------------------------------------------
var _all_bldg_metas: Array = []
var _all_bldg_pos: Array = []
var _all_npcs: Array = []
var _storefront_registry: Array = []
var _npc_init_queue: Array = []

# -- Module instances --------------------------------------------------------
var _building_info_ui: CanvasLayer = null
var _road_graph: Object = null
var _landowner_system: LandownerSystem
var _district_generator: DistrictGenerator
var _npc_spawner: NPCSpawner
var _economy_ticker: EconomyTicker
var _job_market: JobMarket
var _debug_overlay: DebugOverlay
var _npc_view: NPCDataView = null
var _econ_view: EconDataView = null

# -- Layer nodes -------------------------------------------------------------
var _highway_layer: Node2D = null
var _debug_layer: Node2D = null


func _ready() -> void:
# UI and layer containers
	_building_info_ui = BUILDING_INFO_UI_S.new()
	add_child(_building_info_ui)
	_building_info_ui.set_player($Player)

	_highway_layer = Node2D.new()
	_highway_layer.name = "HighwayLayer"
	add_child(_highway_layer)

	_debug_layer = Node2D.new()
	_debug_layer.name = "DebugLayer"
	add_child(_debug_layer)

# World rendering
	WorldRenderer.draw_water(self )
	WorldRenderer.draw_island(self )
	WorldRenderer.draw_highways(_highway_layer)
	WorldRenderer.draw_debug_grid(_debug_layer)
	WorldRenderer.draw_highway_debug_labels(_debug_layer)

# Landowner system
	_landowner_system = LandownerSystemScript.new(self )
	_landowner_system.generate()
	_building_info_ui.owner_inspect_requested.connect(
	func(oid: int) -> void: _landowner_system.show_inspector(oid))

# NPC spawner
	_npc_spawner = NPCSpawnerScript.new(
	self , NPC_SCENE, _all_npcs, _npc_init_queue, _storefront_registry,
	_on_npc_clicked, _on_npc_sale_made)

# District generator
	_district_generator = DistrictGeneratorScript.new(
	self , _building_info_ui,
	_landowner_system.landowners,
	_all_bldg_metas, _all_bldg_pos,
	_storefront_registry, _npc_init_queue)
	_district_generator._npc_spawner = _npc_spawner
	_district_generator.generate_all_districts()

	# Road graph
	_road_graph = RoadGraphScript.new()
	_road_graph.build(WorldData.HIGHWAYS)
	_road_graph.build_districts(WorldData.DISTRICTS)

	# Debug overlay
	_debug_overlay = DebugOverlayScript.new(self , _debug_layer, _highway_layer)
	_debug_overlay.build_npc_info_ui()
	WorldRenderer.draw_road_nodes(_road_graph, _debug_layer)

	# NPC init
	_npc_spawner.spawn_highway_patrols()
	_npc_spawner.init_npc_movement(_road_graph)

	# Data views
	_npc_view = NPCDataViewScript.new()
	add_child(_npc_view)
	_npc_view.setup(_all_npcs, WorldData.DISTRICTS)

	_econ_view = EconDataViewScript.new()
	add_child(_econ_view)
	_econ_view.setup(_all_bldg_metas)

	# Island collision + camera
	WorldRenderer.build_island_boundary(self )
	_setup_camera()

	# Initial layer visibility
	_highway_layer.visible = not _debug_overlay.debug_mode
	_debug_layer.visible = _debug_overlay.debug_mode

	# Economy ticker
	_job_market = JobMarketScript.new(_all_bldg_metas, _all_npcs)
	_job_market.assign_initial_jobs()
	_job_market.assign_initial_homes()

	_economy_ticker = EconomyTickerScript.new(
	_all_bldg_metas, _all_npcs, _landowner_system.landowners, _job_market)
	EconomyManager.phase_changed.connect(_economy_ticker.on_economy_phase_changed)
	EconomyManager.day_started.connect(_economy_ticker.on_economy_day_started)
	EconomyManager.day_started.connect(_on_day_started)

	# Initial tourist batch
	_npc_spawner.spawn_tourists(randi() % 4 + 3)
	_npc_spawner.init_npc_movement(_road_graph)

	$Player.z_index = 10


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if not (ke.pressed and not ke.echo):
		return
	match ke.keycode:
		KEY_P:
			_debug_overlay.toggle()
		KEY_F:
			_npc_view.toggle()
		KEY_G:
			_econ_view.toggle()
		KEY_ESCAPE:
			if _econ_view != null and _econ_view.visible:
				_econ_view.visible = false
			elif _npc_view != null and _npc_view.visible:
				_npc_view.visible = false
			elif _landowner_system.is_inspector_visible():
				_landowner_system.hide_inspector()
			elif _debug_overlay.is_npc_panel_visible():
				_debug_overlay.hide_npc_panel()


func _process(_delta: float) -> void:
	if _debug_overlay.selected_npc != null and is_instance_valid(_debug_overlay.selected_npc):
		_debug_overlay.update_npc_info()


func _on_npc_clicked(npc: NPC) -> void:
	_debug_overlay.on_npc_clicked(npc)


func _on_npc_sale_made(item_name: String, amount: int, _shop_pos: Vector2) -> void:
	print("[SALE] %s -- $%d" % [item_name, amount])


func _on_day_started(_day: int) -> void:
	_landowner_system.reset_daily_income()
	_npc_spawner.spawn_tourists(randi() % 4 + 2)
	_npc_spawner.init_npc_movement(_road_graph)


func _setup_camera() -> void:
	var cam: Camera2D = $Player.get_node("Camera2D")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(WorldData.MAP_W)
	cam.limit_bottom = int(WorldData.MAP_H)
