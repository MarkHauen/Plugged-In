extends RefCounted

# =============================================================================
#  WorldData — all static map/district/building/NPC data constants.
#  No Node lifecycle; consumed by City.gd and DistrictGenerator.gd.
# =============================================================================

class_name WorldData

# ── Map dimensions ─────────────────────────────────────────────────────────
const MAP_W := 30000.0
const MAP_H := 24000.0

# ── Road / block geometry ──────────────────────────────────────────────────
const ROAD_W  := 60.0
const BLOCK_W := 480.0
const BLOCK_H := 360.0
const CELL_W  := BLOCK_W + ROAD_W   # 540
const CELL_H  := BLOCK_H + ROAD_W   # 420
const ALLEY   := 100.0              # gap between sub-buildings inside a block

# ── Colours ────────────────────────────────────────────────────────────────
const WATER_COLOR    := Color(0.10, 0.22, 0.45)
const ROAD_COLOR     := Color(0.18, 0.18, 0.20)
const ISLAND_BASE    := Color(0.38, 0.48, 0.30)
const HIGHWAY_COLOR  := Color(0.14, 0.14, 0.16)
const CENTRE_LINE    := Color(0.92, 0.82, 0.08, 0.75)
const ABANDONED_COLOR  := Color(0.30, 0.28, 0.26)
const STOREFRONT_TINT  := Color(0.35, 0.90, 0.72, 1.0)
const ATM_COLOR        := Color(0.95, 0.82, 0.12, 1.0)

# ── Highway patrol count ───────────────────────────────────────────────────
const HIGHWAY_PATROL_COUNT := 10

# ── Island polygon (30 000 × 24 000) ──────────────────────────────────────
static var ISLAND_POLY: PackedVector2Array = PackedVector2Array([
	Vector2(2400, 1440), Vector2(5400, 780), Vector2(9000, 570),
	Vector2(13200, 480), Vector2(16800, 600), Vector2(21000, 960),
	Vector2(24600, 1680), Vector2(27000, 2880), Vector2(28200, 5100),
	Vector2(28500, 8400), Vector2(28200, 12000), Vector2(27300, 15600),
	Vector2(25800, 18900), Vector2(23100, 21300), Vector2(19200, 22800),
	Vector2(15000, 23280), Vector2(10800, 23100), Vector2(7200, 22140),
	Vector2(4500, 19800), Vector2(2700, 16800), Vector2(1740, 12900),
	Vector2(1560, 8700), Vector2(2040, 5520), Vector2(2580, 3300),
	Vector2(2850, 2160),
])

# ── Ordinal strings ─────────────────────────────────────────────────────────
const ORDINALS: Array = [
	"1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th",
	"11th", "12th", "13th", "14th", "15th",
]

# ── District storefront items (ItemDB.ID values per district) ─────────────
const DISTRICT_STOREFRONT_ITEMS: Array = [
	[0, 1, 2, 6, 7],            # 0 Suburbs
	[11, 14, 10, 8, 18],        # 1 Downtown
	[15, 16, 7, 5, 10],         # 2 Industrial
	[17, 2, 11, 12, 3],         # 3 Tourist Strip
	[16, 15, 4, 1, 2],          # 4 Harbor
	[1, 0, 16, 20, 13],         # 5 Slums
	[10, 5, 9, 8, 7],           # 6 Tech Quarter
	[4, 1, 13, 19, 17, 15, 20], # 7 Market District
	[3, 2, 12, 17, 11],         # 8 Beachfront
	[19, 18, 4, 14, 17],        # 9 Old Town
]

const ATM_DISTRICT_IDS: Array = [5, 6, 8]

