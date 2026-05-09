extends RefCounted

# =============================================================================
#  EconomyTicker — handles DAWN / NOON / NIGHT economy ticks, the market board,
#  and the harbor restock.  Operates on shared arrays passed at construction.
#
#  Usage:
#    var ticker := EconomyTicker.new(all_bldg_metas, all_npcs, landowners)
#    # Wire signals in City._ready():
#    EconomyManager.phase_changed.connect(ticker.on_economy_phase_changed)
#    EconomyManager.day_started.connect(ticker.on_economy_day_started)
# =============================================================================

class_name EconomyTicker

## Daily property tax as a fraction of a building's market price.
## 0.0001 = 0.01% per day ≈ 3.65% annually.
const PROPERTY_TAX_RATE: float = 0.0001

var _all_bldg_metas: Array   # every building's meta Dictionary, shared with City.gd
var _all_npcs:       Array   # every live NPC node, shared with City.gd
var _landowners:     Array   # landowner Dictionaries: { cash, income_per_day, owned_buildings, … }
var _job_market:     JobMarket
var city_treasury:   float = 0.0   # accumulates property taxes; readable by UI


func _init(all_bldg_metas: Array, all_npcs: Array, landowners: Array,
		   job_market: JobMarket) -> void:
	_all_bldg_metas = all_bldg_metas
	_all_npcs       = all_npcs
	_landowners     = landowners
	_job_market     = job_market


## Called on EconomyManager.day_started signal.
## Resets each landowner's rolling daily income counter so the UI shows
## earnings for the current day only, not a running total.
func on_economy_day_started(_day: int) -> void:
	for owner: Dictionary in _landowners:
		owner["income_per_day"] = 0.0


## Called on EconomyManager.phase_changed signal.
func on_economy_phase_changed(phase: int) -> void:
	match phase:
		EconomyManager.Phase.DAWN:  _tick_dawn()
		EconomyManager.Phase.NOON:  _tick_noon()
		EconomyManager.Phase.NIGHT: _tick_night()


# =============================================================================
#  DAWN — wages flow from employer cash reserves into each NPC's balance.
#         If an employer can't pay it goes operational=false (suspended).
# =============================================================================
func _tick_dawn() -> void:
	for npc_node: NPC in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN or npc.daily_wage <= 0.0:
			continue
		if not npc.employer_meta.is_empty() and npc.employer_meta.get("operational", false):
			var reserves: float = float(npc.employer_meta.get("cash_reserves", 0.0))
			if reserves >= npc.daily_wage:
				# Employer can afford to pay — deduct and credit the NPC.
				npc.employer_meta["cash_reserves"] = reserves - npc.daily_wage
				npc.receive_wage()
			else:
				# Can't cover the wage bill — suspend immediately, wage goes unpaid.
				npc.employer_meta["operational"] = false
		else:
			# No employer or already suspended — NPC earns nothing today.
			pass


# =============================================================================
#  NOON — snapshot available services, run production, settle the B2B market,
#         then restock NPC retail shelves.
# =============================================================================
func _tick_noon() -> void:
	# available_services: biz_type → true for any building that produced output
	# this tick.  Used as a gate: e.g. a Restaurant can only produce if a
	# "Food Supplier" entry exists here, simulating service dependencies.
	var available_services: Dictionary = {}
	for svc: Dictionary in _all_bldg_metas:
		if svc.get("operational", false) and not (svc["output_buffer"] as Dictionary).is_empty():
			available_services[svc.get("biz_type", "")] = true

	for meta: Dictionary in _all_bldg_metas:
		if meta.get("operational", false):
			_try_produce(meta, available_services)

	# B2B trade: move goods from output buffers into buyers' input buffers.
	_run_market_board()


