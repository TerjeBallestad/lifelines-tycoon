extends GutTest

var client: ClientState

func before_each() -> void:
    client = ClientState.new()
    client.needs = {&"energy": 0.4, &"social": 0.8, &"security": 0.7}
    client.cognitive = {&"attention": 0.6, &"willpower": 0.2}
    client.skills = {&"phone": 1, &"reading": 5}

func test_empty_require_passes() -> void:
    var e := CaseEntry.new()
    assert_true(e.require_state_satisfied(client))

func test_needs_lt_clause() -> void:
    var e := CaseEntry.new()
    e.require_state = {&"needs_energy_lt": 0.5}
    assert_true(e.require_state_satisfied(client))
    e.require_state = {&"needs_energy_lt": 0.3}
    assert_false(e.require_state_satisfied(client))

func test_cognitive_lt_clause() -> void:
    var e := CaseEntry.new()
    e.require_state = {&"cognitive_willpower_lt": 0.3}
    assert_true(e.require_state_satisfied(client))

func test_needs_ge_clause() -> void:
    var e := CaseEntry.new()
    e.require_state = {&"needs_social_ge": 0.7}
    assert_true(e.require_state_satisfied(client))
    e.require_state = {&"needs_social_ge": 0.9}
    assert_false(e.require_state_satisfied(client))

func test_skill_ge_clause() -> void:
    var e := CaseEntry.new()
    e.require_state = {&"skill_phone_ge": 1}
    assert_true(e.require_state_satisfied(client))
    e.require_state = {&"skill_phone_ge": 2}
    assert_false(e.require_state_satisfied(client))

func test_and_semantics_all_must_hold() -> void:
    var e := CaseEntry.new()
    e.require_state = {&"skill_phone_ge": 1, &"needs_energy_lt": 0.5}
    assert_true(e.require_state_satisfied(client))
    e.require_state = {&"skill_phone_ge": 1, &"needs_energy_lt": 0.1}
    assert_false(e.require_state_satisfied(client))

func test_unknown_op_fails_closed() -> void:
    var e := CaseEntry.new()
    e.require_state = {&"needs_energy_bogus": 0.5}
    assert_false(e.require_state_satisfied(client))

func test_unknown_scope_fails_closed() -> void:
    var e := CaseEntry.new()
    e.require_state = {&"mood_overall_ge": 0.5}
    assert_false(e.require_state_satisfied(client))

func test_missing_field_fails_closed() -> void:
    var e := CaseEntry.new()
    e.require_state = {&"needs_hunger_lt": 0.5}
    assert_false(e.require_state_satisfied(client))  # client has no &"hunger" key in this fixture
