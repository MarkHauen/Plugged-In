extends CanvasLayer
class_name TrendView
## Economy trend line-graph panel.  Toggled via City.gd on the T key.
##
## Each day EconomyManager emits day_started → record_snapshot() is called.
## The graph draws avg / min / max lines for the chosen metric, with a per-
## district overlay when a district is selected.
##
## Metrics tracked per day (economy-wide and per district):
##   wages     — average / min / max daily_wage of operational businesses
##   rents     — average / min / max rent_per_day
##   cash      — average / min / max cash_reserves
##   operating — fraction of businesses that are operational (0-1)
##   inventory — average total items in output_buffer

# ── Constants ─────────────────────────────────────────────────────────────────
const MAX_DAYS  := 60          # rolling window; older days scroll off
const GRAPH_PAD := Vector2(60, 36)   # left / bottom padding for axes

const C_AVG  := Color(0.35, 0.90, 1.00)
const C_MIN  := Color(0.40, 0.60, 0.40, 0.75)
const C_MAX  := Color(1.00, 0.55, 0.25, 0.75)
const C_GRID := Color(1.00, 1.00, 1.00, 0.07)
const C_AXIS := Color(0.55, 0.55, 0.65, 0.60)

const METRICS: Array      = ["wages", "rents", "cash", "operating", "inventory", "npc_balance", "npc_happiness"]
const BLDG_METRICS: Array = ["wages", "rents", "cash", "operating", "inventory"]
const NPC_METRICS:  Array = ["npc_balance", "npc_happiness"]
const METRIC_LABELS: Array = ["Wages", "Rents", "Cash", "Operating%", "Inventory", "NPC Balance", "NPC Happiness%"]

# Colours for per-district lines (cycles through up to 12 districts)
const DISTRICT_PALETTE: Array = [
	Color(1.00, 0.85, 0.30), Color(0.40, 1.00, 0.55), Color(0.90, 0.40, 1.00),
	Color(1.00, 0.45, 0.45), Color(0.35, 0.75, 1.00), Color(1.00, 0.70, 0.30),
	Color(0.55, 1.00, 0.85), Color(1.00, 0.40, 0.75), Color(0.70, 0.70, 1.00),
	Color(0.85, 1.00, 0.40), Color(0.50, 0.85, 0.50), Color(1.00, 0.75, 0.55),
]

# ── Data storage ──────────────────────────────────────────────────────────────
## history[day_idx] = { "wages": {"avg":f,"min":f,"max":f}, "rents":{…}, … }
var _history:   Array  = []   # Array[Dictionary]
var _buildings: Array  = []   # same ref as EconDataView
var _all_npcs:  Array  = []   # Array[NPC] — populated via setup_npcs()

## Per-district history: { district_name: Array[Dictionary] }
var _dist_history: Dictionary = {}

# ── UI references ─────────────────────────────────────────────────────────────
var _graph_node:    Control      = null   # custom-draw graph
var _metric_opts:   OptionButton = null
var _dist_opts:     OptionButton = null
var _mode_opts:     OptionButton = null   # avg / min / max / all
var _day_lbl:       Label        = null
var _built:         bool         = false

var _active_metric: String = "wages"
var _active_dist:   String = ""       # "" = economy-wide
var _active_mode:   String = "avg"    # avg | min | max | all


func _ready() -> void:
	layer   = 22
	visible = false
	EconomyManager.day_started.connect(_on_day_started)


## Called by City.gd after buildings are populated.
func setup(buildings: Array) -> void:
	_buildings = buildings


## Called by City.gd after NPCs are spawned.
func setup_npcs(npcs: Array) -> void:
	_all_npcs = npcs


func toggle() -> void:
	visible = not visible
	if visible:
		if not _built:
			_build_ui()
		_redraw()


func _on_day_started(_day: int) -> void:
	record_snapshot()
	if visible:
		_redraw()


# ── Snapshot collection ────────────────────────────────────────────────────────

