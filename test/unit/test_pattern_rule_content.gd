extends GutTest

## Task 11 content guard for the authored PatternRule .tres set.
##
## The PatternDeriver (the Lens) routes a fired rule's DUPLICATED trace_fact through
## World.case_file.add_entry(), which dedupes by CaseEntry.id. If an authored rule id —
## or its trace_fact's CaseEntry id — collided with a ScheduledConsequence's
## observation_id, the add-order would decide which fact survives. So this test asserts
## the authored ids are unique among themselves AND disjoint from the whole
## Catalog.consequences observation_id set.
##
## It also LINTS the trace facts: every trace title is non-empty, and neither title nor
## body may contain a documented diagnosis keyword. A PatternRule fact is a TRACE — an
## observed behavioural pattern the caseworker must INTERPRET — never a pre-chewed
## label. Parroting "isolating"/"depressed" back from the desk defeats the legibility
## pipe, so those words are banned from authored trace content.
##
## Verified red-green: 2026-06-24
## (Temporarily adding a rule whose id == an existing consequence observation_id, e.g.
## &"obs_phone_unanswered", makes test_ids_disjoint_from_consequence_observation_ids
## FAIL on the collision assertion. Removing it restores green.)

## Diagnosis labels that must never appear in an authored trace fact. Facts describe
## what was observed; the diagnosis is the caseworker's job, not the content's.
const BANNED_DIAGNOSIS_KEYWORDS: Array[String] = [
	"depressed", "depression", "isolating", "isolated",
	"anxious", "withdrawn", "lonely",
]

func _rules() -> Array:
	return Catalog.pattern_rules.values()

func _consequence_observation_ids() -> Dictionary:
	var ids: Dictionary = {}
	for c: ScheduledConsequence in Catalog.consequences.values():
		ids[c.observation_id] = true
	return ids

func test_rules_loaded() -> void:
	# Task 11 authored the real rule set (placeholder removed). Guard the count so a
	# silently-empty load can't pass the disjointness/lint checks vacuously.
	assert_gte(_rules().size(), 5, "expected the 5 authored pattern rules to load")

func test_rule_ids_unique() -> void:
	var seen: Dictionary = {}
	for rule: PatternRule in _rules():
		assert_false(seen.has(rule.id), "duplicate PatternRule id: %s" % rule.id)
		seen[rule.id] = true

func test_trace_fact_ids_unique() -> void:
	var seen: Dictionary = {}
	for rule: PatternRule in _rules():
		assert_not_null(rule.trace_fact, "rule %s must carry a trace_fact" % rule.id)
		var tid: StringName = rule.trace_fact.id
		assert_false(seen.has(tid), "duplicate trace_fact id: %s" % tid)
		seen[tid] = true

func test_ids_disjoint_from_consequence_observation_ids() -> void:
	# Both the rule id AND its trace_fact CaseEntry id must avoid the consequence
	# observation_id namespace (the add_entry dedupe key space).
	var obs_ids: Dictionary = _consequence_observation_ids()
	assert_false(obs_ids.is_empty(), "expected at least one consequence observation_id to test against")
	for rule: PatternRule in _rules():
		assert_false(obs_ids.has(rule.id),
			"PatternRule id '%s' collides with a consequence observation_id" % rule.id)
		assert_false(obs_ids.has(rule.trace_fact.id),
			"trace_fact id '%s' collides with a consequence observation_id" % rule.trace_fact.id)

func test_trace_fact_titles_non_empty() -> void:
	for rule: PatternRule in _rules():
		assert_false(rule.trace_fact.title.strip_edges().is_empty(),
			"trace_fact for rule '%s' has an empty title" % rule.id)

func test_trace_facts_are_traces_not_diagnoses() -> void:
	for rule: PatternRule in _rules():
		var haystack := ("%s %s" % [rule.trace_fact.title, rule.trace_fact.body]).to_lower()
		for banned: String in BANNED_DIAGNOSIS_KEYWORDS:
			assert_false(haystack.contains(banned),
				"trace_fact for rule '%s' contains banned diagnosis keyword '%s' — facts must be TRACES, not labels" % [rule.id, banned])

func test_authored_trace_provenance_not_baked_derived() -> void:
	# The deriver stamps &"derived" on a DUPLICATE at fire time; the authored .tres must
	# keep the default &"authored" so the shared resource is never pre-tagged.
	for rule: PatternRule in _rules():
		assert_eq(rule.trace_fact.provenance, &"authored",
			"authored trace_fact for rule '%s' must not bake provenance=derived" % rule.id)