## Attempt one production cycle for a single building.
## Guards: sufficient input stock AND all required service types are live.
## On success, consumes inputs and fills the output buffer (cap: 3× batch).
func _try_produce(meta: Dictionary, available_services: Dictionary) -> void:
	var recipe:  Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
	var inputs:  Dictionary = recipe.get("inputs",  {})  # item_id → qty needed per cycle
	var outputs: Dictionary = recipe.get("outputs", {})  # item_id → qty produced per cycle
	if outputs.is_empty():
		return  # building type produces nothing (e.g. pure residential)
	# ibuf = this building's input stockpile — goods bought from suppliers sit here
	# until a production cycle consumes them.
	var ibuf := meta["input_buffer"] as Dictionary
	for item_id: int in inputs.keys():
		if int(ibuf.get(item_id, 0)) < int(inputs[item_id]):
			return  # short on at least one ingredient — skip this cycle
	for svc: String in recipe.get("services", []):
		if not available_services.get(svc, false):
			return  # a required external service (e.g. Legal) isn't available today
	# All checks passed — consume inputs then fill output buffer.
	for item_id: int in inputs.keys():
		ibuf[item_id] = int(ibuf.get(item_id, 0)) - int(inputs[item_id])
		if int(ibuf.get(item_id, 0)) <= 0:
			ibuf.erase(item_id)
	# obuf = finished goods waiting to be sold on the market board.
	# Capped at 3× one batch so buildings don't hoard indefinitely.
	var obuf := meta["output_buffer"] as Dictionary
	for item_id: int in outputs.keys():
		var produced: int = int(outputs[item_id])
		obuf[item_id] = min(int(obuf.get(item_id, 0)) + produced, produced * 3)


# =============================================================================
#  NIGHT — harbor restock, rent collection, building recovery, NPC ticks,
#          tourist culling, then the nightly job/housing market pass.
# =============================================================================
func _tick_night() -> void:
	_harbor_restock()
	_update_building_wages()
	_collect_property_taxes()
	_collect_building_rent()
	_check_property_management()
	_recover_suspended_buildings()
	_tick_night_npcs()
	_job_market.run_night_tick()


## Deduct property tax from every non-abandoned building and credit the city treasury.
## Tax is based on the building's market price, so prime real estate pays more.
func _collect_property_taxes() -> void:
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("status", "") == "abandoned":
			continue
		var tax: float = float(meta.get("price", 0)) * PROPERTY_TAX_RATE
		if tax <= 0.0:
			continue
		var reserves: float = float(meta.get("cash_reserves", 0.0))
		if reserves < tax:
			# Can't pay tax — suspend the building.
			if meta.get("status", "") != "squatting":
				meta["operational"] = false
			continue
		meta["cash_reserves"] = reserves - tax
		city_treasury += tax


## Gate residential buildings on Property Management token availability.
## If no Estate Agency has produced PROPERTY_MANAGEMENT tokens this cycle,
## residential buildings suspend (tenants can still live there but no new
## assignments are made by JobMarket until service resumes).
func _check_property_management() -> void:
	var pm_available: bool = false
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("biz_type", "") == "Estate Agency" \
				and meta.get("operational", false):
			var obuf := meta.get("output_buffer", {}) as Dictionary
			if int(obuf.get(ItemDB.ID.PROPERTY_MANAGEMENT, 0)) > 0:
				pm_available = true
				break
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("property_type", "") != "Residential":
			continue
		if meta.get("status", "") in ["abandoned", "squatting"]:
			continue
		meta["operational"] = pm_available


## Recompute each building's wage bill from current output prices, then
## push the updated per-employee wage to all currently employed NPCs.
## This means wages naturally rise/fall as goods prices shift.
func _update_building_wages() -> void:
	for meta: Dictionary in _all_bldg_metas:
		meta["wages_per_day"] = BusinessDB.wages_for(meta)
	for npc_node in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN or npc.employer_meta.is_empty():
			continue
		var recipe: Dictionary = BusinessDB.get_recipe(npc.employer_meta.get("biz_type", ""))
		var max_employees: int = max(int(recipe.get("employees", 1)), 1)
		npc.daily_wage = float(npc.employer_meta.get("wages_per_day", 0.0)) / float(max_employees)