# ── Business type that produces each retail item (must match BusinessDB.RECIPES) ──
# These are the biz_type strings stamped onto generated storefront buildings.
# Each biz_type must exist in BusinessDB so _try_produce() can fill output_buffer.
const ITEM_SHOP_TYPES: Dictionary = {
	0:  "Beachside Cafe",     # COFFEE          — consumes FOOD_INGREDIENT
	1:  "Street Food",        # STREET_FOOD     — consumes FOOD_INGREDIENT
	2:  "Bar",                # BEER            — consumes FOOD_INGREDIENT
	3:  "Ice Cream Parlour",  # ICE_CREAM       — consumes FOOD_INGREDIENT
	4:  "Spice Shop",         # SPICES          — consumes FOOD_INGREDIENT
	5:  "Electronics Bazaar", # USB_CABLE       — consumes ELECTRONICS_COMPONENT
	6:  "Electronics Bazaar", # PHONE_CASE      — consumes ELECTRONICS_COMPONENT
	7:  "Electronics Bazaar", # CHARGER         — consumes ELECTRONICS_COMPONENT
	8:  "Electronics Bazaar", # HEADPHONES      — consumes ELECTRONICS_COMPONENT
	9:  "Electronics Bazaar", # SIM_CARD        — consumes ELECTRONICS_COMPONENT
	10: "Tech Lab",           # LAPTOP          — consumes ELECTRONICS_COMPONENT
	11: "Tech Lab",           # CAMERA          — consumes ELECTRONICS_COMPONENT
	12: "Surf Shop",          # SUNGLASSES      — no inputs required
	13: "Textile Shop",       # STREETWEAR      — consumes RAW_MATERIAL
	14: "Boutique",           # DESIGNER_BAG    — needs Bank service
	15: "Forge",              # TOOLS           — consumes RAW_MATERIAL
	16: "Pawn Shop",          # SCRAP_METAL     — no inputs required
	17: "Souvenir Shop",      # SOUVENIR        — no inputs required
	18: "Bookshop",           # BOOK            — consumes RAW_MATERIAL
	19: "Antique Shop",       # ANTIQUE         — needs Bank service
	20: "Pawn Shop",          # FAKE_ID         — gray-market, same building as scrap
}

# ── NPC role names per [district_id][npc_type] ─────────────────────────────
const NPC_ROLES: Array = [
	["Resident",   "Officer"       ],   # 0 Suburbs
	["Civilian",   "Officer"       ],   # 1 Downtown
	["Worker",     "Guard"         ],   # 2 Industrial
	["Tourist",    "Officer"       ],   # 3 Tourist Strip
	["Dock Worker","Harbor Police" ],   # 4 Harbor
	["Resident",   "Officer"       ],   # 5 Slums
	["Developer",  "Security"      ],   # 6 Tech Quarter
	["Merchant",   "Officer"       ],   # 7 Market District
	["Vendor",     "Officer"       ],   # 8 Beachfront
	["Elder",      "Officer"       ],   # 9 Old Town
]

# ── Landowner name pools ────────────────────────────────────────────────────
const BIG_OWNER_NAMES: Array = [
	"Reeves Holdings", "The Castillo Group", "Nova Properties", "Meridian Estates",
]
const SMALL_OWNER_NAMES: Array = [
	"J. Park",       "T. Kowalski",     "M. Okonkwo",    "S. Petrov",      "L. Nguyen",
	"D. Ferreira",   "A. Bashir",       "R. Santos",     "K. Osei",        "V. Ivanova",
	"C. Morales",    "H. Tanaka",       "B. Nkrumah",    "E. Vasquez",     "F. Klein",
	"G. Mbuyi",      "I. Szabo",        "N. Chakraborty","P. Olawale",     "Q. Beaumont",
]

