extends Node

enum ID {
	# ── Food & Drink ──────────────────────────────────────────────────
	COFFEE,        # 0
	STREET_FOOD,   # 1
	BEER,          # 2
	ICE_CREAM,     # 3
	SPICES,        # 4
	# ── Electronics ──────────────────────────────────────────────────
	USB_CABLE,     # 5
	PHONE_CASE,    # 6
	CHARGER,       # 7
	HEADPHONES,    # 8
	SIM_CARD,      # 9
	LAPTOP,        # 10
	CAMERA,        # 11
	# ── Clothing & Accessories ────────────────────────────────────────
	SUNGLASSES,    # 12
	STREETWEAR,    # 13
	DESIGNER_BAG,  # 14
	# ── Hardware & Industrial ─────────────────────────────────────────
	TOOLS,         # 15
	SCRAP_METAL,   # 16
	# ── Collectibles & Media ──────────────────────────────────────────
	SOUVENIR,      # 17
	BOOK,          # 18
	ANTIQUE,       # 19
	# ── Gray Market ───────────────────────────────────────────────────
	FAKE_ID,       # 20
	# ── Perishables (player-sourced only) ────────────────────────────
	FLOWER,        # 21
	# ── Intermediate Goods (B2B; hidden in retail UI by default) ─────
	FOOD_INGREDIENT,        # 22
	ELECTRONICS_COMPONENT,  # 23
	RAW_MATERIAL,           # 24
	FINANCIAL_SERVICE,      # 25
	LEGAL_SERVICE,          # 26
}

## item_id (ItemDB.ID) → { "name": String, "base_price": int }
const CATALOG: Dictionary = {
	# Food & Drink
	ID.COFFEE:       { "name": "Coffee",       "base_price": 5   },
	ID.STREET_FOOD:  { "name": "Street Food",  "base_price": 3   },
	ID.BEER:         { "name": "Beer",         "base_price": 8   },
	ID.ICE_CREAM:    { "name": "Ice Cream",    "base_price": 4   },
	ID.SPICES:       { "name": "Spices",       "base_price": 7   },
	# Electronics
	ID.USB_CABLE:    { "name": "USB Cable",    "base_price": 12  },
	ID.PHONE_CASE:   { "name": "Phone Case",   "base_price": 18  },
	ID.CHARGER:      { "name": "Charger",      "base_price": 22  },
	ID.HEADPHONES:   { "name": "Headphones",   "base_price": 35  },
	ID.SIM_CARD:     { "name": "SIM Card",     "base_price": 15  },
	ID.LAPTOP:       { "name": "Laptop",       "base_price": 350 },
	ID.CAMERA:       { "name": "Camera",       "base_price": 120 },
	# Clothing & Accessories
	ID.SUNGLASSES:   { "name": "Sunglasses",   "base_price": 25  },
	ID.STREETWEAR:   { "name": "Streetwear",   "base_price": 40  },
	ID.DESIGNER_BAG: { "name": "Designer Bag", "base_price": 180 },
	# Hardware & Industrial
	ID.TOOLS:        { "name": "Tools",        "base_price": 28  },
	ID.SCRAP_METAL:  { "name": "Scrap Metal",  "base_price": 6   },
	# Collectibles & Media
	ID.SOUVENIR:     { "name": "Souvenir",     "base_price": 12  },
	ID.BOOK:         { "name": "Book",         "base_price": 15  },
	ID.ANTIQUE:      { "name": "Antique",      "base_price": 90  },
	# Gray Market
	ID.FAKE_ID:      { "name": "Fake ID",      "base_price": 60  },
	# Perishables
	ID.FLOWER:       { "name": "Flower",       "base_price": 18  },
	# Intermediate Goods — B2B only; never sold at retail storefronts
	ID.FOOD_INGREDIENT:        { "name": "Food Ingredient",        "base_price": 2,  "intermediate": true },
	ID.ELECTRONICS_COMPONENT:  { "name": "Electronics Component",  "base_price": 8,  "intermediate": true },
	ID.RAW_MATERIAL:           { "name": "Raw Material",           "base_price": 3,  "intermediate": true },
	ID.FINANCIAL_SERVICE:      { "name": "Financial Service",      "base_price": 50, "intermediate": true },
	ID.LEGAL_SERVICE:          { "name": "Legal Service",          "base_price": 75, "intermediate": true },
}


func get_item(item_id: int) -> Dictionary:
	return CATALOG[item_id]


func get_item_name(item_id: int) -> String:
	return CATALOG[item_id]["name"]


func get_base_price(item_id: int) -> int:
	return CATALOG[item_id]["base_price"]


## Returns all registered item IDs.
func all_ids() -> Array:
	return CATALOG.keys()


## Returns true if item_id is an intermediate (B2B) good.
func is_intermediate(item_id: int) -> bool:
	return CATALOG[item_id].get("intermediate", false)


## Returns all IDs suitable for retail storefronts (excludes intermediate goods).
## Used by NPCs when randomly choosing a shopping target.
func retail_ids() -> Array:
	var result: Array = []
	for id: int in CATALOG.keys():
		if not CATALOG[id].get("intermediate", false):
			result.append(id)
	return result
