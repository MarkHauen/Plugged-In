extends RefCounted

# =============================================================================
#  PayrollSystem — handles all wage flows each DAWN phase:
#    • police officers paid from the city treasury
#    • civilians paid from their employer's cash reserves
#    • nightly recomputation of per-building wage bills
#
#  Reason to change: wage policy, payroll timing, or NPC pay structure.
# =============================================================================

class_name PayrollSystem

## Daily wage paid from city treasury to each police officer.
const POLICE_DAILY_WAGE: float = 80.0

var _all_bldg_metas: Array
var _all_npcs:       Array
var _govt_budget:    GovernmentBudget


func _init(all_bldg_metas: Array, all_npcs: Array,
		   govt_budget: GovernmentBudget) -> void:
	_all_bldg_metas = all_bldg_metas
	_all_npcs       = all_npcs
	_govt_budget    = govt_budget


## Pay all NPC wages for the current DAWN phase.
## Police are city employees; civilians are paid by their employer.
func tick_dawn() -> void:
	_pay_police()
	_pay_civilians()


## Recompute each building's wage bill from current output prices, then
## push the updated per-employee wage to all currently employed NPCs.
## Wages naturally rise/fall as goods prices shift.
func update_building_wages() -> void:
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


# ── Private ─────────────────────────────────────────────────────────────────

func _pay_police() -> void:
	for npc_node: NPC in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.POLICE:
			continue
		if npc.daily_wage == 0.0:
			npc.daily_wage = POLICE_DAILY_WAGE
		if _govt_budget.city_treasury >= npc.daily_wage:
			_govt_budget.city_treasury -= npc.daily_wage
			npc.balance                += npc.daily_wage
		# If treasury is dry the officer still works; back-pay is not modelled.


func _pay_civilians() -> void:
	for npc_node: NPC in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc.npc_type != NPC.Type.CIVILIAN or npc.daily_wage <= 0.0:
			continue
		if not npc.employer_meta.is_empty() and npc.employer_meta.get("operational", false):
			var reserves: float = float(npc.employer_meta.get("cash_reserves", 0.0))
			if reserves >= npc.daily_wage:
				npc.employer_meta["cash_reserves"] = reserves - npc.daily_wage
				npc.receive_wage()
			else:
				# Can't cover the wage bill — suspend immediately.
				npc.employer_meta["operational"] = false
