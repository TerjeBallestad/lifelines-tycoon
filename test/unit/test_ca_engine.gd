extends GutTest

## Behavioral guards for the CA decision kernel (CAEngine, PLAN-001 Task 6).
##
## Three properties the kernel must hold, ported from the sandbox's validated
## behavior (lifelines-core-loop/playgrounds/full_ca_sandbox.html):
##   (a) DETERMINISM — two engines seeded identically produce IDENTICAL activity-id
##       sequences over the same N-step run (the seeded gate depends on this).
##   (b) NO DEATH-SPIRAL — over a 14-day-equivalent run no single need stays pinned at
##       0 the whole run, AND a healthy variety of activities is chosen (entropy guard).
##   (c) UNIT SANITY — an eat-meal-type activity (effects.hunger > 0) raises hunger
##       toward 1.0 by ~its 0-1 magnitude, NOT 60x. Re-introducing the sandbox /100 in
##       restoration collapses scores and breaks this (see red-green note).
##
## Verified red-green: 2026-06-24

const SEED := 747
const DECISIONS_PER_DAY := 8
const DAYS := 14

# Sandbox NEED_DECAY (L230) and overnight reset (L401-403), expressed in native 0-1
# units (sandbox values / 100). Used only to drive a realistic multi-step run so the
# death-spiral guard is meaningful; the kernel itself owns no time.
const NEED_DECAY := {
	&"hunger": 0.050, &"bladder": 0.055, &"energy": 0.025, &"social": 0.020, &"security": 0.035,
}
const HOURS_PER_DECISION := 14.0 / float(DECISIONS_PER_DAY)
const NEEDS := [&"hunger", &"bladder", &"energy", &"social", &"security"]

# Elling start needs (sandbox L260, /100) and color vector.
const START_NEEDS := {
	&"hunger": 0.75, &"bladder": 0.60, &"energy": 0.70, &"social": 0.40, &"security": 0.55,
}
const ELLING_COLORS := [0.0, 0.8, 0.0, 0.0, 0.4]


func _activities() -> Array:
	var out: Array = []
	for a: Activity in Catalog.activities.values():
		out.append(a)
	# Stable order so the seeded RNG drives a reproducible run regardless of dict order.
	out.sort_custom(func(x, y): return String(x.id) < String(y.id))
	return out


func _fresh_mastery(activities: Array) -> Dictionary:
	# NEED activities start mastered (0.9); others use authored start_mastery.
	var m: Dictionary = {}
	for a: Activity in activities:
		m[a.id] = 0.9 if a.model == &"NEED" else a.start_mastery
	return m


## Drive a full N-day run through the kernel, applying the same per-step need decay and
## overnight reset the sandbox uses. Returns:
##   chosen        Array[StringName]  — the picked activity-id per step
##   above_zero    Dict need->int     — # of post-decision steps the need was > 0
##   total_steps   int
##   distinct      int                — distinct activities chosen
## A need that recovers (is serviced) spends nearly all steps above 0; a death-spiral
## need is pinned at 0 for the whole run (above_zero == 0).
func _run(seed_value: int, days: int) -> Dictionary:
	var activities := _activities()
	var engine := CAEngine.new()
	engine.init_seed(seed_value)
	var needs: Dictionary = START_NEEDS.duplicate()
	var mastery: Dictionary = _fresh_mastery(activities)

	var chosen: Array = []
	var above_zero: Dictionary = {}
	for n: StringName in NEEDS:
		above_zero[n] = 0
	var seen: Dictionary = {}

	var current_day := -1
	var total_steps := days * DECISIONS_PER_DAY
	for step in range(total_steps):
		var day := step / DECISIONS_PER_DAY
		# New day: overnight reset (sandbox L388-405).
		if day != current_day:
			if current_day >= 0:
				needs[&"energy"] = minf(1.0, needs[&"energy"] + 0.85)
				needs[&"hunger"] = maxf(0.0, needs[&"hunger"] - 0.30)
				needs[&"bladder"] = maxf(0.0, needs[&"bladder"] - 0.35)
			current_day = day

		# Per-step decay (sandbox L410-414).
		for n: StringName in NEEDS:
			needs[n] = maxf(0.0, needs[n] - NEED_DECAY[n] * HOURS_PER_DECISION)

		var res := engine.select_and_apply(needs, mastery, ELLING_COLORS, activities)
		var aid: StringName = res["activity_id"]
		chosen.append(aid)
		seen[aid] = true
		# Sample AFTER the kernel responds: this reflects whether the need recovers.
		for n: StringName in NEEDS:
			if needs[n] > 0.0:
				above_zero[n] += 1

	return {
		"chosen": chosen,
		"above_zero": above_zero,
		"total_steps": total_steps,
		"distinct": seen.size(),
	}


