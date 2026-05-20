# AgentBridge + Scripted Playtest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `godot --headless --agent-mode` mode that lets an external process drive the Lifelines economy prototype via file-based JSON-lines comms, plus a Python scripted-strategy player that consumes a static action plan and produces a trace. This is Plan 1 of 6 for the adversarial harness (see `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §11).

**Architecture:** Add a single Godot autoload `AgentBridge` that is dormant by default and activates on `--agent-mode` CLI flag. Bridge tails `cmd.jsonl` for command lines and appends to `events.jsonl` for streaming `EventBus` signals + snapshot replies. All transport via files in `harness/comms/<run-id>/`. Python driver `harness/lib/scripted_player.py` writes scripted command lines and reads events into a trace jsonl. No game logic added — bridge only adapts to existing `World.try_*` API.

**Tech Stack:** Godot 4.5 (GDScript), GUT testing framework, Python 3.11+ (stdlib only), bash for smoke scripts.

---

## File Structure

**Files created:**

```
autoload/agent_bridge.gd                # new autoload — dormant unless --agent-mode
harness/                                 # new top-level directory
├── README.md                            # what plan 1 ships, how to drive it
├── lib/
│   ├── scripted_player.py               # Python driver: feeds cmd.jsonl, reads events.jsonl
│   └── trace_schema.py                  # jsonl event/command schema validation
├── strategies/
│   └── examples/
│       └── baseline_observer.json       # canned scripted strategy
└── test/
    └── smoke_bridge.sh                  # end-to-end smoke harness
test/harness/                            # new test root
├── unit/
│   ├── test_bridge_dormant.gd           # bridge inert when flag absent
│   ├── test_bridge_snapshot.gd          # snapshot op
│   ├── test_bridge_reveal_hidden.gd     # masking
│   ├── test_bridge_diag.gd              # diag op routes to World
│   ├── test_bridge_interv.gd            # interv op
│   ├── test_bridge_advance.gd           # advance ticks Sim
│   ├── test_bridge_set_speed.gd         # speed scale
│   ├── test_bridge_shutdown.gd          # graceful quit
│   └── test_bridge_event_streaming.gd   # EventBus → events.jsonl
└── lib/
    └── bridge_test_helpers.gd           # shared GUT helpers for bridge tests
```

**Files modified:**

```
project.godot                            # add AgentBridge to [autoload] after Sim
main.gd                                  # parse --agent-mode, gate Sim.start() behavior
.gitignore                               # ignore harness/comms/ runtime dir
```

**No files deleted.** No autoloads renamed. EventBus signals untouched.

---

## Task 1: Repo scaffolding

**Files:**
- Create: `harness/README.md`
- Create: `harness/lib/.gitkeep`
- Create: `harness/strategies/examples/.gitkeep`
- Create: `harness/test/.gitkeep`
- Create: `test/harness/unit/.gitkeep`
- Create: `test/harness/lib/.gitkeep`
- Modify: `.gitignore`

- [ ] **Step 1: Create directory skeleton**

```bash
mkdir -p harness/lib harness/strategies/examples harness/test \
         test/harness/unit test/harness/lib
touch harness/lib/.gitkeep \
      harness/strategies/examples/.gitkeep \
      harness/test/.gitkeep \
      test/harness/unit/.gitkeep \
      test/harness/lib/.gitkeep
```

- [ ] **Step 2: Write `harness/README.md`**

```markdown
# Harness — Adversarial Agent Loop

Plan 1 of 6 from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`.

This directory holds the orchestration + comms layer that drives the Lifelines economy prototype from external agents (planner, generator, evaluator, strategy LLMs).

## What's in Plan 1

- `lib/scripted_player.py` — Python driver that runs a scripted action plan against the Godot game via file-based comms and produces a trace jsonl.
- `strategies/examples/` — canned action plans (JSON).
- `test/smoke_bridge.sh` — end-to-end smoke test.

The Godot side is in `autoload/agent_bridge.gd`. The bridge is dormant unless the game is launched with `--agent-mode`.

## Quick start

```bash
# Run scripted playtest, write trace to harness/comms/smoke/events.jsonl
./harness/test/smoke_bridge.sh
```

## Comms layout

```
harness/comms/<run-id>/
├── cmd.jsonl             # external agent appends commands; bridge tails
├── events.jsonl          # bridge appends events; agent tails
├── cmd.cursor            # bridge's byte offset into cmd.jsonl
├── events.cursor         # agent's byte offset into events.jsonl
└── ready                 # sentinel — bridge writes after each command completes
```

All files are append-only JSON-lines (one JSON object per line).

## What's NOT in Plan 1

LLM-driven strategy player, planner, generator, evaluator, contract negotiation, rubric anchors, orchestrator, report.html. Those are Plans 2–6.
```

- [ ] **Step 3: Append to `.gitignore`**

Append the line `harness/comms/` to the existing `.gitignore`. If `.gitignore` does not exist at the repo root, create it with that single line. Verify:

```bash
grep -q '^harness/comms/$' .gitignore || echo 'harness/comms/' >> .gitignore
```

- [ ] **Step 4: Verify skeleton**

```bash
ls -la harness/ test/harness/
```

Expected: each directory listed with `.gitkeep` or content.

- [ ] **Step 5: Commit**

```bash
git add harness/README.md harness/lib/.gitkeep \
        harness/strategies/examples/.gitkeep harness/test/.gitkeep \
        test/harness/unit/.gitkeep test/harness/lib/.gitkeep \
        .gitignore
git commit -m "feat(harness): scaffold harness + test/harness directories"
```

---

## Task 2: AgentBridge autoload skeleton (dormant)

The bridge exists but does nothing yet. Confirms autoload wiring works.

**Files:**
- Create: `autoload/agent_bridge.gd`
- Create: `test/harness/unit/test_bridge_dormant.gd`
- Modify: `project.godot`

- [ ] **Step 1: Write the failing test**

`test/harness/unit/test_bridge_dormant.gd`:

```gdscript
extends GutTest

func test_autoload_present() -> void:
	var bridge: Node = get_node_or_null("/root/AgentBridge")
	assert_not_null(bridge, "AgentBridge autoload should be present")

func test_dormant_by_default() -> void:
	var bridge: Node = get_node("/root/AgentBridge")
	assert_false(bridge.active, "AgentBridge.active should default to false")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
./test/run.sh -gtest=res://test/harness/unit/test_bridge_dormant.gd
```

(If no `test/run.sh` exists yet, use the direct GUT invocation:)

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_dormant.gd -gexit
```

Expected: FAIL — `AgentBridge autoload should be present`.

- [ ] **Step 3: Create the bridge script**

`autoload/agent_bridge.gd`:

```gdscript
extends Node
## Adapter between external agent processes and the game's mutation API.
## Dormant by default; activated by --agent-mode CLI flag (parsed in main.gd).

var active: bool = false
var reveal_hidden: bool = false
var comms_dir: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
```

