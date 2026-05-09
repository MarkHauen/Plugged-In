extends RefCounted

# =============================================================================
#  JobMarket — assigns NPCs to employer buildings and residential homes.
#  Runs a nightly market pass so NPCs can change jobs or move house based on
#  their economic circumstances.
#
#  Usage (City._ready after all districts and NPCs are initialised):
#    var _job_market := JobMarket.new(_all_bldg_metas, _all_npcs)
#    _job_market.assign_initial_jobs()
#    _job_market.assign_initial_homes()
#
#  EconomyTicker calls run_night_tick() each NIGHT phase.
# =============================================================================

class_name JobMarket

# How many tenants each residential building type can house.
const RESIDENTIAL_CAPACITY: Dictionary = {
	"House":        4,
	"Cottage":      3,
	"Bungalow":     4,
	"Flat":         8,
	"Tenement":     12,
	"Manor House":  6,
}

# Residential biz_types (buildings that provide homes, not jobs).
const RESIDENTIAL_TYPES: Array = [
	"House", "Cottage", "Bungalow", "Flat", "Tenement", "Manor House",
]

# How many tourist guests each hotel type can accommodate.
const HOTEL_CAPACITY: Dictionary = {
	"Hotel":         20,
	"Tourist Hotel": 30,
	"Resort":        50,
	"Inn":           10,
}

# biz_types that function as tourist accommodation.
const HOTEL_TYPES: Array = [
	"Hotel", "Tourist Hotel", "Resort", "Inn",
]

# NPCs check for a better job with this probability each night.
const JOB_UPGRADE_CHANCE    := 0.12
# NPCs check for better housing with this probability when doing well.
const HOUSING_UPGRADE_CHANCE := 0.08
# NPCs try to downgrade housing with this probability when struggling.
const HOUSING_DOWNGRADE_CHANCE := 0.15
# A new job must pay at least this fraction more to be worth switching for.
const UPGRADE_WAGE_THRESHOLD := 1.25

# Rent pressure applied each NIGHT to residential buildings.
const RENT_DEFLATE_VACANT:  float = 0.08   # 8 % drop when completely empty
const RENT_DEFLATE_PARTIAL: float = 0.02   # 2 % drop when under half capacity
const RENT_INFLATE_FULL:    float = 0.01   # 1 % rise when every slot is taken
const RENT_MINIMUM:         float = 1.0    # absolute floor ($1 / day)

var _all_bldg_metas: Array   # shared ref from City
var _all_npcs:       Array   # shared ref from City


func _init(all_bldg_metas: Array, all_npcs: Array) -> void:
	_all_bldg_metas = all_bldg_metas
	_all_npcs       = all_npcs


# =============================================================================
#  Initial assignment — called once after all buildings and NPCs are ready.
# =============================================================================

func assign_initial_jobs() -> void:
	var employers: Dictionary = _build_employers_index()
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN:
			continue
		_assign_job(npc, employers)


func assign_initial_homes() -> void:
	var homes: Dictionary = _build_homes_index()
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN:
			continue
		_assign_home(npc, homes)


## Seed each civilian NPC with a realistic starting bank balance.
## Call once after assign_initial_jobs() and assign_initial_homes() so that
## daily_wage and daily_rent are already populated.
## Balance = 7–21 days of wages, floored at $20 so even the unemployed
## have a little spending money at game start.
func seed_starting_balances() -> void:
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN:
			continue
		var days: float = randf_range(7.0, 21.0)
		npc.balance = maxf(20.0, npc.daily_wage * days)
		npc._update_struggling_tint()


## Assign every tourist in _all_npcs to their nearest available hotel.
## Call this after spawn_tourists() so new arrivals get a room.
func assign_tourist_hotels() -> void:
	var hotels: Dictionary = _build_hotels_index()
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.TOURIST or not npc.home_meta.is_empty():
			continue
		_assign_tourist_hotel(npc, hotels)


## Release a tourist's hotel slot (call before culling the tourist).
func release_tourist_hotel(npc: NPC) -> void:
	if npc.home_meta.is_empty():
		return
	var cur: int = int(npc.home_meta.get("_tenant_count", 0))
	npc.home_meta["_tenant_count"] = max(0, cur - 1)
	npc.home_meta  = {}
	npc.daily_rent = 0.0


# =============================================================================
#  Nightly market pass — called by EconomyTicker.tick_night().
# =============================================================================

