extends GutTest

## Sandbox-parity DISTRIBUTION test (oracle check) — PLAN-001 Task 9.
##
## Guards against silent unit/scoring divergence between the GDScript CAEngine
## (features/sim/ca_engine.gd) and the design oracle it was ported from
## (lifelines-core-loop/playgrounds/full_ca_sandbox.html). The classic failure this
## catches is the 0-100 vs 0-1 unit mismatch: re-introducing the sandbox's /100 in
## restoration collapses every need-pressure score and the run death-spirals onto a
## couple of survival activities. A correct port keeps Elling's Blue/Green discretionary
## life (telescope / read / window) alive alongside the recurring needs (eat / bathroom).
##
## WHY DISTRIBUTIONAL, NOT EXACT-SEQUENCE
## --------------------------------------
## The sandbox draws randomness from mulberry32; Godot's RandomNumberGenerator is a
## different PRNG (PCG-family). At the SAME seed the two emit DIFFERENT random streams,
## so the per-step jitter and the weighted top-3 selection diverge — exact activity-id
## sequence parity is IMPOSSIBLE. What IS portable is the SHAPE of the decision field:
## the scoring function, the personality pull, the need urgencies, the catalog, and the
## sim loop are identical, so the DISTRIBUTION of choices over a 14-day run must match.
## We therefore assert: (1) the dominant activity equals the oracle's, (2) the GDScript
## top-3 overlaps the oracle top-3, (3) the stable backbone activities all appear, and
## (4) entropy sits in the oracle's healthy band (no death-spiral, no monoculture).
##
## ORACLE SOURCE
## -------------
## Captured by running the sandbox's scoreActivity / flowOutput / runSimulation /
## ACTIVITIES / CHARACTER_PRESETS[0]=Elling / mulberry32 verbatim under node.js at the
## fixed seed below for a 14-day (112-decision) run. The Elling preset start-mastery is
## baked into the authored .tres start_mastery values (Use Telescope 0.6, Read Book 0.4,
## Look Through Window 0.7, Do Crossword 0.3, Lock Doors 0.8, Small Talk 0.1,
## Water Plants 0.3, Check on Elling 0.5), so the GDScript catalog reproduces the
## oracle's initial mastery exactly.
##
##   Oracle (Elling, seed 747, 14 days x 8/day = 112 decisions):
##     Use Telescope        25  22.3%   <- dominant (Blue/Green personality + high mastery)
##     Read Book            22  19.6%
##     Use Bathroom         19  17.0%
##     Eat Meal             18  16.1%
##     Lock Doors           17  15.2%
##     Look Through Window   5   4.5%
##     Grab a Snack          4   3.6%
##     Check on Elling       2   1.8%
##     distinct = 8   entropy = 2.691 bits
##   The dominant (Use Telescope) is stable across every seed probed (42/747/1/100/2026:
##   always #1 at 22-27%); the {Telescope, Read Book, Bathroom, Eat Meal, Lock Doors}
##   backbone is present at every seed. That stability is what makes a distributional
##   assertion safe against RNG drift.
##
## Verified red-green: 2026-06-24

const SEED := 747
const DECISIONS_PER_DAY := 8
const DAYS := 14
const NEEDS := [&"hunger", &"bladder", &"energy", &"social", &"security"]

# --- Embedded oracle constants (sandbox @ seed 747, see doc above) ------------
const ORACLE_DOMINANT := &"act_use_telescope"
# The oracle's top-3 by count. The GDScript top-3 must overlap this set (>= 2 of 3),
# since RNG drift can swap the #2/#3 slots among the backbone activities.
const ORACLE_TOP3 := [&"act_use_telescope", &"act_read_book", &"act_use_bathroom"]
# Backbone: present at EVERY probed seed. A correct port keeps all five alive; a
# unit-mismatch death-spiral drops the discretionary ones (telescope/read/window).
const ORACLE_BACKBONE := [
	&"act_use_telescope", &"act_read_book", &"act_use_bathroom",
	&"act_eat_meal", &"act_lock_doors",
]
const ORACLE_ENTROPY := 2.691
const ORACLE_DISTINCT := 8