- [ ] **Step 4: Register autoload in `project.godot`**

Modify the `[autoload]` block. Add `AgentBridge` AFTER `Sim` (matches design spec §4.1):

```
[autoload]

EventBus="*res://autoload/event_bus.gd"
Clock="*res://autoload/clock.gd"
Catalog="*res://autoload/catalog.gd"
World="*res://autoload/world.gd"
Sim="*res://autoload/sim.gd"
AgentBridge="*res://autoload/agent_bridge.gd"
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_dormant.gd -gexit
```

Expected: PASS, both tests green.

- [ ] **Step 6: Verify normal game still runs**

```bash
godot --headless --path . --import   # idempotent reimport
godot --headless --path . --quit-after 3
```

Expected: no errors at startup. (The game runs for ~3 frames then exits.)

- [ ] **Step 7: Commit**

```bash
git add autoload/agent_bridge.gd \
        test/harness/unit/test_bridge_dormant.gd \
        project.godot
git commit -m "feat(autoload): add AgentBridge skeleton (dormant)"
```

---

## Task 3: Parse `--agent-mode` and `--reveal-hidden` flags in main.gd

Activate bridge when flag present; keep normal game flow intact otherwise.

**Files:**
- Modify: `main.gd`
- Create: `test/harness/lib/bridge_test_helpers.gd`
- Create: `test/harness/unit/test_bridge_activation.gd`

- [ ] **Step 1: Write the failing test**

`test/harness/lib/bridge_test_helpers.gd`:

```gdscript
class_name BridgeTestHelpers extends RefCounted

## Simulate CLI flag activation without re-launching the engine.
static func activate(bridge: Node, comms_dir: String, reveal_hidden: bool = false) -> void:
	bridge.active = true
	bridge.comms_dir = comms_dir
	bridge.reveal_hidden = reveal_hidden

static func make_tmp_comms_dir() -> String:
	var dir := "user://harness_test_%d" % Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(dir)
	return dir
```

`test/harness/unit/test_bridge_activation.gd`:

```gdscript
extends GutTest

func test_activate_sets_state() -> void:
	var bridge: Node = get_node("/root/AgentBridge")
	bridge.active = false
	bridge.comms_dir = ""
	bridge.reveal_hidden = false

	BridgeTestHelpers.activate(bridge, "user://run1", true)

	assert_true(bridge.active)
	assert_eq(bridge.comms_dir, "user://run1")
	assert_true(bridge.reveal_hidden)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_activation.gd -gexit
```

Expected: FAIL — `BridgeTestHelpers` is a missing identifier in the test, OR the test fails because the bridge's class doesn't pre-clear state. (The exact failure depends on parse order; either way, RED before GREEN.)

- [ ] **Step 3: Update `main.gd` to parse flags and activate the bridge**

Replace `main.gd` entirely:

```gdscript
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
```

**Why `OS.get_cmdline_user_args()` and not `OS.get_cmdline_args()`:** the user args are the ones AFTER `--` on the Godot command line. This keeps our flags from colliding with Godot's own.

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_activation.gd -gexit
```

Expected: PASS.

- [ ] **Step 5: Manual sanity check — flag actually activates the bridge**

```bash
godot --headless --path . --quit-after 5 -- --agent-mode --comms-dir /tmp/lifelines-bridge-test
```

Expected: exits cleanly. No UI scene loaded. (No assertion yet — Step 5 is exploratory.)

- [ ] **Step 6: Commit**

```bash
git add main.gd \
        test/harness/lib/bridge_test_helpers.gd \
        test/harness/unit/test_bridge_activation.gd
git commit -m "feat(main): parse --agent-mode/--comms-dir/--reveal-hidden flags"
```

---

## Task 4: Snapshot op — return state JSON

Implement the first command. Bridge gets a command line, builds a snapshot dict, appends a reply line to `events.jsonl`.

**Files:**
- Modify: `autoload/agent_bridge.gd`
- Create: `test/harness/unit/test_bridge_snapshot.gd`

- [ ] **Step 1: Write the failing test**

`test/harness/unit/test_bridge_snapshot.gd`:

```gdscript
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()

func test_snapshot_returns_required_top_level_keys() -> void:
	var snap: Dictionary = bridge.build_snapshot()

	assert_true(snap.has("time"))
	assert_true(snap.has("client"))
	assert_true(snap.has("case_file"))
	assert_true(snap.has("economy"))
	assert_true(snap.has("catalog"))

func test_snapshot_client_includes_needs_and_overskudd() -> void:
	var snap: Dictionary = bridge.build_snapshot()
	var c: Dictionary = snap["client"]

	assert_true(c.has("needs"))
	assert_true(c.has("cognitive"))
	assert_true(c.has("overskudd"))
	assert_true(c.has("overskudd_ceiling"))
	assert_eq(typeof(c["overskudd"]), TYPE_FLOAT)

func test_snapshot_time_includes_day_hour() -> void:
	var snap: Dictionary = bridge.build_snapshot()
	var t: Dictionary = snap["time"]
	assert_true(t.has("day"))
	assert_true(t.has("hour"))
	assert_true(t.has("scale"))
	assert_true(t.has("paused"))

func test_snapshot_economy_capacity() -> void:
	var snap: Dictionary = bridge.build_snapshot()
	var e: Dictionary = snap["economy"]
	assert_true(e.has("capacity_current"))
	assert_true(e.has("capacity_max"))

func test_snapshot_catalog_has_available_lists() -> void:
	var snap: Dictionary = bridge.build_snapshot()
	var cat: Dictionary = snap["catalog"]
	assert_true(cat.has("diagnostics_available"))
	assert_true(cat.has("interventions_available"))
	assert_eq(typeof(cat["diagnostics_available"]), TYPE_ARRAY)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_snapshot.gd -gexit
```

Expected: FAIL — `build_snapshot()` not defined on AgentBridge.

- [ ] **Step 3: Implement `build_snapshot()`**

Replace `autoload/agent_bridge.gd` with:

```gdscript
extends Node
## Adapter between external agent processes and the game's mutation API.
## Dormant by default; activated by --agent-mode CLI flag (parsed in main.gd).

var active: bool = false
var reveal_hidden: bool = false
var comms_dir: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

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
		"hour": Clock.hour,
		"scale": Clock.time_scale,
		"paused": Clock.is_paused() if Clock.has_method("is_paused") else false,
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
	for k in d.keys():
		out[String(k)] = d[k]
	return out

