## Inventory — holds a list of items owned by an entity (player, shop, etc.)
## Each item is a Dictionary: { "id": int (ItemDB.ID), "name": String, "price": int, "qty": int }
extends RefCounted

signal changed

var _items: Array[Dictionary] = []


# ── Public API ────────────────────────────────────────────────────────────────

## Add qty of an item by ItemDB.ID. If it already exists, increment qty.
func add(item_id: int, qty: int = 1) -> void:
	var idx := _find(item_id)
	if idx == -1:
		var entry: Dictionary = ItemDB.get_item(item_id)
		_items.append({"id": item_id, "name": entry["name"], "price": entry["base_price"], "qty": qty})
	else:
		_items[idx]["qty"] += qty
	changed.emit()


## Remove qty of an item. Returns true on success, false if not enough stock.
func remove(item_id: int, qty: int = 1) -> bool:
	var idx := _find(item_id)
	if idx == -1 or _items[idx]["qty"] < qty:
		return false
	_items[idx]["qty"] -= qty
	if _items[idx]["qty"] <= 0:
		_items.remove_at(idx)
	changed.emit()
	return true


## Returns a copy of the item list (safe to iterate; do not mutate).
func get_items() -> Array[Dictionary]:
	return _items.duplicate()


## Returns true if the inventory contains at least qty of the given item.
func has(item_id: int, qty: int = 1) -> bool:
	var idx := _find(item_id)
	return idx != -1 and _items[idx]["qty"] >= qty


func count(item_id: int) -> int:
	var idx := _find(item_id)
	return _items[idx]["qty"] if idx != -1 else 0


# ── Private ───────────────────────────────────────────────────────────────────

func _find(item_id: int) -> int:
	for i: int in range(_items.size()):
		if _items[i]["id"] == item_id:
			return i
	return -1