# Sandbox NEED_DECAY (L230) and overnight reset (L401-403) in native 0-1 units
# (sandbox values / 100), driving the run so the distribution is comparable.
const NEED_DECAY := {
	&"hunger": 0.050, &"bladder": 0.055, &"energy": 0.025, &"social": 0.020, &"security": 0.035,
}
const HOURS_PER_DECISION := 14.0 / float(DECISIONS_PER_DAY)
const DECAY_FACTOR := 0.905  # sandbox state.decayFactor (L287); overnight mastery decay.

# Elling start needs (sandbox preset, /100) and color vector.
const START_NEEDS := {
	&"hunger": 0.75, &"bladder": 0.60, &"energy": 0.70, &"social": 0.40, &"security": 0.55,
}
const ELLING_COLORS := [0.0, 0.8, 0.0, 0.0, 0.4]


func _activities() -> Array:
	# The 18-activity Elling catalog, in a stable id order so the seeded RNG drives a
	# reproducible run regardless of Dictionary iteration order.
	var out: Array = []
	for a: Activity in Catalog.activities.values():
		out.append(a)
	out.sort_custom(func(x: Activity, y: Activity) -> bool: return String(x.id) < String(y.id))
	return out


func _fresh_mastery(activities: Array) -> Dictionary:
	# NEED activities start mastered (0.9); others use authored start_mastery, which
	# equals the Elling preset mastery the oracle uses.
	var m: Dictionary = {}
	for a: Activity in activities:
		m[a.id] = 0.9 if a.model == &"NEED" else a.start_mastery
	return m


## Drive a full 14-day run through CAEngine, replicating the sandbox sim loop (per-step
## need decay, overnight need reset, overnight mastery decay for activities not done that
## day). `effect_scale` multiplies every authored effect — used by the red-green guard to
## prove a mis-scale collapses the distribution. Returns the activity-choice histogram.
func _run(activities_in: Array, effect_scale: float) -> Dictionary:
	# Local copy of the activities so we can scale effects WITHOUT touching production.
	var activities: Array = []
	for a: Activity in activities_in:
		var clone: Activity = a.duplicate(true)
		if effect_scale != 1.0:
			var scaled: Dictionary = {}
			for n: StringName in clone.effects.keys():
				scaled[n] = float(clone.effects[n]) * effect_scale
			clone.effects = scaled
		activities.append(clone)

	var engine := CAEngine.new()
	engine.init_seed(SEED)
	var needs: Dictionary = START_NEEDS.duplicate()
	var mastery: Dictionary = _fresh_mastery(activities)

	var counts: Dictionary = {}
	var current_day := -1
	var day_activities: Dictionary = {}
	var total_steps := DAYS * DECISIONS_PER_DAY

	for step in range(total_steps):
		var day := step / DECISIONS_PER_DAY
		if day != current_day:
			if current_day >= 0:
				# Overnight mastery decay for activities NOT done today (sandbox L390-396).
				for a: Activity in activities:
					if not day_activities.has(a.id):
						mastery[a.id] = float(mastery.get(a.id, 0.0)) * DECAY_FACTOR
				# Overnight need reset (sandbox L401-403).
				needs[&"energy"] = minf(1.0, needs[&"energy"] + 0.85)
				needs[&"hunger"] = maxf(0.0, needs[&"hunger"] - 0.30)
				needs[&"bladder"] = maxf(0.0, needs[&"bladder"] - 0.35)
			current_day = day
			day_activities = {}

		# Per-step need decay (sandbox L410-414).
		for n: StringName in NEEDS:
			needs[n] = maxf(0.0, needs[n] - NEED_DECAY[n] * HOURS_PER_DECISION)

		var res := engine.select_and_apply(needs, mastery, ELLING_COLORS, activities)
		var aid: StringName = res["activity_id"]
		counts[aid] = int(counts.get(aid, 0)) + 1
		day_activities[aid] = true

	return counts


func _sorted_ids_by_count(counts: Dictionary) -> Array:
	var ids: Array = counts.keys()
	ids.sort_custom(func(x: StringName, y: StringName) -> bool:
		return int(counts[x]) > int(counts[y]))
	return ids