# =============================================================================
#  DISTRICTS
# =============================================================================
const DISTRICTS: Array = [
	{"id": 0, "name": "Suburbs",
	  "floor": Color(0.50, 0.65, 0.36), "bldg": Color(0.78, 0.65, 0.52),
	  "ox": 2400, "oy": 1440, "cols": 8, "rows": 6,
	  "police_w": 0.02, "civilian_w": 0.65, "customer_w": 0.25,
	  "pref": [0, 3], "st_name": "Oak St", "ave_name": "Maple Ave",
	  "special_blocks": [{"col": 3, "row": 2, "type": "park"},
						  {"col": 6, "row": 4, "type": "park"}],
	  "mega_blocks": []},
	{"id": 1, "name": "Downtown",
	  "floor": Color(0.40, 0.46, 0.52), "bldg": Color(0.44, 0.50, 0.60),
	  "ox": 7200, "oy": 2160, "cols": 10, "rows": 8,
	  "police_w": 0.02, "civilian_w": 0.30, "customer_w": 0.25,
	  "pref": [1, 4, 2], "st_name": "Commerce St", "ave_name": "Main Ave",
	  "special_blocks": [],
	  "mega_blocks": [{"col": 2, "row": 1, "type": "bank"},
					  {"col": 5, "row": 1, "type": "law_firm"},
					  {"col": 2, "row": 5, "type": "bank"},
					  {"col": 7, "row": 3, "type": "law_firm"}]},
	{"id": 2, "name": "Industrial",
	  "floor": Color(0.42, 0.36, 0.28), "bldg": Color(0.50, 0.44, 0.36),
	  "ox": 1800, "oy": 7200, "cols": 6, "rows": 8,
	  "police_w": 0.02, "civilian_w": 0.55, "customer_w": 0.35,
	  "pref": [0, 4], "st_name": "Factory St", "ave_name": "Mill Ave",
	  "special_blocks": [],
	  "mega_blocks": [{"col": 1, "row": 2, "type": "factory"},
					  {"col": 4, "row": 5, "type": "factory"},
					  {"col": 2, "row": 6, "type": "factory"}]},
	{"id": 3, "name": "Tourist Strip",
	  "floor": Color(0.74, 0.63, 0.44), "bldg": Color(0.82, 0.72, 0.54),
	  "ox": 13200, "oy": 1080, "cols": 8, "rows": 6,
	  "police_w": 0.02, "civilian_w": 0.30, "customer_w": 0.50,
	  "pref": [2, 3, 1], "st_name": "Neon St", "ave_name": "Strip Ave",
	  "special_blocks": [],
	  "mega_blocks": [{"col": 3, "row": 1, "type": "casino"},
					  {"col": 5, "row": 3, "type": "casino"}]},
	{"id": 4, "name": "Harbor",
	  "floor": Color(0.26, 0.35, 0.42), "bldg": Color(0.34, 0.42, 0.50),
	  "ox": 1800, "oy": 14400, "cols": 7, "rows": 6,
	  "police_w": 0.02, "civilian_w": 0.40, "customer_w": 0.50,
	  "pref": [0, 1, 4], "st_name": "Wharf St", "ave_name": "Dock Ave",
	  "special_blocks": [{"col": 0, "row": 4, "type": "port"},
						  {"col": 1, "row": 4, "type": "port"},
						  {"col": 2, "row": 4, "type": "port"},
						  {"col": 3, "row": 4, "type": "port"},
						  {"col": 4, "row": 4, "type": "port"},
						  {"col": 5, "row": 4, "type": "port"},
						  {"col": 6, "row": 4, "type": "port"},
						  {"col": 0, "row": 5, "type": "port"},
						  {"col": 1, "row": 5, "type": "port"},
						  {"col": 2, "row": 5, "type": "port"},
						  {"col": 3, "row": 5, "type": "port"},
						  {"col": 4, "row": 5, "type": "port"},
						  {"col": 5, "row": 5, "type": "port"},
						  {"col": 6, "row": 5, "type": "port"}],
	  "mega_blocks": [{"col": 1, "row": 1, "type": "warehouse"},
					  {"col": 4, "row": 2, "type": "warehouse"}]},
	{"id": 5, "name": "Slums",
	  "floor": Color(0.32, 0.28, 0.22), "bldg": Color(0.40, 0.36, 0.28),
	  "ox": 5500, "oy": 9600, "cols": 5, "rows": 6,
	  "police_w": 0.00, "civilian_w": 0.40, "customer_w": 0.60,
	  "pref": [0, 3], "st_name": "Row", "ave_name": "Alley",
	  "special_blocks": [{"col": 2, "row": 3, "type": "vacant_lot"}],
	  "mega_blocks": []},
	{"id": 6, "name": "Tech Quarter",
	  "floor": Color(0.32, 0.40, 0.50), "bldg": Color(0.38, 0.46, 0.58),
	  "ox": 18000, "oy": 1800, "cols": 9, "rows": 7,
	  "police_w": 0.02, "civilian_w": 0.35, "customer_w": 0.30,
	  "pref": [1, 2, 4], "st_name": "Circuit St", "ave_name": "Silicon Ave",
	  "special_blocks": [{"col": 4, "row": 3, "type": "statue"}],
	  "mega_blocks": [{"col": 1, "row": 1, "type": "tech_campus"},
					  {"col": 6, "row": 5, "type": "tech_campus"}]},
	{"id": 7, "name": "Market District",
	  "floor": Color(0.58, 0.50, 0.36), "bldg": Color(0.66, 0.56, 0.40),
	  "ox": 14400, "oy": 7200, "cols": 8, "rows": 7,
	  "police_w": 0.02, "civilian_w": 0.30, "customer_w": 0.60,
	  "pref": [0, 1, 2, 3, 4], "st_name": "Market St", "ave_name": "Bazaar Ave",
	  "special_blocks": [{"col": 3, "row": 3, "type": "market_square"},
						  {"col": 4, "row": 3, "type": "market_square"}],
	  "mega_blocks": []},
	{"id": 8, "name": "Beachfront",
	  "floor": Color(0.76, 0.70, 0.50), "bldg": Color(0.84, 0.78, 0.60),
	  "ox": 6000, "oy": 18000, "cols": 28, "rows": 5,
	  "police_w": 0.02, "civilian_w": 0.35, "customer_w": 0.50,
	  "pref": [0, 2, 3], "st_name": "Shore St", "ave_name": "Palm Ave",
	  "special_blocks": [{"col": 0,  "row": 4, "type": "beach"},
						  {"col": 1,  "row": 4, "type": "beach"},
						  {"col": 2,  "row": 4, "type": "beach"},
						  {"col": 3,  "row": 4, "type": "beach"},
						  {"col": 4,  "row": 4, "type": "beach"},
						  {"col": 5,  "row": 4, "type": "beach"},
						  {"col": 6,  "row": 4, "type": "beach"},
						  {"col": 7,  "row": 4, "type": "beach"},
						  {"col": 8,  "row": 4, "type": "beach"},
						  {"col": 9,  "row": 4, "type": "beach"},
						  {"col": 10, "row": 4, "type": "beach"},
						  {"col": 11, "row": 4, "type": "beach"},
						  {"col": 12, "row": 4, "type": "beach"},
						  {"col": 13, "row": 4, "type": "beach"},
						  {"col": 14, "row": 4, "type": "beach"},
						  {"col": 15, "row": 4, "type": "beach"},
						  {"col": 16, "row": 4, "type": "beach"},
						  {"col": 17, "row": 4, "type": "beach"},
						  {"col": 18, "row": 4, "type": "beach"},
						  {"col": 19, "row": 4, "type": "beach"},
						  {"col": 20, "row": 4, "type": "beach"},
						  {"col": 21, "row": 4, "type": "beach"},
						  {"col": 22, "row": 4, "type": "beach"},
						  {"col": 23, "row": 4, "type": "beach"},
						  {"col": 24, "row": 4, "type": "beach"},
						  {"col": 25, "row": 4, "type": "beach"},
						  {"col": 26, "row": 4, "type": "beach"},
						  {"col": 27, "row": 4, "type": "beach"}],
	  "mega_blocks": [{"col": 0,  "row": 0, "type": "mega_hotel"},
					  {"col": 1,  "row": 0, "type": "mega_hotel"},
					  {"col": 2,  "row": 0, "type": "mega_hotel"},
					  {"col": 3,  "row": 0, "type": "mega_hotel"},
					  {"col": 4,  "row": 0, "type": "mega_hotel"},
					  {"col": 5,  "row": 0, "type": "mega_hotel"},
					  {"col": 6,  "row": 0, "type": "mega_hotel"},
					  {"col": 7,  "row": 0, "type": "mega_hotel"},
					  {"col": 8,  "row": 0, "type": "mega_hotel"},
					  {"col": 9,  "row": 0, "type": "mega_hotel"},
					  {"col": 10, "row": 0, "type": "mega_hotel"},
					  {"col": 11, "row": 0, "type": "mega_hotel"},
					  {"col": 12, "row": 0, "type": "mega_hotel"},
					  {"col": 13, "row": 0, "type": "mega_hotel"},
					  {"col": 14, "row": 0, "type": "mega_hotel"},
					  {"col": 15, "row": 0, "type": "mega_hotel"},
					  {"col": 16, "row": 0, "type": "mega_hotel"},
					  {"col": 17, "row": 0, "type": "mega_hotel"},
					  {"col": 18, "row": 0, "type": "mega_hotel"},
					  {"col": 19, "row": 0, "type": "mega_hotel"},
					  {"col": 20, "row": 0, "type": "mega_hotel"},
					  {"col": 21, "row": 0, "type": "mega_hotel"},
					  {"col": 22, "row": 0, "type": "mega_hotel"},
					  {"col": 23, "row": 0, "type": "mega_hotel"},
					  {"col": 24, "row": 0, "type": "mega_hotel"},
					  {"col": 25, "row": 0, "type": "mega_hotel"},
					  {"col": 26, "row": 0, "type": "mega_hotel"},
					  {"col": 27, "row": 0, "type": "mega_hotel"}]},
	{"id": 9, "name": "Old Town",
	  "floor": Color(0.48, 0.40, 0.32), "bldg": Color(0.56, 0.46, 0.36),
	  "ox": 22200, "oy": 7200, "cols": 7, "rows": 9,
	  "police_w": 0.02, "civilian_w": 0.45, "customer_w": 0.45,
	  "pref": [0, 3, 1], "st_name": "Cobble St", "ave_name": "Heritage Ave",
	  "special_blocks": [{"col": 2, "row": 3, "type": "town_square"},
						  {"col": 3, "row": 3, "type": "town_square"},
						  {"col": 2, "row": 4, "type": "town_square"},
						  {"col": 3, "row": 4, "type": "town_square"}],
	  "mega_blocks": [{"col": 5, "row": 1, "type": "manor"},
					  {"col": 1, "row": 6, "type": "manor"}]},
]

