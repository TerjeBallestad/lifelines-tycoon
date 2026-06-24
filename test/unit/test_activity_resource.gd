extends GutTest

## Verifies the Activity Resource type holds and reads back its fields with the right
## types. Effects are NATIVE 0-1 units (sandbox hunger:60 → 0.6).
## Verified red-green: 2026-06-24

func test_activity_fields_read_back_typed() -> void:
	var a := Activity.new()
	a.id = &"eat_meal"
	a.display_name = "Eat Meal"
	a.colors = [0.3, 0.0, 0.0, 0.0, 0.5]
	a.effects = {&"hunger": 0.6, &"energy": 0.05, &"bladder": -0.05}
	a.difficulty = 1.0
	a.model = &"NEED"
	a.start_mastery = 0.9

	assert_eq(a.id, &"eat_meal")
	assert_eq(a.display_name, "Eat Meal")

	assert_eq(a.colors.size(), 5)
	assert_almost_eq(float(a.colors[1]), 0.0, 0.0001) # Blue
	assert_almost_eq(float(a.colors[4]), 0.5, 0.0001) # Green

	# Effects in native 0-1 units; drains may be negative.
	assert_almost_eq(float(a.effects[&"hunger"]), 0.6, 0.0001)
	assert_almost_eq(float(a.effects[&"bladder"]), -0.05, 0.0001)

	assert_almost_eq(a.difficulty, 1.0, 0.0001)
	assert_eq(a.model, &"NEED")
	assert_almost_eq(a.start_mastery, 0.9, 0.0001)

func test_activity_defaults() -> void:
	var a := Activity.new()
	assert_eq(a.colors, [])
	assert_eq(a.effects, {})
	assert_almost_eq(a.difficulty, 0.0, 0.0001)
	assert_almost_eq(a.start_mastery, 0.0, 0.0001)
