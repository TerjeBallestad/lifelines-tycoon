class_name PatternDeriver extends RefCounted

## The Lens. Reads the living sim's activity history through the ONE stable seam —
## World.get_activity_history() (NOT CAEngine internals) — evaluates each authored
## PatternRule's predicate against that history, and for any rule whose predicate
## newly holds emits a DERIVED CaseEntry onto the desk's case file.
##
## A fired fact is a TRACE (an observed behavioural pattern), never a diagnosis: the
## deriver DUPLICATEs the rule's shared trace_fact .tres, tags the copy
## provenance=&"derived", routes it through World.case_file.add_entry(), and emits
## EventBus.case_file_updated(fact.id). The shared .tres is never mutated.
##
## Firing is deduped: a rule that has fired once is never emitted again, even across
## repeated evaluate() calls. Decision categories (activity ids) that NO rule matched
## are accumulated into an uncovered-behavior channel (get_uncovered_summary()) so the
## designer surface and the blind-read prompt can see what the Lens is blind to.

const PREDICATE_NEED_DEFICIT := &"need_deficit_over_window"
const PREDICATE_ACTIVITY_FIXATION := &"activity_fixation"

var _world: Node
## StringName(rule.id) -> true once a rule has fired (dedupe).
var _fired: Dictionary = {}
## StringName(activity_id) -> int count of history records no rule matched.
var _uncovered: Dictionary = {}

func _init(world_ref: Node) -> void:
	_world = world_ref

## Evaluate every loaded PatternRule against `history`. Fires (once) each rule whose
## predicate newly holds, and records every history category no rule covered.
func evaluate(history: Array) -> void:
	var covered_activities: Dictionary = {}
	for rule: PatternRule in Catalog.pattern_rules.values():
		var holds := _predicate_holds(rule, history)
		if holds:
			_mark_covered(rule, history, covered_activities)
		if holds and not _fired.has(rule.id):
			_emit_derived(rule)
			_fired[rule.id] = true
	_accumulate_uncovered(history, covered_activities)

## Returns the uncovered-behavior channel: activity categories present in history that
## no rule matched, with their occurrence counts. Surfaces the Lens's blind spots.
func get_uncovered_summary() -> Dictionary:
	return _uncovered.duplicate()

func has_fired(rule_id: StringName) -> bool:
	return _fired.has(rule_id)

func _emit_derived(rule: PatternRule) -> void:
	if rule.trace_fact == null:
		push_warning("PatternDeriver: rule '%s' has no trace_fact" % rule.id)
		return
	var fact: CaseEntry = rule.trace_fact.duplicate()
	fact.provenance = &"derived"
	_world.case_file.add_entry(fact)
	EventBus.case_file_updated.emit(fact.id)

func _predicate_holds(rule: PatternRule, history: Array) -> bool:
	match rule.predicate_type:
		PREDICATE_NEED_DEFICIT:
			return _need_deficit_over_window(rule, history)
		PREDICATE_ACTIVITY_FIXATION:
			return _activity_fixation(rule, history)
		_:
			push_warning("PatternDeriver: unknown predicate_type '%s' on rule '%s'" % [rule.predicate_type, rule.id])
			return false

## Fires when, within the trailing `window_days`, at least `min_count` history records
## show the named need at/above-deficit (need value >= a high-pressure threshold). Need
## values are normalised 0..1 where higher = more unmet pressure.
func _need_deficit_over_window(rule: PatternRule, history: Array) -> bool:
	var max_day := _latest_day(history)
	var floor_day := max_day - rule.window_days + 1
	var count := 0
	for rec: Dictionary in history:
		if int(rec.get("day", 0)) < floor_day:
			continue
		var snapshot: Dictionary = rec.get("needs_snapshot", {})
		if not snapshot.has(rule.need_key):
			continue
		if float(snapshot[rule.need_key]) >= NEED_DEFICIT_THRESHOLD:
			count += 1
	return count >= rule.min_count

const NEED_DEFICIT_THRESHOLD := 0.7

## Fires when the client performed the `predicate`-named activity at least `min_count`
## times in the whole history (fixation on one behaviour). The activity class is read
## from `need_key` when set, else from `predicate_type`-suffix-free `id`... here we use
## the rule's `need_key` slot as the activity id when authored, falling back to matching
## any record. For Slice-1 authored rules, the activity id to count lives in need_key.
func _activity_fixation(rule: PatternRule, history: Array) -> bool:
	var target := rule.need_key
	var count := 0
	for rec: Dictionary in history:
		if StringName(rec.get("activity_id", &"")) == target:
			count += 1
	return count >= rule.min_count

func _mark_covered(rule: PatternRule, history: Array, covered: Dictionary) -> void:
	# A rule that holds "covers" the activity categories it counts, so they are not
	# reported as uncovered behaviour.
	match rule.predicate_type:
		PREDICATE_ACTIVITY_FIXATION:
			covered[rule.need_key] = true
		PREDICATE_NEED_DEFICIT:
			for rec: Dictionary in history:
				var snapshot: Dictionary = rec.get("needs_snapshot", {})
				if snapshot.has(rule.need_key):
					covered[StringName(rec.get("activity_id", &""))] = true

func _accumulate_uncovered(history: Array, covered: Dictionary) -> void:
	for rec: Dictionary in history:
		var activity := StringName(rec.get("activity_id", &""))
		if covered.has(activity):
			continue
		_uncovered[activity] = int(_uncovered.get(activity, 0)) + 1

func _latest_day(history: Array) -> int:
	var latest := 0
	for rec: Dictionary in history:
		latest = max(latest, int(rec.get("day", 0)))
	return latest
