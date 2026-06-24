class_name CAEngine extends RefCounted

## The CA (cellular-automaton living-sim) decision kernel, ported from the design
## sandbox (lifelines-core-loop/playgrounds/full_ca_sandbox.html: flowOutput L313-322,
## scoreActivity L324-361, weighted-top-3 selection L432-438, mastery growth L446).
##
## PURE kernel: given needs (0-1), per-activity mastery, and the character's 5-float
## color vector, it scores every activity, selects one via weighted-random over the
## top 3, applies that activity's effects to needs (clamped 0-1), and grows the chosen
## activity's mastery. It does NOT own time, history, or Sim wiring.
##
## UNIT CONTRACT: needs and Activity.effects are already in NATIVE 0-1 units (Task 5).
## The sandbox divided needs/effects by 100; that /100 is REMOVED here — deficit is
## (1.0 - need) and restoration/drain use the raw 0-1 effect. Re-introducing the /100
## collapses all need-pressure scores (see test_ca_engine.gd unit-sanity / red-green).
##
## RNG: every random draw goes through the PRIVATE _rng (seeded via init_seed). NEVER
## global randi()/randf() — that would break determinism and the seeded gate.

# --- Frozen "Default" preset constants (sandbox state object, L279-298) ---
const PERS_WEIGHT := 0.20
const COMP_WEIGHT := 0.15
const DRAIN_PEN := 0.40
const LEARN_RATE := 0.09
const DECAY_FACTOR := 0.905
const AUTO_THRESH := 0.05
const RISE_EXP := 1.2
const FALL_EXP := 0.9
const PASSIVE_SOCIAL := 1.0
const PASSIVE_SECURITY := 0.25

## Per-need urgency exponents (sandbox Elling preset, L260 / state.exps L281).
const EXPS := {
	&"hunger": 3.2,
	&"bladder": 2.7,
	&"energy": 3.9,
	&"social": 4.3,
	&"security": 1.6,
}

## Fixed need order (sandbox NEEDS, L228).
const NEEDS := [&"hunger", &"bladder", &"energy", &"social", &"security"]

## Passive environment gains are expressed per sandbox "hour"; the sandbox applies them
## scaled by hoursPerDecision (14 waking hours / decisions-per-day). With the default
## 8 decisions/day that is 1.75h per decision.
const PASSIVE_HOURS_PER_DECISION := 14.0 / 8.0

var _rng := RandomNumberGenerator.new()

## Seed the private RNG. Named init_seed (not init) to avoid colliding with
## Object's constructor.
func init_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Beta-curve flow output (sandbox flowOutput, L313-322). Returns 0-1: peak competence
## at mastery == difficulty/10, falling off on either side.
func flow_output(mastery: float, difficulty: float, rise_exp: float, fall_exp: float) -> float:
	var peak := difficulty / 10.0
	if peak <= 0.01 or peak >= 0.99:
		return mastery
	var alpha := peak * rise_exp * 3.0
	var beta := (1.0 - peak) * fall_exp * 3.0
	if alpha <= 0.0 or beta <= 0.0:
		return 0.0
	var m := maxf(0.0, mastery)
	var raw := pow(m, alpha) * pow(maxf(0.0, 1.0 - mastery), beta)
	var raw_max := pow(peak, alpha) * pow(1.0 - peak, beta)
	return (raw / raw_max) if raw_max > 0.0 else 0.0