func _entropy(counts: Dictionary, total: int) -> float:
	var h := 0.0
	for k: StringName in counts.keys():
		var p := float(counts[k]) / float(total)
		if p > 0.0:
			h -= p * (log(p) / log(2.0))
	return h


# --- DISTRIBUTIONAL PARITY (assert the ORACLE values) -------------------------

func test_dominant_activity_matches_sandbox_oracle() -> void:
	var counts := _run(_activities(), 1.0)
	var ordered := _sorted_ids_by_count(counts)
	assert_gt(ordered.size(), 0, "Run produced no choices")
	var dominant: StringName = ordered[0]
	assert_eq(dominant, ORACLE_DOMINANT,
		"GDScript dominant activity (%s) must match the sandbox oracle (%s @ seed %d). A unit/scoring divergence would surface a survival activity (eat/bathroom) here instead of %s." % [dominant, ORACLE_DOMINANT, SEED, ORACLE_DOMINANT])


func test_top3_overlaps_sandbox_oracle_top3() -> void:
	var counts := _run(_activities(), 1.0)
	var ordered := _sorted_ids_by_count(counts)
	var gds_top3: Array = ordered.slice(0, 3)
	var overlap := 0
	for aid: StringName in gds_top3:
		if ORACLE_TOP3.has(aid):
			overlap += 1
	# RNG drift can swap the #2/#3 backbone slots, so require >= 2 of 3 overlap, not 3.
	assert_gte(overlap, 2,
		"GDScript top-3 %s must overlap the oracle top-3 %s by >= 2 (got %d)." % [gds_top3, ORACLE_TOP3, overlap])


func test_backbone_activities_all_present() -> void:
	# The five activities the oracle reaches for at every seed must all be chosen. If a
	# unit mismatch death-spirals the run, the discretionary backbone (telescope/read)
	# vanishes — this is the primary divergence guard.
	var counts := _run(_activities(), 1.0)
	for aid: StringName in ORACLE_BACKBONE:
		assert_gt(int(counts.get(aid, 0)), 0,
			"Backbone activity %s never chosen — distribution diverged from oracle (likely unit collapse)." % aid)


func test_entropy_in_healthy_band() -> void:
	# Oracle entropy = 2.691 bits. A healthy living-sim sits in a band around it; a
	# death-spiral collapses toward ~1 bit (two survival activities), a uniform random
	# picker would overshoot. Band: [2.0, 3.5] bits, distinct >= 6.
	var counts := _run(_activities(), 1.0)
	var total := DAYS * DECISIONS_PER_DAY
	var h := _entropy(counts, total)
	assert_between(h, 2.0, 3.5,
		"Choice entropy %0.3f bits outside healthy band [2.0,3.5] (oracle %0.3f)." % [h, ORACLE_ENTROPY])
	assert_gte(counts.size(), 6,
		"Only %d distinct activities (oracle %d) — too monotonous." % [counts.size(), ORACLE_DISTINCT])


# --- RED-GREEN GUARD ----------------------------------------------------------
# Documents the failure the suite catches: scaling effects 100x re-creates the 0-1 vs
# 0-100 unit mismatch. Restoration/drain explode, the score field collapses, and the run
# death-spirals onto need-survival activities — dominant flips off Use Telescope and the
# discretionary backbone disappears. This test ASSERTS that collapse so the guard above
# is proven to be able to fail (it is the inverse of the parity tests). Run during
# red-green by temporarily flipping the parity tests to effect_scale=100.0.

func test_red_green_scaled_effects_collapse_distribution() -> void:
	var counts := _run(_activities(), 100.0)
	var ordered := _sorted_ids_by_count(counts)
	var dominant: StringName = ordered[0]
	# With effects 100x, need-pressure dwarfs personality; the dominant is no longer the
	# personality-driven telescope. This proves the parity tests are not vacuous.
	assert_ne(dominant, ORACLE_DOMINANT,
		"Scaling effects 100x should break dominant-activity parity (collapse to survival), but dominant stayed %s." % dominant)
