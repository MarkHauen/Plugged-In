extends RefCounted

# =============================================================================
#  PropertyManager — handles real-estate operations each NIGHT:
#    • collecting rent from buildings to their landowners
#    • checking whether abandoned/suspended buildings can be taken over
#    • recovering buildings that have rebuilt their cash reserves
#
#  Reason to change: rent rules, ownership mechanics, or recovery policy.
# =============================================================================

class_name PropertyManager

var _all_bldg_metas: Array
var _landowners:     Array


func _init(all_bldg_metas: Array, landowners: Array) -> void:
	_all_bldg_metas = all_bldg_metas
	_landowners     = landowners


## Transfer the nightly rent from each building's reserves to its landowner.
func collect_building_rent() -> void:
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("status", "") == "abandoned":
			continue
		var rent: float = float(meta.get("daily_rent", 0.0))
		if rent <= 0.0:
			continue
		var reserves: float = float(meta.get("cash_reserves", 0.0))
		if reserves < rent:
			meta["operational"] = false
			continue
		meta["cash_reserves"] = reserves - rent
		var owner_id: int = int(meta.get("owner_id", -1))
		if owner_id < 0:
			continue
		for owner: Dictionary in _landowners:
			if int(owner.get("id", -1)) == owner_id:
				owner["balance"]        = float(owner.get("balance", 0.0)) + rent
				owner["income_per_day"] = float(owner.get("income_per_day", 0.0)) + rent
				break


## Check whether any abandoned building can be acquired cheaply by a landowner.
## A landowner buys a property if their balance covers double the buy price.
func check_property_management() -> void:
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("status", "") != "abandoned":
			continue
		var buy_price: float = float(meta.get("price", 0.0)) * 0.6
		if buy_price <= 0.0:
			continue
		for owner: Dictionary in _landowners:
			var bal: float = float(owner.get("balance", 0.0))
			if bal >= buy_price * 2.0 and randf() < 0.10:
				owner["balance"] = bal - buy_price
				meta["owner_id"] = int(owner.get("id", 0))
				meta["status"]   = "operational"
				meta["cash_reserves"] = float(meta.get("cash_reserves", 0.0)) + buy_price * 0.5
				break


## Allow suspended buildings to resume once reserves rebuild above a threshold.
func recover_suspended_buildings() -> void:
	for meta: Dictionary in _all_bldg_metas:
		if meta.get("operational", true):
			continue
		var status: String = meta.get("status", "")
		if status == "abandoned" or status == "squatting":
			continue
		var reserves: float = float(meta.get("cash_reserves", 0.0))
		var rent:     float = float(meta.get("daily_rent", 0.0))
		var recovery_target: float = rent * 3.0 + float(meta.get("wages_per_day", 0.0))
		if reserves >= recovery_target:
			meta["operational"] = true
