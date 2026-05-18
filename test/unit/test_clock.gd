extends GutTest

func _clock() -> Node:
	return get_node("/root/Clock")

func test_default_state() -> void:
	var c := _clock()
	c.reset()
	assert_eq(c.day, 1)
	assert_almost_eq(c.hour_of_day, 0.0, 0.0001)
	assert_eq(c.time_scale, 1.0)
	assert_false(c.paused)

func test_real_seconds_to_game_hours() -> void:
	var c := _clock()
	c.reset()
	assert_almost_eq(c.real_to_game_hours(1.0), 24.0 / 60.0, 0.0001)
	c.time_scale = 4.0
	assert_almost_eq(c.real_to_game_hours(1.0), (24.0 / 60.0) * 4.0, 0.0001)

func test_advance_accumulates_hours() -> void:
	var c := _clock()
	c.reset()
	c.advance(2.5)  # game-hours
	assert_almost_eq(c.hour_of_day, 2.5, 0.0001)
	assert_eq(c.day, 1)

func test_advance_crosses_day_boundary_and_emits() -> void:
	var c := _clock()
	c.reset()
	watch_signals(EventBus)
	c.advance(25.0)
	assert_eq(c.day, 2)
	assert_almost_eq(c.hour_of_day, 1.0, 0.0001)
	assert_signal_emitted_with_parameters(EventBus, "day_started", [2])

func test_pause_blocks_tick() -> void:
	var c := _clock()
	c.reset()
	c.paused = true
	var hrs: float = c.real_to_game_hours_when_unpaused(1.0)
	assert_almost_eq(hrs, 0.0, 0.0001)
