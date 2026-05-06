extends Node

# =============================================================================
#  EconomyManager — Autoload singleton.
#  Game clock: 1 day = DAY_SECONDS real seconds, divided into 4 phases of 30 s.
#
#  DAWN  (phase 0,  0–30 s):   Wages paid to NPC workers.
#  NOON  (phase 1, 30–60 s):   Production tick — factories, fisheries, bakeries run.
#  DUSK  (phase 2, 60–90 s):   Retail/consumption — NPCs buy food and wants.
#  NIGHT (phase 3, 90–120 s):  Rent collected, property taxes levied, harbour ships arrive.
# =============================================================================

const DAY_SECONDS   := 120.0
const PHASE_COUNT   := 4
const PHASE_SECONDS := DAY_SECONDS / PHASE_COUNT   # 30.0

enum Phase { DAWN = 0, NOON = 1, DUSK = 2, NIGHT = 3 }

## Emitted at the start of each new day (before the DAWN phase begins).
signal day_started(day: int)
## Emitted each time the phase advances.
signal phase_changed(phase: int)
## Emitted at the very end of NIGHT (just before day_started fires for day + 1).
signal day_ended(day: int)

## Days elapsed since game start.
var day: int = 0
## Current phase within the day (cast to Phase enum for readable comparisons).
var current_phase: int = Phase.DAWN

var _paused:        bool  = false
var _phase_elapsed: float = 0.0


func _process(delta: float) -> void:
	if _paused:
		return
	_phase_elapsed += delta
	if _phase_elapsed >= PHASE_SECONDS:
		_phase_elapsed -= PHASE_SECONDS
		_advance_phase()


func _advance_phase() -> void:
	var next: int = (current_phase + 1) % PHASE_COUNT
	if next == Phase.DAWN:
		emit_signal("day_ended", day)
		day += 1
		emit_signal("day_started", day)
	current_phase = next
	emit_signal("phase_changed", current_phase)


## Pause or resume the economic clock.
func set_paused(value: bool) -> void:
	_paused = value


## 0.0–1.0 progress through the current day.
func day_progress() -> float:
	return (float(current_phase) * PHASE_SECONDS + _phase_elapsed) / DAY_SECONDS


## 0.0–1.0 progress through the current phase.
func phase_progress() -> float:
	return _phase_elapsed / PHASE_SECONDS


## Human-readable name for a phase int (defaults to current_phase when p = -1).
func phase_name(p: int = -1) -> String:
	match (p if p >= 0 else current_phase):
		Phase.DAWN:  return "Dawn"
		Phase.NOON:  return "Noon"
		Phase.DUSK:  return "Dusk"
		Phase.NIGHT: return "Night"
	return "?"
