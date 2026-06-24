extends Control

## Legibility Desk Gym — a designer tool to WATCH the live CA sim turn emergent
## behaviour into legible TRACE FACTS on the desk, in real time.
##
## Open it from the Godot editor with F6 (scene = legibility_desk_gym.tscn). It boots
## the live simulation (World + CAEngine via Sim) at a chosen seed and ticks the Clock,
## so Elling autonomously chooses activities, the day-end PatternDeriver (the Lens) fires
## at each day rollover, and any pattern it newly recognises lands on the desk as a
## DERIVED CaseEntry (provenance == &"derived"). The left desk lists every case-file
## entry, colour-coding the emergent DERIVED reads against the AUTHORED scheduled facts.
## The right panel is the designer's procedural cockpit: live day/hour readout, a
## time-scale slider to fast-forward days, pause, and a seed + Reset Run control to
## replay the same stream or branch a new one. A small counter shows derived-facts /
## days-elapsed and the size of the uncovered-behaviour channel (what the Lens is blind
## to). It reuses production wholesale via the autoloads (Clock / Sim / World / EventBus)
## and adds NO production code — it only observes.
##
## Headless guard: run_assertions() drives ~12 deterministic sim days and asserts at
## least one DERIVED case-file entry surfaced. The GUT shim
## (test/gym/legibility_desk_gym_test.gd) calls it.
##
## Verified red-green: 2026-06-25

const DERIVED := &"derived"
const ASSERTION_DAYS := 12
const HOURS_PER_DAY := 24.0

# Default seed the gym boots and resets to. The live CA sim fires its authored pattern
# rules within ~12 days at every probed seed; this one is just a stable default the
# designer can change in the Seed SpinBox.
const DEFAULT_SEED := 747

# --- desk (left) -----------------------------------------------------------------
var _fact_list: VBoxContainer

# --- cockpit (right) -------------------------------------------------------------
var _day_hour_label: Label
var _counter_label: Label
var _uncovered_label: Label
var _time_scale_slider: HSlider
var _time_scale_value: Label
var _pause_button: CheckButton
var _seed_spin: SpinBox

# Day on which the current run started (for the "days elapsed" counter).
var _run_start_day: int = 1


func _ready() -> void:
	_build_ui()
	_start_run(DEFAULT_SEED)
	EventBus.case_file_updated.connect(_on_case_file_updated)
	EventBus.patterns_evaluated.connect(_on_patterns_evaluated)
	EventBus.day_started.connect(_on_day_started)
	set_process(true)


func _process(_delta: float) -> void:
	_refresh_cockpit()


# --- run lifecycle ----------------------------------------------------------------

## (Re)boot the live sim at `seed`: fresh Elling + fresh deriver via World, then Sim.start()
## so the Clock ticks live and CA drives behaviour. Clears the desk display.
func _start_run(seed_value: int) -> void:
	Clock.reset()
	World.ca_seed = seed_value
	World.reset_for_test()
	Sim.reset_for_test()
	Sim.start()
	_run_start_day = Clock.day
	# Restore designer cockpit state onto the freshly reset Clock.
	Clock.time_scale = _time_scale_slider.value if _time_scale_slider != null else 1.0
	Clock.paused = _pause_button.button_pressed if _pause_button != null else false
	_rebuild_fact_list()
	_refresh_cockpit()


func _on_reset_pressed() -> void:
	_start_run(int(_seed_spin.value))


# --- desk display -----------------------------------------------------------------

func _on_case_file_updated(_entry_id: StringName) -> void:
	_rebuild_fact_list()


func _on_day_started(_day: int) -> void:
	_refresh_cockpit()


func _on_patterns_evaluated(_uncovered: Dictionary) -> void:
	_refresh_cockpit()


