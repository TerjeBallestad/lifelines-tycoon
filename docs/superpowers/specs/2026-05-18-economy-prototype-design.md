# Lifelines — Economy Prototype Design

**Status:** Approved design, ready for implementation planning
**Date:** 2026-05-18
**Target engine:** Godot 4.5 (GDScript)
**Location:** `/Users/godstemning/projects-local/lifelines-tycoon/` (fresh Godot project)

---

## 1. Purpose & validation hypothesis

Lifelines' core simulation layer (needs, skills, overskudd) is being developed in parallel. This prototype isolates and tests the **economy layer** that sits on top: the player as state government allocates scarce caseworker capacity to shape the environment around a single client (Elling) and nudge them toward a healthier equilibrium.

**Hypothesis under test:**

> Allocating finite caseworker capacity to diagnostics and interventions — gated by the player's emerging understanding of the client (Outer Wilds–style knowledge gate) — produces a satisfying loop of *observe → understand → choose action*, and feels like state-care work rather than number-pushing.

**Why a separate prototype:** the economy layer's success criteria are independent of the sim layer's. A stub sim (decay + regen) is enough to make economy decisions bite. If this loop fails to feel meaningful, no amount of sim polish saves it. If it succeeds, integration with the real M2 sim is a wiring task, not a design task.

## 2. Resources (the economy)

Three resources, two scarce:

| Resource | Scope | Behavior |
|---|---|---|
| **Overskudd** | per-client | stored 0–100 value. Each tick: hidden mood + cognitive define an `overskudd_ceiling`; stored overskudd drifts toward the ceiling at a fixed regen rate, never above. Action costs subtract directly, clamped to ≥ 0. |
| **Caseworker capacity** | state-side | finite hours/day (default 6.0); spent on diagnostics/interventions; refills at day boundary; unused hours forfeit |
| **Knowledge** | per-client (player-side) | the player's actual understanding via the **case file** (entries + tag set); pure gate — never consumed; gates which actions appear |

### Overskudd: ceiling + regen model (resolves B1)

The naive "recompute every tick from formula" overwrites consumption within one frame. Instead:

- `overskudd_ceiling()` = `100 · √(mood · cognitive_pool)`, recomputed each tick from hidden state.
- Stored `overskudd` is a separate float on `ClientState`.
- Each tick (`tick_overskudd(game_hours)`):
  - If stored > ceiling (e.g. needs just degraded): snap stored down to ceiling.
  - Else: stored += `overskudd_regen_rate · game_hours`, clamped to ceiling.
- Action consumption: `client.overskudd -= cost`, clamped to ≥ 0.

`overskudd_regen_rate` default 8.0 pts per game-hour (so a fully drained Elling regenerates over a full day if hidden state allows).

Knowledge is not a counter. It lives entirely in the case file's tag set. An intervention is available iff every required tag is present in the case file. This mirrors Outer Wilds: progress is what you have figured out, not a stat.

Explicitly **out of scope** for this prototype: money/budget, political capital, trust as a numeric stat, group program slots.

## 3. Verbs

Three player actions:

1. **Observe (free, passive).** Watching surfaces passive case-file entries over time. The sim rolls candidate observations every ~6 game-hours based on hidden state.
2. **Run diagnostic (paid, gated by prior knowledge).** Costs caseworker hours + client overskudd. Yields specific case-file entries → unlocks downstream actions.
3. **Assign intervention (paid, gated by knowledge).** Costs caseworker hours + client overskudd. Applies effects to needs/skills.

Group programs (1:many) explicitly deferred — would expand scarcity into a new dimension before we validate the single-client loop.

## 4. Population & cadence

- **One client:** Elling Pettersen. Blue/Green MTG profile (hidden). Perfectionist introvert per GDD. Reading skill maxed; phone, eye-contact, cooking, going-outside all at zero.
- **Real-time tick** with adjustable time scale. Default: 1 game-day = 60 real seconds (≈ 1 game-hour every 2.5 seconds). Player pauses freely with `Space`.
- **No multi-client allocation** in this prototype. Scarcity is temporal (more diagnostics now = deeper understanding but no growth this day vs more interventions now = growth but shallow understanding).