func record_snapshot() -> void:
	var snap: Dictionary = {}
	for m: String in METRICS:
		snap[m] = {"avg": 0.0, "min": INF, "max": -INF, "n": 0}

	# Per-district accumulators: { dist: { metric: { avg, min, max, n } } }
	var dist_acc: Dictionary = {}

	# ── Building metrics ──────────────────────────────────────────────────────
	for meta: Dictionary in _buildings:
		if meta.is_empty():
			continue
		var dist: String = meta.get("district", "?")
		if not dist_acc.has(dist):
			var da: Dictionary = {}
			for m: String in METRICS:
				da[m] = {"avg": 0.0, "min": INF, "max": -INF, "n": 0}
			dist_acc[dist] = da

		var wage:  float = float(meta.get("wages_per_day", 0.0))
		var rent:  float = float(meta.get("rent_per_day",  0.0))
		var cash:  float = float(meta.get("cash_reserves", 0.0))
		var is_op: int   = 1 if meta.get("operational", false) else 0
		var inv:   int   = 0
		var obuf: Dictionary = meta.get("output_buffer", {})
		for v: Variant in obuf.values():
			inv += int(v)

		var vals: Dictionary = {
			"wages":     wage,
			"rents":     rent,
			"cash":      cash,
			"operating": float(is_op),
			"inventory": float(inv),
		}
		for m: String in BLDG_METRICS:
			var fv: float = float(vals[m])
			_acc(snap[m], fv)
			_acc(dist_acc[dist][m], fv)

	# ── NPC metrics ───────────────────────────────────────────────────────────
	for npc_node: Variant in _all_npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as NPC
		if npc == null or npc.npc_type != NPC.Type.CIVILIAN:
			continue
		var dist: String = _npc_dist_name(npc.district_id)
		if not dist_acc.has(dist):
			var da: Dictionary = {}
			for m: String in METRICS:
				da[m] = {"avg": 0.0, "min": INF, "max": -INF, "n": 0}
			dist_acc[dist] = da
		_acc(snap["npc_balance"],   npc.balance)
		_acc(snap["npc_happiness"], npc.happy * 100.0)
		_acc(dist_acc[dist]["npc_balance"],   npc.balance)
		_acc(dist_acc[dist]["npc_happiness"], npc.happy * 100.0)

	# ── Finalise & store ──────────────────────────────────────────────────────
	for m: String in METRICS:
		_finalise(snap[m])
	for dist: String in dist_acc.keys():
		for m: String in METRICS:
			_finalise(dist_acc[dist][m])
		if not _dist_history.has(dist):
			_dist_history[dist] = []
		var dh: Array = _dist_history[dist] as Array
		dh.append(dist_acc[dist])
		if dh.size() > MAX_DAYS:
			dh.pop_front()

	_history.append(snap)
	if _history.size() > MAX_DAYS:
		_history.pop_front()


func _acc(d: Dictionary, v: float) -> void:
	d["avg"] = float(d["avg"]) + v
	d["n"]   = int(d["n"]) + 1
	if v < float(d["min"]):
		d["min"] = v
	if v > float(d["max"]):
		d["max"] = v


func _finalise(d: Dictionary) -> void:
	var n: int = int(d["n"])
	if n > 0:
		d["avg"] = float(d["avg"]) / float(n)
	else:
		d["avg"] = 0.0
	if float(d["min"]) == INF:
		d["min"] = 0.0
	if float(d["max"]) == -INF:
		d["max"] = 0.0


## Resolve a district_id to its name for NPC district grouping.
func _npc_dist_name(district_id: int) -> String:
	for d: Dictionary in WorldData.DISTRICTS:
		if int(d.get("id", -1)) == district_id:
			return str(d.get("name", "Unknown"))
	return "Unknown"


