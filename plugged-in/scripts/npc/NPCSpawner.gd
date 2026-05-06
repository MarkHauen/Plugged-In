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
	var npc: NPC      = _npc_scene.instantiate()
	npc.setup(npc_type, role, did, shop_chance, pref)
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


## Build pathfinding data and apply economic values to every queued NPC.
## Must be called after all districts and buildings are generated.
func init_npc_movement(road_graph: Object, all_bldg_metas: Array) -> void:
	var graph_nodes: Array = road_graph.nodes
	if graph_nodes.is_empty():
		return

	var homes_by_district: Dictionary = _build_homes_index(all_bldg_metas)

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

		if npc.npc_type == NPC.Type.CIVILIAN and npc.district_id >= 0:
			_apply_npc_economy(npc, homes_by_district)


## Build a district-id → [residential_meta, …] index from building metadata.
func _build_homes_index(all_bldg_metas: Array) -> Dictionary:
	var dist_name_to_id: Dictionary = {}
	for _d: Dictionary in WorldData.DISTRICTS:
		dist_name_to_id[_d["name"]] = _d["id"]
	var homes_by_district: Dictionary = {}
	for bmeta: Dictionary in all_bldg_metas:
		if bmeta.get("property_type", "") == "Residential":
			var did: int = dist_name_to_id.get(bmeta.get("district", ""), -1)
			if did >= 0:
				if not homes_by_district.has(did):
					homes_by_district[did] = []
				(homes_by_district[did] as Array).append(bmeta)
	return homes_by_district


func _apply_npc_economy(npc: NPC, homes_by_district: Dictionary) -> void:
	var d_id: int        = npc.district_id
	var ecfg: Dictionary = WorldData.DISTRICT_BLDG_CONFIG[d_id] if d_id < WorldData.DISTRICT_BLDG_CONFIG.size() else {}
	var inc_lo: float    = float(ecfg.get("income_lo", 40))
	var inc_hi: float    = float(ecfg.get("income_hi", 200))
	npc.daily_wage = randf_range(inc_lo * 0.025, inc_hi * 0.040)
	npc.daily_rent = npc.daily_wage * randf_range(0.30, 0.50)
	npc.balance    = npc.daily_wage * randf_range(1.5, 4.0)
	var h_list: Array = homes_by_district.get(d_id, [])
	if not h_list.is_empty():
		npc.home_meta = h_list[randi() % h_list.size()]
