extends GutTest

## Verifies the --seed CLI flag parse path (main.gd) captures the integer into
## World.ca_seed BEFORE the Sim/World boot path runs, so CAEngine (a later task)
## can seed its PRIVATE RandomNumberGenerator from it at first tick. We do not
## call global seed(); ca_seed is just a slot CAEngine consumes.
##
## NOTE: Two CA runs started from the same ca_seed must later produce IDENTICAL
## CA history. That determinism is asserted in a later task (once CAEngine exists);
## this test only guards the flag-to-slot wiring.
##
## Verified red-green: 2026-06-24

const MainScript := preload("res://main.gd")

func _world() -> Node:
	return get_node("/root/World")

func test_parse_seed_reads_int_after_flag() -> void:
	var args := PackedStringArray(["--seed", "747"])
	assert_eq(MainScript._parse_seed(args), 747)

func test_parse_seed_among_other_flags() -> void:
	var args := PackedStringArray(["--reveal-hidden", "--seed", "747", "--agent-mode"])
	assert_eq(MainScript._parse_seed(args), 747)

func test_parse_seed_absent_defaults_zero() -> void:
	var args := PackedStringArray(["--agent-mode", "--reveal-hidden"])
	assert_eq(MainScript._parse_seed(args), 0)

func test_parse_seed_trailing_flag_no_value_defaults_zero() -> void:
	var args := PackedStringArray(["--agent-mode", "--seed"])
	assert_eq(MainScript._parse_seed(args), 0)

func test_seed_assigns_world_slot() -> void:
	# Mirror what _apply_cli_flags() does: assign the parsed seed into the
	# World-readable slot. This is the slot CAEngine reads at first tick.
	var w := _world()
	var prior: int = w.ca_seed
	w.ca_seed = MainScript._parse_seed(PackedStringArray(["--seed", "747"]))
	assert_eq(w.ca_seed, 747)
	w.ca_seed = prior
