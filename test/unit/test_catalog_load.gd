extends GutTest

## Catalog load-count + known-id coverage, incl. the Activity + PatternRule allowlist (Task 4).
## Verified red-green: 2026-06-24

func test_catalog_loads_seed_content() -> void:
	assert_gte(Catalog.diagnostics.size(), 3, "Expected 3 diagnostics loaded")
	assert_gte(Catalog.interventions.size(), 5, "Expected 5 interventions loaded")
	assert_gte(Catalog.away_actions.size(), 1, "Expected 1 away action loaded")
	assert_gte(Catalog.observations.size(), 15, "Expected 15 observations loaded")
	assert_gte(Catalog.consequences.size(), 1, "Expected 1 scheduled consequence loaded")
	# Proves the allowlist admits the Activity and PatternRule types and each loads.
	# Task 5 authored the 18 real activities (placeholder removed); Task 11 authored 5 pattern rules (placeholder removed).
	assert_gte(Catalog.activities.size(), 18, "Expected all 18 activities loaded")
	assert_gte(Catalog.pattern_rules.size(), 5, "Expected the 5 authored pattern rules loaded (Task 11)")

func test_known_ids_present() -> void:
	assert_true(Catalog.diagnostics.has(&"diag_psych_eval"))
	assert_true(Catalog.interventions.has(&"int_reading_together"))
	assert_true(Catalog.away_actions.has(&"desk_nav_backlog"))
	assert_true(Catalog.observations.has(&"obs_reading_corner"))
	assert_true(Catalog.observations.has(&"obs_tired"))
	assert_true(Catalog.consequences.has(&"apt_phone_window"))
