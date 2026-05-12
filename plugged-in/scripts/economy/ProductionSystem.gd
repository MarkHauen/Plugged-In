extends RefCounted

# =============================================================================
#  ProductionSystem — manages the supply chain each NOON and overnight:
#    • harbor restock (overnight ship arrivals)
#    • building production cycles (input → output buffers)
#    • B2B market board (matching producers to consumers)
#
#  Reason to change: supply-chain mechanics, trade rules, or harbor logic.
# =============================================================================

class_name ProductionSystem

## Reference distance for normalising travel cost in the B2B provider score.
const PRICE_REF_DISTANCE: float = 8000.0

var _all_bldg_metas: Array


func _init(all_bldg_metas: Array) -> void:
	_all_bldg_metas = all_bldg_metas


## Run one full NOON production cycle: produce goods then settle B2B trade.
func run_production_cycle() -> void:
	var available_services: Dictionary = {}
	for svc: Dictionary in _all_bldg_metas:
		if svc.get("operational", false) and not (svc["output_buffer"] as Dictionary).is_empty():
			available_services[svc.get("biz_type", "")] = true

	for meta: Dictionary in _all_bldg_metas:
		if meta.get("operational", false):
			_try_produce(meta, available_services)

	_run_market_board()


## Restock harbor importers with overnight ship deliveries.
## Call at the start of the NIGHT phase before pricing/tax.
func harbor_restock() -> void:
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


# ── Private ─────────────────────────────────────────────────────────────────

## Attempt one production cycle for a building.
## Requires sufficient input stock AND all service dependencies to be live.
func _try_produce(meta: Dictionary, available_services: Dictionary) -> void:
	var recipe:  Dictionary = BusinessDB.get_recipe(meta.get("biz_type", ""))
	var inputs:  Dictionary = recipe.get("inputs",  {})
	var outputs: Dictionary = recipe.get("outputs", {})
	if outputs.is_empty():
		return
	var ibuf := meta["input_buffer"] as Dictionary
	for item_id: int in inputs.keys():
		if int(ibuf.get(item_id, 0)) < int(inputs[item_id]):
			return
	for svc: String in recipe.get("services", []):
		if not available_services.get(svc, false):
			return
	for item_id: int in inputs.keys():
		ibuf[item_id] = int(ibuf.get(item_id, 0)) - int(inputs[item_id])
		if int(ibuf.get(item_id, 0)) <= 0:
			ibuf.erase(item_id)
	var obuf := meta["output_buffer"] as Dictionary
	for item_id: int in outputs.keys():
		var produced: int = int(outputs[item_id])
		obuf[item_id] = min(int(obuf.get(item_id, 0)) + produced, produced * 3)


## Match B2B supply to demand: producers' output buffers → consumers' input buffers.
func _run_market_board() -> void:
	# Phase 1 — build supply index: item_id → [{pos, qty, meta, price}]
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
				"pos":   meta.get("_world_pos", Vector2.ZERO),
				"qty":   qty,
				"meta":  meta,
				"price": _get_sell_price(meta, item_id),
			})
	# Phase 2 — match each consumer's shortfalls to the best available provider.
	for consumer: Dictionary in _all_bldg_metas:
		if not consumer.get("operational", false):
			continue
		var recipe: Dictionary = BusinessDB.get_recipe(consumer.get("biz_type", ""))
		var needed: Dictionary = recipe.get("inputs", {})
		if needed.is_empty():
			continue
		var cpos: Vector2 = consumer.get("_world_pos", Vector2.ZERO)
		for item_id: int in needed.keys():
			var cibuf     := consumer["input_buffer"] as Dictionary
			var have:      int = int(cibuf.get(item_id, 0))
			var shortfall: int = int(needed[item_id]) - have
			if shortfall <= 0 or not supply.has(item_id):
				continue
			var providers: Array = supply[item_id]
			# B2B buyers weight proximity more than price (supply security > cost).
			var best_idx: int = _find_best_provider(providers, cpos, item_id, 0.25)
			if best_idx < 0:
				continue
			var provider: Dictionary = providers[best_idx]
			var transfer: int   = mini(shortfall, int(provider["qty"]))
			var cost:     float = float(transfer) * float(provider.get("price", ItemDB.get_base_price(item_id)))
			cibuf[item_id] = have + transfer
			consumer["cash_reserves"] = float(consumer.get("cash_reserves", 0.0)) - cost
			provider["qty"] = int(provider["qty"]) - transfer
			var pmeta := provider["meta"] as Dictionary
			var pobuf := pmeta["output_buffer"] as Dictionary
			pobuf[item_id] = int(pobuf.get(item_id, 0)) - transfer
			if int(pobuf.get(item_id, 0)) <= 0:
				pobuf.erase(item_id)
			pmeta["cash_reserves"] = float(pmeta.get("cash_reserves", 0.0)) + cost


## Returns the best provider index blending proximity and sell price.
## price_weight: 0 = pure nearest, 1 = pure cheapest. Returns -1 if exhausted.
func _find_best_provider(providers: Array, cpos: Vector2,
						 item_id: int, price_weight: float) -> int:
	var base_price: float = float(ItemDB.get_base_price(item_id))
	var best_idx:   int   = -1
	var best_score: float = INF
	for k: int in range(providers.size()):
		if int(providers[k]["qty"]) <= 0:
			continue
		var d: float     = cpos.distance_to(providers[k]["pos"]) / PRICE_REF_DISTANCE
		var p: float     = float(providers[k].get("price", base_price)) / maxf(base_price, 1.0)
		var score: float = d * (1.0 - price_weight) + p * price_weight
		if score < best_score:
			best_score = score
			best_idx   = k
	return best_idx


func _get_sell_price(meta: Dictionary, item_id: int) -> float:
	return float(meta.get("sell_prices", {}).get(item_id, ItemDB.get_base_price(item_id)))