# =============================================================================
#  PER-DISTRICT BUILDING METADATA CONFIG
# =============================================================================
const DISTRICT_BLDG_CONFIG: Array = [
	# 0 — Suburbs
	{"biz_types": ["House", "Cottage", "Bungalow", "Corner Shop",
					 "Pharmacy", "Bakery", "Nursery"],
	  "prop_types": ["Residential", "Residential", "Residential", "Commercial",
					 "Commercial", "Commercial", "Commercial"],
	  "prefixes": ["Oak", "Maple", "Sunny", "Green", "Quiet",
					 "Hillside", "Garden", "Cedar", "Birch", "Elm"],
	  "price_lo": 30000, "price_hi": 90000,
	  "income_lo": 200, "income_hi": 700,
	  "bldg_size_lo": 0.55, "bldg_size_hi": 0.82,
	  "abandon_chance": 0.00},
	# 1 — Downtown
	{"biz_types": ["Office Tower", "Law Firm", "Bank", "Hotel",
					 "Restaurant", "Boutique", "Gallery", "Insurance Co.", "Flat", "Estate Agency"],
	  "prop_types": ["Office", "Office", "Financial", "Hotel",
					 "Commercial", "Retail", "Cultural", "Financial", "Residential", "Office"],
	  "prefixes": ["Central", "Metro", "Premier", "Elite", "Grand", "City",
					 "Urban", "Apex", "Pinnacle", "Meridian"],
	  "price_lo": 200000, "price_hi": 800000,
	  "income_lo": 2000, "income_hi": 8000,
	  "bldg_size_lo": 0.72, "bldg_size_hi": 0.95,
	  "abandon_chance": 0.00},
	# 2 — Industrial
	{"biz_types": ["Warehouse", "Factory", "Auto Shop", "Scrapyard",
					 "Depot", "Forge", "Mill", "Printing Works"],
	  "prop_types": ["Industrial", "Industrial", "Commercial", "Industrial",
					 "Industrial", "Industrial", "Industrial", "Industrial"],
	  "prefixes": ["Iron", "Steel", "Heavy", "North", "South", "Bay",
					 "River", "Delta", "Summit", "Crown"],
	  "price_lo": 40000, "price_hi": 120000,
	  "income_lo": 300, "income_hi": 1200,
	  "bldg_size_lo": 0.65, "bldg_size_hi": 0.93,
	  "abandon_chance": 0.00},
	# 3 — Tourist Strip
	{"biz_types": ["Casino", "Nightclub", "Hotel", "Bar",
					 "Souvenir Shop", "Arcade", "Lounge", "Show Venue", "Flat"],
	  "prop_types": ["Entertainment", "Entertainment", "Hotel", "Commercial",
					 "Retail", "Entertainment", "Commercial", "Entertainment", "Residential"],
	  "prefixes": ["Neon", "Lucky", "Golden", "Vegas", "Strip", "Glitter",
					 "Sunset", "Electric", "Dazzle", "Jackpot"],
	  "price_lo": 80000, "price_hi": 300000,
	  "income_lo": 800, "income_hi": 3500,
	  "bldg_size_lo": 0.60, "bldg_size_hi": 0.90,
	  "abandon_chance": 0.00},
	# 4 — Harbor
	{"biz_types": ["Warehouse", "Fishery", "Import/Export Co.", "Ship Repair",
					 "Chandlery", "Dockside Bar", "Customs Office", "Cold Store"],
	  "prop_types": ["Industrial", "Commercial", "Commercial", "Industrial",
					 "Commercial", "Commercial", "Government", "Industrial"],
	  "prefixes": ["Blue", "Sea", "Salt", "Dock", "Port", "Wave",
					 "Anchor", "Tidal", "Harbour", "Coastal"],
	  "price_lo": 50000, "price_hi": 180000,
	  "income_lo": 400, "income_hi": 1800,
	  "bldg_size_lo": 0.55, "bldg_size_hi": 0.90,
	  "abandon_chance": 0.00},
	# 5 — Slums
	{"biz_types": ["Flat", "Tenement", "Pawn Shop", "Corner Store",
					 "Laundromat", "Takeaway", "Repair Shop"],
	  "prop_types": ["Residential", "Residential", "Commercial", "Commercial",
					 "Commercial", "Commercial", "Commercial"],
	  "prefixes": ["Old", "Broken", "Grey", "Dark", "Dusty",
					 "Crumbling", "Faded", "Worn", "Rusty", "Dim"],
	  "price_lo": 3000, "price_hi": 18000,
	  "income_lo": 40, "income_hi": 180,
	  "bldg_size_lo": 0.28, "bldg_size_hi": 0.70,
	  "abandon_chance": 0.05},
	# 6 — Tech Quarter
	{"biz_types": ["Tech Lab", "Startup Hub", "Data Centre", "Co-working Space",
					 "Chip Factory", "R&D Campus", "VR Studio", "Server Farm", "Flat"],
	  "prop_types": ["Industrial", "Office", "Industrial", "Office",
					 "Industrial", "Office", "Commercial", "Industrial", "Residential"],
	  "prefixes": ["Nano", "Pixel", "Quantum", "Binary", "Digital",
					 "Cyber", "Neural", "Helix", "Vertex", "Apex"],
	  "price_lo": 150000, "price_hi": 600000,
	  "income_lo": 1500, "income_hi": 6000,
	  "bldg_size_lo": 0.72, "bldg_size_hi": 0.95,
	  "abandon_chance": 0.00},
	# 7 — Market District
	{"biz_types": ["Market Stall", "Street Food", "Import Store", "Electronics Bazaar",
					 "Spice Shop", "Textile Shop", "Jewellers", "Florist", "Flat", "Estate Agency"],
	  "prop_types": ["Retail", "Commercial", "Retail", "Retail",
					 "Retail", "Retail", "Retail", "Commercial", "Residential", "Office"],
	  "prefixes": ["Grand", "Old", "Spice", "East", "West", "Night",
					 "Gold", "Silver", "Silk", "Jade"],
	  "price_lo": 20000, "price_hi": 80000,
	  "income_lo": 200, "income_hi": 1000,
	  "bldg_size_lo": 0.36, "bldg_size_hi": 0.72,
	  "abandon_chance": 0.00},
	# 8 — Beachfront
	{"biz_types": ["Beach Bar", "Resort", "Surf Shop", "Ice Cream Parlour",
					 "Tourist Hotel", "Dive School", "Beachside Cafe", "Sunbed Rental"],
	  "prop_types": ["Commercial", "Hotel", "Retail", "Commercial",
					 "Hotel", "Commercial", "Commercial", "Commercial"],
	  "prefixes": ["Sunny", "Blue", "Wave", "Palm", "Coral",
					 "Breeze", "Sandy", "Reef", "Lagoon", "Horizon"],
	  "price_lo": 60000, "price_hi": 250000,
	  "income_lo": 600, "income_hi": 2500,
	  "bldg_size_lo": 0.50, "bldg_size_hi": 0.82,
	  "abandon_chance": 0.00},
	# 9 — Old Town
	{"biz_types": ["Antique Shop", "Guild Hall", "Manor House", "Inn",
					 "Cobbler", "Jewellers", "Apothecary", "Bookshop", "Estate Agency"],
	  "prop_types": ["Retail", "Cultural", "Residential", "Hotel",
					 "Commercial", "Retail", "Commercial", "Retail", "Office"],
	  "prefixes": ["Old", "Ancient", "Royal", "Grand", "Stone",
					 "Gilded", "Cobbled", "Ivory", "Raven", "Crimson"],
	  "price_lo": 45000, "price_hi": 160000,
	  "income_lo": 350, "income_hi": 1400,
	  "bldg_size_lo": 0.52, "bldg_size_hi": 0.82,
	  "abandon_chance": 0.00},
]

