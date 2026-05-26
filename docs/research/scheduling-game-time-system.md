# Scheduling Game Time System Notes

Source repo: `/Users/godstemning/dev/scheduling-game`

Purpose: compact cross-repo context for a Lifelines Tycoon harness test. Use this as inspiration, not as code to copy blindly.

## Design question

Can Lifelines Tycoon support a foreground **desk/economy/resource-arbitrage** loop while an apartment/patient simulation advances asynchronously in the background, so the player periodically returns to inspect changed state rather than babysitting the apartment?

## Scheduling-game implementation observed

### `core/time_keeping/datetime.gd`

- `DateTime` stores a raw `time: float` in real seconds.
- It derives game time through constants:
  - `seconds_second = 60 / game_time_factor`
  - `seconds_minute = seconds_second * 60`
  - `seconds_hour = seconds_minute * 60`
  - `seconds_day = seconds_hour * 24`
- Derived properties:
  - `game_minutes`, `game_hours`, `game_days`
  - `minute = fmod(game_minutes, 60)`
  - `hour = fmod(game_hours, 24)`
  - `day = fmod(game_days, 7)`
- Formatting helpers: `formatted`, `formatted_time`, `formatted_day`.
- Scheduling helpers:
  - `target_date(day, hour, minute)` mutates the timestamp forward to the target weekday/time, registers itself as an alarm with `TimeManager.add_alarm(self)`, and returns itself.
  - `countdown(seconds)` adds seconds, registers itself as an alarm, and returns itself.
  - `add_days`, `add_hours`, `add_minutes` mutate the timestamp.

### `core/time_keeping/time_manager.gd`

- Global-ish node with:
  - `time: float`
  - `datetime: DateTime`
  - `calendar: Calendar`
  - `alarms: Array[DateTime]`
- `_ready()` seeds time, creates `DateTime` and `Calendar`, and sets `Engine.time_scale = 1`.
- `_process(delta)` increments raw time by `delta`, updates `datetime`, emits `update_time` when the formatted time string changes, then checks alarms.
- Alarm check is simple:
  - if `alarm.time <= datetime.time`, emit `alarm.date_target_reached`, erase it, and `queue_free()` it.

### `core/time_keeping/calendar.gd`

- Builds `current_week` as 15-minute `DateTime` slots over `10080` minutes.
- Emits `slot_added(date)` as slots are created.

### `user_interface/calendar/calendar_container.gd`

- `schedule_activity(activity)` creates `DateTime.new().countdown(3)` and connects `date_target_reached` to `on_patient_try_activity(activity)`.
- When the alarm fires, active patient moves to the interactable activity.

## What is useful for Lifelines Tycoon

- A timestamp object as an explicit value, not just UI text.
- A scheduler/alarm queue that can trigger simulation consequences later.
- Calendar slots as a planning surface, not only an animation clock.
- A simple return-to-state loop: player schedules/chooses, time advances elsewhere, then consequences are visible later.

## What should not be copied directly

- `DateTime` extends `Node` and is mutated/registers itself with `TimeManager`; for Tycoon, prefer plain data objects or small services where possible.
- Alarm removal happens while iterating the `alarms` array; this can skip entries or behave oddly as complexity grows.
- `target_date` and `countdown` have side effects by registering alarms. For Tycoon, creating a timestamp and scheduling an event should probably be separate decisions.
- Time factor is duplicated/conflicting (`DateTime.game_time_factor = 60000`, `TimeManager.game_time_factor = 500`).
- The current system is frame-driven via `_process(delta)`. Tycoon may need deterministic `advance_background(minutes)` calls so desk gameplay can fast-forward sim state without relying on visible apartment frames.

## Candidate Lifelines Tycoon seam

A minimal background-sim seam could be:

```text
BackgroundClock
- now_minutes: int
- advance(minutes) -> list[SimEvent]

ScheduleQueue
- schedule_at(minute, event)
- due_between(start, end) -> list[event]

ApartmentSim
- snapshot() -> ApartmentSnapshot
- apply_event(event)
- tick(minutes) -> list[Consequence]

DeskLoop
- player makes economy/resource decisions
- each desk action advances BackgroundClock by N minutes
- returning to apartment shows a compact state delta report
```

## Harness test prompt intent

Use this repo as a test-case for Phase 6 harness quality. We want the harness to produce small, inspectable sprint(s) that answer:

> Can desk/economy play advance an apartment/patient sim in the background, and does returning to the apartment produce legible, interesting state changes rather than chores?

Smallest valuable prototype:

- one desk action advances background time,
- one scheduled apartment/patient event resolves while away,
- returning to apartment produces a concise changed-state report,
- no broad UI/dashboard work,
- no full port of scheduling-game.
