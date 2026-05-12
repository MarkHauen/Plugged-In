extends RefCounted

# =============================================================================
#  RetailMarket — manages consumer-facing market activity each NOON:
#    • dynamic sell-price updates based on stock levels (NIGHT phase)
#    • background daily consumption by civilian NPCs
#    • item selection logic per NPC wealth/happiness tier
#
#  Reason to change: consumer behaviour, pricing curves, or shopping logic.
# =============================================================================

class_name RetailMarket

## Fraction of shop score that comes from price vs distance.
## 0 = proximity only, 1 = cheapest only.
const RETAIL_PRICE_WEIGHT: float = 0.45
## Reference distance to normalise travel cost in the score formula.
const PRICE_REF_DISTANCE:  float = 8000.0

var _all_bldg_metas: Array
var _all_npcs:       Array


func _init(all_bldg_metas: Array, all_npcs: Array) -> void:
	_all_bldg_metas = all_bldg_metas
	_all_npcs       = all_npcs


## Run background consumer spending for the current NOON phase.
## Each civilian makes up to three purchases without requiring pathfinding.
func run_consumer_spending() -> void:
	_daily_consumption_tick()


## Reprice every building's retail goods based on stock vs one-batch target.
## Prices drift ≤ 10% per night; clamped to [50%, 220%] of base price.
## Call at the start of NIGHT before tax collection.
func update_sell_prices() -> void:
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("status", "") == "abandoned":
			continue
		var recipe:  Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
		var outputs: Dictionary = recipe.get("outputs", {})
		if outputs.is_empty():
			continue
		if not meta.has("sell_prices"):
			meta["sell_prices"] = {}
		var prices: Dictionary = meta["sell_prices"]
		var obuf:   Dictionary = meta["output_buffer"]
		for item_id: int in outputs.keys():
			if ItemDB.is_intermediate(item_id):
				continue
			var base:    float = float(ItemDB.get_base_price(item_id))
			var batch:   int   = int(outputs[item_id])
			var stock:   int   = int(obuf.get(item_id, 0))
			var ratio:   float = float(stock) / maxf(float(batch), 1.0)
			var current: float = float(prices.get(item_id, base))
			if ratio > 2.0:
				current = lerpf(current, base * 0.55, 0.10)
			elif ratio > 1.0:
				current = lerpf(current, base * 0.80, 0.06)
			elif ratio < 0.25:
				current = lerpf(current, base * 2.10, 0.10)
			elif ratio < 0.75:
				current = lerpf(current, base * 1.35, 0.06)
			else:
				current = lerpf(current, base, 0.04)
			prices[item_id] = clampf(current, base * 0.50, base * 2.20)


## Returns the current dynamic sell price for item_id at a building.
## Falls back to ItemDB base price before prices are initialised.
func get_sell_price(meta: Dictionary, item_id: int) -> float:
	return float(meta.get("sell_prices", {}).get(item_id, ItemDB.get_base_price(item_id)))


# ── Private ─────────────────────────────────────────────────────────────────

func _daily_consumption_tick() -> void:
	# Identify top-15% wage earners for the elite spending tier.
	var wages: Array = []
	for npc_node: NPC in _all_npcs:
		if is_instance_valid(npc_node):
			var npc := npc_node as NPC
			if npc.npc_type == NPC.Type.CIVILIAN and npc.daily_wage > 0.0:
				wages.append(npc.daily_wage)
	wages.sort()
	var top15_threshold: float = 0.0
	if wages.size() > 0:
		var cutoff_idx: int = int(float(wages.size()) * 0.85)
		top15_threshold = float(wages[mini(cutoff_idx, wages.size() - 1)])

	# Build retail supply snapshot: item_id → [building metas with stock]
	var supply: Dictionary = {}
	for meta: Dictionary in _all_bldg_metas:
		if not meta.get("operational", false):
			continue
		var obuf := meta["output_buffer"] as Dictionary
		for item_id: int in obuf.keys():
			if int(obuf.get(item_id, 0)) <= 0 or ItemDB.is_intermediate(item_id):
				continue
			if not supply.has(item_id):
				supply[item_id] = []
			(supply[item_id] as Array).append(meta)

	for npc_node: NPC in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN:
			continue

		var is_hungry: bool = npc.hunger >= NPC.HUNGER_THRESHOLD
		if is_hungry:
			if npc.balance < 0.50:
				continue
		else:
			if npc.balance < npc.daily_rent * 2.5:
				continue
			if randf() > 0.55:
				continue

		var item_id: int = _pick_daily_item(npc, supply)
		if item_id < 0 or not supply.has(item_id):
			continue

		var best_meta: Dictionary = _best_store(npc.position, supply[item_id], item_id)
		if best_meta.is_empty():
			continue
		var price: float = get_sell_price(best_meta, item_id)
		if npc.balance < price:
			continue

		_execute_purchase(npc, best_meta, item_id, price)

		# Rich NPCs make a bonus food purchase on top of their main buy.
		var is_rich: bool = npc.daily_wage > 0.0 and npc.balance > npc.daily_wage * 30.0
		if is_rich and item_id not in [0, 1, 2, 3, 28, 29]:
			_try_bonus_purchase(npc, supply, [28, 29, 0, 1, 3])

		# Top-15% earners make a guaranteed extra lifestyle purchase.
		if top15_threshold > 0.0 and npc.daily_wage >= top15_threshold \
				and npc.balance > npc.daily_rent * 5.0:
			_try_bonus_purchase(npc, supply, [29, 28, 14, 11, 10, 8, 13, 19, 12, 18, 17, 3, 2])


