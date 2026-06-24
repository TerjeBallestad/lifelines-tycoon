extends GutTest

## Task 12 cadence guard: the PatternDeriver (the Lens) is evaluated at the DAY BOUNDARY
## — exactly once per day rollover — NOT per tick. The hook lives in Sim._on_day_started
## (after World.start_new_day), which World routes through evaluate_patterns_for_day_end.
## That method runs the deriver and emits EventBus.patterns_evaluated(uncovered) so the
## uncovered-behaviour summary lands in agent_bridge's events.jsonl stream each day.
##
## This test injects a counting spy deriver (subclass of PatternDeriver) via World's
## test-only seam and drives two real day rollovers through Clock.advance. It asserts the
## spy's evaluate() ran exactly twice (once per rollover, not once per tick) and that the
## uncovered summary is recorded each day (one patterns_evaluated emission per rollover).
##
## Verified red-green: 2026-06-24
## (Temporarily moving World.evaluate_patterns_for_day_end() out of Sim._on_day_started and
## into Sim.apply_tick makes evaluate fire once PER TICK — the per-day assertions below fail
## because the count climbs to many-per-day instead of exactly one.)

# Counting spy: records each evaluate() call and the uncovered summary visible at that
# moment, then defers to the real PatternDeriver behaviour so World.case_file / emits stay
# faithful. Inner class so it has no .gd file of its own to import.
class SpyDeriver extends PatternDeriver:
	var evaluate_calls: int = 0
	var histories_seen: Array = []

	func _init(world_ref: Node) -> void:
		super(world_ref)

	func evaluate(history: Array) -> void:
		evaluate_calls += 1
		histories_seen.append(history.size())
		super(history)

var sim: Node
var w: Node
var _spy: SpyDeriver
var _patterns_evaluated_events: Array = []

func before_each() -> void:
	Clock.reset()
	sim = get_node("/root/Sim")
	w = get_node("/root/World")
	World.ca_seed = 747
	w.reset_for_test()
	sim.reset_for_test()
	w.client.needs = {&"energy": 0.4, &"hunger": 0.4, &"bladder": 0.4, &"social": 0.4, &"security": 0.4}
	w.client.cognitive = {&"attention": 0.5, &"willpower": 1.0}
	w.client.overskudd = 80.0
	_spy = SpyDeriver.new(w)
	w.set_pattern_deriver_for_test(_spy)
	_patterns_evaluated_events = []
	EventBus.patterns_evaluated.connect(_on_patterns_evaluated)

func after_each() -> void:
	if EventBus.patterns_evaluated.is_connected(_on_patterns_evaluated):
		EventBus.patterns_evaluated.disconnect(_on_patterns_evaluated)

func _on_patterns_evaluated(uncovered: Dictionary) -> void:
	_patterns_evaluated_events.append(uncovered.duplicate(true))

func test_deriver_evaluates_once_per_day_not_per_tick() -> void:
	# Two day rollovers via real Clock advancement. Each 24h advance crosses the day
	# boundary exactly once, firing day_started → Sim._on_day_started → the Lens pass.
	# Crucially this runs MANY ticks (Clock.advance emits tick once per call, and each
	# 24h spans ~13 CA decision steps inside apply_tick) — so if the hook were per-tick
	# the count would be far above 2.
	assert_eq(_spy.evaluate_calls, 0, "no Lens pass before any day boundary")

	Clock.advance(24.0)  # day 1 -> day 2 (one rollover)
	assert_eq(_spy.evaluate_calls, 1, "exactly one Lens pass after the first day rollover")

	Clock.advance(24.0)  # day 2 -> day 3 (second rollover)
	assert_eq(_spy.evaluate_calls, 2, "exactly one Lens pass per day rollover — not per tick")

	assert_eq(Clock.day, 3, "two rollovers advanced the clock to day 3")

func test_intra_day_ticks_do_not_trigger_extra_evaluations() -> void:
	# Several sub-day advances inside a single day must NOT trigger the Lens — only the
	# boundary crossing does. This is the direct per-tick-vs-per-day discriminator.
	Clock.advance(6.0)
	Clock.advance(6.0)
	Clock.advance(6.0)
	assert_eq(Clock.day, 1, "still day 1 after 18h of intra-day ticks")
	assert_eq(_spy.evaluate_calls, 0, "no Lens pass without a day boundary, despite many ticks")

	Clock.advance(6.0)  # crosses into day 2
	assert_eq(Clock.day, 2, "crossed into day 2")
	assert_eq(_spy.evaluate_calls, 1, "exactly one Lens pass on the single boundary crossing")

func test_uncovered_summary_recorded_each_day() -> void:
	# The uncovered-behaviour summary must be emitted (and thus stream to events.jsonl)
	# once per day rollover. Assert one patterns_evaluated emission per day, each carrying
	# a Dictionary summary.
	Clock.advance(24.0)  # day 2
	Clock.advance(24.0)  # day 3
	assert_eq(_patterns_evaluated_events.size(), 2, "uncovered summary emitted exactly once per day rollover")
	for summary: Dictionary in _patterns_evaluated_events:
		assert_typeof(summary, TYPE_DICTIONARY, "each day-end emission carries an uncovered-behaviour Dictionary")
	# The history grows across the day, so the second pass saw at least as many records
	# as the first — proving the Lens reads the live, accumulating history each day.
	assert_eq(_spy.histories_seen.size(), 2, "spy observed two day-end evaluations")
	assert_gte(_spy.histories_seen[1], _spy.histories_seen[0], "history is non-shrinking across day-end passes")

func test_summary_streams_to_events_jsonl_via_agent_bridge() -> void:
	# Wiring proof: agent_bridge captures patterns_evaluated into its events buffer (the
	# same buffer drained to events.jsonl), so a day-end pass produces a streamable event.
	var bridge: Node = AgentBridge
	bridge.start_event_capture()
	bridge.drain_events()  # clear anything from boot
	Clock.advance(24.0)    # one day rollover → one Lens pass → one patterns_evaluated
	var drained: Array = bridge.drain_events()
	bridge.stop_event_capture()
	var found := false
	for ev: Dictionary in drained:
		if String(ev.get("ev", "")) == "patterns_evaluated":
			found = true
			assert_true(ev.has("uncovered"), "streamed event carries the uncovered summary")
	assert_true(found, "a patterns_evaluated event reached the agent_bridge events stream")
