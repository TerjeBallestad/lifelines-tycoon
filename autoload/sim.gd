extends Node

const OVERSKUDD_EMIT_THRESHOLD := 0.5

# CA decision cadence. The sandbox runs the CA kernel once per "decision", where a
# decision spans CAEngine.PASSIVE_HOURS_PER_DECISION game-hours (14 waking hours /
# 8 decisions/day = 1.75 game-hours per decision). apply_tick accumulates elapsed
# game_hours and fires one CAEngine.select_and_apply step per whole 1.75h crossed,
# mirroring the (now-retired) observation accumulator.
const CA_HOURS_PER_STEP := CAEngine.PASSIVE_HOURS_PER_DECISION  # 1.75

var _last_emitted_overskudd: float = -1.0
var _last_seen_day: int = 1
var _running: bool = false

# Sim owns the CAEngine (the tick driver that calls select_and_apply each step) and
# its private seeded RNG. OWNERSHIP DECISION: history lives on World (the orchestrator),
# but the engine instance lives on Sim because Sim drives time → CA decision steps.
# Seeded from World.ca_seed; rebuilt lazily on first use and on reset_for_test so a
# --seed change before boot is honoured.
var _ca: CAEngine = null
var _ca_step: int = 0
var _ca_hours_accum: float = 0.0
# Activity ids chosen on the current day, for the overnight non-chosen mastery decay.
var _chosen_today: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)  # Clock owns advancement; Sim only reacts to tick events.
	EventBus.tick.connect(_on_tick)
	EventBus.day_started.connect(_on_day_started)
	_last_seen_day = Clock.day

func start() -> void:
	_running = true
	Clock.start()

func stop() -> void:
	_running = false
	Clock.stop()

# Lazily build/seed the CAEngine from World.ca_seed. Idempotent per Sim lifetime;
# reset_for_test() drops it so a later seed change is re-read.
func _ensure_ca() -> CAEngine:
	if _ca == null:
		_ca = CAEngine.new()
		_ca.init_seed(World.ca_seed)
	return _ca

func apply_tick(game_hours: float) -> void:
	var client: ClientState = World.client
	var decay: ClientDecay = World.decay
	# NEEDS-decay + autonomous activity selection are now owned by the CA kernel:
	# accumulate elapsed game-hours and run one CA decision step per 1.75h crossed.
	# Each step scores the 18 Catalog activities against the client's needs/mastery/
	# colors, applies the chosen activity, and appends a record to World history.
	var ca := _ensure_ca()
	_ca_hours_accum += game_hours
	while _ca_hours_accum >= CA_HOURS_PER_STEP:
		_ca_hours_accum -= CA_HOURS_PER_STEP
		var activities: Array = Catalog.activities.values()
		var result := ca.select_and_apply(client.needs, client.mastery, client.colors, activities)
		var activity_id: StringName = result["activity_id"]
		_chosen_today[activity_id] = true
		World.append_activity_record({
			"day": Clock.day,
			"step": _ca_step,
			"activity_id": activity_id,
			"needs_snapshot": client.needs.duplicate(true),
			"mastery_snapshot": client.mastery.duplicate(true),
		})
		_ca_step += 1
	# Cognitive (attention/willpower) decay SURVIVES the CA replacement — the CA kernel
	# does not model cognitive pools, so this loop stays exactly as it was.
	for k: StringName in decay.cognitive_per_hour.keys():
		if client.cognitive.has(k):
			client.cognitive[k] = clamp(client.cognitive[k] + float(decay.cognitive_per_hour[k]) * game_hours, 0.0, 1.0)
	client.tick_overskudd(game_hours)
	if abs(client.overskudd - _last_emitted_overskudd) >= OVERSKUDD_EMIT_THRESHOLD:
		_last_emitted_overskudd = client.overskudd
		EventBus.overskudd_changed.emit(client.id, client.overskudd)

func advance_away_time(game_hours: float) -> void:
	Clock.advance(game_hours)

func reset_for_test() -> void:
	set_process(false)
	_running = false
	_last_emitted_overskudd = -1.0
	_last_seen_day = Clock.day
	_ca = null
	_ca_step = 0
	_ca_hours_accum = 0.0
	_chosen_today = {}

func _on_tick(game_hours: float) -> void:
	apply_tick(game_hours)

func _on_day_started(day: int) -> void:
	if day == _last_seen_day: return
	_last_seen_day = day
	World.start_new_day(day, _chosen_today.keys())
	# DAY-END LENS PASS (Task 12). The day rollover is the decided deriver cadence —
	# exactly once per day, NOT per tick. This handler is already day-boundary-guarded
	# by the _last_seen_day check above, so the Lens runs once per rollover. World owns
	# the deriver and emits the uncovered-behaviour summary on EventBus from here.
	World.evaluate_patterns_for_day_end()
	_chosen_today = {}
