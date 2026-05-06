## RoadGraph.gd
## Builds a navigable graph from the HIGHWAYS array and exposes A* pathfinding.
##
## Each highway segment contributes two centerline endpoints as graph nodes.
## Where an E-W and an N-S segment overlap, an intersection node is inserted on
## both segments so NPCs can change direction at junctions.
## Nodes that fall within SNAP_DIST of each other are merged into one, keeping
## the graph clean even when segment endpoints are only approximately aligned.

class_name RoadGraph

var nodes: Array = []   # Array of Vector2 — road junction world positions
var _adj:  Array = []   # _adj[i] = [[neighbor_idx, cost], …]

const SNAP_DIST := 80.0   # px — endpoints closer than this are the same junction

# District grid constants — must match City.gd
const _ROAD_W := 60.0
const _CELL_W := 540.0   # BLOCK_W 480 + ROAD_W 60
const _CELL_H := 420.0   # BLOCK_H 360 + ROAD_W 60


# ---------------------------------------------------------------------------
## Build the graph from the HIGHWAYS array (Array of Dictionaries with x/y/w/h).
func build(highways: Array) -> void:
	nodes.clear()
	_adj.clear()

	# ── Step 1: compute each segment's centreline endpoints ──────────────────
	var cls: Array = []   # {a, b, is_ew, x, y, w, h}
	for seg: Dictionary in highways:
		var x := float(seg["x"])
		var y := float(seg["y"])
		var w := float(seg["w"])
		var h := float(seg["h"])
		var is_ew: bool = w >= h
		var a: Vector2
		var b: Vector2
		if is_ew:
			a = Vector2(x,     y + h * 0.5)
			b = Vector2(x + w, y + h * 0.5)
		else:
			a = Vector2(x + w * 0.5, y    )
			b = Vector2(x + w * 0.5, y + h)
		cls.append({"a": a, "b": b, "is_ew": is_ew, "x": x, "y": y, "w": w, "h": h})

	# ── Step 2: find E-W × N-S intersection points ───────────────────────────
	var extra: Array = []   # extra[i] = Array of Vector2 on segment i's line
	for _i: int in range(cls.size()):
		extra.append([])

	for i: int in range(cls.size()):
		for j: int in range(i + 1, cls.size()):
			var si: Dictionary = cls[i]
			var sj: Dictionary = cls[j]
			if si["is_ew"] == sj["is_ew"]:
				continue   # parallel — endpoints handled by snap below

			var ew: Dictionary = si if si["is_ew"] else sj
			var ns: Dictionary = si if not si["is_ew"] else sj
			var ei: int        = i  if si["is_ew"] else j
			var ni: int        = i  if not si["is_ew"] else j

			var ns_cx: float = ns["x"] + ns["w"] * 0.5
			var ew_cy: float = ew["y"] + ew["h"] * 0.5

			if ns_cx >= ew["x"] and ns_cx <= ew["x"] + ew["w"] and \
			   ew_cy >= ns["y"] and ew_cy <= ns["y"] + ns["h"]:
				var pt := Vector2(ns_cx, ew_cy)
				extra[ei].append(pt)
				extra[ni].append(pt)

	# ── Step 3: for each segment, build ordered waypoint list & register ─────
	for i: int in range(cls.size()):
		var cl: Dictionary = cls[i]
		var pts: Array     = [cl["a"]] + extra[i] + [cl["b"]]

		# Sort along the dominant axis
		if cl["is_ew"]:
			pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		else:
			pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)

		# Deduplicate consecutive near-identical points
		var deduped: Array = [pts[0]]
		for k: int in range(1, pts.size()):
			if pts[k].distance_to(deduped[-1]) > 2.0:
				deduped.append(pts[k])

		# Register nodes (with snapping) and edges
		var node_ids: Array = []
		for pt: Vector2 in deduped:
			node_ids.append(_add_node(pt))

		for k: int in range(node_ids.size() - 1):
			var ai: int    = node_ids[k]
			var bi: int    = node_ids[k + 1]
			var cost: float = nodes[ai].distance_to(nodes[bi])
			_add_edge(ai, bi, cost)


# ---------------------------------------------------------------------------
func _add_node(pt: Vector2) -> int:
	for i: int in range(nodes.size()):
		if nodes[i].distance_to(pt) < SNAP_DIST:
			return i
	nodes.append(pt)
	_adj.append([])
	return nodes.size() - 1


