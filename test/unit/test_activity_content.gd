extends GutTest

## Content assertions for the 18 authored Activity .tres (PLAN-001 Task 5) and the
## frozen Elling color-identity vector.
##  - all 18 activities load from Catalog
##  - every effect value is in native 0-1 units, bounded to [-1.0, 1.0]
##  - the Elling color vector is 5 floats == [0, 0.8, 0, 0, 0.4]
##
## Verified red-green: 2026-06-24

const ELLING_INIT := "res://features/client/elling_init.tres"
const ELLING_COLORS := [0.0, 0.8, 0.0, 0.0, 0.4]

func test_eighteen_activities_load() -> void:
	assert_eq(Catalog.activities.size(), 18, "Expected exactly 18 activities loaded")

func test_every_effect_value_within_unit_bounds() -> void:
	for a: Activity in Catalog.activities.values():
		for need: StringName in a.effects.keys():
			var v := float(a.effects[need])
			assert_between(v, -1.0, 1.0,
				"%s effect %s = %s out of native [-1,1] bounds" % [a.id, need, v])

func test_elling_color_vector_is_known_hidden_truth() -> void:
	var init: ClientInitData = load(ELLING_INIT)
	assert_not_null(init, "Elling init data should load")
	assert_eq(init.colors.size(), 5, "Elling color vector must have 5 elements")
	for i in range(5):
		assert_almost_eq(float(init.colors[i]), float(ELLING_COLORS[i]), 0.0001,
			"Elling color[%d] mismatch" % i)
