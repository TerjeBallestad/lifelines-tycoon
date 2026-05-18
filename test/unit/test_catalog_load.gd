extends GutTest

func test_catalog_loads_seed_content() -> void:
	assert_gte(Catalog.diagnostics.size(), 3, "Expected 3 diagnostics loaded")
	assert_gte(Catalog.interventions.size(), 5, "Expected 5 interventions loaded")
	assert_gte(Catalog.observations.size(), 15, "Expected 15 observations loaded")

func test_known_ids_present() -> void:
	assert_true(Catalog.diagnostics.has(&"diag_psych_eval"))
	assert_true(Catalog.interventions.has(&"int_reading_together"))
	assert_true(Catalog.observations.has(&"obs_reading_corner"))
	assert_true(Catalog.observations.has(&"obs_tired"))