func _stringify_array(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(String(x))
	return out
```

**Note on `Clock.is_paused()`:** the existing `Clock` autoload may not expose this exact method. The guarded `if Clock.has_method(...)` line keeps the snapshot robust. If `Clock` later gains `is_paused()`, the snapshot will use it automatically.

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_snapshot.gd -gexit
```

Expected: PASS — all 5 snapshot tests green.

- [ ] **Step 5: Commit**

```bash
git add autoload/agent_bridge.gd test/harness/unit/test_bridge_snapshot.gd
git commit -m "feat(bridge): snapshot op — build state dict from World"
```

---

## Task 5: `--reveal-hidden` masking

Confirm that `mtg_primary` and `mtg_secondary` are absent unless `reveal_hidden` is true.

**Files:**
- Create: `test/harness/unit/test_bridge_reveal_hidden.gd`

(No production code change — Task 4 already implements masking. This task is a guard test ensuring the behavior is locked.)

- [ ] **Step 1: Write the test**

`test/harness/unit/test_bridge_reveal_hidden.gd`:

```gdscript
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()

func test_mtg_absent_when_reveal_hidden_off() -> void:
	bridge.reveal_hidden = false
	var snap: Dictionary = bridge.build_snapshot()
	var c: Dictionary = snap["client"]
	assert_false(c.has("mtg_primary"))
	assert_false(c.has("mtg_secondary"))

func test_mtg_present_when_reveal_hidden_on() -> void:
	bridge.reveal_hidden = true
	var snap: Dictionary = bridge.build_snapshot()
	var c: Dictionary = snap["client"]
	assert_true(c.has("mtg_primary"))
	assert_true(c.has("mtg_secondary"))
	assert_eq(typeof(c["mtg_primary"]), TYPE_STRING)

func test_reveal_hidden_resets_to_off_after_test() -> void:
	# Defensive: clean up state for other tests that may run in the same session.
	bridge.reveal_hidden = false
	assert_false(bridge.reveal_hidden)
```

- [ ] **Step 2: Run test**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_reveal_hidden.gd -gexit
```

Expected: PASS — masking already implemented in Task 4.

- [ ] **Step 3: Red-green verification**

Verify the test has teeth: temporarily comment out the `if reveal_hidden:` block in `_client_snapshot()` (set mtg fields always on). Run the test — `test_mtg_absent_when_reveal_hidden_off` MUST fail.

Restore the `if reveal_hidden:` block. Re-run. Tests pass again.

Add a `## Verified red-green: 2026-05-20` comment at the top of the test file.

- [ ] **Step 4: Commit**

```bash
git add test/harness/unit/test_bridge_reveal_hidden.gd
git commit -m "test(bridge): mtg color fields gated by --reveal-hidden"
```

---

## Task 6: `diag` op — route to `World.try_run_diagnostic`

**Files:**
- Modify: `autoload/agent_bridge.gd`
- Create: `test/harness/unit/test_bridge_diag.gd`

- [ ] **Step 1: Write the failing test**

`test/harness/unit/test_bridge_diag.gd`:

```gdscript
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	World.client.overskudd = 100.0
	World.economy.capacity_max = 6.0
	World.economy.capacity_current = 6.0

func test_diag_unknown_id_returns_error() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "diag", "id": "does_not_exist"})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "unknown_id")

func test_diag_known_id_succeeds() -> void:
	# Pick the first diagnostic from the catalog.
	var keys: Array = Catalog.diagnostics.keys()
	assert_gt(keys.size(), 0, "Catalog should have at least one diagnostic")
	var first_id: StringName = keys[0]
	var d: Diagnostic = Catalog.diagnostics[first_id]
	# Force gate clear by setting case-file tags to whatever the diag needs.
	for t: StringName in d.gate_tags:
		World.case_file.tags[t] = true

	var reply: Dictionary = bridge.handle_command({"op": "diag", "id": String(first_id)})
	assert_eq(reply.get("ok"), true)
	# Capacity should have decreased.
	assert_lt(World.economy.capacity_current, 6.0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_diag.gd -gexit
```

Expected: FAIL — `handle_command()` not defined.

- [ ] **Step 3: Add `handle_command()` to AgentBridge**

Append to `autoload/agent_bridge.gd`:

```gdscript
# ---------------------------------------------------------------- commands

func handle_command(cmd: Dictionary) -> Dictionary:
	var op: String = String(cmd.get("op", ""))
	match op:
		"snapshot":
			return {"ok": true, "snapshot": build_snapshot()}
		"diag":
			return _handle_diag(cmd)
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_diag.gd -gexit
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autoload/agent_bridge.gd test/harness/unit/test_bridge_diag.gd
git commit -m "feat(bridge): diag op routes to World.try_run_diagnostic"
```

---

## Task 7: `interv` op — route to `World.try_assign_intervention`

**Files:**
- Modify: `autoload/agent_bridge.gd`
- Create: `test/harness/unit/test_bridge_interv.gd`

- [ ] **Step 1: Write the failing test**

`test/harness/unit/test_bridge_interv.gd`:

```gdscript
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	World.client.overskudd = 100.0
	World.economy.capacity_max = 6.0
	World.economy.capacity_current = 6.0

func test_interv_unknown_id_returns_error() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "interv", "id": "nope"})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "unknown_id")

func test_interv_known_id_succeeds() -> void:
	var keys: Array = Catalog.interventions.keys()
	assert_gt(keys.size(), 0, "Catalog should have at least one intervention")
	var first_id: StringName = keys[0]
	var i: Intervention = Catalog.interventions[first_id]
	for t: StringName in i.gate_tags:
		World.case_file.tags[t] = true

	var reply: Dictionary = bridge.handle_command({"op": "interv", "id": String(first_id)})
	assert_eq(reply.get("ok"), true)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_interv.gd -gexit
```

Expected: FAIL — `interv` op falls through to `unsupported_op`.

- [ ] **Step 3: Add `_handle_interv` and wire into the match**

In `autoload/agent_bridge.gd`, update `handle_command()`:

```gdscript
func handle_command(cmd: Dictionary) -> Dictionary:
	var op: String = String(cmd.get("op", ""))
	match op:
		"snapshot":
			return {"ok": true, "snapshot": build_snapshot()}
		"diag":
			return _handle_diag(cmd)
		"interv":
			return _handle_interv(cmd)
		_:
			return {"ok": false, "err": "unsupported_op", "op": op}

func _handle_interv(cmd: Dictionary) -> Dictionary:
	var id_str: String = String(cmd.get("id", ""))
	if id_str == "":
		return {"ok": false, "err": "missing_id"}
	var id_sn: StringName = StringName(id_str)
	if not Catalog.interventions.has(id_sn):
		return {"ok": false, "err": "unknown_id"}
	var success: bool = World.try_assign_intervention(id_sn)
	return {"ok": success}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_interv.gd -gexit
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autoload/agent_bridge.gd test/harness/unit/test_bridge_interv.gd
git commit -m "feat(bridge): interv op routes to World.try_assign_intervention"
```

---

## Task 8: `advance` op — tick Sim by N game hours without real time

The bridge's most important command for headless deterministic playthroughs. Real-time scaling is bypassed.

**Files:**
- Modify: `autoload/agent_bridge.gd`
- Modify: `autoload/sim.gd` (expose direct hour-advance method if not already public)
- Create: `test/harness/unit/test_bridge_advance.gd`

- [ ] **Step 1: Inspect existing Sim API**

```bash
grep -n "apply_tick\|func.*hours" autoload/sim.gd
```

Note the existing public surface: `apply_tick(game_hours: float)` (already present per current code).

`Clock.advance(hrs)` is also already public (called from `Sim._process`).

No new method needed on `Sim`. Bridge calls `Sim.apply_tick()` directly — this is the same method `Sim._process()` calls per frame.

- [ ] **Step 2: Write the failing test**

`test/harness/unit/test_bridge_advance.gd`:

```gdscript
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	if Clock.has_method("reset_for_test"):
		Clock.reset_for_test()
	Sim.reset_for_test()
	World.client.overskudd = 100.0

func test_advance_moves_clock() -> void:
	var hour_before: float = Clock.hour
	var day_before: int = Clock.day
	bridge.handle_command({"op": "advance", "game_hours": 3.0})
	# 3 hours later (no day wrap in this case)
	assert_almost_eq(Clock.hour, hour_before + 3.0, 0.01)
	assert_eq(Clock.day, day_before)

func test_advance_zero_hours_is_no_op() -> void:
	var hour_before: float = Clock.hour
	var reply: Dictionary = bridge.handle_command({"op": "advance", "game_hours": 0.0})
	assert_eq(reply.get("ok"), true)
	assert_almost_eq(Clock.hour, hour_before, 0.01)

func test_advance_negative_hours_returns_error() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "advance", "game_hours": -1.0})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "negative_hours")
```

- [ ] **Step 3: Run test to verify it fails**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_advance.gd -gexit
```

Expected: FAIL — `advance` op falls through to `unsupported_op`.

- [ ] **Step 4: Add `_handle_advance` and wire it in**

In `autoload/agent_bridge.gd`, update `handle_command()` match and add the helper:

```gdscript
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
		_:
			return {"ok": false, "err": "unsupported_op", "op": op}

func _handle_advance(cmd: Dictionary) -> Dictionary:
	var hrs: float = float(cmd.get("game_hours", 0.0))
	if hrs < 0.0:
		return {"ok": false, "err": "negative_hours"}
	if hrs == 0.0:
		return {"ok": true}
	Clock.advance(hrs)
	Sim.apply_tick(hrs)
	return {"ok": true}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_advance.gd -gexit
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add autoload/agent_bridge.gd test/harness/unit/test_bridge_advance.gd
git commit -m "feat(bridge): advance op ticks Sim/Clock without real time"
```

---

## Task 9: `set_speed` op

Allows the agent to change the wall-clock speed scale, primarily for interactive runs (a UI-driven evaluator would set this). For headless `advance`-driven runs, speed doesn't matter — but the op is part of the protocol.

**Files:**
- Modify: `autoload/agent_bridge.gd`
- Create: `test/harness/unit/test_bridge_set_speed.gd`

- [ ] **Step 1: Confirm `Clock` has a `set_speed` method (or equivalent)**

```bash
grep -n "set_speed\|time_scale" autoload/clock.gd
```

If `Clock` already exposes `set_speed(scale: float)` or has a `time_scale` property, use that. If not, use the property assignment directly. The plan assumes a `time_scale` property exists on `Clock` (matches the rest of the codebase's `Clock.time_scale` references).

- [ ] **Step 2: Write the failing test**

`test/harness/unit/test_bridge_set_speed.gd`:

```gdscript
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")

func test_set_speed_changes_clock_time_scale() -> void:
	bridge.handle_command({"op": "set_speed", "scale": 4.0})
	assert_almost_eq(Clock.time_scale, 4.0, 0.01)
	# Reset for next tests
	bridge.handle_command({"op": "set_speed", "scale": 1.0})

func test_set_speed_zero_rejected() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "set_speed", "scale": 0.0})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "invalid_scale")

