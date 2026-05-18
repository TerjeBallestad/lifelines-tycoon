extends GutTest

func _make_entry(id: StringName, tags: Array[StringName]) -> CaseEntry:
    var e := CaseEntry.new()
    e.id = id
    e.tags = tags
    return e

func test_add_entry_appends_and_aggregates_tags() -> void:
    var cf := CaseFile.new()
    cf.add_entry(_make_entry(&"obs_a", [&"mtg:blue", &"affinity:reading"]))
    assert_eq(cf.entries.size(), 1)
    assert_true(cf.tags.has(&"mtg:blue"))
    assert_true(cf.tags.has(&"affinity:reading"))

func test_add_is_idempotent_by_id() -> void:
    var cf := CaseFile.new()
    cf.add_entry(_make_entry(&"obs_a", [&"mtg:blue"]))
    cf.add_entry(_make_entry(&"obs_a", [&"mtg:green"]))  # same id
    assert_eq(cf.entries.size(), 1)
    assert_false(cf.tags.has(&"mtg:green"), "Re-add must not stamp new tags")

func test_has_entry_lookup() -> void:
    var cf := CaseFile.new()
    cf.add_entry(_make_entry(&"obs_a", []))
    assert_true(cf.has_entry(&"obs_a"))
    assert_false(cf.has_entry(&"obs_b"))

func test_has_all_tags_true_when_subset() -> void:
    var cf := CaseFile.new()
    cf.add_entry(_make_entry(&"obs_a", [&"mtg:blue", &"trauma:strangers"]))
    var required: Array[StringName] = [&"mtg:blue"]
    assert_true(cf.has_all_tags(required))
    required = [&"mtg:blue", &"trauma:strangers"]
    assert_true(cf.has_all_tags(required))

func test_has_all_tags_false_when_missing_one() -> void:
    var cf := CaseFile.new()
    cf.add_entry(_make_entry(&"obs_a", [&"mtg:blue"]))
    var required: Array[StringName] = [&"mtg:blue", &"mtg:green"]
    assert_false(cf.has_all_tags(required))

func test_has_all_tags_true_when_required_empty() -> void:
    var cf := CaseFile.new()
    var required: Array[StringName] = []
    assert_true(cf.has_all_tags(required))