# --- (a) DETERMINISM ---------------------------------------------------------

func test_determinism_identical_seeds_identical_sequences() -> void:
	var a := _run(SEED, DAYS)
	var b := _run(SEED, DAYS)
	assert_eq(a["chosen"].size(), b["chosen"].size(), "Run lengths must match")
	assert_eq(a["chosen"], b["chosen"],
		"Two CAEngines seeded %d must produce identical activity-id sequences" % SEED)


func test_determinism_different_seeds_differ() -> void:
	# Sanity: the seed actually drives the sequence (guards against a dead RNG).
	var a := _run(SEED, DAYS)
	var b := _run(SEED + 1, DAYS)
	assert_ne(a["chosen"], b["chosen"],
		"Different seeds should not produce identical sequences (RNG must be live)")


# --- (b) NO DEATH-SPIRAL ------------------------------------------------------

func test_no_need_pinned_at_zero_whole_run() -> void:
	var r := _run(SEED, DAYS)
	var total: int = r["total_steps"]
	for n: StringName in NEEDS:
		var ok: int = r["above_zero"][n]
		# A serviced need recovers: it is above 0 for the large majority of steps. A
		# death-spiralled need is stuck at 0 (ok == 0) or near it. Floor at 80% of steps.
		assert_gte(ok, int(total * 0.80),
			"Need %s recovered on only %d/%d steps — pinned near 0 (death-spiral)" % [n, ok, total])


func test_activity_variety_entropy_guard() -> void:
	var r := _run(SEED, DAYS)
	# Over 112 decisions a healthy living-sim should reach for a real variety of
	# activities, not loop on 2-3. K = 6 distinct of 18.
	assert_gte(int(r["distinct"]), 6,
		"Only %d distinct activities chosen over %d days — too monotonous" % [r["distinct"], DAYS])


# --- (c) UNIT SANITY ----------------------------------------------------------

func test_eat_meal_raises_hunger_by_its_magnitude_not_60x() -> void:
	var act: Activity = Catalog.activities[&"act_eat_meal"]
	assert_not_null(act, "act_eat_meal must exist in Catalog")
	var magnitude := float(act.effects[&"hunger"])
	assert_gt(magnitude, 0.0, "Eat Meal must have positive hunger effect")

	# Hungry client: hunger low so eat-meal is the obvious pick.
	var needs: Dictionary = {
		&"hunger": 0.10, &"bladder": 0.80, &"energy": 0.80, &"social": 0.80, &"security": 0.80,
	}
	var before := float(needs[&"hunger"])
	var mastery: Dictionary = {&"act_eat_meal": 0.9}

	var engine := CAEngine.new()
	engine.init_seed(SEED)
	# Single activity in the pool so the chosen effect is unambiguous.
	engine.select_and_apply(needs, mastery, ELLING_COLORS, [act])

	var after := float(needs[&"hunger"])
	var delta := after - before
	# Native 0-1: delta ~= magnitude (0.6), bounded by clamp to 1.0. NOT 60x (which the
	# old /100 sandbox scale would imply if effects were mis-scaled).
	assert_almost_eq(delta, magnitude, 0.001,
		"Eat Meal should raise hunger by ~%s (native 0-1), got delta %s" % [magnitude, delta])
	assert_lte(after, 1.0, "Hunger must stay clamped to 1.0")
	assert_lt(delta, 1.0, "A single eat-meal must not jump hunger by ~60 (mis-scaled units)")
