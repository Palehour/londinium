class_name SimTime
extends RefCounted

# One tick is one game second (docs/ARCHITECTURE.md), so a game minute is this many ticks.
const TICKS_PER_MINUTE: int = 60


# The one conversion from the minutes of the data (`*_min`, issue #63) to ticks: nobody else converts them.
static func minutes_to_ticks(minutes: float) -> int:
	return roundi(minutes * TICKS_PER_MINUTE)
