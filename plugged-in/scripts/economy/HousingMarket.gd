extends RefCounted

# =============================================================================
#  HousingMarket — manages residential housing and tourist accommodation:
#    • initial home assignment for all civilians
#    • tourist hotel booking (assign / release)
#    • nightly housing market pass (re-house, upgrade, downgrade)
#    • rent pressure (vacancy deflates, saturation inflates)
#
#  Reason to change: housing rules, rent policy, or hotel mechanics.
# =============================================================================

class_name HousingMarket

## Max tenants each residential building type can hold.
const RESIDENTIAL_CAPACITY: Dictionary = {
	"House":        4,
	"Cottage":      3,
	"Bungalow":     4,
	"Flat":         8,
	"Tenement":     12,
	"Manor House":  6,
}

## All biz_types that provide civilian housing (not hotels).
const RESIDENTIAL_TYPES: Array = [
	"House", "Cottage", "Bungalow", "Flat", "Tenement", "Manor House",
]

## Max guests each hotel type can accommodate.
const HOTEL_CAPACITY: Dictionary = {
	"Hotel":         20,
	"Tourist Hotel": 30,
	"Resort":        50,
	"Inn":           10,
}

## biz_types that function as tourist accommodation.
const HOTEL_TYPES: Array = [
	"Hotel", "Tourist Hotel", "Resort", "Inn",
]

## Probability a housed, non-struggling NPC seeks an upgrade each night.
const HOUSING_UPGRADE_CHANCE:   float = 0.08
## Probability a struggling NPC tries to downgrade to cut costs each night.
const HOUSING_DOWNGRADE_CHANCE: float = 0.15

## Rent change rates applied to buildings each night.
const RENT_DEFLATE_VACANT:  float = 0.08   # 8 % drop  — completely empty
const RENT_DEFLATE_PARTIAL: float = 0.02   # 2 % drop  — under half capacity
const RENT_INFLATE_FULL:    float = 0.01   # 1 % rise  — every slot taken
const RENT_MINIMUM:         float = 1.0    # absolute floor ($1 / day)

var _all_bldg_metas: Array
var _all_npcs:       Array


func _init(all_bldg_metas: Array, all_npcs: Array) -> void:
	_all_bldg_metas = all_bldg_metas
	_all_npcs       = all_npcs


# =============================================================================
#  Initial assignment — called once from City._ready().
# =============================================================================

## Assign the nearest available home to every civilian NPC at game start.
func assign_initial_homes() -> void:
	var homes: Dictionary = _build_homes_index()
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN:
			continue
		_assign_home(npc, homes)


## Assign the nearest available hotel room to every tourist NPC.
## Call after spawn_tourists() so new arrivals are homed immediately.
func assign_tourist_hotels() -> void:
	var hotels: Dictionary = _build_hotels_index()
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.TOURIST or not npc.home_meta.is_empty():
			continue
		_assign_tourist_hotel(npc, hotels)


## Release a tourist's hotel slot — call before culling the tourist node.
func release_tourist_hotel(npc: NPC) -> void:
	if npc.home_meta.is_empty():
		return
	var cur: int = int(npc.home_meta.get("_tenant_count", 0))
	npc.home_meta["_tenant_count"] = max(0, cur - 1)
	npc.home_meta  = {}
	npc.daily_rent = 0.0


# =============================================================================
#  Nightly housing market pass — called by EconomyTicker._tick_night().
# =============================================================================

