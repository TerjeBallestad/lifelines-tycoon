extends Node

const DEFAULT_COMMS_DIR := "user://harness_comms_default"

func _ready() -> void:
	_apply_cli_flags()
	if AgentBridge.active:
		# Headless agent run: skip UI, do not auto-start Sim.
		# Bridge controls Sim ticking via `advance` op.
		return
	var ui: PackedScene = load("res://features/ui/main_ui.tscn")
	add_child(ui.instantiate())
	EventBus.day_started.emit(Clock.day)
	Sim.start()

func _apply_cli_flags() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
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
		i += 1