## 5. Architecture (Layer Cake + service autoloads)

Following godot-master conventions: presentation → logic → data → infrastructure, signals UP, calls DOWN.

```
PRESENTATION   features/ui/                                 text panels + buttons; binds to EventBus
LOGIC          autoload/{world,sim}.gd                      mutation API + tick loop
DATA           autoload/catalog.gd + features/{client,economy,case_file}/   .tres registry + RefCounted state
INFRASTRUCTURE autoload/{event_bus,clock}.gd                signal bus + time service
```

Catalog is a Data-layer query service (read-only registry of `.tres` files exposing `available_*` and `observation_candidates` filters). World is Logic — it owns the mutable runtime state and is the only mutation API; queries from UI go through it.

### Folder layout

```
lifelines-tycoon/
├── project.godot
├── .gitignore
├── icon.svg
├── main.tscn                       # root: spawns UI, kicks Sim
├── main.gd
├── autoload/
│   ├── event_bus.gd                # global signals, < 15 events
│   ├── clock.gd                    # game time + day boundaries + pause/speed
│   ├── catalog.gd                  # loads diagnostics/interventions/observations .tres at boot
│   ├── world.gd                    # owns ClientState, EconomyState, CaseFile; only mutation API
│   └── sim.gd                      # _process tick, advances state, rolls observations
├── features/
│   ├── client/
│   │   ├── client_state.gd         # RefCounted — Elling's runtime state
│   │   └── elling_init.tres        # initial state Resource
│   ├── case_file/
│   │   ├── case_file.gd            # RefCounted — entries + tag set
│   │   ├── case_entry.gd           # Resource (.tres)
│   │   └── seed/                   # passive observation pool, *.tres
│   ├── economy/
│   │   ├── economy_state.gd        # RefCounted — caseworker capacity
│   │   ├── diagnostic.gd           # Resource
│   │   ├── intervention.gd         # Resource
│   │   ├── diagnostics/            # *.tres catalog
│   │   └── interventions/          # *.tres catalog
│   └── ui/
│       ├── main_ui.tscn            # only UI scene; F6-testable
│       ├── main_ui.gd
│       ├── overskudd_bar.gd
│       ├── capacity_label.gd
│       ├── case_file_panel.gd
│       └── action_list.gd
└── docs/
    └── superpowers/specs/2026-05-18-economy-prototype-design.md   (this file)
```

**Autoload order:** `event_bus → clock → catalog → world → sim`

**Critical rules applied:**
- `World` is the only mutation API. UI calls `World.try_*`; World emits via EventBus.
- `Resource` catalog files have `local_to_scene = false` (read-only templates).
- `StringName` (`&"phone_call"`) for all dict keys and tags.
- `_physics_process` unused. Sim runs on `_process` via Clock tick.
- No hardcoded `res://` paths in logic scripts; use `@export_dir` or `DirAccess` for catalog scanning.

## 6. Data model

### Runtime state (RefCounted, owned by `World` autoload)

**`ClientState`** (`features/client/client_state.gd`)

```gdscript
class_name ClientState extends RefCounted

var id: StringName                              # &"elling"
var display_name: String
var mtg_primary: StringName                     # &"blue"  (hidden)
var mtg_secondary: StringName                   # &"green" (hidden)

# Hidden physiological needs (0.0–1.0). Higher = better.
var needs: Dictionary = {
    &"energy":   1.0,
    &"hunger":   1.0,
    &"bladder":  1.0,
    &"social":   1.0,
    &"security": 1.0,
}

# Hidden cognitive resources (0.0–1.0). Higher = better.
var cognitive: Dictionary = {
    &"attention": 1.0,
    &"willpower": 1.0,
}

# Visible: stored value 0–100, drifts toward ceiling.
var overskudd: float = 71.0
var overskudd_regen_rate: float = 8.0           # points per game-hour

var skills:  Dictionary = {}                    # Dict[StringName, int]
var mastery: Dictionary = {}                    # Dict[StringName, int]

func mood() -> float:
    var sum := 0.0
    for v in needs.values(): sum += v
    return sum / needs.size()

func cognitive_pool() -> float:
    return (cognitive[&"attention"] + cognitive[&"willpower"]) * 0.5

func overskudd_ceiling() -> float:
    return clamp(100.0 * sqrt(mood() * cognitive_pool()), 0.0, 100.0)

func tick_overskudd(game_hours: float) -> void:
    var ceiling := overskudd_ceiling()
    if overskudd > ceiling:
        overskudd = ceiling                     # ceiling drop snaps stored down
    else:
        overskudd = min(overskudd + overskudd_regen_rate * game_hours, ceiling)
```