func run_night_tick() -> void:
	var homes: Dictionary = _build_homes_index()

	# ── Civilian housing loop ────────────────────────────────────────────────
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN:
			continue

		if not npc.home_meta.is_empty():
			# Home abandoned — release occupancy and look for a replacement.
			if npc.home_meta.get("status", "") == "abandoned":
				_release_home(npc)

		if npc.home_meta.is_empty():
			npc.days_unhoused += 1
			_assign_home(npc, homes)
		elif npc._is_struggling and randf() < HOUSING_DOWNGRADE_CHANCE:
			_try_downgrade_home(npc, homes)
		elif not npc._is_struggling \
				and npc.balance > npc.daily_wage * 10.0 \
				and randf() < HOUSING_UPGRADE_CHANCE:
			_try_upgrade_home(npc, homes)

	# ── Tourist hotel loop ───────────────────────────────────────────────────
	var hotels: Dictionary = _build_hotels_index()
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.TOURIST:
			continue
		if not npc.home_meta.is_empty():
			if npc.home_meta.get("status", "") == "abandoned":
				release_tourist_hotel(npc)
		if npc.home_meta.is_empty():
			_assign_tourist_hotel(npc, hotels)

	_tick_rent_pressure()


# =============================================================================
#  Index builders
# =============================================================================

func _build_homes_index() -> Dictionary:
	var result: Dictionary = {}
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("property_type", "") != "Residential":
			continue
		var biz_type: String = meta.get("biz_type", "House")
		var cap: int = RESIDENTIAL_CAPACITY.get(biz_type, 2)
		if int(meta.get("_tenant_count", 0)) >= cap:
			continue
		var did: int = _district_id_for(meta)
		if not result.has(did):
			result[did] = []
		(result[did] as Array).append(meta)
	return result


func _build_hotels_index() -> Dictionary:
	var result: Dictionary = {}
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("property_type", "") != "Hotel":
			continue
		var biz_type: String = meta.get("biz_type", "Hotel")
		var cap: int = HOTEL_CAPACITY.get(biz_type, 10)
		if int(meta.get("_tenant_count", 0)) >= cap:
			continue
		var did: int = _district_id_for(meta)
		if not result.has(did):
			result[did] = []
		(result[did] as Array).append(meta)
	return result


# =============================================================================
#  Home assignment helpers
# =============================================================================

func _assign_home(npc: NPC, homes: Dictionary) -> void:
	var raw: Array = _candidates_for_npc(npc.district_id, homes)
	var candidates: Array = []
	for meta: Dictionary in raw:
		var cap: int = RESIDENTIAL_CAPACITY.get(meta.get("biz_type", "House"), 2)
		if int(meta.get("_tenant_count", 0)) < cap:
			candidates.append(meta)
	if candidates.is_empty():
		return
	var best: Dictionary = _nearest(candidates, npc.position)
	if best.is_empty():
		return
	_assign_home_to(npc, best)


func _assign_home_to(npc: NPC, meta: Dictionary) -> void:
	npc.home_meta = meta
	var biz_type: String = meta.get("biz_type", "House")
	var cap: int = max(RESIDENTIAL_CAPACITY.get(biz_type, 2), 1)
	npc.daily_rent = float(meta.get("rent_per_day", 8.0)) / float(cap)
	meta["_tenant_count"] = int(meta.get("_tenant_count", 0)) + 1
	npc.days_unhoused = 0
	npc.log_event("Moved to %s ($%.0f/day rent)" % [meta.get("biz_name", "?"), npc.daily_rent])


func _assign_tourist_hotel(npc: NPC, hotels: Dictionary) -> void:
	var candidates: Array = _candidates_for_npc(npc.district_id, hotels)
	var best: Dictionary = _nearest(candidates, npc.position)
	if best.is_empty():
		return
	npc.home_meta = best
	var biz_type: String = best.get("biz_type", "Hotel")
	var cap: int = max(HOTEL_CAPACITY.get(biz_type, 10), 1)
	npc.daily_rent = float(best.get("rent_per_day", 50.0)) / float(cap)
	best["_tenant_count"] = int(best.get("_tenant_count", 0)) + 1


func _release_home(npc: NPC) -> void:
	if not npc.home_meta.is_empty():
		npc.log_event("Lost home @ %s" % npc.home_meta.get("biz_name", "?"))
		npc.home_meta["_tenant_count"] = \
			max(0, int(npc.home_meta.get("_tenant_count", 0)) - 1)
	npc.home_meta  = {}
	npc.daily_rent = 0.0


