extends GutTest

## Guards the provenance origin tag on CaseEntry (Option B — no EventBus signature
## change). Provenance is SEPARATE from the `source` KIND enum: it distinguishes
## derived (CA-emergent) facts from authored (scheduled-consequence) facts, so the
## desk + blind-read snapshot can tell them apart.
##
## Verified red-green: 2026-06-24

const PHONE_ENTRY := "res://features/case_file/seed/obs_phone_unanswered.tres"

func test_fresh_entry_defaults_to_authored() -> void:
	var e := CaseEntry.new()
	assert_eq(e.provenance, &"authored")

func test_consequence_linked_tres_reports_authored() -> void:
	# obs_phone_unanswered is the CaseEntry referenced by the apt_phone_window
	# ScheduledConsequence (observation_id = &"obs_phone_unanswered").
	var entry: CaseEntry = load(PHONE_ENTRY)
	assert_not_null(entry, "consequence-linked CaseEntry .tres should load")
	assert_eq(entry.provenance, &"authored")
