extends GutTest

## Headless guard for the Legibility Desk Gym (scenes/gym/legibility_desk_gym.tscn).
## Loads + instantiates the gym scene, lets it boot (its _ready() starts the live sim),
## then calls gym.run_assertions(), which drives ~12 deterministic sim days and asserts
## at least one DERIVED case-file entry (provenance == &"derived") surfaced on the desk.
## This proves the gym actually boots the live CA sim and that the day-end PatternDeriver
## turns emergent behaviour into legible trace facts.
##
## Verified red-green: 2026-06-25
## (Temporarily editing run_assertions in legibility_desk_gym.gd to advance 0 days makes
## the derived-fact count 0, and this shim fails as required.)

const GYM_SCENE := "res://scenes/gym/legibility_desk_gym.tscn"


func test_gym_boots_and_derives_at_least_one_fact() -> void:
	var packed: PackedScene = load(GYM_SCENE) as PackedScene
	assert_not_null(packed, "gym scene must load")

	var gym: Control = packed.instantiate() as Control
	assert_not_null(gym, "gym scene must instantiate as a Control")
	add_child(gym)

	# Let _ready() run and a couple of frames settle (it boots the live sim).
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(gym.has_method("run_assertions"), "gym exposes run_assertions()")
	var result: Dictionary = gym.run_assertions()

	gut.p("gym run_assertions -> %s" % str(result))
	assert_true(bool(result.get("passed", false)), "gym run_assertions must pass")
	var failures: Array = result.get("failures", [])
	assert_eq(failures.size(), 0, "gym run_assertions reported failures: %s" % str(failures))

	gym.queue_free()