func _try_upgrade_home(npc: NPC, homes: Dictionary) -> void:
	var all_candidates: Array = _all_candidates(homes)
	for meta: Dictionary in all_candidates:
		if meta == npc.home_meta:
			continue
		var biz_type: String = meta.get("biz_type", "House")
		var cap: int = max(RESIDENTIAL_CAPACITY.get(biz_type, 2), 1)
		var new_rent: float = float(meta.get("rent_per_day", 0.0)) / float(cap)
		if new_rent > npc.daily_rent and new_rent < npc.daily_wage * 0.40:
			_release_home(npc)
			_assign_home_to(npc, meta)
			return


func _try_downgrade_home(npc: NPC, homes: Dictionary) -> void:
	var all_candidates: Array = _all_candidates(homes)
	for meta: Dictionary in all_candidates:
		if meta == npc.home_meta:
			continue
		var biz_type: String = meta.get("biz_type", "House")
		var cap: int = max(RESIDENTIAL_CAPACITY.get(biz_type, 2), 1)
		var new_rent: float = float(meta.get("rent_per_day", 0.0)) / float(cap)
		if new_rent < npc.daily_rent:
			_release_home(npc)
			_assign_home_to(npc, meta)
			return


# =============================================================================
#  Rent pressure — adjust rent each night based on occupancy.
# =============================================================================

func _tick_rent_pressure() -> void:
	for meta: Dictionary in _all_bldg_metas:
		var prop_type: String = meta.get("property_type", "")
		if prop_type != "Residential" and prop_type != "Hotel":
			continue
		var biz_type: String = meta.get("biz_type", "House")
		var cap: int = max(
			RESIDENTIAL_CAPACITY.get(biz_type, HOTEL_CAPACITY.get(biz_type, 2)), 1)
		var tenants: int   = int(meta.get("_tenant_count", 0))
		var rent:    float = float(meta.get("rent_per_day", 8.0))
		if tenants == 0:
			rent = maxf(RENT_MINIMUM, rent * (1.0 - RENT_DEFLATE_VACANT))
		elif tenants < cap / 2.0:
			rent = maxf(RENT_MINIMUM, rent * (1.0 - RENT_DEFLATE_PARTIAL))
		elif tenants >= cap:
			rent *= (1.0 + RENT_INFLATE_FULL)
		meta["rent_per_day"] = rent
	# Push the new nightly rate to every current tenant.
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.home_meta.is_empty():
			continue
		var biz_type: String = npc.home_meta.get("biz_type", "House")
		var cap: int = max(
			RESIDENTIAL_CAPACITY.get(biz_type, HOTEL_CAPACITY.get(biz_type, 2)), 1)
		npc.daily_rent = float(npc.home_meta.get("rent_per_day", 8.0)) / float(cap)


# =============================================================================
#  Shared utility helpers (duplicated from JobMarket for independence).
# =============================================================================

func _candidates_for_npc(district_id: int, index: Dictionary) -> Array:
	var local: Array = (index.get(district_id, []) as Array).duplicate()
	if not local.is_empty():
		return local
	return _all_candidates(index)


func _all_candidates(index: Dictionary) -> Array:
	var result: Array = []
	for key: int in index.keys():
		result.append_array(index[key] as Array)
	return result


func _nearest(candidates: Array, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for c: Dictionary in candidates:
		var d: float = (c.get("_world_pos", Vector2.ZERO) as Vector2).distance_to(pos)
		if d < best_dist:
			best_dist = d
			best      = c
	return best


func _district_id_for(meta: Dictionary) -> int:
	var dist_name: String = meta.get("district", "")
	for d: Dictionary in WorldData.DISTRICTS:
		if d["name"] == dist_name:
			return int(d["id"])
	return 0
