extends Node

# =============================================================================
#  BusinessDB — Autoload singleton.
#  Maps every biz_type string (from DISTRICT_BLDG_CONFIG) to an economic recipe.
#
#  Recipe fields:
#    inputs     : {item_id → qty}   items consumed per NOON production tick
#    outputs    : {item_id → qty}   items produced per NOON production tick
#    employees  : int               headcount needed to operate at full capacity
#    services   : Array[String]     biz_type names this building must be supplied by
#    category   : String            determines rent ratio and economic role
#    wage_band  : String            "low" | "mid" | "high" → daily wage per employee
#
#  Supply chain overview:
#    Harbor (Import/Export Co., Warehouse, Fishery, Cold Store)
#      → produces FOOD_INGREDIENT, RAW_MATERIAL, ELECTRONICS_COMPONENT
#    Industrial (Factory, Forge, Scrapyard, Chip Factory …)
#      → transforms raw inputs into finished goods
#    Financial layer (Law Firm → Bank → everyone else)
#      → produces LEGAL_SERVICE and FINANCIAL_SERVICE tokens
#    Retail / Hospitality / Tech
#      → sells finished goods to NPCs
# =============================================================================

## Populated in _ready() using ItemDB.ID values.
var RECIPES: Dictionary = {}

## Daily wage per employee by band (applied once per DAWN tick).
const WAGE_BANDS: Dictionary = {
	"low":  80.0,
	"mid":  120.0,
	"high": 200.0,
}

## Fraction of a building's declared daily income paid as rent (per NIGHT tick).
const RENT_RATIOS: Dictionary = {
	"residential":   0.85,
	"production":    0.20,
	"industrial":    0.18,
	"retail":        0.28,
	"hospitality":   0.25,
	"financial":     0.15,
	"legal":         0.18,
	"tech":          0.15,
	"entertainment": 0.22,
	"government":    0.05,
	"commercial":    0.25,
	"import":        0.20,
	"storage":       0.15,
	"office":        0.18,
}


func _ready() -> void:
	_build_recipes()


