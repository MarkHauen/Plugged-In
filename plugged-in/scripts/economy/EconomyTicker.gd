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

var _all_bldg_metas: Array   # shared ref from City
var _all_npcs:       Array   # shared ref from City
var _landowners:     Array   # shared ref from City
var _job_market:     JobMarket


func _init(all_bldg_metas: Array, all_npcs: Array, landowners: Array,
		   job_market: JobMarket) -> void:
	_all_bldg_metas = all_bldg_metas
	_all_npcs       = all_npcs
	_landowners     = landowners
	_job_market     = job_market


## Called on EconomyManager.day_started signal.
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
		# Deduct from employer reserves
		if not npc.employer_meta.is_empty() and npc.employer_meta.get("operational", false):
			npc.employer_meta["cash_reserves"] = \
					float(npc.employer_meta.get("cash_reserves", 0.0)) - npc.daily_wage
			# Suspend employer if deeply in debt
			if float(npc.employer_meta.get("cash_reserves", 0.0)) \
					< -float(npc.employer_meta.get("price", 1000.0)) * 0.10:
				npc.employer_meta["operational"] = false
		# Credit NPC
		npc.receive_wage()


# =============================================================================
#  NOON — production + services gating + market board
# =============================================================================
func _tick_noon() -> void:
	var available_services: Dictionary = {}
	for _svc: Dictionary in _all_bldg_metas:
		if _svc.get("operational", false) and not (_svc["output_buffer"] as Dictionary).is_empty():
			available_services[_svc.get("biz_type", "")] = true

	for meta: Dictionary in _all_bldg_metas:
		if not meta.get("operational", false):
			continue
		var recipe:  Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var inputs:  Dictionary = recipe.get("inputs",  {})
		var outputs: Dictionary = recipe.get("outputs", {})
		if outputs.is_empty():
			continue
		var can_produce: bool = true
		var ibuf := meta["input_buffer"] as Dictionary
		for item_id: int in inputs.keys():
			if int(ibuf.get(item_id, 0)) < int(inputs[item_id]):
				can_produce = false
				break
		if not can_produce:
			continue
		var req_svcs: Array = recipe.get("services", [])
		if not req_svcs.is_empty():
			var svcs_ok: bool = true
			for svc: String in req_svcs:
				if not available_services.get(svc, false):
					svcs_ok = false
					break
			if not svcs_ok:
				continue
		for item_id: int in inputs.keys():
			ibuf[item_id] = int(ibuf.get(item_id, 0)) - int(inputs[item_id])
			if int(ibuf.get(item_id, 0)) <= 0:
				ibuf.erase(item_id)
		var obuf := meta["output_buffer"] as Dictionary
		for item_id: int in outputs.keys():
			var produced: int = int(outputs[item_id])
			obuf[item_id] = min(int(obuf.get(item_id, 0)) + produced, produced * 3)

	_run_market_board()


# =============================================================================
#  NIGHT — collect rent + building recovery + harbor restock + NPC ticks
# =============================================================================
func _tick_night() -> void:
	_harbor_restock()
	for meta: Dictionary in _all_bldg_metas:
		var rent: float = float(meta.get("rent_per_day", 0.0))
		if rent <= 0.0:
			continue
		meta["cash_reserves"] = float(meta.get("cash_reserves", 0.0)) - rent
		var owner_id: int = int(meta.get("owner_id", -1))
		if owner_id >= 0 and owner_id < _landowners.size():
			var owner: Dictionary = _landowners[owner_id]
			owner["cash"]           = float(owner.get("cash", 0.0)) + rent
			owner["income_per_day"] = float(owner.get("income_per_day", 0.0)) + rent
	for meta: Dictionary in _all_bldg_metas:
		if not meta.get("operational", false) \
				and float(meta.get("cash_reserves", 0.0)) > 0.0 \
				and meta.get("status", "") not in ["abandoned", "squatting"]:
			meta["operational"] = true
	for npc_node: NPC in _all_npcs:
		if is_instance_valid(npc_node):
			(npc_node as NPC).pay_rent()
			(npc_node as NPC).tick_hunger()
	# Remove tourists who have spent their budget or stayed long enough
	var i: int = _all_npcs.size() - 1
	while i >= 0:
		var node: Object = _all_npcs[i]
		if not is_instance_valid(node as Object):
			_all_npcs.remove_at(i)
		else:
			var npc := node as NPC
			if npc.npc_type == NPC.Type.TOURIST:
				npc.days_in_city += 1
				if npc.balance <= 10.0 or npc.days_in_city >= 5:
					npc.queue_free()
					_all_npcs.remove_at(i)
		i -= 1
	# Nightly job and housing market
	_job_market.run_night_tick()