func test_set_speed_negative_rejected() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "set_speed", "scale": -1.0})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "invalid_scale")
```

- [ ] **Step 3: Run test to verify it fails**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_set_speed.gd -gexit
```

Expected: FAIL.

- [ ] **Step 4: Add `_handle_set_speed`**

In `autoload/agent_bridge.gd`:

```gdscript
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
		_:
			return {"ok": false, "err": "unsupported_op", "op": op}

func _handle_set_speed(cmd: Dictionary) -> Dictionary:
	var scale: float = float(cmd.get("scale", 0.0))
	if scale <= 0.0:
		return {"ok": false, "err": "invalid_scale"}
	Clock.time_scale = scale
	return {"ok": true}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_set_speed.gd -gexit
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add autoload/agent_bridge.gd test/harness/unit/test_bridge_set_speed.gd
git commit -m "feat(bridge): set_speed op writes Clock.time_scale"
```

---

## Task 10: `shutdown` op — clean quit

**Files:**
- Modify: `autoload/agent_bridge.gd`
- Create: `test/harness/unit/test_bridge_shutdown.gd`

- [ ] **Step 1: Write the test**

`test/harness/unit/test_bridge_shutdown.gd`:

```gdscript
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	bridge.shutdown_requested = false   # cleared each test

func test_shutdown_op_sets_flag_only() -> void:
	# Bridge should not actually quit the engine during a GUT run — it sets
	# `shutdown_requested = true` and the comms loop (Task 11) acts on it.
	var reply: Dictionary = bridge.handle_command({"op": "shutdown"})
	assert_eq(reply.get("ok"), true)
	assert_true(bridge.shutdown_requested)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_shutdown.gd -gexit
```

Expected: FAIL — `shutdown_requested` is not a member of AgentBridge.

- [ ] **Step 3: Add `shutdown_requested` flag and `_handle_shutdown`**

In `autoload/agent_bridge.gd`:

Add near the other state vars:

```gdscript
var shutdown_requested: bool = false
```

Update `handle_command()`:

```gdscript
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_shutdown.gd -gexit
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autoload/agent_bridge.gd test/harness/unit/test_bridge_shutdown.gd
git commit -m "feat(bridge): shutdown op flags graceful quit"
```

---

## Task 11: Event streaming — EventBus signals → events buffer

The bridge subscribes to every `EventBus` signal at activation and buffers them as JSON dicts. The file-comms loop (Task 12) drains this buffer to `events.jsonl`.

**Files:**
- Modify: `autoload/agent_bridge.gd`
- Create: `test/harness/unit/test_bridge_event_streaming.gd`

- [ ] **Step 1: Write the failing test**

`test/harness/unit/test_bridge_event_streaming.gd`:

