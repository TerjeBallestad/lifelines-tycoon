extends GutTest

func test_catalog_loads_seed_content() -> void:
	assert_gte(Catalog.diagnostics.size(), 3, "Expected 3 diagnostics loaded")
	assert_gte(Catalog.interventions.size(), 5, "Expected 5 interventions loaded")
	assert_gte(Catalog.away_actions.size(), 1, "Expected 1 away action loaded")
	assert_gte(Catalog.observations.size(), 15, "Expected 15 observations loaded")
	assert_gte(Catalog.consequences.size(), 1, "Expected 1 scheduled consequence loaded")

func test_known_ids_present() -> void:
	assert_true(Catalog.diagnostics.has(&"diag_psych_eval"))
	assert_true(Catalog.interventions.has(&"int_reading_together"))
	assert_true(Catalog.away_actions.has(&"desk_nav_backlog"))
	assert_true(Catalog.observations.has(&"obs_reading_corner"))
	assert_true(Catalog.observations.has(&"obs_tired"))
	assert_true(Catalog.consequences.has(&"apt_phone_window"))