# Rebuilds the desk fact list (reusing CaseFilePanel's iteration approach): one styled
# row per case-file entry, DERIVED (emergent) rows highlighted, AUTHORED rows muted.
func _rebuild_fact_list() -> void:
	for child: Node in _fact_list.get_children():
		child.queue_free()
	if World.case_file == null:
		return
	for entry: CaseEntry in World.case_file.entries:
		_fact_list.add_child(_make_fact_row(entry))


func _make_fact_row(entry: CaseEntry) -> PanelContainer:
	var is_derived := entry.provenance == DERIVED
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_content_margin_all(8.0)
	style.set_corner_radius_all(4)
	if is_derived:
		style.bg_color = Color(0.15, 0.30, 0.18, 1.0)
		style.set_border_width_all(2)
		style.border_color = Color(0.45, 0.85, 0.50, 1.0)
	else:
		style.bg_color = Color(0.16, 0.16, 0.18, 1.0)
		style.set_border_width_all(1)
		style.border_color = Color(0.30, 0.30, 0.34, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var tag := Label.new()
	if is_derived:
		tag.text = "● DERIVED  (emergent — the Lens read this)"
		tag.add_theme_color_override("font_color", Color(0.55, 0.95, 0.60, 1.0))
	else:
		tag.text = "○ AUTHORED  (scheduled fact)"
		tag.add_theme_color_override("font_color", Color(0.60, 0.60, 0.66, 1.0))
	vbox.add_child(tag)

	var title := Label.new()
	title.text = entry.title
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97, 1.0))
	vbox.add_child(title)

	var body := Label.new()
	body.text = entry.body
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82, 1.0))
	vbox.add_child(body)

	return panel


# --- cockpit display --------------------------------------------------------------

func _refresh_cockpit() -> void:
	if _day_hour_label == null:
		return
	_day_hour_label.text = "Day %d   %02d:%02d" % [Clock.day, int(Clock.hour_of_day), int(fposmod(Clock.hour_of_day, 1.0) * 60.0)]

	var derived_count := _count_derived()
	var days_elapsed: int = max(0, Clock.day - _run_start_day)
	_counter_label.text = "Derived facts: %d    Days elapsed: %d" % [derived_count, days_elapsed]

	var uncovered: Dictionary = World.pattern_deriver().get_uncovered_summary() if World.pattern_deriver() != null else {}
	_uncovered_label.text = "Uncovered behaviour categories (Lens blind spots): %d" % uncovered.size()

	if _time_scale_value != null:
		_time_scale_value.text = "%d×" % int(Clock.time_scale)


func _count_derived() -> int:
	if World.case_file == null:
		return 0
	var n := 0
	for entry: CaseEntry in World.case_file.entries:
		if entry.provenance == DERIVED:
			n += 1
	return n


# --- cockpit controls -------------------------------------------------------------

func _on_time_scale_changed(value: float) -> void:
	Clock.time_scale = value
	_refresh_cockpit()


func _on_pause_toggled(pressed: bool) -> void:
	Clock.paused = pressed


# --- headless guard ---------------------------------------------------------------

## Drives ~12 deterministic sim days (each Clock.advance(24.0) crosses exactly one day
## boundary, firing day_started → Sim._on_day_started → the day-end Lens pass) and asserts
## at least one DERIVED case-file entry surfaced. Returns {name, passed, failures}.
func run_assertions() -> Dictionary:
	var failures: Array[String] = []

	# Fresh deterministic run for the guard, independent of any live UI state.
	Clock.reset()
	World.ca_seed = DEFAULT_SEED
	World.reset_for_test()
	Sim.reset_for_test()

	for _i: int in range(ASSERTION_DAYS):
		Clock.advance(HOURS_PER_DAY)

	var derived := _count_derived()
	if derived < 1:
		failures.append(
			"expected >=1 DERIVED case-file entry after %d sim days, got %d (total entries: %d, history: %d)"
			% [ASSERTION_DAYS, derived, World.case_file.entries.size() if World.case_file != null else 0, World.get_activity_history().size()]
		)

	return {
		"name": "legibility_desk_gym",
		"passed": failures.is_empty(),
		"failures": failures,
	}


