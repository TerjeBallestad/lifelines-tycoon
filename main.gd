extends Node

const DEFAULT_COMMS_DIR := "user://harness_comms_default"

func _ready() -> void:
	_apply_cli_flags()
	if AgentBridge.active:
		AgentBridge.start_event_capture()
		AgentBridge.bind_comms(AgentBridge.comms_dir)
		AgentBridge.set_process(true)
		return
	var ui: PackedScene = load("res://features/ui/main_ui.tscn")
	add_child(ui.instantiate())
	EventBus.day_started.emit(Clock.day)
	Sim.start()

func _apply_cli_flags() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# Capture the CA seed FIRST, before any boot path consumes it. _apply_cli_flags
	# itself is the first call in _ready(), so World.ca_seed is set before Sim.start()
	# and before CAEngine's first tick can read it.
	World.ca_seed = _parse_seed(args)
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--agent-mode":
				AgentBridge.active = true
				AgentBridge.comms_dir = DEFAULT_COMMS_DIR
			"--comms-dir":
				if i + 1 < args.size():
					AgentBridge.comms_dir = args[i + 1]
					i += 1
			"--reveal-hidden":
				AgentBridge.reveal_hidden = true
			"--seed":
				# Mirror --comms-dir: read the following arg and step past it.
				if i + 1 < args.size():
					i += 1
		i += 1

# Pure, side-effect-free parse of `--seed <int>` so it can be unit-tested
# without launching the full boot. Returns the integer following the flag, or
# 0 when the flag is absent. CAEngine consumes World.ca_seed into its private RNG.
static func _parse_seed(args: PackedStringArray) -> int:
	var i := 0
	while i < args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
		i += 1
	return 0