**`CaseFile`** (`features/case_file/case_file.gd`)

```gdscript
class_name CaseFile extends RefCounted

var entries: Array[CaseEntry] = []              # ordered, append-only
var tags: Dictionary = {}                       # Dict[StringName, bool] — flat tag set

func add_entry(entry: CaseEntry) -> void:
    if has_entry(entry.id): return
    entries.append(entry)
    for t: StringName in entry.tags: tags[t] = true

func has_entry(id: StringName) -> bool:
    return entries.any(func(e): return e.id == id)

func has_all_tags(required: Array[StringName]) -> bool:
    for t: StringName in required:
        if not tags.has(t): return false
    return true
```

`has_entry` is O(n) per add (linear scan). Acceptable for prototype (entries < 50). Note for M2: switch to `Dict[StringName, bool]` mirror if scaling.

**`EconomyState`** (`features/economy/economy_state.gd`)

```gdscript
class_name EconomyState extends RefCounted

var capacity_max: float = 6.0                   # tuned to make V2 scarcity bite by day 3
var capacity_current: float = 6.0

func can_spend(hours: float) -> bool: return capacity_current >= hours
func spend(hours: float) -> bool:
    if not can_spend(hours): return false
    capacity_current -= hours
    return true
func refill_to_max() -> void: capacity_current = capacity_max
```

### Catalog data (Resource → `.tres` files)

**`CaseEntry`** (`features/case_file/case_entry.gd`)

```gdscript
class_name CaseEntry extends Resource

@export var id: StringName
@export_enum("Observation", "Diagnostic") var source: int = 0
@export var title: String
@export_multiline var body: String
@export var tags: Array[StringName] = []
# Optional gate for *conditional* observations. See `require_state` DSL below.
@export var require_state: Dictionary = {}
```

#### `require_state` DSL (resolves B2)

Each key in the dict is a clause; all clauses must hold (AND). Empty dict = no precondition.

Key format: `<scope>_<field>_<op>` where:

| Component | Allowed values |
|---|---|
| scope | `needs`, `cognitive`, `skill` |
| field | any key in the named scope's dict on `ClientState` (e.g. `energy`, `attention`, `phone`) |
| op | `lt` (strictly less than), `ge` (greater than or equal) |

Value type: `float` for `needs`/`cognitive`, `int` for `skill`.

Examples:

```gdscript
{&"needs_energy_lt": 0.3}                 # client.needs[&"energy"] < 0.3
{&"cognitive_willpower_lt": 0.3}          # client.cognitive[&"willpower"] < 0.3
{&"needs_social_ge": 0.7}                 # client.needs[&"social"] >= 0.7
{&"skill_phone_ge": 1, &"needs_energy_lt": 0.5}   # both must hold
```

Implementer note: `Catalog.observation_candidates` evaluates this DSL when filtering passive observation candidates. Unknown ops or scopes log a warning and treat the clause as false (fail-closed).

**`Diagnostic`** (`features/economy/diagnostic.gd`)

```gdscript
class_name Diagnostic extends Resource

@export var id: StringName
@export var label: String
@export_multiline var description: String
@export var caseworker_cost: float = 2.0
@export var overskudd_cost: float = 20.0
@export var gate_tags: Array[StringName] = []   # all must be present in case file
@export var yields: Array[CaseEntry] = []       # added on completion
```

**`Intervention`** (`features/economy/intervention.gd`)

```gdscript
class_name Intervention extends Resource

@export var id: StringName
@export var label: String
@export_multiline var description: String
@export var caseworker_cost: float = 1.0
@export var overskudd_cost: float = 15.0
@export var gate_tags: Array[StringName] = []
@export var needs_effects: Dictionary = {}      # Dict[StringName, float] additive
@export var skill_effects: Dictionary = {}      # Dict[StringName, int] additive
```

