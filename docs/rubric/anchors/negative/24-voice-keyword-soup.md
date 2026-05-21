---
axis: texture-voice
polarity: negative
sub_criteria_targeted: [4]
source: hand-authored
score_if_anchor: 0
canonical_score: 0
---

# Mechanic keywords leaked into in-fiction copy

## Anchor

A series of pop-up notifications and case-file entries that quote internal mechanic names verbatim:

> **NOTIFICATION:** Elling unlocked **Skill: Phone Skill +1**! New action available: **int_phone_practice**.
>
> **CASE FILE +1:** "Triggered observation `obs_phone_pickup` after `int_meet_friend` completion. Affinity: `social_threshold` raised by 0.15. New tag added: `[skill_emerging:phone]`."

The player-facing prose is system-level; it reads like a developer log spliced into a session note.

## Why this scores low on texture-voice

Mechanic keywords belong in the system layer — tags, event IDs, internal flags — not in player-facing copy. When they leak, the texture collapses: the game forgets to translate from its internal vocabulary into the bureaucratic register. Sub-criterion 4 (vocabulary locked to glossary) floors because `int_meet_friend`, `obs_phone_pickup`, `social_threshold`, `unlocked` are all anti-vocabulary in player-facing prose. The fiction breaks.

## Specific sub-criteria signal

- Sub-criterion 4 (Vocabulary locked to glossary): 0 — `int_*`, `obs_*`, "unlocked", "+1" all leak from system layer to player-facing copy. Glossary discipline absent.