func run_night_tick() -> void:
	var employers: Dictionary = _build_employers_index()
	var homes:     Dictionary = _build_homes_index()

	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN:
			continue

		# ── Job market ──────────────────────────────────────────────────────
		if not npc.employer_meta.is_empty():
			# Employer closed — release the job
			if not npc.employer_meta.get("operational", false):
				_release_job(npc)

		if npc.employer_meta.is_empty():
			# Unemployed: seek any job
			npc.days_unemployed += 1
			_assign_job(npc, employers)
		elif randf() < JOB_UPGRADE_CHANCE:
			# Employed but ambitious: look for a higher-paying opening
			_try_upgrade_job(npc, employers)

		# ── Housing market ───────────────────────────────────────────────────
		if not npc.home_meta.is_empty():
			# Home abandoned — release and find a new one
			if npc.home_meta.get("status", "") == "abandoned":
				_release_home(npc)

		if npc.home_meta.is_empty():
			# Unhoused: find any available home
			npc.days_unhoused += 1
			_assign_home(npc, homes)
		elif npc._is_struggling and randf() < HOUSING_DOWNGRADE_CHANCE:
			_try_downgrade_home(npc, homes)
		elif not npc._is_struggling \
				and npc.balance > npc.daily_wage * 10.0 \
				and randf() < HOUSING_UPGRADE_CHANCE:
			_try_upgrade_home(npc, homes)

	# ── Tourist hotel market ─────────────────────────────────────────────────
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

## Returns: district_id → [building metas with remaining employee capacity]
func _build_employers_index() -> Dictionary:
	var result: Dictionary = {}
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("property_type", "") == "Residential":
			continue
		if not meta.get("operational", false):
			continue
		var recipe: Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var cap: int = int(recipe.get("employees", 0))
		if cap <= 0:
			continue
		var cur: int = int(meta.get("_employee_count", 0))
		if cur >= cap:
			continue
		var did: int = _district_id_for(meta)
		if not result.has(did):
			result[did] = []
		(result[did] as Array).append(meta)
	return result


## Returns: district_id → [residential building metas with remaining capacity]
func _build_homes_index() -> Dictionary:
	var result: Dictionary = {}
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("property_type", "") != "Residential":
			continue
		var biz_type: String = meta.get("biz_type", "House")
		var cap: int = RESIDENTIAL_CAPACITY.get(biz_type, 2)
		var cur: int = int(meta.get("_tenant_count", 0))
		if cur >= cap:
			continue
		var did: int = _district_id_for(meta)
		if not result.has(did):
			result[did] = []
		(result[did] as Array).append(meta)
	return result


## Returns: district_id → [hotel building metas with remaining guest capacity]
func _build_hotels_index() -> Dictionary:
	var result: Dictionary = {}
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("property_type", "") != "Hotel":
			continue
		var biz_type: String = meta.get("biz_type", "Hotel")
		var cap: int = HOTEL_CAPACITY.get(biz_type, 10)
		var cur: int = int(meta.get("_tenant_count", 0))
		if cur >= cap:
			continue
		var did: int = _district_id_for(meta)
		if not result.has(did):
			result[did] = []
		(result[did] as Array).append(meta)
	return result


## Resolves the district name on a building meta to its integer ID.
func _district_id_for(meta: Dictionary) -> int:
	var dist_name: String = meta.get("district", "")
	for d: Dictionary in WorldData.DISTRICTS:
		if d["name"] == dist_name:
			return int(d["id"])
	return 0


# =============================================================================
#  Job assignment helpers
# =============================================================================

func _assign_job(npc: NPC, employers: Dictionary) -> void:
	# Search home district first, then city-wide.
	# Re-check capacity live: the index is built once per tick so _employee_count
	# may have advanced since the index snapshot was taken.
	var raw: Array = _candidates_for_npc(npc.district_id, employers)
	var candidates: Array = []
	for meta: Dictionary in raw:
		var recipe: Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var cap: int = int(recipe.get("employees", 0))
		if int(meta.get("_employee_count", 0)) < cap:
			candidates.append(meta)
	if candidates.is_empty():
		return
	var best: Dictionary = _nearest(candidates, npc.position)
	if best.is_empty():
		return
	_assign_job_to(npc, best)


func _assign_job_to(npc: NPC, meta: Dictionary) -> void:
	npc.employer_meta = meta
	var recipe: Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
	var max_employees: int = max(int(recipe.get("employees", 1)), 1)
	var wages_total: float = float(meta.get("wages_per_day", BusinessDB.wages_for(meta)))
	npc.daily_wage = wages_total / float(max_employees)
	meta["_employee_count"] = int(meta.get("_employee_count", 0)) + 1
	npc.days_unemployed = 0


func _release_job(npc: NPC) -> void:
	if not npc.employer_meta.is_empty():
		npc.employer_meta["_employee_count"] = \
			max(0, int(npc.employer_meta.get("_employee_count", 0)) - 1)
	npc.employer_meta = {}
	npc.daily_wage    = 0.0