### `Catalog` autoload (Data layer)

- `_ready()` scans `res://features/economy/diagnostics/`, `interventions/`, `case_file/seed/`
- For each scan dir: iterate `DirAccess.get_files()`, **filter to entries ending in `.tres`** (skip `.tres.uid` and `.tres.import` siblings), then `ResourceLoader.load(path)`.
- Stores typed dicts: `Dict[StringName, Diagnostic]`, `Dict[StringName, Intervention]`, `Dict[StringName, CaseEntry]`.
- `available_diagnostics(case_file: CaseFile) -> Array[Diagnostic]` — filters by `gate_tags` matched
- `available_interventions(case_file: CaseFile) -> Array[Intervention]` — same
- `observation_candidates(client: ClientState, case_file: CaseFile) -> Array[CaseEntry]` — filters by `require_state` matched AND not already in case file

### Tag taxonomy (seed; grows organically)

- `mtg:white|blue|black|red|green` — MTG color evidence
- `need:energy_low|willpower_low|...` — observed need pattern
- `trauma:strangers|crowds|...` — anxiety triggers
- `skill_gap:phone|eye_contact|cooking|going_outside|...` — missing competencies
- `affinity:reading|nature|order|...` — interests
- `dependency:mother|...` — relational dependencies
- `flow:solo_focused|...` — activity flow profile
- `cognitive:high_attention_low_willpower|...` — psych eval findings
- `trust:warming|...` — relational micro-changes

## 7. Game loop

### Time scale (designer-tunable)

| Layer | Rate |
|---|---|
| `_process` tick | every frame (60Hz) |
| Game-hour | 2.5 real seconds |
| Game-day | 60 real seconds (24 game-hours) |
| Player session | ~10 minutes for a 10-day arc |

### Day cycle

```
day_started(n) → Economy.refill_to_max()
              → EventBus.day_started.emit(n)
              → UI re-enables/redisplays actions

  (24 in-game hours pass; Sim._process running each frame)

day_ended(n)  → unused capacity forfeited
              → next day auto-starts after a brief beat
```

### `Sim._process(delta)` work per frame

```
game_seconds := delta * Clock.time_scale
game_hours   := game_seconds / 3600.0          # but at default scale 1 real-sec ≈ 0.4 game-hr,
                                               # actually: game_hours = game_seconds * (24/60) — see Clock
1. Decay needs by per-hour rates × game_hours.
2. Tick cognitive: attention regen, willpower decay (see table).
3. client.tick_overskudd(game_hours).
4. If overskudd changed > 0.5 since last emit: EventBus.overskudd_changed.emit(...)
5. Roll passive observation every ~6 game-hours (see below).
6. Advance Clock; if day boundary crossed → World.start_new_day().
```

Per-game-hour rates (`client_decay.tres`):

| Stat | Rate | Note |
|---|---|---|
| needs.energy | −0.003 | drains over ~14 game-days if untreated |
| needs.hunger | −0.005 | drains over ~8 days; will floor mid-arc — restorative intervention or auto-refill (M2) needed |
| needs.bladder | −0.004 | stub; M2 sim adds in-world toilet behavior |
| needs.social | −0.001 | Elling is introverted; slow decay |
| needs.security | −0.002 | erodes from disruption (here: passive baseline) |
| cognitive.attention | +0.02 | passive regen (rest) |
| cognitive.willpower | −0.003 | passive decay (existing in the world is slowly tiring); restored only by `int_quiet_walk` and similar |

These are stubs — they let the prototype run without the real M2 sim (which adds autonomous eating/sleeping/bathroom). Expect needs to drift downward across the 10-day arc; restorative interventions counter this. Tune during V2/V3 playtest.

### Passive observation roll

Every 6 game-hours, `Sim` calls `World.try_surface_observation()`:

1. Get candidate list from `Catalog.observation_candidates(client, case_file)`.
2. Subtract entries already in case file.
3. If non-empty: pick random one, `case_file.add_entry(entry)`, emit `case_file_updated`.

Idle time becomes informative — even doing nothing teaches the player.

