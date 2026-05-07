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
	"House":        2,
	"Cottage":      2,
	"Bungalow":     2,
	"Flat":         4,
	"Tenement":     6,
	"Manor House":  3,
}

# Residential biz_types (buildings that provide homes, not jobs).
const RESIDENTIAL_TYPES: Array = [
	"House", "Cottage", "Bungalow", "Flat", "Tenement", "Manor House",
]

# NPCs check for a better job with this probability each night.
const JOB_UPGRADE_CHANCE    := 0.12
# NPCs check for better housing with this probability when doing well.
const HOUSING_UPGRADE_CHANCE := 0.08
# NPCs try to downgrade housing with this probability when struggling.
const HOUSING_DOWNGRADE_CHANCE := 0.15
# A new job must pay at least this fraction more to be worth switching for.
const UPGRADE_WAGE_THRESHOLD := 1.25

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
	var candidates: Array = _candidates_for_npc(npc.district_id, employers)
	if candidates.is_empty():
		return
	var best: Dictionary = _nearest(candidates, npc.position)
	if best.is_empty():
		return
	_assign_job_to(npc, best)


func _assign_job_to(npc: NPC, meta: Dictionary) -> void:
	npc.employer_meta = meta
	var recipe: Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
	npc.daily_wage = BusinessDB.WAGE_BANDS.get(recipe.get("wage_band", "low"), 80.0)
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
		var recipe:    Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var new_wage:  float = BusinessDB.WAGE_BANDS.get(recipe.get("wage_band", "low"), 80.0)
		if new_wage >= npc.daily_wage * UPGRADE_WAGE_THRESHOLD:
			_release_job(npc)
			_assign_job_to(npc, meta)
			return


# =============================================================================
#  Home assignment helpers
# =============================================================================

func _assign_home(npc: NPC, homes: Dictionary) -> void:
	var candidates: Array = _candidates_for_npc(npc.district_id, homes)
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
