extends RefCounted

# =============================================================================
#  NPCSpawner — instantiates NPCs, builds their pathfinding data, and
#  applies economic setup.  Separates NPC creation from City orchestration.
#
#  Usage:
#    var spawner := NPCSpawner.new(scene_root, npc_scene, all_npcs, npc_init_queue,
#                                  storefront_registry, on_npc_clicked_cb,
#                                  on_sale_made_cb)
#    spawner.spawn_npc_at(...)
#    spawner.spawn_highway_patrols()
#    spawner.init_npc_movement(road_graph)
# =============================================================================

class_name NPCSpawner

var _scene_root:          Node
var _npc_scene:           PackedScene
var _all_npcs:            Array    # shared ref
var _npc_init_queue:      Array    # shared ref
var _storefront_registry: Array    # shared ref
var _on_npc_clicked:      Callable
var _on_sale_made:        Callable


func _init(scene_root:          Node,
		   npc_scene:           PackedScene,
		   all_npcs:            Array,
		   npc_init_queue:      Array,
		   storefront_registry: Array,
		   on_npc_clicked:      Callable,
		   on_sale_made:        Callable) -> void:
	_scene_root          = scene_root
	_npc_scene           = npc_scene
	_all_npcs            = all_npcs
	_npc_init_queue      = npc_init_queue
	_storefront_registry = storefront_registry
	_on_npc_clicked      = on_npc_clicked
	_on_sale_made        = on_sale_made


## Instantiate and place one NPC; append to shared arrays.
func spawn_npc_at(cx: float, cy: float,
				  did: int, pref: Array,
				  pw: float, cw: float, shop_chance: float) -> void:
	var npc_type: int = NPC.Type.POLICE if randf() < pw / (pw + cw) else NPC.Type.CIVILIAN
	var role: String  = WorldData.NPC_ROLES[did][npc_type]
	# Give civilians a realistic full name; police keep their role label.
	var npc_name: String = NameDB.random_full_name() if npc_type == NPC.Type.CIVILIAN else role
	var npc: NPC      = _npc_scene.instantiate()
	npc.setup(npc_type, npc_name, did, shop_chance, pref)
	npc.position = Vector2(cx, cy)
	_scene_root.add_child(npc)
	npc.npc_clicked.connect(_on_npc_clicked)
	if npc_type == NPC.Type.CIVILIAN:
		npc.sale_made.connect(_on_sale_made)
	_all_npcs.append(npc)
	_npc_init_queue.append({"npc": npc, "pos": Vector2(cx, cy)})


## Spawn highway patrol officers distributed across long highway segments.
func spawn_highway_patrols() -> void:
	var long_segs: Array = []
	for seg: Dictionary in WorldData.HIGHWAYS:
		if maxf(float(seg["w"]), float(seg["h"])) >= 800.0:
			long_segs.append(seg)
	if long_segs.is_empty():
		return
	long_segs.shuffle()
	var count: int = min(WorldData.HIGHWAY_PATROL_COUNT, long_segs.size())
	for i: int in range(count):
		var seg:  Dictionary = long_segs[i]
		var frac: float      = randf_range(0.15, 0.85)
		var cx:   float      = float(seg["x"]) + float(seg["w"]) * frac
		var cy:   float      = float(seg["y"]) + float(seg["h"]) * frac
		var npc:  NPC        = _npc_scene.instantiate()
		npc.setup(NPC.Type.POLICE, "Highway Patrol", -1, 0.0, [], true)
		npc.position = Vector2(cx, cy)
		_scene_root.add_child(npc)
		npc.npc_clicked.connect(_on_npc_clicked)
		_all_npcs.append(npc)
		_npc_init_queue.append({"npc": npc, "pos": Vector2(cx, cy)})


## Build pathfinding data for every queued NPC, then clear the queue.
## Call again after spawn_tourists() to initialise newly added tourists.
func init_npc_movement(road_graph: Object) -> void:
	var graph_nodes: Array = road_graph.nodes
	if graph_nodes.is_empty():
		return

	for entry: Dictionary in _npc_init_queue:
		var npc:  NPC     = entry["npc"]
		var home: Vector2 = entry["pos"]

		var local_pts: Array = []
		var roam_pts:  Array = []

		if npc.npc_type == NPC.Type.POLICE:
			if npc.is_highway_police:
				local_pts = graph_nodes.duplicate()
			else:
				var d_id: int = npc.district_id
				if d_id >= 0 and d_id < WorldData.DISTRICTS.size():
					var d: Dictionary = WorldData.DISTRICTS[d_id]
					var rect := Rect2(
						float(d["ox"]), float(d["oy"]),
						float(d["cols"]) * WorldData.CELL_W + WorldData.ROAD_W,
						float(d["rows"]) * WorldData.CELL_H + WorldData.ROAD_W
					)
					for n_pos: Vector2 in graph_nodes:
						if rect.has_point(n_pos):
							local_pts.append(n_pos)
				if local_pts.is_empty():
					var tmp: Array = graph_nodes.duplicate()
					tmp.sort_custom(func(a: Vector2, b: Vector2) -> bool:
						return a.distance_to(home) < b.distance_to(home))
					local_pts = tmp.slice(0, 20)
		else:
			var nearby: Array = []
			var far:    Array = []
			for n_pos: Vector2 in graph_nodes:
				if n_pos.distance_to(home) <= 3000.0:
					nearby.append(n_pos)
				else:
					far.append(n_pos)
			nearby.shuffle()
			local_pts = nearby.slice(0, min(24, nearby.size()))
			far.shuffle()
			roam_pts = far.slice(0, min(12, far.size()))

		npc.init_pathfinding(road_graph, local_pts, roam_pts, _storefront_registry)

	_npc_init_queue.clear()


## Tourist districts: Tourist Strip (3), Market District (7), Beachfront (8).
const TOURIST_DISTRICT_IDS: Array = [3, 7, 8]

## Spawn a batch of tourists into tourist-friendly districts.
## Call init_npc_movement() afterward to give them pathfinding data.
func spawn_tourists(count: int) -> void:
	for _i: int in range(count):
		var did: int        = TOURIST_DISTRICT_IDS[randi() % TOURIST_DISTRICT_IDS.size()]
		var d:   Dictionary = WorldData.DISTRICTS[did]
		var cx:  float      = float(d["ox"]) + randf_range(0.1, 0.9) * float(d["cols"]) * WorldData.CELL_W
		var cy:  float      = float(d["oy"]) + randf_range(0.1, 0.9) * float(d["rows"]) * WorldData.CELL_H
		var npc: NPC        = _npc_scene.instantiate()
		var pref: Array     = WorldData.DISTRICT_STOREFRONT_ITEMS[did]
		npc.setup(NPC.Type.TOURIST, NameDB.random_full_name(), did, 0.55, pref)
		npc.tourist_budget = randf_range(120.0, 500.0)
		npc.balance        = npc.tourist_budget
		npc.position       = Vector2(cx, cy)
		_scene_root.add_child(npc)
		npc.npc_clicked.connect(_on_npc_clicked)
		npc.sale_made.connect(_on_sale_made)
		_all_npcs.append(npc)
		_npc_init_queue.append({"npc": npc, "pos": Vector2(cx, cy)})
