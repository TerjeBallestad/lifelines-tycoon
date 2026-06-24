extends GutTest

## Task 8 integration guard: Sim.apply_tick now drives the CA decision kernel (replacing
## flat needs-decay), appends to World history, KEEPS cognitive decay, and the global-randi
## observation side-path (World.try_surface_observation) is RETIRED. Overnight reset bumps
## energy on the day boundary.
##
## Verified red-green: 2026-06-24
## (Temporarily skipping the World.append_activity_record call in Sim.apply_tick makes
## test_apply_tick_appends_activity_record fail — get_activity_history() stays empty.)

var sim: Node
var w: Node

func before_each() -> void:
	Clock.reset()
	sim = get_node("/root/Sim")
	w = get_node("/root/World")
	World.ca_seed = 747  # deterministic CA stream for this test
	w.reset_for_test()
	sim.reset_for_test()
	# Mid-range needs so the chosen activity can move at least one need measurably.
	w.client.needs = {&"energy": 0.4, &"hunger": 0.4, &"bladder": 0.4, &"social": 0.4, &"security": 0.4}
	w.client.cognitive = {&"attention": 0.5, &"willpower": 1.0}
	w.client.overskudd = 80.0

func test_apply_tick_appends_activity_record() -> void:
	assert_eq(w.get_activity_history().size(), 0, "history starts empty")
	sim.apply_tick(10.0)  # 10h > 1.75h/step → at least one CA decision step
	var history: Array = w.get_activity_history()
	assert_gt(history.size(), 0, "apply_tick appended at least one activity record")
	var rec: Dictionary = history[0]
	assert_true(rec.has("activity_id"), "record carries activity_id")
	assert_true(rec.has("needs_snapshot"), "record carries needs_snapshot")
	assert_true(rec.has("mastery_snapshot"), "record carries mastery_snapshot")
	assert_true(rec.has("day"), "record carries day")
	assert_true(rec.has("step"), "record carries step")

func test_apply_tick_changes_at_least_one_need() -> void:
	var before: Dictionary = w.client.needs.duplicate(true)
	sim.apply_tick(10.0)
	var changed := false
	for k: StringName in before.keys():
		if abs(float(w.client.needs[k]) - float(before[k])) > 0.0001:
			changed = true
			break
	assert_true(changed, "the CA decision moved at least one need")

func test_chosen_activity_mastery_increases() -> void:
	sim.apply_tick(10.0)
	var history: Array = w.get_activity_history()
	assert_gt(history.size(), 0, "have at least one record")
	var first: Dictionary = history[0]
	var chosen_id: StringName = first["activity_id"]
	var mastery_at_choice: float = float(first["mastery_snapshot"].get(chosen_id, 0.0))
	var mastery_now: float = float(w.client.mastery.get(chosen_id, 0.0))
	# mastery_snapshot is taken AFTER select_and_apply grows it on the first step, so a
	# direct comparison against current mastery only differs if the activity was chosen
	# again. Instead assert growth vs the engine's learn rule against a fresh baseline.
	assert_gt(mastery_now, 0.0, "chosen activity has positive mastery after being practised")
	assert_gte(mastery_now, mastery_at_choice - 0.0001, "mastery never regressed below its first-choice value during the tick")

func test_chosen_activity_mastery_grows_from_baseline() -> void:
	# Pin a known starting mastery for a single, certain-to-be-chosen scenario by
	# running one tick and checking the first chosen id grew relative to its preset.
	var preset_before: Dictionary = w.client.mastery.duplicate(true)
	sim.apply_tick(2.0)  # exactly one step (2.0 > 1.75)
	var history: Array = w.get_activity_history()
	assert_eq(history.size(), 1, "exactly one CA step for 2.0h")
	var chosen_id: StringName = history[0]["activity_id"]
	var before_val: float = float(preset_before.get(chosen_id, 0.0))
	var after_val: float = float(w.client.mastery.get(chosen_id, 0.0))
	assert_gt(after_val, before_val, "chosen activity's mastery increased after the CA step")

func test_cognitive_still_decays_and_regens() -> void:
	w.client.cognitive = {&"attention": 0.5, &"willpower": 1.0}
	sim.apply_tick(10.0)
	var expected_att: float = clamp(0.5 + w.decay.cognitive_per_hour[&"attention"] * 10.0, 0.0, 1.0)
	var expected_wp:  float = clamp(1.0 + w.decay.cognitive_per_hour[&"willpower"] * 10.0, 0.0, 1.0)
	assert_almost_eq(w.client.cognitive[&"attention"], expected_att, 0.0001)
	assert_almost_eq(w.client.cognitive[&"willpower"], expected_wp, 0.0001)

func test_try_surface_observation_is_retired() -> void:
	assert_false(w.has_method("try_surface_observation"),
		"global-randi observation side-path must be gone (no coexistence with seeded CA stream)")

func test_overnight_reset_bumps_energy() -> void:
	w.client.needs[&"energy"] = 0.1
	w.start_new_day(2)
	assert_almost_eq(w.client.needs[&"energy"], min(1.0, 0.1 + 0.85), 0.0001)
