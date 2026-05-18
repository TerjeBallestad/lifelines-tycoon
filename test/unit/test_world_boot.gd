extends GutTest

func test_world_constructs_state() -> void:
    var w := get_node("/root/World")
    w.reset_for_test()
    assert_not_null(w.client)
    assert_not_null(w.case_file)
    assert_not_null(w.economy)
    assert_eq(w.client.id, &"elling")
    assert_almost_eq(w.economy.capacity_current, w.economy.capacity_max, 0.0001)
