extends CanvasLayer

## ClockUI — persistent HUD clock widget.
## Displays the current game day, phase name (colour-coded), and a smooth
## progress bar that tracks progress through the full day.
## Phase divider marks at 25 / 50 / 75 % show when each phase ends.

const PHASE_NAMES: Array  = ["DAWN", "NOON", "DUSK", "NIGHT"]
const PHASE_COLORS: Array = [
	Color(1.00, 0.85, 0.30),   # DAWN  — gold
	Color(1.00, 1.00, 0.35),   # NOON  — yellow
	Color(1.00, 0.55, 0.20),   # DUSK  — orange
	Color(0.50, 0.70, 1.00),   # NIGHT — blue
]
const BAR_H := 8.0

var _day_lbl:   Label     = null
var _phase_lbl: Label     = null
var _bar_root:  Control   = null
var _bar_bg:    ColorRect = null
var _bar_fg:    ColorRect = null
var _dividers:  Array     = []


func _ready() -> void:
	layer = 3
	_build_ui()


func _process(_delta: float) -> void:
	if _bar_root == null:
		return
	var phase: int    = EconomyManager.current_phase
	var col:   Color  = PHASE_COLORS[phase]

	_day_lbl.text  = "Day %d" % maxi(1, EconomyManager.day)
	_phase_lbl.text = PHASE_NAMES[phase]
	_phase_lbl.add_theme_color_override("font_color", col)

	var bw: float = _bar_root.size.x
	_bar_fg.size.x = bw * EconomyManager.day_progress()
	_bar_fg.color  = col
	for i: int in _dividers.size():
		(_dividers[i] as ColorRect).position.x = bw * float(i + 1) * 0.25


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position            = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(220, 0)

	var style := StyleBoxFlat.new()
	style.bg_color   = Color(0.08, 0.08, 0.12, 0.88)
	style.border_color = Color(0.35, 0.35, 0.45, 0.80)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	# ── Top row: "Day N"  (spacer)  "PHASE" ─────────────────────────────
	var row := HBoxContainer.new()
	vbox.add_child(row)

	_day_lbl = Label.new()
	_day_lbl.add_theme_font_size_override("font_size", 13)
	_day_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	_day_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_day_lbl)

	_phase_lbl = Label.new()
	_phase_lbl.add_theme_font_size_override("font_size", 13)
	_phase_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_phase_lbl)

	# ── Progress bar ─────────────────────────────────────────────────────
	_bar_root = Control.new()
	_bar_root.custom_minimum_size   = Vector2(0, BAR_H)
	_bar_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_bar_root)

	# Background track
	_bar_bg               = ColorRect.new()
	_bar_bg.color         = Color(0.15, 0.15, 0.20)
	_bar_bg.anchor_right  = 1.0
	_bar_bg.anchor_bottom = 1.0
	_bar_root.add_child(_bar_bg)

	# Foreground fill
	_bar_fg               = ColorRect.new()
	_bar_fg.anchor_bottom = 1.0
	_bar_fg.size.x        = 0.0
	_bar_root.add_child(_bar_fg)

	# Phase divider marks at 25 % / 50 % / 75 %
	for _i: int in 3:
		var div := ColorRect.new()
		div.color         = Color(0.50, 0.50, 0.60, 0.55)
		div.anchor_bottom = 1.0
		div.size.x        = 1.0
		_bar_root.add_child(div)
		_dividers.append(div)
