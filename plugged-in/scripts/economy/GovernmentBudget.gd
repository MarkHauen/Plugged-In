extends RefCounted

# =============================================================================
#  GovernmentBudget — owns the city treasury and all fiscal policy:
#    • dynamic property-tax rate computation
#    • tax collection from buildings
#    • fixed infrastructure costs
#    • welfare disbursements to struggling civilians
#
#  Reason to change: government economic policy or treasury mechanics.
# =============================================================================

class_name GovernmentBudget

## Fixed daily infrastructure / road-maintenance cost charged to the treasury.
const ROAD_MAINTENANCE_PER_DAY: float = 100.0
## Treasury cushion the dynamic tax rate aims to maintain.
const GOVT_RESERVE_TARGET:      float = 2000.0
## Minimum tax rate — charged even when the city is flush.
const GOVT_TAX_MIN_RATE:        float = 0.000025
## Hard ceiling so no single night's tax bill can bankrupt a building.
const GOVT_TAX_MAX_RATE:        float = 0.008
## Fraction of any treasury shortfall to recover per day (smooth ramp-up).
const GOVT_DEFICIT_CATCHUP:     float = 0.25
## Flat cash payment given each NIGHT to civilians who are unhoused or struggling.
const WELFARE_PAYMENT:          float = 25.0
## Treasury must hold at least this much before welfare is disbursed.
const WELFARE_TREASURY_MIN:     float = 500.0

## Readable by UI.
var city_treasury:    float = 0.0
var effective_tax_rate: float = 0.0001

var _last_welfare_paid: float = 0.0

var _all_bldg_metas: Array
var _all_npcs:       Array


func _init(all_bldg_metas: Array, all_npcs: Array) -> void:
	_all_bldg_metas = all_bldg_metas
	_all_npcs       = all_npcs


## Recompute effective_tax_rate to cover tonight's estimated government expenses.
## Must be called before collect_property_taxes().
## police_daily_wage is passed in from PayrollSystem to avoid a circular reference.
func compute_tax_rate(police_daily_wage: float) -> void:
	var police_count: int = 0
	for npc_node: NPC in _all_npcs:
		if is_instance_valid(npc_node):
			if (npc_node as NPC).npc_type == NPC.Type.POLICE:
				police_count += 1
	var police_cost: float = float(police_count) * police_daily_wage

	var est_cost: float = police_cost + _last_welfare_paid + ROAD_MAINTENANCE_PER_DAY
	var deficit:  float = maxf(0.0, GOVT_RESERVE_TARGET - city_treasury)
	var target:   float = est_cost + deficit * GOVT_DEFICIT_CATCHUP

	var total_value: float = 0.0
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("status", "") != "abandoned":
			total_value += float(meta.get("price", 0))

	if total_value > 0.0:
		effective_tax_rate = clampf(
			target / total_value, GOVT_TAX_MIN_RATE, GOVT_TAX_MAX_RATE)


## Deduct property tax from every non-abandoned building; credit the treasury.
func collect_property_taxes() -> void:
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("status", "") == "abandoned":
			continue
		var tax: float = float(meta.get("price", 0)) * effective_tax_rate
		if tax <= 0.0:
			continue
		var reserves: float = float(meta.get("cash_reserves", 0.0))
		if reserves < tax:
			if meta.get("status", "") != "squatting":
				meta["operational"] = false
			continue
		meta["cash_reserves"] = reserves - tax
		city_treasury += tax


## Deduct fixed infrastructure costs from the treasury.
## Call after collect_property_taxes() so fresh revenue absorbs the bill.
func pay_infrastructure_costs() -> void:
	city_treasury = maxf(0.0, city_treasury - ROAD_MAINTENANCE_PER_DAY)


## Pay welfare to civilians who are unhoused or struggling.
## Tracks total paid so compute_tax_rate() can estimate next night's cost.
func pay_welfare() -> void:
	_last_welfare_paid = 0.0
	if city_treasury < WELFARE_TREASURY_MIN:
		return
	for npc_node: NPC in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN:
			continue
		var unhoused:   bool = npc.home_meta.is_empty()
		var struggling: bool = npc._is_struggling
		if not (unhoused or struggling):
			continue
		if city_treasury < WELFARE_TREASURY_MIN:
			break
		npc.balance        += WELFARE_PAYMENT
		npc.log_event("Welfare +$%.0f  -> $%.0f" % [WELFARE_PAYMENT, npc.balance])
		_last_welfare_paid += WELFARE_PAYMENT
		city_treasury      -= WELFARE_PAYMENT
		npc._update_struggling_tint()