```gdscript
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	bridge.start_event_capture()
	bridge.drain_events()   # clear any pre-existing buffered events

func after_each() -> void:
	bridge.stop_event_capture()

func test_overskudd_changed_buffered() -> void:
	EventBus.overskudd_changed.emit(&"elling", 42.0)
	var events: Array = bridge.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["ev"], "overskudd_changed")
	assert_eq(events[0]["client"], "elling")
	assert_almost_eq(events[0]["v"], 42.0, 0.01)

func test_case_file_updated_buffered() -> void:
	EventBus.case_file_updated.emit(&"obs_alphabetizes")
	var events: Array = bridge.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["ev"], "case_file_updated")
	assert_eq(events[0]["entry"], "obs_alphabetizes")

func test_day_started_buffered() -> void:
	EventBus.day_started.emit(2)
	var events: Array = bridge.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["ev"], "day_started")
	assert_eq(events[0]["day"], 2)

func test_drain_clears_buffer() -> void:
	EventBus.overskudd_changed.emit(&"elling", 10.0)
	var first: Array = bridge.drain_events()
	assert_eq(first.size(), 1)
	var second: Array = bridge.drain_events()
	assert_eq(second.size(), 0)

func test_events_include_time_field() -> void:
	EventBus.overskudd_changed.emit(&"elling", 10.0)
	var events: Array = bridge.drain_events()
	assert_eq(events.size(), 1)
	assert_true(events[0].has("t"))
	assert_true(events[0]["t"].has("d"))
	assert_true(events[0]["t"].has("h"))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_event_streaming.gd -gexit
```

Expected: FAIL — methods undefined.

- [ ] **Step 3: Implement event capture in `autoload/agent_bridge.gd`**

Append to `autoload/agent_bridge.gd`:

```gdscript
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
	ev["t"] = {"d": Clock.day, "h": Clock.hour}
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_event_streaming.gd -gexit
```

Expected: PASS — all 5 streaming tests green.

- [ ] **Step 5: Commit**

```bash
git add autoload/agent_bridge.gd test/harness/unit/test_bridge_event_streaming.gd
git commit -m "feat(bridge): capture EventBus signals into drain-able buffer"
```

---

## Task 12: File-based comms loop

Wire `start_event_capture`, command-file tailing, and event-file appending into the bridge's runtime. When `active`, on `_process`: drain pending commands from `cmd.jsonl`, execute each, drain events, append to `events.jsonl`, write `ready` sentinel.

**Files:**
- Modify: `autoload/agent_bridge.gd`
- Modify: `main.gd` (start the comms loop after flags parsed)
- Create: `test/harness/unit/test_bridge_comms_io.gd`

- [ ] **Step 1: Write the failing test**

`test/harness/unit/test_bridge_comms_io.gd`:

```gdscript
extends GutTest

var bridge: Node
var tmp_dir: String

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	tmp_dir = BridgeTestHelpers.make_tmp_comms_dir()
	bridge.shutdown_requested = false
	bridge.active = false   # reset
	bridge.start_event_capture()
	bridge.drain_events()
	# Initialize file-comms state
	bridge.bind_comms(tmp_dir)

func after_each() -> void:
	bridge.stop_event_capture()
	bridge.unbind_comms()

func _write_cmd_line(line: String) -> void:
	var path := tmp_dir + "/cmd.jsonl"
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	f.seek_end()
	f.store_line(line)
	f.close()

func _read_events_lines() -> Array:
	var path := tmp_dir + "/events.jsonl"
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	var lines: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() != "":
			lines.append(JSON.parse_string(line))
	f.close()
	return lines

func test_pump_processes_pending_commands() -> void:
	_write_cmd_line(JSON.stringify({"op": "snapshot"}))
	bridge.pump()
	var events := _read_events_lines()
	# Snapshot reply is the only output of a snapshot command (no event-bus signal involved).
	assert_eq(events.size(), 1)
	assert_eq(events[0]["reply"]["ok"], true)
	assert_true(events[0]["reply"].has("snapshot"))

func test_pump_appends_eventbus_events() -> void:
	_write_cmd_line(JSON.stringify({"op": "advance", "game_hours": 0.0}))
	EventBus.day_started.emit(2)
	bridge.pump()
	var events := _read_events_lines()
	# At least one "ev":"day_started" appears
	var found := false
	for e in events:
		if e.get("ev", "") == "day_started":
			found = true
	assert_true(found, "day_started event must be flushed to events.jsonl")

func test_ready_sentinel_written_after_each_command() -> void:
	_write_cmd_line(JSON.stringify({"op": "snapshot"}))
	bridge.pump()
	assert_true(FileAccess.file_exists(tmp_dir + "/ready"))

func test_shutdown_op_stops_pump() -> void:
	_write_cmd_line(JSON.stringify({"op": "shutdown"}))
	bridge.pump()
	assert_true(bridge.shutdown_requested)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_comms_io.gd -gexit
```

Expected: FAIL — `bind_comms`, `pump`, `unbind_comms` not defined.

- [ ] **Step 3: Implement comms loop in `autoload/agent_bridge.gd`**

Append to `autoload/agent_bridge.gd`:

```gdscript
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
	# Truncate events.jsonl so each run starts fresh.
	var ev_path := _events_path()
	if FileAccess.file_exists(ev_path):
		DirAccess.remove_absolute(ev_path)
	# Ensure cmd.jsonl exists (so tailing works on first write).
	var cmd_path := _cmd_path()
	if not FileAccess.file_exists(cmd_path):
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
	for line in lines:
		if line.strip_edges() == "":
			continue
		var parsed = JSON.parse_string(line)
		if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
			_append_event({"ev": "parse_error", "raw": line})
			continue
		var reply := handle_command(parsed)
		_append_event({"reply": reply, "for": parsed.get("op", ""), "t": {"d": Clock.day, "h": Clock.hour}})
		# Flush any EventBus events that fired during this command.
		for ev in drain_events():
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
```

- [ ] **Step 4: Wire comms loop into main runtime**

Update `main.gd`'s `_ready()`:

```gdscript
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
```

Update `autoload/agent_bridge.gd`'s `_process()` (or `_ready` if not yet present):

```gdscript
func _process(_delta: float) -> void:
	pump()
	if shutdown_requested:
		get_tree().quit(0)
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/harness/unit/test_bridge_comms_io.gd -gexit
```

Expected: PASS — all 4 comms tests green.

- [ ] **Step 6: Run all bridge unit tests as regression sweep**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://test/harness/unit -gexit
```

Expected: every prior bridge test still green.

- [ ] **Step 7: Commit**

```bash
git add autoload/agent_bridge.gd main.gd test/harness/unit/test_bridge_comms_io.gd
git commit -m "feat(bridge): file-based comms loop — tail cmd.jsonl, append events.jsonl"
```

---

## Task 13: Python scripted-strategy player

Driver that writes scripted command lines to `cmd.jsonl`, waits for `ready` sentinel, reads `events.jsonl`, and saves a complete trace. Pure stdlib Python — no third-party deps.

**Files:**
- Create: `harness/lib/scripted_player.py`
- Create: `harness/lib/trace_schema.py`

- [ ] **Step 1: Write `harness/lib/trace_schema.py`**

```python
"""Minimal schema validation for harness JSON-lines.

This module is intentionally dependency-free — no jsonschema, no pydantic.
The harness can run on any machine with a recent stdlib Python.
"""
from __future__ import annotations
import json
from typing import Any, Iterable


