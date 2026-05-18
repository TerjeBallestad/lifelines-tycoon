extends GutTest

func test_apply_copies_all_fields() -> void:
    var init := ClientInitData.new()
    init.id = &"elling"
    init.display_name = "Elling Pettersen"
    init.mtg_primary = &"blue"
    init.mtg_secondary = &"green"
    init.needs = {&"energy": 0.9, &"social": 0.5}
    init.cognitive = {&"attention": 0.8, &"willpower": 0.5}
    init.overskudd = 71.0
    init.skills = {&"reading": 5, &"phone": 0}

    var c := ClientState.new()
    c.apply_init_data(init)

    assert_eq(c.id, &"elling")
    assert_eq(c.display_name, "Elling Pettersen")
    assert_eq(c.mtg_primary, &"blue")
    assert_eq(c.mtg_secondary, &"green")
    assert_eq(c.needs[&"energy"], 0.9)
    assert_eq(c.cognitive[&"willpower"], 0.5)
    assert_almost_eq(c.overskudd, 71.0, 0.0001)
    assert_eq(c.skills[&"reading"], 5)

func test_apply_duplicates_dicts_no_aliasing() -> void:
    var init := ClientInitData.new()
    init.needs = {&"energy": 0.5}
    var c := ClientState.new()
    c.apply_init_data(init)
    c.needs[&"energy"] = 0.1
    assert_eq(init.needs[&"energy"], 0.5, "Init data must not be aliased")