# --- UI construction --------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Background.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.09, 0.09, 0.11, 1.0)
	add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	add_child(hbox)

	# LEFT / MAIN — the desk.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.70
	left.add_theme_constant_override("separation", 8)
	hbox.add_child(left)

	var desk_header := Label.new()
	desk_header.text = "THE DESK — trace facts"
	desk_header.add_theme_color_override("font_color", Color(0.90, 0.90, 0.95, 1.0))
	desk_header.add_theme_font_size_override("font_size", 20)
	left.add_child(desk_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)

	_fact_list = VBoxContainer.new()
	_fact_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fact_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_fact_list)

	# RIGHT (~30%) — the procedural cockpit. Lives on its own CanvasLayer per the brief.
	var layer := CanvasLayer.new()
	add_child(layer)

	var right_anchor := Control.new()
	right_anchor.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_anchor.anchor_left = 0.70
	right_anchor.anchor_right = 1.0
	right_anchor.anchor_top = 0.0
	right_anchor.anchor_bottom = 1.0
	layer.add_child(right_anchor)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.13, 0.13, 0.16, 1.0)
	pstyle.set_content_margin_all(12.0)
	pstyle.set_border_width_all(0)
	pstyle.border_width_left = 2
	pstyle.border_color = Color(0.30, 0.30, 0.36, 1.0)
	panel.add_theme_stylebox_override("panel", pstyle)
	right_anchor.add_child(panel)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	panel.add_child(right)

	var cockpit_header := Label.new()
	cockpit_header.text = "DESIGNER COCKPIT"
	cockpit_header.add_theme_color_override("font_color", Color(0.90, 0.90, 0.95, 1.0))
	cockpit_header.add_theme_font_size_override("font_size", 18)
	right.add_child(cockpit_header)

	# Day + hour readout.
	_day_hour_label = Label.new()
	_day_hour_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.65, 1.0))
	_day_hour_label.add_theme_font_size_override("font_size", 22)
	right.add_child(_day_hour_label)

	right.add_child(_make_separator())

	# Time-scale slider (1..200).
	var ts_row := HBoxContainer.new()
	right.add_child(ts_row)
	var ts_label := Label.new()
	ts_label.text = "Time scale"
	ts_row.add_child(ts_label)
	_time_scale_value = Label.new()
	_time_scale_value.add_theme_color_override("font_color", Color(0.70, 0.90, 1.0, 1.0))
	ts_row.add_child(_time_scale_value)

	_time_scale_slider = HSlider.new()
	_time_scale_slider.min_value = 1.0
	_time_scale_slider.max_value = 200.0
	_time_scale_slider.step = 1.0
	_time_scale_slider.value = 1.0
	_time_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_scale_slider.value_changed.connect(_on_time_scale_changed)
	right.add_child(_time_scale_slider)

	# Pause.
	_pause_button = CheckButton.new()
	_pause_button.text = "Pause"
	_pause_button.toggled.connect(_on_pause_toggled)
	right.add_child(_pause_button)

	right.add_child(_make_separator())

	# Seed + Reset Run.
	var seed_row := HBoxContainer.new()
	right.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_row.add_child(seed_label)
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0.0
	_seed_spin.max_value = 999999.0
	_seed_spin.step = 1.0
	_seed_spin.value = float(DEFAULT_SEED)
	_seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_spin)

	var reset_button := Button.new()
	reset_button.text = "Reset Run"
	reset_button.pressed.connect(_on_reset_pressed)
	right.add_child(reset_button)

	right.add_child(_make_separator())

	# Counters.
	_counter_label = Label.new()
	_counter_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.60, 1.0))
	_counter_label.add_theme_font_size_override("font_size", 16)
	right.add_child(_counter_label)

	_uncovered_label = Label.new()
	_uncovered_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_uncovered_label.add_theme_color_override("font_color", Color(0.85, 0.70, 0.55, 1.0))
	right.add_child(_uncovered_label)


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	return sep