REQUIRED_TOP_LEVEL_SNAPSHOT_KEYS = ("time", "client", "case_file", "economy", "catalog")
REQUIRED_CLIENT_KEYS = ("needs", "cognitive", "overskudd", "overskudd_ceiling")
KNOWN_EVENT_TYPES = (
    "day_started",
    "day_ended",
    "overskudd_changed",
    "caseworker_capacity_changed",
    "case_file_updated",
    "diagnostic_completed",
    "intervention_completed",
    "action_failed",
)


class SchemaError(ValueError):
    pass


def validate_event_line(line: str) -> dict[str, Any]:
    """Parse one JSON line and verify it's either a reply, an event, or a parse_error."""
    try:
        obj = json.loads(line)
    except json.JSONDecodeError as e:
        raise SchemaError(f"Invalid JSON: {e}") from e

    if not isinstance(obj, dict):
        raise SchemaError("Top-level must be an object")

    if "reply" in obj:
        if not isinstance(obj["reply"], dict):
            raise SchemaError("reply must be an object")
        return obj
    if "ev" in obj:
        if obj["ev"] not in KNOWN_EVENT_TYPES and obj["ev"] != "parse_error":
            raise SchemaError(f"Unknown event type: {obj['ev']}")
        return obj
    raise SchemaError("Line is neither a reply nor an event")


def validate_snapshot(snap: dict[str, Any]) -> None:
    for key in REQUIRED_TOP_LEVEL_SNAPSHOT_KEYS:
        if key not in snap:
            raise SchemaError(f"snapshot missing required key: {key}")
    for key in REQUIRED_CLIENT_KEYS:
        if key not in snap["client"]:
            raise SchemaError(f"client missing required key: {key}")


def validate_trace_file(path: str) -> tuple[int, int]:
    """Returns (line_count, error_count). Raises only on file-level IO failure."""
    lines = 0
    errors = 0
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            lines += 1
            try:
                validate_event_line(line)
            except SchemaError:
                errors += 1
    return lines, errors
