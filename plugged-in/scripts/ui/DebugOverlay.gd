extends RefCounted

# =============================================================================
#  DebugOverlay — manages the debug layer toggle (P key) and the NPC inspector
#  popup panel.  Everything debug-UI lives here so City.gd stays clean.
#
#  Usage:
#    var overlay := DebugOverlay.new(scene_root, road_graph, debug_layer, highway_layer)
#    overlay.build_npc_info_ui()
#    overlay.on_npc_clicked(npc)
#    overlay.toggle()                    # P key
#    overlay.update_npc_info()           # call each _process frame if selected
# =============================================================================

class_name DebugOverlay

var debug_mode:    bool = false
var _scene_root:   Node
var _debug_layer:  Node2D
var _highway_layer:Node2D

var _npc_info_panel: Panel         = null
var _npc_info_label: RichTextLabel = null
var selected_npc:    NPC           = null


func _init(scene_root: Node, debug_layer: Node2D, highway_layer: Node2D) -> void:
	_scene_root    = scene_root
	_debug_layer   = debug_layer
	_highway_layer = highway_layer


## Toggle between production and debug views (P key).
func toggle() -> void:
	debug_mode             = not debug_mode
	_debug_layer.visible   = debug_mode
	_highway_layer.visible = not debug_mode


## Build the NPC inspector panel (screen-space CanvasLayer).
func build_npc_info_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	_scene_root.add_child(ui)

	_npc_info_panel          = Panel.new()
	_npc_info_panel.size     = Vector2(320, 230)
	_npc_info_panel.position = Vector2(16, 16)
	_npc_info_panel.visible  = false
	ui.add_child(_npc_info_panel)

	_npc_info_label                 = RichTextLabel.new()
	_npc_info_label.bbcode_enabled  = true
	_npc_info_label.position        = Vector2(8, 8)
	_npc_info_label.size            = Vector2(304, 214)
	_npc_info_label.add_theme_font_size_override("normal_font_size", 12)
	_npc_info_panel.add_child(_npc_info_label)


## Show the NPC inspector panel for a clicked NPC.
func on_npc_clicked(npc: NPC) -> void:
	selected_npc = npc
	if _npc_info_panel != null:
		_npc_info_panel.visible = true
		update_npc_info()


## Hide the NPC inspector and clear selection.
func hide_npc_panel() -> void:
	if _npc_info_panel != null:
		_npc_info_panel.visible = false
	selected_npc = null


func is_npc_panel_visible() -> bool:
	return _npc_info_panel != null and _npc_info_panel.visible


## Refresh the NPC inspector label from selected_npc's current state.
func update_npc_info() -> void:
	if selected_npc == null or not is_instance_valid(selected_npc):
		return
	var npc: NPC = selected_npc
	const MOVE_NAMES      := ["Idle", "Moving"]
	const BEHAVIOUR_NAMES := ["Wander", "Going to Shop"]
	var d_name: String = WorldData.DISTRICTS[npc.district_id]["name"] \
		if npc.district_id >= 0 and npc.district_id < WorldData.DISTRICTS.size() \
		else "All Districts"
	var pts_left: int = max(0, npc._path.size() - npc._path_idx)

	var type_lbl: String
	if npc.npc_type == NPC.Type.POLICE:
		type_lbl = "Highway Patrol" if npc.is_highway_police else "Police"
	else:
		type_lbl = "Civilian"

	var text := "[b]%s[/b]  [color=#aaaaff]%s[/color]\n" % [npc.display_name, type_lbl]
	text += "[b]District:[/b] %s\n" % d_name
	text += "[b]Move:[/b] %s" % MOVE_NAMES[npc._move_state]
	if npc._move_state == NPC.MoveState.MOVING:
		text += "  (%d waypoints left)" % pts_left
	text += "\n[b]Behaviour:[/b] %s" % BEHAVIOUR_NAMES[npc._behaviour]
	if npc._behaviour == NPC.Behaviour.GOING_TO_SHOP and npc._shop_item >= 0:
		text += "  [color=#72ffa0]→ %s[/color]" % ItemDB.get_item_name(npc._shop_item)
	text += "\n[b]Speed:[/b] %.0f px/s\n" % NPC.SPEEDS[npc.npc_type]
	if npc.npc_type == NPC.Type.CIVILIAN:
		text += "[b]Balance:[/b] $%.0f  [b]Wage:[/b] $%.0f  [b]Rent:[/b] $%.0f\n" % [
			npc.balance, npc.daily_wage, npc.daily_rent]
		var h_col: String = "#ff6666" if npc.hunger >= NPC.HUNGER_THRESHOLD else "#88ff88"
		text += "[b]Hunger:[/b] [color=%s]%.0f%%[/color]" % [h_col, npc.hunger * 100.0]
		if npc._is_struggling:
			text += "  [color=#ff8800][b]⚠ STRUGGLING[/b][/color]"
		text += "\n"
	_npc_info_label.text = text
