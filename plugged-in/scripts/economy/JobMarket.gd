extends RefCounted

# =============================================================================
#  JobMarket -- assigns NPCs to employer buildings and manages job mobility.
#  Runs a nightly job-market pass so NPCs can find work, change employer,
#  or be released when a business closes.
#
#  Housing / hotel assignment is handled separately by HousingMarket.
#
#  Usage (City._ready after all districts and NPCs are initialised):
#    var _job_market := JobMarket.new(_all_bldg_metas, _all_npcs)
#    _job_market.assign_initial_jobs()
#
#  EconomyTicker calls run_night_tick() each NIGHT phase.
# =============================================================================

class_name JobMarket

## NPCs check for a better job with this probability each night.
const JOB_UPGRADE_CHANCE:    float = 0.12
## A new job must pay at least this fraction more to be worth switching for.
const UPGRADE_WAGE_THRESHOLD: float = 1.25

var _all_bldg_metas: Array
var _all_npcs:       Array


func _init(all_bldg_metas: Array, all_npcs: Array) -> void:
	_all_bldg_metas = all_bldg_metas
	_all_npcs       = all_npcs


# =============================================================================
#  Initial assignment -- called once after all buildings and NPCs are ready.
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


## Seed each civilian NPC with a realistic starting bank balance.
## Call once after assign_initial_jobs() and HousingMarket.assign_initial_homes()
## so that daily_wage and daily_rent are already populated.
## Balance = 7-21 days of wages, floored at $20 so even the unemployed
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


# =============================================================================
#  Nightly market pass -- called by EconomyTicker._tick_night().
# =============================================================================

func run_night_tick() -> void:
	var employers: Dictionary = _build_employers_index()

	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN:
			continue

		# Employer closed -- release the job.
		if not npc.employer_meta.is_empty():
			if not npc.employer_meta.get("operational", false):
				_release_job(npc)

		if npc.employer_meta.is_empty():
			npc.days_unemployed += 1
			_assign_job(npc, employers)
		elif randf() < JOB_UPGRADE_CHANCE:
			_try_upgrade_job(npc, employers)

	_cull_overstaffed_jobs()


# =============================================================================
#  Index builder
# =============================================================================

## Returns: district_id -> [building metas with remaining employee capacity]
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


# =============================================================================
#  Job assignment helpers
# =============================================================================

func _assign_job(npc: NPC, employers: Dictionary) -> void:
	# Search home district first, then city-wide.
	var raw: Array = _candidates_for_npc(npc.district_id, employers)
	var candidates: Array = []
	for meta: Dictionary in raw:
		var recipe: Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var cap: int = int(recipe.get("employees", 0))
		if int(meta.get("_employee_count", 0)) >= cap:
			continue
		# Financial gate: employer must have at least 7 days of wages in reserve.
		var wage_per_emp: float = float(meta.get("wages_per_day", 0.0)) / float(max(cap, 1))
		if float(meta.get("cash_reserves", 0.0)) < wage_per_emp * 7.0:
			continue
		candidates.append(meta)
	if candidates.is_empty():
		return
	var best: Dictionary = _nearest(candidates, npc.position)
	if best.is_empty():
		return
	_assign_job_to(npc, best)


func _assign_job_to(npc: NPC, meta: Dictionary) -> void:
	var recipe: Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
	var max_employees: int = max(int(recipe.get("employees", 1)), 1)
	if int(meta.get("_employee_count", 0)) >= max_employees:
		return
	npc.employer_meta = meta
	var wages_total: float = float(meta.get("wages_per_day", BusinessDB.wages_for(meta)))
	npc.daily_wage = wages_total / float(max_employees)
	meta["_employee_count"] = int(meta.get("_employee_count", 0)) + 1
	npc.days_unemployed = 0
	npc.log_event("Hired @ %s ($%.0f/day)" % [meta.get("biz_name", "?"), npc.daily_wage])


func _release_job(npc: NPC) -> void:
	if not npc.employer_meta.is_empty():
		npc.log_event("Left job @ %s" % npc.employer_meta.get("biz_name", "?"))
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
		if int(meta.get("_employee_count", 0)) >= max_employees:
			continue
		var wages_total:   float     = float(meta.get("wages_per_day", BusinessDB.wages_for(meta)))
		var new_wage:      float     = wages_total / float(max_employees)
		if new_wage >= npc.daily_wage * UPGRADE_WAGE_THRESHOLD:
			_release_job(npc)
			_assign_job_to(npc, meta)
			return


## Release any NPCs whose employer has more staff than the recipe allows.
func _cull_overstaffed_jobs() -> void:
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN or npc.employer_meta.is_empty():
			continue
		var meta: Dictionary = npc.employer_meta
		var recipe: Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var cap: int = int(recipe.get("employees", 0))
		if cap <= 0 or int(meta.get("_employee_count", 0)) > cap:
			_release_job(npc)


# =============================================================================
#  Shared utility helpers (duplicated in HousingMarket for independence).
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