## Find the highest-scoring store for item_id based on proximity and price.
func _best_store(buyer_pos: Vector2, stores: Array, item_id: int) -> Dictionary:
	var best_meta:  Dictionary = {}
	var best_score: float      = INF
	var base_p:     float      = float(ItemDB.get_base_price(item_id))
	for meta: Dictionary in stores:
		if int((meta["output_buffer"] as Dictionary).get(item_id, 0)) <= 0:
			continue
		var d: float     = buyer_pos.distance_to(meta.get("_world_pos", Vector2.ZERO)) / PRICE_REF_DISTANCE
		var p: float     = get_sell_price(meta, item_id) / maxf(base_p, 1.0)
		var score: float = d * (1.0 - RETAIL_PRICE_WEIGHT) + p * RETAIL_PRICE_WEIGHT
		if score < best_score:
			best_score = score
			best_meta  = meta
	return best_meta


## Deduct stock and cash, then apply hunger/happiness side-effects.
func _execute_purchase(npc: NPC, store: Dictionary, item_id: int, price: float) -> void:
	var obuf := store["output_buffer"] as Dictionary
	var qty: int = int(obuf.get(item_id, 0))
	if qty <= 1:
		obuf.erase(item_id)
	else:
		obuf[item_id] = qty - 1
	store["cash_reserves"] = float(store.get("cash_reserves", 0.0)) + price
	npc.balance -= price
	if item_id in [0, 1, 2, 3]:
		npc.hunger = maxf(0.0, npc.hunger - 0.25)
	if item_id in [28, 29]:
		npc.happy = minf(1.0, npc.happy + 0.30)
		npc._update_unhappy_tint()
	elif item_id in [2, 3]:
		npc.happy = minf(1.0, npc.happy + 0.08)
	npc._update_struggling_tint()


## Attempt one extra purchase from a prioritised list of item IDs.
func _try_bonus_purchase(npc: NPC, supply: Dictionary, priority_ids: Array) -> void:
	var ids := priority_ids.duplicate()
	ids.shuffle()
	for fid: int in ids:
		if not supply.has(fid):
			continue
		var store: Dictionary = _best_store(npc.position, supply[fid], fid)
		if store.is_empty():
			continue
		var price: float = get_sell_price(store, fid)
		if npc.balance < price:
			continue
		_execute_purchase(npc, store, fid, price)
		break


## Choose the best item for an NPC's daily routine purchase.
func _pick_daily_item(npc: NPC, supply: Dictionary) -> int:
	var is_rich: bool = npc.daily_wage > 0.0 and npc.balance > npc.daily_wage * 30.0

	# 1. Hunger relief — always highest priority.
	if npc.hunger >= NPC.HUNGER_THRESHOLD:
		var food_ids: Array = [1, 0, 3, 2]
		food_ids.shuffle()
		for id: int in food_ids:
			if supply.has(id):
				return id

	# 2. Rich NPCs: consumer goods first (bonus food slot handled separately).
	if is_rich:
		var consumer_ids: Array = [8, 10, 11, 12, 13, 14, 17, 18, 19, 28, 29]
		consumer_ids.shuffle()
		for id: int in consumer_ids:
			if supply.has(id) and ItemDB.get_base_price(id) <= int(npc.balance * 0.15):
				return id

	# 3. Happiness boost when unhappy and not financially stretched.
	if npc.happy < NPC.HAPPY_THRESHOLD and npc.balance > npc.daily_rent * 4.0:
		var luxury_ids: Array = [28, 29, 2, 3]
		luxury_ids.shuffle()
		for id: int in luxury_ids:
			if supply.has(id):
				return id

	# 4. Routine treat.
	var routine_ids: Array = [0, 1, 3, 2]
	routine_ids.shuffle()
	for id: int in routine_ids:
		if supply.has(id):
			return id
	return -1
