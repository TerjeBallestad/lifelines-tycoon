extends GutTest

var econ: EconomyState

func before_each() -> void:
    econ = EconomyState.new()
    econ.capacity_max = 6.0
    econ.capacity_current = 6.0

func test_can_spend_when_capacity_sufficient() -> void:
    assert_true(econ.can_spend(2.5))
    assert_true(econ.can_spend(6.0))
    assert_false(econ.can_spend(6.01))

func test_spend_decrements_when_affordable() -> void:
    assert_true(econ.spend(2.5))
    assert_almost_eq(econ.capacity_current, 3.5, 0.0001)

func test_spend_refuses_when_short() -> void:
    econ.capacity_current = 1.0
    assert_false(econ.spend(2.0))
    assert_almost_eq(econ.capacity_current, 1.0, 0.0001)

func test_refill_resets_to_max() -> void:
    econ.capacity_current = 0.0
    econ.refill_to_max()
    assert_almost_eq(econ.capacity_current, 6.0, 0.0001)

func test_resource_spend_uses_hidden_subsidy() -> void:
    econ.resources = {&"trust": 1.0, &"dice": 1.0, &"knowledge": 0.0}
    assert_false(econ.can_spend_resources({&"trust": 2.0, &"dice": 1.0}))
    assert_true(econ.can_spend_resources({&"trust": 2.0, &"dice": 1.0}, {&"trust": 1.0}))
    var delta := econ.spend_resources({&"trust": 2.0, &"dice": 1.0}, {&"trust": 1.0})
    assert_almost_eq(econ.resources[&"trust"], 0.0, 0.0001)
    assert_almost_eq(econ.resources[&"dice"], 0.0, 0.0001)
    assert_almost_eq(delta[&"trust"], -1.0, 0.0001)
    assert_almost_eq(delta[&"dice"], -1.0, 0.0001)

func test_resource_effects_add_and_clamp_non_negative() -> void:
    econ.resources = {&"trust": 0.5, &"knowledge": 0.0}
    var delta := econ.add_resources({&"trust": -2.0, &"knowledge": 2.0})
    assert_almost_eq(econ.resources[&"trust"], 0.0, 0.0001)
    assert_almost_eq(econ.resources[&"knowledge"], 2.0, 0.0001)
    assert_almost_eq(delta[&"trust"], -0.5, 0.0001)
    assert_almost_eq(delta[&"knowledge"], 2.0, 0.0001)
