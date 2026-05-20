extends Node
## Adapter between external agent processes and the game's mutation API.
## Dormant by default; activated by --agent-mode CLI flag (parsed in main.gd).

var active: bool = false
var reveal_hidden: bool = false
var comms_dir: String = ""
var shutdown_requested: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func _process(_delta: float) -> void:
	if not active:
		return
	pump()
	if shutdown_requested:
		get_tree().quit(0)

# ---------------------------------------------------------------- snapshot

func build_snapshot() -> Dictionary:
	return {
		"time": _time_snapshot(),
		"client": _client_snapshot(),
		"case_file": _case_file_snapshot(),
		"economy": _economy_snapshot(),
		"catalog": _catalog_snapshot(),
	}

func _time_snapshot() -> Dictionary:
	return {
		"day": Clock.day,
		"hour": Clock.hour_of_day,
		"scale": Clock.time_scale,
		"paused": Clock.is_paused() if Clock.has_method("is_paused") else Clock.paused,
	}

func _client_snapshot() -> Dictionary:
	var c: ClientState = World.client
	var out := {
		"id": String(c.id),
		"display_name": c.display_name,
		"needs": _stringify_dict_keys(c.needs),
		"cognitive": _stringify_dict_keys(c.cognitive),
		"overskudd": c.overskudd,
		"overskudd_ceiling": c.overskudd_ceiling(),
		"skills": _stringify_dict_keys(c.skills),
	}
	if reveal_hidden:
		out["mtg_primary"] = String(c.mtg_primary)
		out["mtg_secondary"] = String(c.mtg_secondary)
	return out

func _case_file_snapshot() -> Dictionary:
	var cf: CaseFile = World.case_file
	var entries: Array = []
	for e: CaseEntry in cf.entries:
		entries.append({
			"id": String(e.id),
			"title": e.title,
			"tags": _stringify_array(e.tags),
		})
	return {
		"entries": entries,
		"tags": _stringify_dict_keys(cf.tags),
	}

func _economy_snapshot() -> Dictionary:
	var e: EconomyState = World.economy
	return {
		"capacity_current": e.capacity_current,
		"capacity_max": e.capacity_max,
	}

func _catalog_snapshot() -> Dictionary:
	var diags: Array = []
	for d: Diagnostic in Catalog.available_diagnostics(World.case_file):
		diags.append({
			"id": String(d.id),
			"label": d.label,
			"gate_met": true,
			"affordable": World.economy.can_spend(d.caseworker_cost) and World.client.overskudd >= d.overskudd_cost,
			"costs": {"hours": d.caseworker_cost, "overskudd": d.overskudd_cost},
		})
	var intervs: Array = []
	for i: Intervention in Catalog.available_interventions(World.case_file):
		intervs.append({
			"id": String(i.id),
			"label": i.label,
			"gate_met": true,
			"affordable": World.economy.can_spend(i.caseworker_cost) and World.client.overskudd >= i.overskudd_cost,
			"costs": {"hours": i.caseworker_cost, "overskudd": i.overskudd_cost},
		})
	return {
		"diagnostics_available": diags,
		"interventions_available": intervs,
	}

# ---------------------------------------------------------------- helpers

func _stringify_dict_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d.keys():
		out[String(k)] = d[k]
	return out

func _stringify_array(a: Array) -> Array:
	var out: Array = []
	for x: Variant in a:
		out.append(String(x))
	return out

# ---------------------------------------------------------------- commands

func handle_command(cmd: Dictionary) -> Dictionary:
	var op: String = String(cmd.get("op", ""))
	match op:
		"snapshot":
			return {"ok": true, "snapshot": build_snapshot()}
		"diag":
			return _handle_diag(cmd)
		"interv":
			return _handle_interv(cmd)
		"advance":
			return _handle_advance(cmd)
		"set_speed":
			return _handle_set_speed(cmd)
		"shutdown":
			shutdown_requested = true
			return {"ok": true}
		_:
			return {"ok": false, "err": "unsupported_op", "op": op}

func _handle_diag(cmd: Dictionary) -> Dictionary:
	var id_str: String = String(cmd.get("id", ""))
	if id_str == "":
		return {"ok": false, "err": "missing_id"}
	var id_sn: StringName = StringName(id_str)
	if not Catalog.diagnostics.has(id_sn):
		return {"ok": false, "err": "unknown_id"}
	var success: bool = World.try_run_diagnostic(id_sn)
	return {"ok": success}

func _handle_interv(cmd: Dictionary) -> Dictionary:
	var id_str: String = String(cmd.get("id", ""))
	if id_str == "":
		return {"ok": false, "err": "missing_id"}
	var id_sn: StringName = StringName(id_str)
	if not Catalog.interventions.has(id_sn):
		return {"ok": false, "err": "unknown_id"}
	var success: bool = World.try_assign_intervention(id_sn)
	return {"ok": success}

func _handle_set_speed(cmd: Dictionary) -> Dictionary:
	var scale: float = float(cmd.get("scale", 0.0))
	if scale <= 0.0:
		return {"ok": false, "err": "invalid_scale"}
	Clock.time_scale = scale
	return {"ok": true}