func _try_upgrade_job(npc: NPC, employers: Dictionary) -> void:
	var all_candidates: Array = _all_candidates(employers)
	for meta: Dictionary in all_candidates:
		if meta == npc.employer_meta:
			continue
		var recipe:        Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var max_employees: int       = max(int(recipe.get("employees", 1)), 1)
		var wages_total:   float     = float(meta.get("wages_per_day", BusinessDB.wages_for(meta)))
		var new_wage:      float     = wages_total / float(max_employees)
		if new_wage >= npc.daily_wage * UPGRADE_WAGE_THRESHOLD:
			_release_job(npc)
			_assign_job_to(npc, meta)
			return


# =============================================================================
#  Home assignment helpers
# =============================================================================

func _assign_home(npc: NPC, homes: Dictionary) -> void:
	# Re-check capacity live: the index is built once per tick so _tenant_count
	# may have advanced since the index snapshot was taken.
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
	var cap: int         = max(RESIDENTIAL_CAPACITY.get(biz_type, 2), 1)
	# Rent is split equally among the max occupants so price is stable.
	npc.daily_rent = float(meta.get("rent_per_day", 8.0)) / float(cap)
	meta["_tenant_count"] = int(meta.get("_tenant_count", 0)) + 1
	npc.days_unhoused = 0


## Assign a tourist to their nearest available hotel.
func _assign_tourist_hotel(npc: NPC, hotels: Dictionary) -> void:
	var candidates: Array = _candidates_for_npc(npc.district_id, hotels)
	var best: Dictionary = _nearest(candidates, npc.position)
	if best.is_empty():
		return
	npc.home_meta = best
	var biz_type: String = best.get("biz_type", "Hotel")
	var cap: int         = max(HOTEL_CAPACITY.get(biz_type, 10), 1)
	npc.daily_rent       = float(best.get("rent_per_day", 50.0)) / float(cap)
	best["_tenant_count"] = int(best.get("_tenant_count", 0)) + 1


func _release_home(npc: NPC) -> void:
	if not npc.home_meta.is_empty():
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
		var cap: int         = max(RESIDENTIAL_CAPACITY.get(biz_type, 2), 1)
		var new_rent: float  = float(meta.get("rent_per_day", 0.0)) / float(cap)
		# Better home has higher rent but still affordable (< 40 % of wage).
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
		var cap: int         = max(RESIDENTIAL_CAPACITY.get(biz_type, 2), 1)
		var new_rent: float  = float(meta.get("rent_per_day", 0.0)) / float(cap)
		if new_rent < npc.daily_rent:
			_release_home(npc)
			_assign_home_to(npc, meta)
			return


# =============================================================================
#  Utility
# =============================================================================

## Candidates for an NPC: home district first, then city-wide fallback.
func _candidates_for_npc(district_id: int, index: Dictionary) -> Array:
	var local: Array = (index.get(district_id, []) as Array).duplicate()
	if not local.is_empty():
		return local
	return _all_candidates(index)


## Flatten all values in an index into a single array.
func _all_candidates(index: Dictionary) -> Array:
	var result: Array = []
	for key: int in index.keys():
		result.append_array(index[key] as Array)
	return result


# =============================================================================
#  RENT PRESSURE — called at the end of every night tick.
#  Vacant buildings deflate rent so they eventually attract tenants;
#  full buildings inflate slightly.  All current tenants get their daily_rent
#  updated to match the building's new rate.
# =============================================================================
func _tick_rent_pressure() -> void:
	for meta: Dictionary in _all_bldg_metas:
		var prop_type: String = meta.get("property_type", "")
		if prop_type != "Residential" and prop_type != "Hotel":
			continue
		var biz_type: String = meta.get("biz_type", "House")
		var cap: int = max(
			RESIDENTIAL_CAPACITY.get(biz_type, HOTEL_CAPACITY.get(biz_type, 2)), 1)
		var tenants:  int    = int(meta.get("_tenant_count", 0))
		var rent:     float  = float(meta.get("rent_per_day", 8.0))
		if tenants == 0:
			rent = maxf(RENT_MINIMUM, rent * (1.0 - RENT_DEFLATE_VACANT))
		elif tenants < cap / 2.0:
			rent = maxf(RENT_MINIMUM, rent * (1.0 - RENT_DEFLATE_PARTIAL))
		elif tenants >= cap:
			rent *= (1.0 + RENT_INFLATE_FULL)
		meta["rent_per_day"] = rent
	# Propagate the new rent to all current tenants (civilian and tourist).
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


## Return the candidate closest to pos; empty dict if array is empty.
func _nearest(candidates: Array, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for c: Dictionary in candidates:
		var d: float = (c.get("_world_pos", Vector2.ZERO) as Vector2).distance_to(pos)
		if d < best_dist:
			best_dist = d
			best      = c
	return best