## Deduct rent from every building's cash_reserves and credit the landowner.
## NPC home-rent is handled separately by NPC.pay_rent() to keep the flow
## traceable: tenant balance → home reserves → landowner cash.
func _collect_building_rent() -> void:
	for meta: Dictionary in _all_bldg_metas:
		var rent: float = float(meta.get("rent_per_day", 0.0))
		if rent <= 0.0:
			continue
		var reserves: float = float(meta.get("cash_reserves", 0.0))
		if reserves < rent:
			# Can't afford rent — suspend the building, payment skipped.
			if meta.get("status", "") not in ["abandoned", "squatting"]:
				meta["operational"] = false
			continue
		meta["cash_reserves"] = reserves - rent
		# owner_id indexes into _landowners.  -1 means city-owned (no one collects).
		var owner_id: int = int(meta.get("owner_id", -1))
		if owner_id >= 0 and owner_id < _landowners.size():
			var owner: Dictionary = _landowners[owner_id]
			owner["cash"]           = float(owner.get("cash", 0.0)) + rent
			owner["income_per_day"] = float(owner.get("income_per_day", 0.0)) + rent


## Re-enable buildings that were suspended for non-payment once their reserves
## are positive again.  Abandoned / squatted buildings require player action.
func _recover_suspended_buildings() -> void:
	for meta: Dictionary in _all_bldg_metas:
		if not meta.get("operational", false) \
				and float(meta.get("cash_reserves", 0.0)) > 0.0 \
				and meta.get("status", "") not in ["abandoned", "squatting"]:
			meta["operational"] = true


## Advance per-NPC overnight state: pay rent, tick hunger, evict stale tourists.
func _tick_night_npcs() -> void:
	for npc_node: NPC in _all_npcs:
		if is_instance_valid(npc_node):
			(npc_node as NPC).pay_rent()
			(npc_node as NPC).tick_hunger()
	_cull_tourists()


## Remove tourists who have exhausted their budget or overstayed their welcome.
func _cull_tourists() -> void:
	# Iterate backwards so remove_at doesn't shift unvisited indices.
	var i: int = _all_npcs.size() - 1
	while i >= 0:
		var node: Object = _all_npcs[i]
		if not is_instance_valid(node as Object):
			# Node was freed elsewhere (e.g. scene reload) — clean up the stale ref.
			_all_npcs.remove_at(i)
		else:
			var npc := node as NPC
			if npc.npc_type == NPC.Type.TOURIST:
				npc.days_in_city += 1
				# Tourist leaves when broke ($10 threshold) or after 5 days.
				if npc.balance <= 10.0 or npc.days_in_city >= 5:
					_job_market.release_tourist_hotel(npc)
					npc.queue_free()
					_all_npcs.remove_at(i)
		i -= 1