# ── UI build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_built = true

	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.06, 0.96)
	add_child(bg)

	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_top",    16)
	mc.add_theme_constant_override("margin_bottom", 16)
	mc.add_theme_constant_override("margin_left",   20)
	mc.add_theme_constant_override("margin_right",  20)
	bg.add_child(mc)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	mc.add_child(outer)

	# ── Title bar ────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)

	var ttl := Label.new()
	ttl.text = "  ECONOMY TRENDS"
	ttl.add_theme_font_size_override("font_size", 15)
	ttl.add_theme_color_override("font_color", Color(1.00, 0.85, 0.38))
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(ttl)

	_day_lbl = Label.new()
	_day_lbl.add_theme_font_size_override("font_size", 12)
	_day_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	_day_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_day_lbl)

	var close_btn := Button.new()
	close_btn.text = "  ✕  Close  [T]  "
	close_btn.pressed.connect(func() -> void: visible = false)
	title_row.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# ── Controls bar ──────────────────────────────────────────────────────
	var cbar := HBoxContainer.new()
	cbar.add_theme_constant_override("separation", 12)
	outer.add_child(cbar)

	# Metric picker
	var ml := Label.new()
	ml.text = "Metric:"
	ml.add_theme_font_size_override("font_size", 12)
	ml.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	cbar.add_child(ml)
	_metric_opts = OptionButton.new()
	for i: int in METRICS.size():
		_metric_opts.add_item(METRIC_LABELS[i])
	_metric_opts.item_selected.connect(func(idx: int) -> void:
		_active_metric = METRICS[idx]
		_redraw()
	)
	cbar.add_child(_metric_opts)

	# District picker
	var dl := Label.new()
	dl.text = "District:"
	dl.add_theme_font_size_override("font_size", 12)
	dl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	cbar.add_child(dl)
	_dist_opts = OptionButton.new()
	_dist_opts.add_item("All (economy-wide)")
	var _seen: Array = []
	for meta: Dictionary in _buildings:
		var d: String = meta.get("district", "")
		if d != "" and d not in _seen:
			_seen.append(d)
	_seen.sort()
	for d: String in _seen:
		_dist_opts.add_item(d)
	_dist_opts.item_selected.connect(func(idx: int) -> void:
		_active_dist = "" if idx == 0 else _dist_opts.get_item_text(idx)
		_redraw()
	)
	cbar.add_child(_dist_opts)

	# Mode picker
	var mml := Label.new()
	mml.text = "Show:"
	mml.add_theme_font_size_override("font_size", 12)
	mml.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	cbar.add_child(mml)
	_mode_opts = OptionButton.new()
	for s: String in ["Average", "Min", "Max", "All three"]:
		_mode_opts.add_item(s)
	_mode_opts.item_selected.connect(func(idx: int) -> void:
		match idx:
			0: _active_mode = "avg"
			1: _active_mode = "min"
			2: _active_mode = "max"
			3: _active_mode = "all"
		_redraw()
	)
	cbar.add_child(_mode_opts)

	# Legend
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 16)
	cbar.add_child(legend)
	_add_legend_item(legend, "Avg", C_AVG)
	_add_legend_item(legend, "Min", C_MIN)
	_add_legend_item(legend, "Max", C_MAX)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbar.add_child(spacer)

	outer.add_child(HSeparator.new())

	# ── Graph canvas ──────────────────────────────────────────────────────
	_graph_node = _GraphCanvas.new(self)
	_graph_node.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_graph_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_graph_node)


func _add_legend_item(parent: HBoxContainer, label: String, col: Color) -> void:
	var swatch := ColorRect.new()
	swatch.color = col
	swatch.custom_minimum_size = Vector2(16, 10)
	parent.add_child(swatch)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", col)
	parent.add_child(lbl)


func _redraw() -> void:
	if _day_lbl != null:
		_day_lbl.text = "%d day(s) recorded" % _history.size()
	if _graph_node != null:
		_graph_node.queue_redraw()