### Action resolution (instant, gated)

```
World.try_run_diagnostic(id):
  d := Catalog.diagnostics[id]
  if not case_file.has_all_tags(d.gate_tags):    fail("locked"); return
  if not economy.can_spend(d.caseworker_cost):   fail("no_capacity"); return
  if client.overskudd < d.overskudd_cost:        fail("client_refuses"); return
  economy.spend(d.caseworker_cost)
  client.overskudd = max(0.0, client.overskudd - d.overskudd_cost)
  for entry in d.yields: case_file.add_entry(entry)
  EventBus.diagnostic_completed.emit(id)
  EventBus.caseworker_capacity_changed.emit(economy.capacity_current, economy.capacity_max)
  EventBus.overskudd_changed.emit(client.id, client.overskudd)
  for entry in d.yields: EventBus.case_file_updated.emit(entry.id)
```

`World.try_assign_intervention(id)` same shape; replaces yields step with:

```
  for k: StringName in i.needs_effects:
      client.needs[k] = clamp(client.needs[k] + i.needs_effects[k], 0.0, 1.0)
  for k: StringName in i.skill_effects:
      client.skills[k] = client.skills.get(k, 0) + i.skill_effects[k]
  EventBus.intervention_completed.emit(id)
```

`fail(reason)` → `EventBus.action_failed.emit(reason)`. UI surfaces it as an `ActionLog` entry prefixed with `⚠` (no separate toast component).

### Boot sequence (`main.gd._ready()`)

```gdscript
# 1. Construct runtime state (in autoload World; main calls into it):
World.client = ClientState.new()
var init_data: Resource = load("res://features/client/elling_init.tres")
World.client.apply_init_data(init_data)        # method on ClientState; copies fields
World.economy = EconomyState.new()
World.case_file = CaseFile.new()

# 2. Catalog loads at autoload _ready() — already populated by now.

# 3. Open scene shows MainUI.

# 4. Clock.start() begins ticking (Sim listens to its `tick` signal or polls via _process).
EventBus.day_started.emit(1)
```

`elling_init.tres` is a separate Resource (e.g. `ClientInitData`) with the starting values. `ClientState.apply_init_data()` copies fields onto the runtime RefCounted (mutation of `.tres` files at runtime is forbidden — godot-master rule).

### Controls

| Key | Action |
|---|---|
| Space | Toggle pause |
| 1 / 2 / 3 | Set time scale 1× / 2× / 4× |
| ~ | Toggle DebugPanel (hidden state inspector) |

## 8. UI (text-mode debug)

Single scene `features/ui/main_ui.tscn`. F6-testable. Three-column layout in a `MarginContainer`:

```
┌─ Left (35%) ──────────────┬─ Middle (40%) ─────────┬─ Right (25%) ──────────┐
│  Header (Day 3 14:30 ▶1×) │  Case File             │  Diagnostics           │
│  Overskudd bar            │   📓 Observation       │   [Psych Eval] 2.5h 15⚡│
│  Capacity label           │   🔍 Diagnostic        │   [Soc Worker] 1.0h 10⚡│
│  Action log (8 lines)     │   …                    │   [Locked: ?]          │
│                           │   (scrollable)         │  ―――                   │
│                           │                        │  Interventions         │
│                           │                        │   [Reading]    0.5h 5⚡ │
│                           │                        │   [Walk]      1.0h 10⚡ │
│                           │                        │   [Locked: ?]          │
└───────────────────────────┴────────────────────────┴────────────────────────┘
```

### Button states

| State | Visual | Click |
|---|---|---|
| Available + affordable | filled, hover-bright | resolves action |
| Available + capacity short | dim, "0.5h short" | grayed; tooltip |
| Available + overskudd short | dim, "Elling refuses" | grayed; tooltip |
| Gated (locked) | "Locked: ?" + hint tag | non-clickable |

Locked hint tag = one of the missing `gate_tags` (e.g. "Needs: trauma observed"). Tells player what to discover without spoiling — Outer Wilds-style.

### Component scripts (all under `features/ui/`)