```

- [ ] **Step 2: Write `harness/lib/scripted_player.py`**

```python
#!/usr/bin/env python3
"""Drive a Godot --agent-mode session via file-comms with a scripted action plan.

Usage:
    python harness/lib/scripted_player.py \\
        --godot /Applications/Godot.app/Contents/MacOS/Godot \\
        --project /path/to/lifelines-tycoon \\
        --plan harness/strategies/examples/baseline_observer.json \\
        --comms-dir /tmp/lifelines-harness/run1 \\
        --trace-out /tmp/lifelines-harness/run1/trace.jsonl

Action plan JSON format:
    {
      "default":   {"op":"snapshot"},
      "checkpoints": [
        {"at":{"d":1,"h":9},  "ops":[{"op":"diag","id":"diag_psych_eval"}]},
        ...
      ],
      "stop_at": {"d":3, "h":0}
    }
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

# Re-import from sibling
sys.path.insert(0, str(Path(__file__).parent))
from trace_schema import validate_event_line, SchemaError  # noqa: E402


def load_plan(path: str) -> dict:
    with open(path) as fh:
        plan = json.load(fh)
    plan.setdefault("default", {"op": "snapshot"})
    plan.setdefault("checkpoints", [])
    plan.setdefault("stop_at", {"d": 3, "h": 0})
    return plan


def init_comms_dir(comms_dir: str) -> None:
    p = Path(comms_dir)
    if p.exists():
        shutil.rmtree(p)
    p.mkdir(parents=True)
    # Initialize cmd.jsonl as empty so Godot can open it.
    (p / "cmd.jsonl").write_text("")


def append_command(comms_dir: str, cmd: dict) -> None:
    line = json.dumps(cmd, ensure_ascii=False) + "\n"
    with open(Path(comms_dir) / "cmd.jsonl", "a") as fh:
        fh.write(line)


def wait_for_ready(comms_dir: str, timeout_s: float = 30.0) -> bool:
    ready = Path(comms_dir) / "ready"
    if ready.exists():
        ready.unlink()
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if ready.exists():
            ready.unlink()
            return True
        time.sleep(0.05)
    return False


def read_events_since(comms_dir: str, cursor: int) -> tuple[list[dict], int]:
    path = Path(comms_dir) / "events.jsonl"
    if not path.exists():
        return [], cursor
    events: list[dict] = []
    with open(path) as fh:
        fh.seek(cursor)
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            try:
                events.append(validate_event_line(line))
            except SchemaError as e:
                events.append({"ev": "schema_error", "raw": line, "err": str(e)})
        new_cursor = fh.tell()
    return events, new_cursor


def current_time(events_in_window: list[dict]) -> tuple[int, float]:
    """Look at the last event with a 't' field; return (day, hour)."""
    for ev in reversed(events_in_window):
        t = ev.get("t") or ev.get("reply", {}).get("snapshot", {}).get("time")
        if t and "d" in t and ("h" in t or "hour" in t):
            return int(t["d"]), float(t.get("h", t.get("hour", 0.0)))
    return 1, 0.0


def checkpoint_due(plan_checkpoint: dict, day: int, hour: float) -> bool:
    at = plan_checkpoint["at"]
    return (day, hour) >= (int(at["d"]), float(at["h"]))


def stop_reached(plan_stop_at: dict, day: int, hour: float) -> bool:
    return (day, hour) >= (int(plan_stop_at["d"]), float(plan_stop_at["h"]))


def run(args: argparse.Namespace) -> int:
    plan = load_plan(args.plan)
    init_comms_dir(args.comms_dir)

    # Launch Godot in agent mode.
    godot_cmd = [
        args.godot,
        "--headless",
        "--path",
        args.project,
        "--",
        "--agent-mode",
        "--comms-dir",
        args.comms_dir,
    ]
    if args.reveal_hidden:
        godot_cmd.append("--reveal-hidden")
    print(f"[player] launching: {' '.join(godot_cmd)}", file=sys.stderr)
    godot_proc = subprocess.Popen(godot_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    cursor = 0
    all_events: list[dict] = []
    pending_checkpoints = list(plan["checkpoints"])

    try:
        # Initial snapshot — establish baseline time.
        append_command(args.comms_dir, {"op": "snapshot"})
        if not wait_for_ready(args.comms_dir, args.checkpoint_timeout):
            print("[player] timeout waiting for initial snapshot", file=sys.stderr)
            return 2
        events, cursor = read_events_since(args.comms_dir, cursor)
        all_events.extend(events)

        day, hour = current_time(all_events)
        step_hours = float(args.step_hours)

        while not stop_reached(plan["stop_at"], day, hour):
            # Execute any due checkpoint actions before advancing.
            still_pending = []
            for cp in pending_checkpoints:
                if checkpoint_due(cp, day, hour):
                    for op in cp.get("ops", []):
                        append_command(args.comms_dir, op)
                        if not wait_for_ready(args.comms_dir, args.checkpoint_timeout):
                            print(f"[player] timeout on op {op}", file=sys.stderr)
                            return 3
                        ev, cursor = read_events_since(args.comms_dir, cursor)
                        all_events.extend(ev)
                else:
                    still_pending.append(cp)
            pending_checkpoints = still_pending

            # Apply default op (typically snapshot) then advance.
            append_command(args.comms_dir, plan["default"])
            wait_for_ready(args.comms_dir, args.checkpoint_timeout)
            ev, cursor = read_events_since(args.comms_dir, cursor)
            all_events.extend(ev)

            append_command(args.comms_dir, {"op": "advance", "game_hours": step_hours})
            wait_for_ready(args.comms_dir, args.checkpoint_timeout)
            ev, cursor = read_events_since(args.comms_dir, cursor)
            all_events.extend(ev)
            day, hour = current_time(all_events)

        # Shutdown
        append_command(args.comms_dir, {"op": "shutdown"})
        wait_for_ready(args.comms_dir, args.checkpoint_timeout)
        godot_proc.wait(timeout=10)
    finally:
        if godot_proc.poll() is None:
            godot_proc.terminate()
            try:
                godot_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                godot_proc.kill()

    # Write final trace.
    Path(args.trace_out).parent.mkdir(parents=True, exist_ok=True)
    with open(args.trace_out, "w") as fh:
        for ev in all_events:
            fh.write(json.dumps(ev) + "\n")
    print(f"[player] wrote {len(all_events)} trace lines to {args.trace_out}", file=sys.stderr)
    return 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--godot", required=True, help="Path to Godot binary")
    p.add_argument("--project", required=True, help="Path to lifelines-tycoon project root")
    p.add_argument("--plan", required=True, help="Path to scripted action plan JSON")
    p.add_argument("--comms-dir", required=True, help="Per-run comms directory")
    p.add_argument("--trace-out", required=True, help="Output trace jsonl path")
    p.add_argument("--reveal-hidden", action="store_true", help="Pass --reveal-hidden to Godot")
    p.add_argument("--step-hours", type=float, default=1.0, help="Game-hours per tick step")
    p.add_argument("--checkpoint-timeout", type=float, default=30.0, help="Seconds to wait per command")
    return p.parse_args()


if __name__ == "__main__":
    sys.exit(run(parse_args()))
```

- [ ] **Step 3: Make scripts executable**

```bash
chmod +x harness/lib/scripted_player.py
```

- [ ] **Step 4: Smoke-import the modules to verify they parse**

```bash
python3 -c "import sys; sys.path.insert(0,'harness/lib'); import trace_schema, scripted_player; print('OK')"
```

Expected: prints `OK`. No import errors.

- [ ] **Step 5: Commit**

```bash
git add harness/lib/scripted_player.py harness/lib/trace_schema.py
git commit -m "feat(harness): Python scripted strategy player + trace schema"
```

---

## Task 14: Example scripted strategy

Concrete action plan the smoke test will consume.

**Files:**
- Create: `harness/strategies/examples/baseline_observer.json`

- [ ] **Step 1: Write the JSON**

`harness/strategies/examples/baseline_observer.json`:

```json
{
  "name": "baseline_observer",
  "description": "Runs a single diagnostic on day 1 hour 9, otherwise observes. Drives a 2-day arc.",
  "default": {"op": "snapshot"},
  "checkpoints": [
    {"at": {"d": 1, "h": 9.0}, "ops": [{"op": "diag", "id": "diag_psych_eval"}]},
    {"at": {"d": 2, "h": 9.0}, "ops": [{"op": "interv", "id": "int_reading_together"}]}
  ],
  "stop_at": {"d": 3, "h": 0.0}
}
```

- [ ] **Step 2: Verify the file parses as JSON**

```bash
python3 -m json.tool harness/strategies/examples/baseline_observer.json > /dev/null
```

Expected: no output (silent success).

- [ ] **Step 3: Commit**

```bash
git add harness/strategies/examples/baseline_observer.json
git commit -m "feat(harness): baseline observer example scripted strategy"
```

---

## Task 15: End-to-end smoke test

Bash script that launches the scripted player against a known Godot install, runs the example plan, and asserts trace shape.

**Files:**
- Create: `harness/test/smoke_bridge.sh`

- [ ] **Step 1: Write the script**

`harness/test/smoke_bridge.sh`:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for AgentBridge + scripted player.
#
# Runs the baseline_observer plan against the prototype, verifies:
#   1. Godot exits cleanly (rc 0)
#   2. trace.jsonl is non-empty
#   3. trace contains at least one diagnostic_completed event
#   4. trace contains at least one day_started event

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Resolve Godot binary
if [ -n "${GODOT_BIN:-}" ]; then
    GODOT="$GODOT_BIN"
else
    GODOT=""
    for candidate in \
        "$HOME/Applications/Godot/Godot.app/Contents/MacOS/Godot" \
        "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
        "/Applications/Godot.app/Contents/MacOS/Godot" \
        "/Applications/Godot_4.app/Contents/MacOS/Godot"; do
        if [ -x "$candidate" ]; then GODOT="$candidate"; break; fi
    done
    if [ -z "$GODOT" ] && command -v godot &>/dev/null; then GODOT=godot; fi
fi
if [ -z "${GODOT:-}" ]; then echo "Error: cannot find Godot binary"; exit 1; fi

COMMS_DIR="/tmp/lifelines-harness-smoke/$(date +%s)"
TRACE_OUT="$COMMS_DIR/trace.jsonl"

echo "[smoke] godot:       $GODOT"
echo "[smoke] project:     $PROJECT_DIR"
echo "[smoke] comms-dir:   $COMMS_DIR"

# Ensure assets are imported before headless run.
"$GODOT" --headless --path "$PROJECT_DIR" --import &>/dev/null || true

python3 "$PROJECT_DIR/harness/lib/scripted_player.py" \
    --godot "$GODOT" \
    --project "$PROJECT_DIR" \
    --plan "$PROJECT_DIR/harness/strategies/examples/baseline_observer.json" \
    --comms-dir "$COMMS_DIR" \
    --trace-out "$TRACE_OUT" \
    --step-hours 1.0 \
    --checkpoint-timeout 30.0

if [ ! -s "$TRACE_OUT" ]; then
    echo "[smoke] FAIL: trace file empty: $TRACE_OUT"; exit 1
fi

# Trace assertions
if ! grep -q '"ev":"day_started"' "$TRACE_OUT"; then
    echo "[smoke] FAIL: no day_started event in trace"; exit 1
fi

if ! grep -q '"ev":"diagnostic_completed"' "$TRACE_OUT"; then
    echo "[smoke] FAIL: no diagnostic_completed event in trace"; exit 1
fi

# Schema validate every line
python3 - "$TRACE_OUT" <<'PY'
import sys
sys.path.insert(0, "harness/lib")
from trace_schema import validate_trace_file
lines, errs = validate_trace_file(sys.argv[1])
print(f"[smoke] {lines} lines, {errs} schema errors")
if errs > 0:
    sys.exit(2)
PY

echo "[smoke] PASS"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x harness/test/smoke_bridge.sh
```

- [ ] **Step 3: Run it**

```bash
./harness/test/smoke_bridge.sh
```

Expected output ends with: `[smoke] PASS`.

If Godot binary cannot be located, set `GODOT_BIN` explicitly:

```bash
GODOT_BIN=/path/to/Godot ./harness/test/smoke_bridge.sh
```

- [ ] **Step 4: Commit**

```bash
git add harness/test/smoke_bridge.sh
git commit -m "feat(harness): end-to-end smoke test for AgentBridge + player"
```

---

## Task 16: Regression sweep + project-wide test sanity

Verify nothing in the existing prototype regressed when we added the bridge.

**Files:** none (verification step only)

- [ ] **Step 1: Run ALL GUT tests**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit
```

Expected: every test green — including all pre-existing unit tests (`test/unit/`) and all new harness tests (`test/harness/unit/`).

- [ ] **Step 2: Confirm normal game still boots**

```bash
godot --headless --path . --quit-after 30
```

Expected: clean exit. No errors. UI scene loads (no harness flag = normal mode).

- [ ] **Step 3: Confirm `--agent-mode` doesn't load UI**

```bash
rm -rf /tmp/lifelines-agent-check
godot --headless --path . --quit-after 10 -- --agent-mode --comms-dir /tmp/lifelines-agent-check
ls /tmp/lifelines-agent-check/
```

Expected: `cmd.jsonl`, `events.jsonl` exist. UI not loaded (no `main_ui.tscn` errors).

- [ ] **Step 4: Run smoke test once more**

```bash
./harness/test/smoke_bridge.sh
```

Expected: `[smoke] PASS`.

(No commit needed — this is a verification task.)

---

## Task 17: Finalize README with current status

**Files:**
- Modify: `harness/README.md`

- [ ] **Step 1: Update README to reflect what Plan 1 actually shipped**

Replace `harness/README.md` with:

```markdown
# Harness — Adversarial Agent Loop

Plan 1 of 6 from `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`.

This directory holds the orchestration + comms layer that drives the Lifelines economy prototype from external agents.

## Status

| Plan | Ships | Status |
|------|-------|--------|
| 1 | AgentBridge + scripted playtest | ✅ done |
| 2 | Rubric authoring (vision.md + ~70 anchor files) | pending |
| 3 | Generator agent + worktree loop | pending |
| 4 | Evaluator + strategy tournament | pending |
| 5 | Planner + orchestrator + report.html | pending |
| 6 | Meta-evaluation | pending |

## What's in Plan 1

- `autoload/agent_bridge.gd` — Godot autoload exposing JSON-line commands + events
- `lib/scripted_player.py` — Python driver for a static action plan
- `lib/trace_schema.py` — jsonl schema validator
- `strategies/examples/baseline_observer.json` — canned plan
- `test/smoke_bridge.sh` — end-to-end smoke test

Bridge is dormant unless the game is launched with `--agent-mode`.

## Quick start

```bash
# End-to-end smoke
./harness/test/smoke_bridge.sh

# Run a custom plan (requires Godot)
python3 harness/lib/scripted_player.py \
  --godot /Applications/Godot.app/Contents/MacOS/Godot \
  --project "$PWD" \
  --plan harness/strategies/examples/baseline_observer.json \
  --comms-dir /tmp/lifelines-harness/run1 \
  --trace-out /tmp/lifelines-harness/run1/trace.jsonl
```

## Comms layout

```
harness/comms/<run-id>/
├── cmd.jsonl             # external agent appends commands; bridge tails
├── events.jsonl          # bridge appends events; agent tails
└── ready                 # sentinel — bridge writes after each command completes
```

All files are append-only JSON-lines (one JSON object per line).

## Bridge protocol

Supported commands (input to `cmd.jsonl`):

| op | args | effect |
|---|---|---|
| `snapshot` | — | reply contains full state dict |
| `diag` | `id` | calls `World.try_run_diagnostic` |
| `interv` | `id` | calls `World.try_assign_intervention` |
| `advance` | `game_hours` (float) | advances Clock + Sim by N game hours |
| `set_speed` | `scale` (float > 0) | sets `Clock.time_scale` |
| `shutdown` | — | sets `shutdown_requested = true`, engine quits next tick |

Replies (appended to `events.jsonl`): one line of the form
`{"reply": {"ok": true|false, ...}, "for": "<op>", "t": {"d": N, "h": F}}`

EventBus events (also appended to `events.jsonl`):
`{"ev": "<event_type>", "t": {"d": N, "h": F}, ...payload}`

See `autoload/agent_bridge.gd` for the canonical handler list and `harness/lib/trace_schema.py` for known event types.

## What's NOT in Plan 1

LLM-driven strategy player, planner, generator, evaluator, contract negotiation, rubric anchors, orchestrator, report.html. See `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md` §11 for upcoming plans.
```

- [ ] **Step 2: Commit**

```bash
git add harness/README.md
git commit -m "docs(harness): finalize Plan 1 README with shipped protocol"
```

---

## Spec-coverage check (post-plan)

Self-review against `docs/superpowers/specs/2026-05-20-adversarial-harness-design.md`:

| Spec section | Covered by | Notes |
|---|---|---|
| §4.1 AgentBridge — activation, protocol, commands, events, snapshot shape, reveal-hidden | Tasks 2–12 | Full coverage. Transport revised to file-based per design discussion. |
| §4.2 (a) Scripted strategy player | Tasks 13–14 | Full coverage. |
| §4.2 (b) Prior-guided LLM strategy | Deferred | Plan 4. |
| §4.3 Planner | Deferred | Plan 5. |
| §4.4 Generator | Deferred | Plan 3. |
| §4.5 Evaluator | Deferred | Plan 4. |
| §4.6 Orchestrator | Deferred | Plan 5. |
| §5 Data flow | Partial | Bridge-side comms shape is the foundation; full flow needs orchestrator. |
| §7.1 L1 unit tests | Tasks 2, 4, 5, 6, 7, 8, 9, 10, 11, 12 | Full coverage of bridge tests listed in spec. |
| §7.2 L2 smoke | Task 15 | First-version smoke covers bridge + scripted player. Full L2 (full-harness smoke) deferred to Plan 5. |
| §7.3 L3 meta-eval | Deferred | Plan 6. |

**Gaps acknowledged:** Plan 1 ships the foundation — the bridge and a scripted player to exercise it. LLM agents, rubric, contracts, tournaments, and orchestration are explicitly out of scope and live in Plans 2–6.

---

**End of Plan 1.**
