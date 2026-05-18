extends GutTest

var client: ClientState

func before_each() -> void:
	client = ClientState.new()
	client.needs = {
		&"energy":   0.9,
		&"hunger":   0.9,
		&"bladder":  0.9,
		&"social":   0.5,
		&"security": 0.7,
	}
	client.cognitive = {&"attention": 0.8, &"willpower": 0.5}
	client.overskudd = 71.0
	client.overskudd_regen_rate = 8.0

func test_mood_is_average_of_needs() -> void:
	assert_almost_eq(client.mood(), (0.9 + 0.9 + 0.9 + 0.5 + 0.7) / 5.0, 0.0001)

func test_cognitive_pool_is_average() -> void:
	assert_almost_eq(client.cognitive_pool(), (0.8 + 0.5) * 0.5, 0.0001)

func test_overskudd_ceiling_matches_formula() -> void:
	var expected := 100.0 * sqrt(client.mood() * client.cognitive_pool())
	assert_almost_eq(client.overskudd_ceiling(), expected, 0.01)

func test_overskudd_ceiling_clamped_to_100() -> void:
	client.needs = {&"a": 1.0, &"b": 1.0}
	client.cognitive = {&"x": 1.0, &"y": 1.0}
	assert_almost_eq(client.overskudd_ceiling(), 100.0, 0.0001)

func test_tick_regens_toward_ceiling() -> void:
	var ceiling := client.overskudd_ceiling()
	client.overskudd = max(0.0, ceiling - 10.0)
	client.tick_overskudd(1.0)  # +8 pts at default rate
	assert_almost_eq(client.overskudd, min(ceiling, max(0.0, ceiling - 10.0) + 8.0), 0.01)

func test_tick_snaps_down_when_above_ceiling() -> void:
	client.overskudd = 99.0
	client.needs[&"energy"] = 0.1
	client.tick_overskudd(0.1)
	assert_lte(client.overskudd, client.overskudd_ceiling() + 0.0001)

func test_tick_never_exceeds_ceiling() -> void:
	client.overskudd = 0.0
	client.tick_overskudd(1000.0)
	assert_lte(client.overskudd, client.overskudd_ceiling() + 0.0001)
