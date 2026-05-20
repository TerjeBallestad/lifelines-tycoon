extends Node
## Adapter between external agent processes and the game's mutation API.
## Dormant by default; activated by --agent-mode CLI flag (parsed in main.gd).

var active: bool = false
var reveal_hidden: bool = false
var comms_dir: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