func _build_recipes() -> void:
	var I := ItemDB.ID
	RECIPES = {
		# ── Residential ──────────────────────────────────────────────────────
		"House":              _r({}, {},                                            0,  [], "residential", "low"),
		"Cottage":            _r({}, {},                                            0,  [], "residential", "low"),
		"Bungalow":           _r({}, {},                                            0,  [], "residential", "low"),
		"Flat":               _r({}, {},                                            0,  [], "residential", "low"),
		"Tenement":           _r({}, {},                                            0,  [], "residential", "low"),
		"Manor House":        _r({}, {},                                            1,  [], "residential", "mid"),

		# ── Food Production ───────────────────────────────────────────────────
		"Bakery":             _r({I.FOOD_INGREDIENT: 4},    {I.STREET_FOOD: 6},               2, ["Bank"],          "production",  "low"),
		"Fishery":            _r({},                        {I.FOOD_INGREDIENT: 8},           3, [],                "production",  "low"),
		"Takeaway":           _r({I.FOOD_INGREDIENT: 2},    {I.STREET_FOOD: 3},               1, [],                "production",  "low"),
		"Street Food":        _r({I.FOOD_INGREDIENT: 2},    {I.STREET_FOOD: 4},               1, [],                "retail",      "low"),
		"Market Stall":       _r({I.FOOD_INGREDIENT: 2},    {I.SPICES: 2, I.STREET_FOOD: 3}, 1, [],                "retail",      "low"),
		"Spice Shop":         _r({I.FOOD_INGREDIENT: 2},    {I.SPICES: 4},                   1, [],                "retail",      "low"),
		"Apothecary":         _r({I.FOOD_INGREDIENT: 2},    {I.SPICES: 3},                   1, [],                "commercial",  "low"),
		"Florist":            _r({I.FOOD_INGREDIENT: 1},    {},                              1, [],                "commercial",  "low"),
		"Nursery":            _r({I.FOOD_INGREDIENT: 1},    {},                              2, [],                "commercial",  "low"),

		# ── Industrial Production ─────────────────────────────────────────────
		"Scrapyard":          _r({},                        {I.RAW_MATERIAL: 6, I.SCRAP_METAL: 4}, 3, [],          "industrial",  "low"),
		"Depot":              _r({},                        {I.RAW_MATERIAL: 3},             2, [],                "industrial",  "low"),
		"Factory":            _r({I.RAW_MATERIAL: 5},       {I.TOOLS: 3, I.CHARGER: 2},      6, ["Bank"],          "industrial",  "mid"),
		"Forge":              _r({I.RAW_MATERIAL: 4},       {I.TOOLS: 5},                    4, [],                "industrial",  "mid"),
		"Mill":               _r({I.RAW_MATERIAL: 3},       {I.TOOLS: 2},                    3, [],                "industrial",  "mid"),
		"Printing Works":     _r({I.RAW_MATERIAL: 1},       {I.BOOK: 4},                     2, [],                "industrial",  "low"),
		"Chip Factory":       _r({I.RAW_MATERIAL: 3},       {I.ELECTRONICS_COMPONENT: 6},    5, ["Bank"],          "industrial",  "mid"),
		"Auto Shop":          _r({I.RAW_MATERIAL: 2},       {I.TOOLS: 2},                    3, [],                "commercial",  "mid"),
		"Chandlery":          _r({I.RAW_MATERIAL: 2},       {I.TOOLS: 3},                    2, [],                "commercial",  "mid"),
		"Cobbler":            _r({I.RAW_MATERIAL: 1},       {I.STREETWEAR: 1},               1, [],                "commercial",  "low"),
		"Repair Shop":        _r({I.ELECTRONICS_COMPONENT: 1}, {I.USB_CABLE: 2},             1, [],                "commercial",  "low"),
		"Ship Repair":        _r({I.RAW_MATERIAL: 4, I.TOOLS: 2}, {},                        5, [],                "industrial",  "mid"),

		# ── Harbor / Import ───────────────────────────────────────────────────
		"Warehouse":          _r({},                        {I.RAW_MATERIAL: 4, I.FOOD_INGREDIENT: 3}, 3, [],       "import",      "low"),
		"Cold Store":         _r({},                        {I.FOOD_INGREDIENT: 5},          2, [],                "storage",     "low"),
		"Import/Export Co.":  _r({},                        {I.FOOD_INGREDIENT: 10, I.RAW_MATERIAL: 8, I.ELECTRONICS_COMPONENT: 5},
		                                                                                      4, ["Bank", "Law Firm"], "import",   "mid"),
		"Customs Office":     _r({},                        {},                              3, ["Law Firm"],       "government",  "mid"),
		"Dockside Bar":       _r({I.FOOD_INGREDIENT: 2},    {I.BEER: 5},                     2, [],                "hospitality", "low"),

		# ── Financial ─────────────────────────────────────────────────────────
		"Bank":               _r({I.LEGAL_SERVICE: 1},      {I.FINANCIAL_SERVICE: 10},       5, [],                "financial",   "high"),
		"Insurance Co.":      _r({I.FINANCIAL_SERVICE: 1, I.LEGAL_SERVICE: 1},
		                         {I.FINANCIAL_SERVICE: 3},                                   4, ["Bank"],          "financial",   "high"),
		"Server Farm":        _r({I.ELECTRONICS_COMPONENT: 5}, {I.FINANCIAL_SERVICE: 2},     4, ["Bank"],          "tech",        "high"),
		"Bitcoin ATM":        _r({},                        {},                              0, ["Bank"],           "financial",   "high"),

		# ── Legal ─────────────────────────────────────────────────────────────
		"Law Firm":           _r({},                        {I.LEGAL_SERVICE: 8},            4, ["Bank"],          "legal",       "high"),
		"Guild Hall":         _r({},                        {I.LEGAL_SERVICE: 3},            2, [],                "legal",       "mid"),

		# ── Retail ────────────────────────────────────────────────────────────
		"Corner Shop":        _r({I.FOOD_INGREDIENT: 2},    {I.COFFEE: 3, I.USB_CABLE: 2},   1, [],                "retail",      "low"),
		"Corner Store":       _r({I.FOOD_INGREDIENT: 2},    {I.COFFEE: 3, I.STREET_FOOD: 2}, 1, [],                "retail",      "low"),
		"Pharmacy":           _r({},                        {},                              2, ["Bank"],           "retail",      "low"),
		"Boutique":           _r({},                        {I.STREETWEAR: 3, I.DESIGNER_BAG: 2}, 2, ["Bank"],     "retail",      "mid"),
		"Souvenir Shop":      _r({},                        {I.SOUVENIR: 5},                 1, [],                "retail",      "low"),
		"Antique Shop":       _r({},                        {I.ANTIQUE: 3},                  1, ["Bank"],          "retail",      "mid"),
		"Bookshop":           _r({I.RAW_MATERIAL: 1},       {I.BOOK: 4},                     1, [],                "retail",      "low"),
		"Textile Shop":       _r({I.RAW_MATERIAL: 2},       {I.STREETWEAR: 3},               2, [],                "retail",      "low"),
		"Electronics Bazaar": _r({I.ELECTRONICS_COMPONENT: 3},
		                         {I.USB_CABLE: 4, I.CHARGER: 3, I.PHONE_CASE: 2},           2, [],                "retail",      "low"),
		"Jewellers":          _r({I.RAW_MATERIAL: 1},       {I.ANTIQUE: 2},                  2, ["Bank"],          "retail",      "mid"),
		"Import Store":       _r({I.FOOD_INGREDIENT: 1, I.ELECTRONICS_COMPONENT: 1, I.RAW_MATERIAL: 1},
		                         {I.SPICES: 2, I.USB_CABLE: 2, I.TOOLS: 1},                 2, ["Bank"],          "retail",      "mid"),
		"Surf Shop":          _r({},                        {I.SUNGLASSES: 2, I.STREETWEAR: 2}, 2, [],             "retail",      "low"),
		"Pawn Shop":          _r({},                        {I.SCRAP_METAL: 2},              1, [],                "retail",      "low"),
		"Laundromat":         _r({},                        {},                              1, [],                "commercial",  "low"),
		"Gallery":            _r({},                        {I.ANTIQUE: 1},                  2, ["Bank"],          "entertainment","mid"),

		# ── Hospitality ───────────────────────────────────────────────────────
		"Restaurant":         _r({I.FOOD_INGREDIENT: 6},    {I.STREET_FOOD: 8, I.BEER: 4},   4, ["Bank"],          "hospitality", "low"),
		"Bar":                _r({I.FOOD_INGREDIENT: 2},    {I.BEER: 6},                     2, [],                "hospitality", "low"),
		"Beach Bar":          _r({I.FOOD_INGREDIENT: 2},    {I.BEER: 5, I.ICE_CREAM: 2},     2, [],                "hospitality", "low"),
		"Beachside Cafe":     _r({I.FOOD_INGREDIENT: 3},    {I.COFFEE: 5, I.ICE_CREAM: 3},   2, [],                "hospitality", "low"),
		"Ice Cream Parlour":  _r({I.FOOD_INGREDIENT: 2},    {I.ICE_CREAM: 5},                2, [],                "hospitality", "low"),
		"Hotel":              _r({I.FINANCIAL_SERVICE: 1},  {},                              6, ["Bank"],           "hospitality", "mid"),
		"Tourist Hotel":      _r({I.FINANCIAL_SERVICE: 1},  {},                              5, ["Bank"],           "hospitality", "mid"),
		"Resort":             _r({I.FINANCIAL_SERVICE: 1, I.FOOD_INGREDIENT: 4}, {},         8, ["Bank"],           "hospitality", "mid"),
		"Inn":                _r({I.FOOD_INGREDIENT: 2, I.FINANCIAL_SERVICE: 1}, {},         3, ["Bank"],           "hospitality", "mid"),
		"Lounge":             _r({I.FOOD_INGREDIENT: 1},    {I.BEER: 3},                     3, [],                "hospitality", "low"),

		# ── Entertainment ─────────────────────────────────────────────────────
		"Casino":             _r({I.FINANCIAL_SERVICE: 2},  {},                              8, ["Bank", "Law Firm"],"entertainment","mid"),
		"Nightclub":          _r({I.FOOD_INGREDIENT: 2},    {I.BEER: 4},                     5, ["Bank"],           "entertainment","mid"),
		"Arcade":             _r({I.ELECTRONICS_COMPONENT: 1}, {},                           2, [],                "entertainment","low"),
		"Show Venue":         _r({},                        {},                              4, ["Bank"],           "entertainment","mid"),
		"VR Studio":          _r({I.ELECTRONICS_COMPONENT: 2}, {},                           3, ["Bank"],           "tech",        "high"),
		"Dive School":        _r({},                        {},                              2, [],                "commercial",  "mid"),
		"Sunbed Rental":      _r({},                        {},                              1, [],                "commercial",  "low"),

		# ── Tech ─────────────────────────────────────────────────────────────
		"Tech Lab":           _r({I.ELECTRONICS_COMPONENT: 3},
		                         {I.LAPTOP: 2, I.CAMERA: 1},                                5, ["Bank", "Law Firm"],"tech",        "high"),
		"Startup Hub":        _r({I.ELECTRONICS_COMPONENT: 2}, {},                           4, ["Bank"],           "tech",        "high"),
		"Data Centre":        _r({I.ELECTRONICS_COMPONENT: 4}, {},                           3, ["Bank", "Law Firm"],"tech",        "high"),
		"Co-working Space":   _r({},                        {},                              1, ["Bank"],            "commercial",  "mid"),
		"R&D Campus":         _r({I.ELECTRONICS_COMPONENT: 3, I.RAW_MATERIAL: 2},
		                         {I.LAPTOP: 1, I.HEADPHONES: 2},                             6, ["Bank", "Law Firm"],"tech",        "high"),

		# ── Office ────────────────────────────────────────────────────────────
		"Office Tower":       _r({I.FINANCIAL_SERVICE: 1, I.LEGAL_SERVICE: 1},
		                         {I.FINANCIAL_SERVICE: 3},                                  10, ["Bank", "Law Firm"],"office",      "high"),
	}