# =============================================================================
#  MARKET BOARD — matches B2B supply to demand each noon tick.
#  Producers that ran this tick have goods in their output buffers; consumers
#  buy from the nearest available supplier at ItemDB base price.
# =============================================================================
func _run_market_board() -> void:
	# Phase 1 — build the supply index.
	# supply: item_id → Array of { pos, qty, meta } for every building
	# that has that item sitting in its output buffer right now.
	var supply: Dictionary = {}
	for meta: Dictionary in _all_bldg_metas:
		if not meta.get("operational", false):
			continue
		var obuf := meta["output_buffer"] as Dictionary  # finished goods ready to sell
		for item_id: int in obuf.keys():
			var qty: int = int(obuf.get(item_id, 0))
			if qty <= 0:
				continue
			if not supply.has(item_id):
				supply[item_id] = []
			(supply[item_id] as Array).append({
				"pos":  meta.get("_world_pos", Vector2.ZERO),
				"qty":  qty,
				"meta": meta,
			})
	# Phase 2 — match each consumer's shortfalls to the nearest supplier.
	for consumer: Dictionary in _all_bldg_metas:
		if not consumer.get("operational", false):
			continue
		var recipe: Dictionary = BusinessDB.get_recipe(consumer.get("biz_type", ""))
		var needed: Dictionary = recipe.get("inputs", {})  # item_id → qty required per cycle
		if needed.is_empty():
			continue  # this building type needs no inputs
		var cpos: Vector2 = consumer.get("_world_pos", Vector2.ZERO)
		for item_id: int in needed.keys():
			var cibuf := consumer["input_buffer"] as Dictionary  # buyer's stockpile
			var have:      int = int(cibuf.get(item_id, 0))
			var shortfall: int = int(needed[item_id]) - have  # how many more units needed
			if shortfall <= 0 or not supply.has(item_id):
				continue
			var providers: Array = supply[item_id]
			var best_idx: int = _find_nearest_provider(providers, cpos)
			if best_idx < 0:
				continue  # no stock anywhere this tick
			var provider: Dictionary = providers[best_idx]
			# Transfer as much of the shortfall as the provider has available.
			var transfer: int   = mini(shortfall, int(provider["qty"]))
			var cost:     float = float(transfer) * float(ItemDB.get_base_price(item_id))
			# Move goods: provider output buffer → consumer input buffer.
			cibuf[item_id] = have + transfer
			consumer["cash_reserves"] = float(consumer.get("cash_reserves", 0.0)) - cost
			provider["qty"] = int(provider["qty"]) - transfer
			# Mirror the reduction into the actual building meta so the next
			# consumer in the loop sees an accurate remaining-stock figure.
			var pmeta := provider["meta"] as Dictionary
			var pobuf := pmeta["output_buffer"] as Dictionary
			pobuf[item_id] = int(pobuf.get(item_id, 0)) - transfer
			if int(pobuf.get(item_id, 0)) <= 0:
				pobuf.erase(item_id)
			pmeta["cash_reserves"] = float(pmeta.get("cash_reserves", 0.0)) + cost


## Returns the index of the nearest provider in the array that still has stock.
## Returns -1 if every provider has been exhausted this tick.
func _find_nearest_provider(providers: Array, cpos: Vector2) -> int:
	var best_idx:  int   = -1
	var best_dist: float = INF
	for k: int in range(providers.size()):
		if int(providers[k]["qty"]) <= 0:
			continue
		var d: float = cpos.distance_to(providers[k]["pos"])
		if d < best_dist:
			best_dist = d
			best_idx  = k
	return best_idx


# =============================================================================
#  HARBOR RESTOCK — simulates overnight ship arrivals.
#  Only buildings in the Harbor district with import-capable biz_types receive
#  free stock each night, representing goods flowing in from outside the island.
#  This is the economy's primary external input — all other goods are produced
#  internally from these raw imports.
# =============================================================================
func _harbor_restock() -> void:
	var harbor_name:  String = WorldData.DISTRICTS[4]["name"]
	# Only these business types receive overnight ship deliveries.
	var import_types: Array  = ["Import/Export Co.", "Warehouse", "Cold Store", "Fishery"]
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("district", "") != harbor_name:
			continue
		if meta.get("biz_type", "") not in import_types:
			continue
		var recipe:  Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var outputs: Dictionary = recipe.get("outputs", {})  # what this importer receives per ship
		var obuf    := meta["output_buffer"] as Dictionary
		for item_id: int in outputs.keys():
			var qty: int = int(outputs[item_id])
			# Cap at 5× one shipment so a neglected importer can't stockpile infinitely.
			obuf[item_id] = min(int(obuf.get(item_id, 0)) + qty, qty * 5)
		# Receiving a shipment is enough to bring an idle importer back online.
		if meta.get("status", "") != "abandoned":
			meta["operational"] = true
