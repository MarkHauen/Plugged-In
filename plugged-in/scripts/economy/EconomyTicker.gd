extends RefCounted

# =============================================================================
#  EconomyTicker -- thin orchestrator for all economy phases.
#
#  Each phase delegates entirely to specialist subsystems; no business logic
#  lives here.  Wiring points:
#    EconomyManager.phase_changed.connect(ticker.on_economy_phase_changed)
#    EconomyManager.day_started.connect(ticker.on_economy_day_started)
# =============================================================================

class_name EconomyTicker

const GovernmentBudgetScript := preload("res://scripts/economy/GovernmentBudget.gd")
const PayrollSystemScript    := preload("res://scripts/economy/PayrollSystem.gd")
const ProductionSystemScript := preload("res://scripts/economy/ProductionSystem.gd")
const RetailMarketScript     := preload("res://scripts/economy/RetailMarket.gd")
const PropertyManagerScript  := preload("res://scripts/economy/PropertyManager.gd")

var _all_bldg_metas: Array
var _all_npcs:       Array
var _landowners:     Array
var _job_market:     JobMarket
var _housing_market: HousingMarket

var _govt_budget:  GovernmentBudget
var _payroll:      PayrollSystem
var _production:   ProductionSystem
var _retail:       RetailMarket
var _property_mgr: PropertyManager

## Pass-through so existing UI reads of city_treasury still work.
var city_treasury: float:
	get: return _govt_budget.city_treasury

## Pass-through for any future UI read of the effective tax rate.
var effective_tax_rate: float:
	get: return _govt_budget.effective_tax_rate


func _init(all_bldg_metas: Array, all_npcs: Array, landowners: Array,
		   job_market: JobMarket, housing_market: HousingMarket) -> void:
	_all_bldg_metas = all_bldg_metas
	_all_npcs       = all_npcs
	_landowners     = landowners
	_job_market     = job_market
	_housing_market = housing_market
	_govt_budget  = GovernmentBudgetScript.new(all_bldg_metas, all_npcs)
	_payroll      = PayrollSystemScript.new(all_bldg_metas, all_npcs, _govt_budget)
	_production   = ProductionSystemScript.new(all_bldg_metas)
	_retail       = RetailMarketScript.new(all_bldg_metas, all_npcs)
	_property_mgr = PropertyManagerScript.new(all_bldg_metas, landowners)


## Resets rolling income trackers and records NPC balance snapshots.
## Connected to EconomyManager.day_started.
func on_economy_day_started(_day: int) -> void:
	for owner: Dictionary in _landowners:
		owner["income_per_day"] = 0.0
	for npc_node in _all_npcs:
		if is_instance_valid(npc_node):
			(npc_node as NPC).record_daily_snapshot()


## Routes each economy phase to the appropriate subsystem calls.
## Connected to EconomyManager.phase_changed.
func on_economy_phase_changed(phase: int) -> void:
	match phase:
		EconomyManager.Phase.DAWN:  _tick_dawn()
		EconomyManager.Phase.NOON:  _tick_noon()
		EconomyManager.Phase.NIGHT: _tick_night()


# == Phase handlers ===========================================================

func _tick_dawn() -> void:
	_payroll.tick_dawn()


func _tick_noon() -> void:
	_production.run_production_cycle()
	_retail.run_consumer_spending()


func _tick_night() -> void:
	# Supply chain restocked before pricing so fresh stock is priced correctly.
	_production.harbor_restock()
	# Pricing must run before tax so new sell_prices inform building values.
	_retail.update_sell_prices()
	# Wages updated so compute_tax_rate sees current police/civilian costs.
	_payroll.update_building_wages()
	# Tax rate set before collection -- rate and collection are paired each cycle.
	_govt_budget.compute_tax_rate(PayrollSystem.POLICE_DAILY_WAGE)
	_govt_budget.collect_property_taxes()
	_govt_budget.pay_infrastructure_costs()
	# Rent and property management after tax so buildings use post-tax reserves.
	_property_mgr.collect_building_rent()
	_property_mgr.check_property_management()
	_property_mgr.recover_suspended_buildings()
	# NPC life-cycle (rent, hunger, happiness) before welfare + market passes.
	_tick_night_npcs()
	_govt_budget.pay_welfare()
	_job_market.run_night_tick()
	_housing_market.run_night_tick()


# == NPC nightly life-cycle ===================================================
# Kept here (not a subsystem) because it is exactly 3 method calls per NPC.

func _tick_night_npcs() -> void:
	for npc_node in _all_npcs:
		if is_instance_valid(npc_node):
			var npc := npc_node as NPC
			npc.pay_rent()
			npc.tick_hunger()
			npc.tick_happy()
	_cull_tourists()


func _cull_tourists() -> void:
	var i: int = _all_npcs.size() - 1
	while i >= 0:
		var node = _all_npcs[i]
		if not is_instance_valid(node):
			_all_npcs.remove_at(i)
		else:
			var npc := node as NPC
			if npc.npc_type == NPC.Type.TOURIST:
				npc.days_in_city += 1
				if npc.balance <= 10.0 or npc.days_in_city >= 5:
					_housing_market.release_tourist_hotel(npc)
					npc.queue_free()
					_all_npcs.remove_at(i)
		i -= 1