- `main_ui.gd` — instantiates panels, subscribes to EventBus, repaints on signal
- `overskudd_bar.gd` — `ProgressBar` + label; listens `overskudd_changed`
- `capacity_label.gd` — listens `caseworker_capacity_changed` + `day_started`
- `case_file_panel.gd` — listens `case_file_updated`; appends `CaseEntryRow`s
- `action_list.gd` — listens `case_file_updated` (gates may unlock) + `caseworker_capacity_changed` + `overskudd_changed`; rebuilds button list from `Catalog.available_*(case_file)`; calls `World.try_*` on click

### Signal-to-listener map

| EventBus signal | Listeners |
|---|---|
| `day_started(n)` | Header, CapacityLabel, ActionLog |
| `day_ended(n)` | ActionLog |
| `overskudd_changed(client_id, v)` | OverskuddBar, ActionList (re-eval afford) |
| `caseworker_capacity_changed(current, max)` | CapacityLabel, ActionList |
| `case_file_updated(entry_id)` | CaseFilePanel (append), ActionList (re-eval gates), ActionLog |
| `diagnostic_completed(id)` | ActionLog |
| `intervention_completed(id)` | ActionLog |
| `action_failed(reason)` | ActionLog |

Styling: default Godot theme, monospace font (DejaVu Sans Mono), dark grey background, off-white text. No art. Throwaway.

## 9. Seed content

### Elling starting state

```
needs:     energy 0.9   hunger 0.9   bladder 0.9   social 0.5   security 0.7
cognitive: attention 0.8   willpower 0.5
overskudd: 71 (stored; ceiling at boot = 100·√(0.78·0.65) ≈ 71.2)
skills:    reading 5   phone 0   eye_contact 0   cooking 0   going_outside 0
mtg_primary:   blue    (hidden)
mtg_secondary: green   (hidden)
```

### Diagnostics (3)

| id | label | cost | gate | key yield tags |
|---|---|---|---|---|
| `diag_psych_eval` | Psych Eval | 2.5h · 15⚡ | (none) | `mtg:blue`, `mtg:green`, `cognitive:high_attention_low_willpower` |
| `diag_social_worker` | Social Worker Visit | 1.0h · 10⚡ | (none) | `trauma:strangers`, `dependency:mother` |
| `diag_aptitude` | Aptitude Test | 2.0h · 25⚡ | `mtg:blue` | `affinity:reading`, `affinity:order`, `flow:solo_focused` |

### Interventions (5)

| id | label | cost | gate | effects |
|---|---|---|---|---|
| `int_reading_together` | Reading Together | 0.5h · 5⚡ | (none) | social +0.10, willpower +0.05 |
| `int_quiet_walk` | Quiet Walk | 1.0h · 10⚡ | `mtg:green` | energy +0.20, willpower +0.10 |
| `int_eye_contact` | Eye Contact Practice | 0.5h · 15⚡ | `trauma:strangers` | skill `eye_contact` +1, willpower −0.05 |
| `int_phone_practice` | Phone Call Practice | 1.0h · 25⚡ | `skill_gap:phone` + `trauma:strangers` | skill `phone` +1, security −0.10 |
| `int_cooking_basics` | Cooking Basics | 1.5h · 20⚡ | `dependency:mother` + `flow:solo_focused` | skill `cooking` +1, security +0.05 |

### Observations (15 passive pool)

Pool depletion is intentional. With ~4 rolls/day at the 6-hour cadence, the unconditional pool drains by ~day 3. After that, growth requires either spending caseworker hours on diagnostics or letting state drift to unlock conditional observations.

Unconditional pool (11):

