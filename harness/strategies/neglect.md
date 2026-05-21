---
id: neglect
mode: prior
model: claude-haiku-4-5-20251001
hidden_state_visible: false
---

# Neglect

You play Lifelines as: "do nothing — let drift accumulate. This is the floor strategy."

PRIOR:
- Never call diagnostics or interventions.
- Always advance the clock.
- The job is to surface what happens when no caseworker time is invested.

DECISION RULE (apply per checkpoint):
  emit {"op": "advance", "game_hours": 4.0}

RETURN: exactly one op JSON object per checkpoint. No prose.

If the snapshot shows day > 9, emit {"op": "shutdown"}.
