extends Node

const REAL_SECONDS_PER_GAME_DAY := 60.0
const GAME_HOURS_PER_DAY := 24.0
const GAME_HOURS_PER_REAL_SECOND := GAME_HOURS_PER_DAY / REAL_SECONDS_PER_GAME_DAY

var time_scale: float = 1.0
var paused: bool = false
var day: int = 1
var hour_of_day: float = 0.0
var total_game_hours: float = 0.0
var _running: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)  # disabled until start() — keeps GUT tests deterministic

func start() -> void:
	_running = true
	set_process(true)

func stop() -> void:
	_running = false
	set_process(false)

func _process(delta: float) -> void:
	var hrs := real_to_game_hours_when_unpaused(delta)
	if hrs > 0.0:
		advance(hrs)
		EventBus.tick.emit(hrs)

func real_to_game_hours(real_seconds: float) -> float:
	return real_seconds * GAME_HOURS_PER_REAL_SECOND * time_scale

func real_to_game_hours_when_unpaused(real_seconds: float) -> float:
	if paused: return 0.0
	return real_to_game_hours(real_seconds)

func advance(game_hours: float) -> void:
	total_game_hours += game_hours
	hour_of_day += game_hours
	while hour_of_day >= GAME_HOURS_PER_DAY:
		hour_of_day -= GAME_HOURS_PER_DAY
		day += 1
		EventBus.day_started.emit(day)

func reset() -> void:
	time_scale = 1.0
	paused = false
	day = 1
	hour_of_day = 0.0
	total_game_hours = 0.0
	set_process(false)