# =============================================================================
#  HIGHWAYS
# =============================================================================
const HIGHWAYS: Array = [
	{"x": 6780,  "y": 2640,  "w": 420,   "h": 120,  "name": "Suburbs → Downtown (E-W)"},
	{"x": 3540,  "y": 4020,  "w": 120,   "h": 3180, "name": "Suburbs → Industrial (N-S)"},
	{"x": 12660, "y": 2640,  "w": 540,   "h": 120,  "name": "Downtown → Tourist Strip (E-W)"},
	{"x": 17580, "y": 2100,  "w": 420,   "h": 120,  "name": "Tourist Strip → Tech Quarter (E-W)"},
	{"x": 7200,  "y": 5580,  "w": 120,   "h": 4020, "name": "Downtown → Slums (N-S)"},
	{"x": 12660, "y": 5460,  "w": 1740,  "h": 120,  "name": "Downtown → Market E-W leg"},
	{"x": 14400, "y": 5460,  "w": 120,   "h": 1740, "name": "Downtown → Market N-S leg"},
	{"x": 18000, "y": 4800,  "w": 120,   "h": 2400, "name": "Tech Quarter → Market (N-S)"},
	{"x": 22500, "y": 4800,  "w": 120,   "h": 2400, "name": "Tech Quarter → Old Town (N-S)"},
	{"x": 22500, "y": 11040, "w": 120,   "h": 10020,"name": "Old Town → South Connector (N-S)"},
	{"x": 18780, "y": 8610,  "w": 3420,  "h": 120,  "name": "Market Dist → Old Town (E-W)"},
	{"x": 3540,  "y": 10620, "w": 120,   "h": 3780, "name": "Industrial → Harbor (N-S)"},
	{"x": 5500,  "y": 12180, "w": 120,   "h": 2220, "name": "Slums → Harbor (N-S)"},
	{"x": 5640,  "y": 16800, "w": 1200,  "h": 120,  "name": "Harbor East Connector (E-W)"},
	{"x": 6720,  "y": 12180, "w": 120,   "h": 5820, "name": "Slums → Beachfront (long N-S)"},
	{"x": 6000,  "y": 780,   "w": 12120, "h": 120,  "name": "North Beltway (E-W)"},
	{"x": 6000,  "y": 780,   "w": 120,   "h": 660,  "name": "North Beltway - Subburb Connector (N-S)"},
	{"x": 18000, "y": 780,   "w": 120,   "h": 1020, "name": "North Beltway (N-S) - Tech Quarter Connector"},
	{"x": 12720, "y": 780,   "w": 120,   "h": 17220,"name": "Central Spine (N-S)"},
	{"x": 26340, "y": 6000,  "w": 120,   "h": 7120, "name": "East Expressway (N-S)"},
	{"x": 3540,  "y": 6000,  "w": 22920, "h": 120,  "name": "Central Ring Road N (E-W)"},
	{"x": 3540,  "y": 13000, "w": 22920, "h": 120,  "name": "Central Ring Road S (E-W)"},
	{"x": 6000,  "y": 20940, "w": 16620, "h": 120,  "name": "South Coastal Road (E-W)"},
	{"x": 6000,  "y": 20160, "w": 120,   "h": 900,  "name": "South Coastal Road - BeachFront Connector 1 (N-S)"},
	{"x": 13000, "y": 20160, "w": 120,   "h": 900,  "name": "South Coastal Road - BeachFront Connector 2 (N-S)"},
	{"x": 21000, "y": 20160, "w": 120,   "h": 900,  "name": "South Coastal Road - BeachFront Connector 3 (N-S)"},
]
