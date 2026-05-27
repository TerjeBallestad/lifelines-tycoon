extends GutTest

var sim: Node
var w: Node

func before_each() -> void:
	Clock.reset()
	sim = get_node("/root/Sim")
	w = get_node("/root/World")
	w.reset_for_test()
	sim.reset_for_test()
	w.client.needs = {&"energy": 1.0, &"hunger": 1.0, &"bladder": 1.0, &"social": 1.0, &"security": 1.0}
	w.client.cognitive = {&"attention": 0.5, &"willpower": 1.0}
	w.client.overskudd = 80.0

func test_apply_tick_decays_needs() -> void:
	sim.apply_tick(10.0)  # 10 game-hours
	var expected_energy: float = clamp(1.0 + w.decay.needs_per_hour[&"energy"] * 10.0, 0.0, 1.0)
	assert_almost_eq(w.client.needs[&"energy"], expected_energy, 0.0001)

func test_apply_tick_regens_attention_and_decays_willpower() -> void:
	sim.apply_tick(10.0)
	var expected_att: float = clamp(0.5 + w.decay.cognitive_per_hour[&"attention"] * 10.0, 0.0, 1.0)
	var expected_wp:  float = clamp(1.0 + w.decay.cognitive_per_hour[&"willpower"] * 10.0, 0.0, 1.0)
	assert_almost_eq(w.client.cognitive[&"attention"], expected_att, 0.0001)
	assert_almost_eq(w.client.cognitive[&"willpower"], expected_wp, 0.0001)

func test_apply_tick_emits_overskudd_when_changed_enough() -> void:
	watch_signals(EventBus)
	w.client.overskudd = 50.0
	sim.apply_tick(5.0)
	assert_signal_emitted(EventBus, "overskudd_changed")

func test_observation_roll_fires_every_6_game_hours() -> void:
	var saved: Dictionary = Catalog.observations.duplicate()
	Catalog.observations.clear()
	var e := CaseEntry.new()
	e.id = &"obs_only"
	e.tags = []
	Catalog.observations[&"obs_only"] = e
	sim.apply_tick(5.9)
	assert_false(w.case_file.has_entry(&"obs_only"))
	sim.apply_tick(0.2)  # cumulative 6.1
	assert_true(w.case_file.has_entry(&"obs_only"))
	Catalog.observations = saved  # restore for any later test

func test_day_boundary_refills_capacity() -> void:
	# Clock.advance drives the day_started signal → Sim._on_day_started → World.start_new_day.
	w.economy.capacity_current = 0.0
	Clock.reset()
	sim._last_seen_day = Clock.day
	Clock.advance(25.0)
	assert_almost_eq(w.economy.capacity_current, w.economy.capacity_max, 0.0001)

func test_clock_tick_applies_sim_decay_once() -> void:
	var start_energy: float = w.client.needs[&"energy"]
	Clock.advance(1.0)
	var expected_energy: float = clamp(start_energy + w.decay.needs_per_hour[&"energy"], 0.0, 1.0)
	assert_almost_eq(w.client.needs[&"energy"], expected_energy, 0.0001)

func test_sim_start_uses_clock_as_only_live_process_authority() -> void:
	assert_false(sim.is_processing())
	sim.start()
	assert_false(sim.is_processing())
	assert_true(Clock.is_processing())
	Clock._process(1.0)
	sim.stop()
	assert_almost_eq(Clock.total_game_hours, 24.0 / 60.0, 0.0001)

func test_manual_advance_and_away_time_share_clock_tick_path() -> void:
	var start_energy: float = w.client.needs[&"energy"]
	Clock.advance(1.0)
	Sim.advance_away_time(1.0)
	var expected_energy: float = clamp(start_energy + w.decay.needs_per_hour[&"energy"] * 2.0, 0.0, 1.0)
	assert_almost_eq(w.client.needs[&"energy"], expected_energy, 0.0001)
	assert_almost_eq(Clock.total_game_hours, 2.0, 0.0001)