# =============================================================================
#  MARKET BOARD — nearest supplier matching
# =============================================================================
func _run_market_board() -> void:
	var supply: Dictionary = {}
	for meta: Dictionary in _all_bldg_metas:
		if not meta.get("operational", false):
			continue
		var obuf := meta["output_buffer"] as Dictionary
		for item_id: int in obuf.keys():
			var qty: int = int(obuf.get(item_id, 0))
			if qty <= 0:
				continue
			if not supply.has(item_id):
				supply[item_id] = []
			(supply[item_id] as Array).append({
				"pos": meta.get("_world_pos", Vector2.ZERO),
				"qty": qty,
				"meta": meta,
			})
	for consumer: Dictionary in _all_bldg_metas:
		if not consumer.get("operational", false):
			continue
		var recipe: Dictionary = BusinessDB.get_recipe(consumer.get("biz_type", ""))
		var needed: Dictionary = recipe.get("inputs", {})
		if needed.is_empty():
			continue
		var cpos: Vector2 = consumer.get("_world_pos", Vector2.ZERO)
		for item_id: int in needed.keys():
			var cibuf    := consumer["input_buffer"] as Dictionary
			var have:      int   = int(cibuf.get(item_id, 0))
			var shortfall: int   = int(needed[item_id]) - have
			if shortfall <= 0 or not supply.has(item_id):
				continue
			var providers: Array = supply[item_id]
			var best_idx:  int   = -1
			var best_dist: float = INF
			for k: int in range(providers.size()):
				if int(providers[k]["qty"]) <= 0:
					continue
				var d: float = cpos.distance_to(providers[k]["pos"])
				if d < best_dist:
					best_dist = d
					best_idx  = k
			if best_idx < 0:
				continue
			var provider: Dictionary = providers[best_idx]
			var transfer: int   = mini(shortfall, int(provider["qty"]))
			var cost:     float = float(transfer) * float(ItemDB.get_base_price(item_id))
			cibuf[item_id] = have + transfer
			consumer["cash_reserves"] = float(consumer.get("cash_reserves", 0.0)) - cost
			provider["qty"] = int(provider["qty"]) - transfer
			var pmeta := provider["meta"] as Dictionary
			var pobuf := pmeta["output_buffer"] as Dictionary
			pobuf[item_id] = int(pobuf.get(item_id, 0)) - transfer
			if int(pobuf.get(item_id, 0)) <= 0:
				pobuf.erase(item_id)
			pmeta["cash_reserves"] = float(pmeta.get("cash_reserves", 0.0)) + cost


# =============================================================================
#  HARBOR RESTOCK — simulates overnight ship arrivals
# =============================================================================
func _harbor_restock() -> void:
	var harbor_name:  String = WorldData.DISTRICTS[4]["name"]
	var import_types: Array  = ["Import/Export Co.", "Warehouse", "Cold Store", "Fishery"]
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("district", "") != harbor_name:
			continue
		if meta.get("biz_type", "") not in import_types:
			continue
		var recipe:  Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var outputs: Dictionary = recipe.get("outputs", {})
		var obuf    := meta["output_buffer"] as Dictionary
		for item_id: int in outputs.keys():
			var qty: int = int(outputs[item_id])
			obuf[item_id] = min(int(obuf.get(item_id, 0)) + qty, qty * 5)
		if meta.get("status", "") != "abandoned":
			meta["operational"] = true
