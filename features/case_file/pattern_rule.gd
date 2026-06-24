class_name PatternRule extends Resource

## A Lens rule that reads the CA living-sim's activity history and, when its predicate
## holds, yields an OBSERVATIONAL-TRACE fact onto the desk's case file (provenance
## &"derived"). Pure content type — no behavior; PatternDeriver (Slice C) evaluates it.
##
## A rule fires when, within the trailing `window_days`, the client has performed an
## activity matching `predicate_type` at least `min_count` times (optionally scoped to a
## need via `need_key`). When it fires, the deriver DUPLICATEs `trace_fact`, tags it
## provenance=&"derived", and emits it — the rule itself never mutates its trace_fact.
##
## `evidence_query` is a Slice-2 placeholder (authored empty this slice).

@export var id: StringName

## Activity / behavior class the predicate counts (e.g. &"isolation", &"avoidance").
@export var predicate_type: StringName

## Minimum matching occurrences within the window for the rule to fire.
@export var min_count: int = 0

## Trailing window, in days, over which occurrences are counted.
@export var window_days: int = 0

## Optional need the predicate is scoped to (e.g. &"social"); &"" = unscoped.
@export var need_key: StringName

## The fact emitted (after duplication + provenance tagging) when the rule fires.
@export var trace_fact: CaseEntry

## Slice-2 placeholder — authored empty this slice.
@export var evidence_query: StringName = &""