- `obs_reading_corner` — "Elling reads in the corner for hours." → `[affinity:reading, mtg:blue]`
- `obs_avoids_window` — "Elling avoids the window when the postman passes." → `[trauma:strangers]`
- `obs_phone_unanswered` — "The phone rings; Elling stares at it until it stops." → `[skill_gap:phone, trauma:strangers]`
- `obs_mother_cooks` — "Mother makes every meal. Elling doesn't enter the kitchen." → `[dependency:mother, skill_gap:cooking]`
- `obs_alphabetizes` — "Elling reorders the bookshelf alphabetically. Again." → `[mtg:blue, affinity:order]`
- `obs_door_hesitation` — "Elling reaches for the front door, then turns back." → `[trauma:strangers, skill_gap:going_outside]`
- `obs_waters_plants` — "Elling waters Mother's plants without being asked." → `[affinity:nature, mtg:green]`
- `obs_dishes_correct` — "Elling stacks the drying dishes by diameter, then re-stacks them." → `[mtg:blue, affinity:order]`
- `obs_radio_news` — "Elling listens to the radio news with full attention, then quickly turns it off." → `[mtg:blue, trauma:strangers]`
- `obs_morning_routine` — "Same breakfast, same chair, same window-side angle every morning." → `[mtg:green, affinity:routine]`
- `obs_mother_laundry` — "Mother irons Elling's shirts. He has not touched the iron." → `[dependency:mother, skill_gap:self_care]`

Conditional pool (4):

- `obs_tired` (require_state: `{&"needs_energy_lt": 0.3}`) — "Elling looks pale. He hasn't been sleeping." → `[need:energy_low]`
- `obs_chair` (require_state: `{&"cognitive_willpower_lt": 0.3}`) — "Elling won't get up. Just sits." → `[need:willpower_low]`
- `obs_smile` (require_state: `{&"needs_social_ge": 0.7}`) — "Brief, almost reflexive — Elling smiled at greeting." → `[trust:warming]`
- `obs_brittle` (require_state: `{&"needs_security_lt": 0.3}`) — "Elling flinches when the door clicks closed." → `[need:security_low, trauma:strangers]`

### Illustrative discovery arc

- **Day 1.** Empty case file. Only `int_reading_together` gate-clear. Player runs a diagnostic. Passive observations start appearing.
- **Day 2–3.** First MTG tags. `int_quiet_walk` unlocks after `mtg:green` enters case file. `int_eye_contact` unlocks after `trauma:strangers`.
- **Day 4–6.** `obs_phone_unanswered` + diagnostic results unlock `int_phone_practice`. Player must bank overskudd on prior light days.
- **Day 7–10.** `diag_aptitude` (gated on `mtg:blue`) yields `flow:solo_focused` → `int_cooking_basics` unlocks. End-of-day-10 summary.

## 10. Out of scope (deferred)

- Activities, furniture, in-world sim (the `_process` decay/regen here is a stub for M2's real sim)
- MTG-driven autonomous behavior
- Skill tree gating of activities; mastery system
- Mother character; multi-client cohort
- HD-2D visuals, sprites, audio
- Save/load
- Resource production (creativity/trust/knowledge/wealth abstracts → quests)
- Group programs (1:many)
- Tutorial / onboarding
  
(Money, political capital, and numeric trust are also out of scope — listed in §2.)

## 11. Validation criteria

The prototype validates the hypothesis if all five hold by end-of-day-10:

1. **V1 — Gate unlocked through play.** At least one intervention starts locked and becomes available via case-file growth.
2. **V2 — Scarcity bites.** Player runs out of caseworker capacity at least once by day 3.
3. **V3 — Client refusal happens.** Overskudd drops low enough that at least one action is refused.
4. **V4 — Discovery feels earned.** Player can describe Elling in 2–3 sentences without consulting hidden state.
5. **V5 — Decision tradeoff exists.** Player identifies at least one "deep diagnostic now vs cheap intervention now" call they had to make.

H1 (willpower decay) and H2 (capacity tuning) numeric values above are first guesses; expect to retune during V2/V3 playtest.

Subjective: caring for Elling felt like state-care work, not number-pushing.

## 12. Integration path back to M2 (future)

When M2's real sim is ready:

- Replace `Sim._process` decay/regen with calls into M2's sim API.
- Replace stub `ClientState` with M2's full client model (or wrap it).
- `Catalog`, `World`, `CaseFile`, `EventBus`, UI remain unchanged.

Economy layer is engineered to be sim-agnostic. The only contract is "client exposes `overskudd: float` and a way to apply `needs_effects` / `skill_effects`".

---

**Open questions deferred to implementation plan:**

- `.gitignore` template (Godot 4.5 default + project specifics)
- Whether to seed `tests/` with one smoke test now or later
- Whether to commit `icon.svg` from Godot's default or supply custom
