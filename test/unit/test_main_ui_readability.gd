extends GutTest

func before_each() -> void:
	Clock.reset()
	Sim.reset_for_test()
	World.reset_for_test()

func test_resource_strip_shows_visible_resource_state() -> void:
	var ui := _spawn_ui()
	await get_tree().process_frame

	var resource_label := ui.find_child("ResourceLabel", true, false) as Label
	assert_not_null(resource_label, "Main UI should include a visible resource strip")
	if resource_label == null:
		return
	assert_string_contains(resource_label.text, "Trust 1")
	assert_string_contains(resource_label.text, "Dice 1")
	assert_string_contains(resource_label.text, "Knowledge 0")

func test_phone_practice_button_explains_visible_costs_and_effects() -> void:
	World.try_run_away_action(&"desk_nav_backlog")
	World.return_to_apartment()
	var ui := _spawn_ui()
	await get_tree().process_frame

	var button := _find_button_containing(ui, "Phone Call Practice")
	assert_not_null(button, "Unlocked intervention should be visible in the real action list")
	assert_string_contains(button.text, "Trust -2")
	assert_string_contains(button.text, "Dice -1")
	assert_string_contains(button.text, "Knowledge +2")

func test_resource_change_log_makes_arbitrage_result_readable() -> void:
	World.try_run_away_action(&"desk_nav_backlog")
	World.return_to_apartment()
	var ui := _spawn_ui()
	await get_tree().process_frame

	assert_true(World.try_assign_intervention(&"int_phone_practice"))
	await get_tree().process_frame

	var action_log := ui.find_child("ActionLog", true, false) as RichTextLabel
	assert_not_null(action_log)
	var text := action_log.get_parsed_text()
	assert_string_contains(text, "Resources")
	assert_string_contains(text, "Trust -1")
	assert_string_contains(text, "Dice -1")
	assert_string_contains(text, "Knowledge +2")

func _spawn_ui() -> MainUI:
	var ui := preload("res://features/ui/main_ui.tscn").instantiate() as MainUI
	add_child_autofree(ui)
	return ui

func _find_button_containing(root: Node, needle: String) -> Button:
	if root is Button and (root as Button).text.find(needle) >= 0:
		return root as Button
	for child: Node in root.get_children():
		var found := _find_button_containing(child, needle)
		if found != null:
			return found
	return null
