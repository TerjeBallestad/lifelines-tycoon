---
axis: earned-discovery
polarity: positive
sub_criteria_targeted: [1, 3]
source: tycoon-design-md-sections-6-9
score_if_anchor: 3
canonical_score: 3
---

# Tycoon prototype — MTG colors masked, surfaced only by diagnostic

## Anchor

From `docs/tycoon-design.md` §6 (Client model):

> Each citizen has hidden `mtg_primary` and `mtg_secondary` fields. These fields are NEVER returned in `bridge.snapshot()` unless the harness is launched with `--reveal-hidden`. They are observable only through diagnostic results that surface a `mtg:<color>` tag.

The shipped enforcement lives in `autoload/agent_bridge.gd` and is verified by `test/harness/unit/test_bridge_snapshot.gd` — calling snapshot without the flag returns no `mtg_*` keys.

A model in-game diagnostic-completion log line (from §9 illustrative arc):

> **Psych Eval — Outcome: Elling complies.**
> Case file +1: "Elling sits where you ask, then composes each sentence before delivering it. Volunteered no detail not directly asked for." → tags `[mtg:blue, comm:reserved]`.

The player never sees "MTG: Blue." They see the *behaviour* that the model interprets as blue.

## Why this scores high on earned-discovery

Hidden state is structurally hidden — at the bridge level, not behind a hover panel. The diagnostic does not reveal the tag; it reveals the *behaviour*, with the tag attached as an analytic shorthand. Sub-criterion 1 (hidden state not shown directly) hits because the bridge enforcement means even a probing harness cannot accidentally surface the colour. Sub-criterion 3 (diagnostics yield revelation) hits because the diagnostic delivers a *sentence*, not a number; the player must read.

## Specific sub-criteria signal

- Sub-criterion 1 (Hidden state isn't shown directly): 3 — `--reveal-hidden` gate is enforced at the bridge layer; structurally impossible to leak.
- Sub-criterion 3 (Diagnostics yield revelation, not data): 3 — the case-file entry is a *behaviour-sentence*, not a stat. The tag is a margin note, not the headline.