func _handle_advance(cmd: Dictionary) -> Dictionary:
	var hrs: float = float(cmd.get("game_hours", 0.0))
	if hrs < 0.0:
		return {"ok": false, "err": "negative_hours"}
	if hrs == 0.0:
		return {"ok": true}
	Clock.advance(hrs)
	Sim.apply_tick(hrs)
	return {"ok": true}

# ---------------------------------------------------------------- events

var _event_buffer: Array = []
var _event_capture_active: bool = false

func start_event_capture() -> void:
	if _event_capture_active:
		return
	_event_capture_active = true
	EventBus.day_started.connect(_on_day_started)
	EventBus.day_ended.connect(_on_day_ended)
	EventBus.overskudd_changed.connect(_on_overskudd_changed)
	EventBus.caseworker_capacity_changed.connect(_on_capacity_changed)
	EventBus.case_file_updated.connect(_on_case_file_updated)
	EventBus.diagnostic_completed.connect(_on_diagnostic_completed)
	EventBus.intervention_completed.connect(_on_intervention_completed)
	EventBus.action_failed.connect(_on_action_failed)

func stop_event_capture() -> void:
	if not _event_capture_active:
		return
	_event_capture_active = false
	EventBus.day_started.disconnect(_on_day_started)
	EventBus.day_ended.disconnect(_on_day_ended)
	EventBus.overskudd_changed.disconnect(_on_overskudd_changed)
	EventBus.caseworker_capacity_changed.disconnect(_on_capacity_changed)
	EventBus.case_file_updated.disconnect(_on_case_file_updated)
	EventBus.diagnostic_completed.disconnect(_on_diagnostic_completed)
	EventBus.intervention_completed.disconnect(_on_intervention_completed)
	EventBus.action_failed.disconnect(_on_action_failed)

func drain_events() -> Array:
	var out := _event_buffer
	_event_buffer = []
	return out

func _push_event(ev: Dictionary) -> void:
	ev["t"] = {"d": Clock.day, "h": Clock.hour_of_day}
	_event_buffer.append(ev)

func _on_day_started(day: int) -> void:
	_push_event({"ev": "day_started", "day": day})

func _on_day_ended(day: int) -> void:
	_push_event({"ev": "day_ended", "day": day})

func _on_overskudd_changed(client_id: StringName, v: float) -> void:
	_push_event({"ev": "overskudd_changed", "client": String(client_id), "v": v})

func _on_capacity_changed(current: float, max_val: float) -> void:
	_push_event({"ev": "caseworker_capacity_changed", "current": current, "max": max_val})

func _on_case_file_updated(entry_id: StringName) -> void:
	_push_event({"ev": "case_file_updated", "entry": String(entry_id)})

func _on_diagnostic_completed(id: StringName) -> void:
	_push_event({"ev": "diagnostic_completed", "id": String(id)})

func _on_intervention_completed(id: StringName) -> void:
	_push_event({"ev": "intervention_completed", "id": String(id)})

func _on_action_failed(reason: StringName) -> void:
	_push_event({"ev": "action_failed", "reason": String(reason)})

# ---------------------------------------------------------------- comms loop

const _CMD_FILENAME := "cmd.jsonl"
const _EVENTS_FILENAME := "events.jsonl"
const _READY_FILENAME := "ready"

var _cmd_cursor: int = 0
var _comms_bound: bool = false

func bind_comms(dir: String) -> void:
	comms_dir = dir
	_cmd_cursor = 0
	DirAccess.make_dir_recursive_absolute(dir)
	# Truncate both files so each bind starts from a clean slate.
	var ev_path := _events_path()
	if FileAccess.file_exists(ev_path):
		DirAccess.remove_absolute(ev_path)
	var cmd_path := _cmd_path()
	if FileAccess.file_exists(cmd_path):
		DirAccess.remove_absolute(cmd_path)
	# Create an empty cmd.jsonl so external writers can append immediately.
	FileAccess.open(cmd_path, FileAccess.WRITE).close()
	_comms_bound = true

func unbind_comms() -> void:
	_comms_bound = false
	_cmd_cursor = 0

func _cmd_path() -> String:
	return comms_dir.path_join(_CMD_FILENAME)

func _events_path() -> String:
	return comms_dir.path_join(_EVENTS_FILENAME)

func _ready_path() -> String:
	return comms_dir.path_join(_READY_FILENAME)

func pump() -> void:
	if not _comms_bound:
		return
	var lines := _read_pending_command_lines()
	for line: String in lines:
		if line.strip_edges() == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
			_append_event({"ev": "parse_error", "raw": line})
			continue
		var reply := handle_command(parsed)
		_append_event({"reply": reply, "for": parsed.get("op", ""), "t": {"d": Clock.day, "h": Clock.hour_of_day}})
		# Flush any EventBus events that fired during this command.
		for ev: Dictionary in drain_events():
			_append_event(ev)
		_write_ready_sentinel()
		if shutdown_requested:
			return

func _read_pending_command_lines() -> Array:
	var path := _cmd_path()
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	f.seek(_cmd_cursor)
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line.length() > 0 or not f.eof_reached():
			out.append(line)
	_cmd_cursor = f.get_position()
	f.close()
	return out

func _append_event(ev: Dictionary) -> void:
	var path := _events_path()
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(ev))
	f.close()

func _write_ready_sentinel() -> void:
	var f := FileAccess.open(_ready_path(), FileAccess.WRITE)
	f.store_string(str(Time.get_ticks_msec()))
	f.close()