## Helper to build a recipe dict from positional arguments.
func _r(inputs: Dictionary, outputs: Dictionary, employees: int,
		services: Array, category: String, wage_band: String) -> Dictionary:
	return {
		"inputs":    inputs,
		"outputs":   outputs,
		"employees": employees,
		"services":  services,
		"category":  category,
		"wage_band": wage_band,
	}


## Returns the recipe for biz_type, or a sensible generic fallback if unknown.
## Unknown storefront types (from ITEM_SHOP_TYPES) get the generic retail recipe.
func get_recipe(biz_type: String) -> Dictionary:
	if RECIPES.has(biz_type):
		return RECIPES[biz_type]
	return _r({}, {}, 1, [], "commercial", "low")


## Total daily wages a building owes its workers (called once meta["biz_type"] is set).
func wages_for(meta: Dictionary) -> float:
	var recipe: Dictionary = get_recipe(meta.get("biz_type", ""))
	return float(recipe.get("employees", 0)) * WAGE_BANDS.get(recipe.get("wage_band", "low"), 80.0)


## Daily rent a building owes its landowner (proportional to its declared income).
func rent_for(meta: Dictionary) -> float:
	var recipe: Dictionary = get_recipe(meta.get("biz_type", ""))
	var ratio: float       = RENT_RATIOS.get(recipe.get("category", "commercial"), 0.25)
	return float(meta.get("income", 0)) * ratio