func _add_edge(a: int, b: int, cost: float) -> void:
	for e: Array in _adj[a]:
		if e[0] == b:
			return   # already exists
	_adj[a].append([b, cost])
	_adj[b].append([a, cost])


# ---------------------------------------------------------------------------
## Returns the index of the node whose world position is closest to `pos`.
func nearest_node(pos: Vector2) -> int:
	if nodes.is_empty():
		return -1
	var best_i := 0
	var best_d := pos.distance_to(nodes[0])
	for i: int in range(1, nodes.size()):
		var d := pos.distance_to(nodes[i])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


# ---------------------------------------------------------------------------
## Dijkstra's shortest-path search.
## Returns an Array of Vector2 road-node positions from the node nearest
## `from_pos` to the node nearest `to_pos`.  Only graph nodes are included —
## no raw world positions are prepended or appended — so callers that snap
## their position to a node before calling will stay strictly on the road grid.
func find_path(from_pos: Vector2, to_pos: Vector2) -> Array:
	if nodes.is_empty():
		return []

	var start: int = nearest_node(from_pos)
	var goal:  int = nearest_node(to_pos)

	if start < 0 or goal < 0:
		return []
	if start == goal:
		return [nodes[start]]

	# open_set entry: [dist, node_idx]
	var open_set:  Array      = [[0.0, start]]
	var came_from: Dictionary = {}               # node_idx → parent_node_idx
	var dist:      Dictionary = {start: 0.0}
	var visited:   Dictionary = {}

	while not open_set.is_empty():
		# Linear-scan min-extract — adequate for city-scale node counts (~2 000)
		var min_d := INF
		var min_k := 0
		for k: int in range(open_set.size()):
			if open_set[k][0] < min_d:
				min_d = open_set[k][0]
				min_k = k
		var cur: Array = open_set[min_k]
		open_set.remove_at(min_k)

		var d: float = cur[0]
		var n: int   = cur[1]

		if visited.has(n):
			continue
		visited[n] = true

		if n == goal:
			var path: Array = []
			var c: int = n
			while came_from.has(c):
				path.push_front(nodes[c])
				c = came_from[c]
			path.push_front(nodes[start])
			return path

		for edge: Array in _adj[n]:
			var nb:    int   = edge[0]
			var cost:  float = edge[1]
			if visited.has(nb):
				continue
			var new_d: float = d + cost
			if not dist.has(nb) or new_d < float(dist[nb]):
				dist[nb]      = new_d
				came_from[nb] = n
				open_set.append([new_d, nb])

	# No path found — return start node only so caller stays put
	return [nodes[start]]


# ---------------------------------------------------------------------------
## Add every street-grid intersection for all districts to the graph.
## Call this after build() so highway nodes already exist and snap correctly.
func build_districts(districts: Array) -> void:
	for d: Dictionary in districts:
		_add_district_grid(d)


func _add_district_grid(d: Dictionary) -> void:
	var ox: float = float(d["ox"])
	var oy: float = float(d["oy"])
	var cols: int = d["cols"]
	var rows: int = d["rows"]

	# Centreline x of each vertical avenue (col 0 … cols)
	var xs: Array = []
	for c: int in range(cols + 1):
		xs.append(ox + c * _CELL_W + _ROAD_W * 0.5)

	# Centreline y of each horizontal street (row 0 … rows)
	var ys: Array = []
	for r: int in range(rows + 1):
		ys.append(oy + r * _CELL_H + _ROAD_W * 0.5)

	# Register intersection nodes; keep a 2-D index for edge wiring
	var grid: Array = []   # grid[r][c] = node_idx
	for r: int in range(rows + 1):
		var row_ids: Array = []
		for c: int in range(cols + 1):
			row_ids.append(_add_node(Vector2(xs[c], ys[r])))
		grid.append(row_ids)

	# Horizontal edges along each street row
	for r: int in range(rows + 1):
		for c: int in range(cols):
			var a: int    = grid[r][c]
			var b: int    = grid[r][c + 1]
			var cost: float = nodes[a].distance_to(nodes[b])
			_add_edge(a, b, cost)

	# Vertical edges along each avenue column
	for c: int in range(cols + 1):
		for r: int in range(rows):
			var a: int    = grid[r][c]
			var b: int    = grid[r + 1][c]
			var cost: float = nodes[a].distance_to(nodes[b])
			_add_edge(a, b, cost)
