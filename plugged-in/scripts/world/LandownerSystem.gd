extends RefCounted

# =============================================================================
#  LandownerSystem — generates landowners and manages the inspector popup UI.
#
#  Usage:
#    var los := LandownerSystem.new(scene_root)
#    los.generate()                      # fills los.landowners array
#    los.show_inspector(owner_id)        # opens the popup
# =============================================================================

class_name LandownerSystem

## The populated landowner array; shared with City and DistrictGenerator.
var landowners: Array = []

var _scene_root:      Node
var _panel:           Panel         = null
var _label:           RichTextLabel = null


func _init(scene_root: Node) -> void:
	_scene_root = scene_root


## Populate the landowners array: 1 government + 4 big + 20 small owners.
func generate() -> void:
	landowners.clear()
	landowners.append({
		"id": 0, "name": "City Government", "type": "government",
		"cash": 5_000_000.0, "income_per_day": 0.0, "owned_buildings": [],
		"district_focus": -1,
	})
	for i: int in range(WorldData.BIG_OWNER_NAMES.size()):
		landowners.append({
			"id": i + 1,
			"name": WorldData.BIG_OWNER_NAMES[i],
			"type": "big",
			"cash": randf_range(500_000.0, 1_200_000.0),
			"income_per_day": 0.0,
			"owned_buildings": [],
			"district_focus": -1,
		})
	for i: int in range(WorldData.SMALL_OWNER_NAMES.size()):
		landowners.append({
			"id": i + 5,
			"name": WorldData.SMALL_OWNER_NAMES[i],
			"type": "small",
			"cash": randf_range(20_000.0, 120_000.0),
			"income_per_day": 0.0,
			"owned_buildings": [],
			"district_focus": randi() % WorldData.DISTRICTS.size(),
		})


## Reset per-day income on all landowners (call at day_started signal).
func reset_daily_income() -> void:
	for owner: Dictionary in landowners:
		owner["income_per_day"] = 0.0


## Open (or build then open) the landowner inspector panel for the given id.
func show_inspector(owner_id: int) -> void:
	if owner_id < 0 or owner_id >= landowners.size():
		return
	if _panel == null:
		_build_panel_ui()
	_populate_panel(owner_id)


func hide_inspector() -> void:
	if _panel != null:
		_panel.visible = false


func is_inspector_visible() -> bool:
	return _panel != null and _panel.visible


# ── Private ────────────────────────────────────────────────────────────────

func _build_panel_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 14
	_scene_root.add_child(ui)

	_panel          = Panel.new()
	_panel.size     = Vector2(340, 260)
	_panel.position = Vector2(16, 260)
	_panel.visible  = false
	ui.add_child(_panel)

	_label                  = RichTextLabel.new()
	_label.bbcode_enabled   = true
	_label.position         = Vector2(8, 8)
	_label.size             = Vector2(322, 242)
	_label.add_theme_font_size_override("normal_font_size", 12)
	_panel.add_child(_label)

	var close_btn          := Button.new()
	close_btn.text          = "✕"
	close_btn.position      = Vector2(308, 4)
	close_btn.size          = Vector2(28, 22)
	close_btn.pressed.connect(func() -> void: _panel.visible = false)
	_panel.add_child(close_btn)


func _populate_panel(owner_id: int) -> void:
	var owner: Dictionary = landowners[owner_id]
	var text := "[b]%s[/b]\n" % owner.get("name", "Unknown")
	var o_type: String = (owner.get("type", "private") as String).capitalize()
	text += "[color=#aaddff]%s[/color]\n" % o_type
	text += "[b]Cash:[/b]  $%.0f\n" % float(owner.get("cash", 0.0))
	text += "[b]Income/day:[/b]  $%.0f\n" % float(owner.get("income_per_day", 0.0))
	var buildings: Array = owner.get("owned_buildings", [])
	text += "[b]Properties owned:[/b]  %d\n" % buildings.size()
	var by_district: Dictionary = {}
	for bm: Dictionary in buildings:
		var dname: String = bm.get("district", "Unknown")
		by_district[dname] = int(by_district.get(dname, 0)) + 1
	if not by_district.is_empty():
		text += "[color=#888888]— by district —[/color]\n"
		for dname: String in by_district.keys():
			text += "  %s:  %d\n" % [dname, int(by_district[dname])]
	_label.text    = text
	_panel.visible = true
