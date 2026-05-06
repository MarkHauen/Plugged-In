extends RefCounted

class_name Wallet

enum Currency { CASH, BITCOIN }

signal changed

# Balances keyed by Currency enum value.
# CASH    — whole dollars (stored as float, displayed as int)
# BITCOIN — BTC units up to 8 decimal places
var _balances: Dictionary = {}


func _init() -> void:
	_balances[Currency.CASH]    = 0.0
	_balances[Currency.BITCOIN] = 0.0


# ── Public API ────────────────────────────────────────────────────────────────

func add(currency: Currency, amount: float) -> void:
	_balances[currency] = _balances[currency] + amount
	changed.emit()


## Returns false and makes no change if funds are insufficient.
func remove(currency: Currency, amount: float) -> bool:
	if _balances[currency] < amount:
		return false
	_balances[currency] = _balances[currency] - amount
	changed.emit()
	return true


func get_balance(currency: Currency) -> float:
	return _balances[currency]


## Returns a display string for the given currency.
func format(currency: Currency) -> String:
	match currency:
		Currency.CASH:
			return "$%d" % int(_balances[currency])
		Currency.BITCOIN:
			return "\u20bf%.8f" % _balances[currency]
		_:
			return str(_balances[currency])