# ── Inner draw class ──────────────────────────────────────────────────────────
## Separated into an inner class so _draw() has access to TrendView state
## without a separate script file.
class _GraphCanvas extends Control:
	var _tv: TrendView

	func _init(tv: TrendView) -> void:
		_tv = tv
		clip_contents = true

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 10.0 or h < 10.0:
			return

		var pad_l: float = TrendView.GRAPH_PAD.x
		var pad_b: float = TrendView.GRAPH_PAD.y
		var gw: float = w - pad_l - 8.0
		var gh: float = h - pad_b - 8.0
		if gw < 2.0 or gh < 2.0:
			return

		var metric: String = _tv._active_metric
		var dist:   String = _tv._active_dist
		var mode:   String = _tv._active_mode

		# Pick history source
		var hist: Array
		if dist == "" or not _tv._dist_history.has(dist):
			hist = _tv._history
		else:
			hist = _tv._dist_history[dist] as Array

		if hist.is_empty():
			draw_string(ThemeDB.fallback_font,
				Vector2(pad_l + gw * 0.5 - 80.0, gh * 0.5),
				"No data yet — wait for day 2", HORIZONTAL_ALIGNMENT_LEFT,
				-1, 13, Color(0.45, 0.45, 0.55))
			return

		# Build value arrays
		var avgs: Array = []
		var mins: Array = []
		var maxs: Array = []
		for snap: Dictionary in hist:
			var entry: Dictionary = snap.get(metric, {"avg": 0.0, "min": 0.0, "max": 0.0})
			avgs.append(float(entry.get("avg", 0.0)))
			mins.append(float(entry.get("min", 0.0)))
			maxs.append(float(entry.get("max", 0.0)))

		# Value range
		var all_vals: Array = avgs + mins + maxs
		var lo: float = all_vals.min() if not all_vals.is_empty() else 0.0
		var hi: float = all_vals.max() if not all_vals.is_empty() else 1.0
		if hi == lo:
			hi = lo + 1.0
		# nice round ceiling
		var range_v: float = hi - lo
		var step: float = _nice_step(range_v / 5.0)
		lo = floor(lo / step) * step
		hi = ceil(hi / step) * step
		if hi == lo:
			hi = lo + step

		# Grid lines + Y-axis labels
		var grid_steps: int = int(round((hi - lo) / step))
		if grid_steps < 1:
			grid_steps = 1
		for gi: int in range(grid_steps + 1):
			var gval: float = lo + float(gi) * step
			var gy: float = gh - (gval - lo) / (hi - lo) * gh + 8.0
			draw_line(Vector2(pad_l, gy), Vector2(pad_l + gw, gy), TrendView.C_GRID, 1.0)
			var lbl_str: String = _fmt_val(gval, metric)
			draw_string(ThemeDB.fallback_font, Vector2(0.0, gy + 4.0),
				lbl_str, HORIZONTAL_ALIGNMENT_LEFT, int(pad_l) - 4, 10, TrendView.C_AXIS)

		# X-axis day labels
		var n: int = hist.size()
		var day_start: int = maxi(1, EconomyManager.day - n + 1)
		var x_step: int = maxi(1, n / 8)
		for xi: int in range(0, n, x_step):
			var xp: float = pad_l + float(xi) / float(maxi(n - 1, 1)) * gw
			draw_line(Vector2(xp, 8.0), Vector2(xp, gh + 8.0), TrendView.C_GRID, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(xp - 10.0, h - 4.0),
				"D%d" % (day_start + xi), HORIZONTAL_ALIGNMENT_LEFT,
				-1, 10, TrendView.C_AXIS)

		# Axes
		draw_line(Vector2(pad_l, 8.0), Vector2(pad_l, gh + 8.0), TrendView.C_AXIS, 1.5)
		draw_line(Vector2(pad_l, gh + 8.0), Vector2(pad_l + gw, gh + 8.0), TrendView.C_AXIS, 1.5)

		# Draw lines
		if mode == "all" or mode == "min":
			_draw_series(mins, lo, hi, gw, gh, pad_l, TrendView.C_MIN, 1.5)
		if mode == "all" or mode == "max":
			_draw_series(maxs, lo, hi, gw, gh, pad_l, TrendView.C_MAX, 1.5)
		if mode == "all" or mode == "avg":
			_draw_series(avgs, lo, hi, gw, gh, pad_l, TrendView.C_AVG, 2.0)

		# Current-value callout
		if not avgs.is_empty():
			var last_avg: float = float(avgs.back())
			var last_min: float = float(mins.back())
			var last_max: float = float(maxs.back())
			var cx: float = pad_l + gw + 4.0
			var cy: float = gh - (last_avg - lo) / (hi - lo) * gh + 8.0
			draw_string(ThemeDB.fallback_font, Vector2(cx - 50.0, cy),
				"avg %s" % _fmt_val(last_avg, metric), HORIZONTAL_ALIGNMENT_LEFT,
				-1, 10, TrendView.C_AVG)
			if mode == "all":
				var cymi: float = gh - (last_min - lo) / (hi - lo) * gh + 8.0
				var cyma: float = gh - (last_max - lo) / (hi - lo) * gh + 8.0
				draw_string(ThemeDB.fallback_font, Vector2(cx - 50.0, cymi + 12.0),
					"min %s" % _fmt_val(last_min, metric), HORIZONTAL_ALIGNMENT_LEFT,
					-1, 10, TrendView.C_MIN)
				draw_string(ThemeDB.fallback_font, Vector2(cx - 50.0, cyma - 6.0),
					"max %s" % _fmt_val(last_max, metric), HORIZONTAL_ALIGNMENT_LEFT,
					-1, 10, TrendView.C_MAX)

	func _draw_series(vals: Array, lo: float, hi: float,
			gw: float, gh: float, pad_l: float,
			col: Color, width: float) -> void:
		var n: int = vals.size()
		if n < 2:
			return
		for i: int in range(1, n):
			var x0: float = pad_l + float(i - 1) / float(n - 1) * gw
			var x1: float = pad_l + float(i)     / float(n - 1) * gw
			var y0: float = 8.0 + gh - (float(vals[i - 1]) - lo) / (hi - lo) * gh
			var y1: float = 8.0 + gh - (float(vals[i])     - lo) / (hi - lo) * gh
			draw_line(Vector2(x0, y0), Vector2(x1, y1), col, width)
			# dot at last point
			if i == n - 1:
				draw_circle(Vector2(x1, y1), 3.0, col)

	func _fmt_val(v: float, metric: String) -> String:
		if metric == "operating":
			return "%.0f%%" % (v * 100.0)
		if metric == "inventory":
			return "%.0f" % v
		return "$%.0f" % v

	func _nice_step(raw: float) -> float:
		if raw <= 0.0:
			return 1.0
		var mag: float = pow(10.0, floor(log(raw) / log(10.0)))
		var norm: float = raw / mag
		if norm < 1.5:
			return 1.0 * mag
		elif norm < 3.5:
			return 2.0 * mag
		elif norm < 7.5:
			return 5.0 * mag
		return 10.0 * mag