## Score one activity for the given need state, color vector, and current mastery.
## Returns {score: float, breakdown: Dictionary, affinity: float}.
## UNIT FIX vs sandbox: deficit = (1.0 - need); restoration/drain use the raw 0-1
## effect (no /100).
func score_activity(activity: Activity, needs: Dictionary, colors: Array, mastery: float) -> Dictionary:
	# 1. Need pressure
	var need_pressure := 0.0
	for n: StringName in NEEDS:
		var need_val: float = needs.get(n, 0.0)
		var deficit := maxf(0.0, 1.0 - need_val)
		var exp_n: float = EXPS[n]
		var urgency := pow(deficit, exp_n)
		var effect: float = activity.effects.get(n, 0.0)
		var restoration := maxf(0.0, effect)
		var drain := maxf(0.0, -effect)
		need_pressure += urgency * restoration
		need_pressure -= urgency * drain * DRAIN_PEN

	# 2. Personality pull
	var affinity := 0.0
	for i: int in range(5):
		var c: float = colors[i] if i < colors.size() else 0.0
		var ac: float = activity.colors[i] if i < activity.colors.size() else 0.0
		affinity += c * ac
	affinity = clampf(affinity, 0.0, 1.0)
	var personality_pull := affinity * PERS_WEIGHT

	# 3. Competence (mastery + flow output). DD-064: unmastered non-NEED activities are
	# not chosen autonomously (large negative competence).
	var competence := 0.0
	if mastery <= 0.0 and activity.model != &"NEED":
		competence = -10.0
	else:
		var flow := flow_output(mastery, activity.difficulty, RISE_EXP, FALL_EXP)
		competence = flow * COMP_WEIGHT

	# 4. Jitter (PRIVATE rng)
	var jitter := (_rng.randf() - 0.5) * 0.02

	var raw_score := need_pressure + personality_pull + competence + jitter
	return {
		"score": maxf(raw_score, 0.0),
		"breakdown": {
			"need_pressure": need_pressure,
			"personality_pull": personality_pull,
			"competence": competence,
			"jitter": jitter,
		},
		"affinity": affinity,
	}


## Select one activity via weighted-random over the top-3 scorers (sandbox L432-438).
## `scored` is an Array of {activity, score, ...} sorted nowhere yet; this sorts a copy.
## Returns the chosen entry Dictionary.
func _select_weighted_top3(scored: Array) -> Dictionary:
	var ordered := scored.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var top3 := ordered.slice(0, 3)
	var total := 0.0
	for t: Dictionary in top3:
		total += t["score"]
	var chosen: Dictionary = top3[0]
	if total > 0.0:
		var r := _rng.randf() * total
		for t: Dictionary in top3:
			r -= t["score"]
			if r <= 0.0:
				chosen = t
				break
	return chosen


## One decision step. Scores all `activities`, picks one, then MUTATES `needs`
## (applies the chosen effects, clamped 0-1, plus passive social/security gains) and
## `mastery` (grows the chosen activity per sandbox L446).
## Returns {activity_id: StringName, breakdown: Dictionary, score: float}.
func select_and_apply(needs: Dictionary, mastery: Dictionary, colors: Array, activities: Array) -> Dictionary:
	# Score all activities.
	var scored: Array = []
	for a: Activity in activities:
		var m: float = mastery.get(a.id, 0.0)
		var s := score_activity(a, needs, colors, m)
		scored.append({
			"activity": a,
			"score": s["score"],
			"breakdown": s["breakdown"],
		})

	var chosen := _select_weighted_top3(scored)
	var act: Activity = chosen["activity"]

	# Apply chosen effects to needs (clamp 0-1).
	for n: StringName in NEEDS:
		var delta: float = act.effects.get(n, 0.0)
		needs[n] = clampf(needs.get(n, 0.0) + delta, 0.0, 1.0)

	# Passive environment gains (sandbox L416-422), scaled per-decision.
	if PASSIVE_SOCIAL > 0.0:
		var soc_gain := PASSIVE_SOCIAL * PASSIVE_HOURS_PER_DECISION / 100.0
		needs[&"social"] = clampf(needs.get(&"social", 0.0) + soc_gain, 0.0, 1.0)
	if PASSIVE_SECURITY > 0.0:
		var sec_gain := PASSIVE_SECURITY * PASSIVE_HOURS_PER_DECISION / 100.0
		needs[&"security"] = clampf(needs.get(&"security", 0.0) + sec_gain, 0.0, 1.0)

	# Grow chosen activity's mastery (sandbox L446).
	var cur: float = mastery.get(act.id, 0.0)
	mastery[act.id] = minf(1.0, cur + (1.0 - cur) * LEARN_RATE)

	return {
		"activity_id": act.id,
		"breakdown": chosen["breakdown"],
		"score": chosen["score"],
	}
