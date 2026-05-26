extends Node

const OBSERVATION_INTERVAL_HOURS := 6.0
const OVERSKUDD_EMIT_THRESHOLD := 0.5

var _hours_since_observation: float = 0.0
var _last_emitted_overskudd: float = -1.0
var _last_seen_day: int = 1
var _running: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)  # disabled until start() — keeps tests deterministic
	EventBus.day_started.connect(_on_day_started)
	_last_seen_day = Clock.day

func start() -> void:
	_running = true
	set_process(true)
	Clock.start()

func _process(delta: float) -> void:
	var hrs := Clock.real_to_game_hours_when_unpaused(delta)
	if hrs <= 0.0: return
	Clock.advance(hrs)
	apply_tick(hrs)

func apply_tick(game_hours: float) -> void:
	var client: ClientState = World.client
	var decay: ClientDecay = World.decay
	for k: StringName in decay.needs_per_hour.keys():
		if client.needs.has(k):
			client.needs[k] = clamp(client.needs[k] + float(decay.needs_per_hour[k]) * game_hours, 0.0, 1.0)
	for k: StringName in decay.cognitive_per_hour.keys():
		if client.cognitive.has(k):
			client.cognitive[k] = clamp(client.cognitive[k] + float(decay.cognitive_per_hour[k]) * game_hours, 0.0, 1.0)
	client.tick_overskudd(game_hours)
	if abs(client.overskudd - _last_emitted_overskudd) >= OVERSKUDD_EMIT_THRESHOLD:
		_last_emitted_overskudd = client.overskudd
		EventBus.overskudd_changed.emit(client.id, client.overskudd)
	_hours_since_observation += game_hours
	while _hours_since_observation >= OBSERVATION_INTERVAL_HOURS:
		_hours_since_observation -= OBSERVATION_INTERVAL_HOURS
		World.try_surface_observation()

func advance_away_time(game_hours: float) -> void:
	if game_hours <= 0.0:
		return
	Clock.advance(game_hours)
	apply_tick(game_hours)

func reset_for_test() -> void:
	set_process(false)
	_hours_since_observation = 0.0
	_last_emitted_overskudd = -1.0
	_last_seen_day = Clock.day

func _on_day_started(day: int) -> void:
	if day == _last_seen_day: return
	_last_seen_day = day
	World.start_new_day(day)
