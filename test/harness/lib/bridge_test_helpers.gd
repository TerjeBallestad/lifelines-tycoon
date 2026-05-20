class_name BridgeTestHelpers extends RefCounted

## Simulate CLI flag activation without re-launching the engine.
static func activate(bridge: Node, comms_dir: String, reveal_hidden: bool = false) -> void:
	bridge.active = true
	bridge.comms_dir = comms_dir
	bridge.reveal_hidden = reveal_hidden

static var _dir_counter: int = 0

static func make_tmp_comms_dir() -> String:
	_dir_counter += 1
	var dir := "user://harness_test_%d_%d" % [Time.get_ticks_msec(), _dir_counter]
	DirAccess.make_dir_recursive_absolute(dir)
	return dir
