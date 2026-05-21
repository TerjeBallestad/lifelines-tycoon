# Anti-Rubric — Failure modes the evaluator must reject

These are cross-axis patterns. Any one of them appearing in a sprint is grounds for axis floor failure on the relevant axis, even if everything else looks polished.

## 1. Welfare-state cosplay

**Symptom:** state-care vocabulary wrapped around RPG mechanics. Buttons labeled "Dispatch" that mechanically behave like "buy an upgrade." A "case file" that's actually a stat sheet.

**Examples:**
- A "Tiltak" that gives +5 to a skill stat permanently. (RPG perk.)
- A "Caseworker hour" that recharges automatically with no day boundary. (Hidden currency.)
- A "Hjemmebesøk" cinematic that ends with "+10 trust." (Numerical buff.)

**Floors:** Axis 1, Axis 5.

## 2. Empathy theatre

**Symptom:** the game performs care at the player. Motivational copy. "You're doing great!" Sad-face icons. Animated heart explosions when something good happens.

**Examples:**
- "Elling smiled today! :)"
- "You helped Elling overcome his fear!"
- A trust meter that fills up with sparkles.

**Floors:** Axis 5.

## 3. Tooltip-dump exposition

**Symptom:** the citizen's hidden state is explained directly to the player by UI. Stat sheets. Hover-tooltips that reveal MTG colors or trauma history. A "character bio" panel.

**Examples:**
- Hovering Elling shows "MTG: Blue/Green, Introverted Perfectionist, Trauma: strangers."
- A starting briefing scene that lists Elling's needs and skills.
- A diagnostic that returns a numeric stat dump instead of a case-file entry.

**Floors:** Axis 3.

## 4. Numbers-go-up gameplay

**Symptom:** the play is to make a number larger. Optimization loop. Best strategy emerges by day 2 and dominates.

**Examples:**
- "Maximum overskudd" as a goal.
- A "100% completion" badge for the case file.
- A leaderboard.

**Floors:** Axis 2, Axis 4.

## 5. RPG-progression frame

**Symptom:** XP bars on the player or citizen. Skill trees. Talent draft screens. Level-up cinematics.

**Examples:**
- "Caseworker XP: 42 / 100."
- A skill tree where you pick Tiltak shape per node.
- "LEVEL UP! New Tiltak unlocked!"

**Floors:** Axis 1.

## 6. Click-everything-wins loop

**Symptom:** no opportunity cost. The player can run every diagnostic and every intervention without ever choosing. Capacity refills make every action free over time.

**Examples:**
- Daily capacity reset to 100 hours.
- All Tiltak free.
- A "skip to tomorrow" button that resets all costs.

**Floors:** Axis 2 (scarcity sub-criterion at 0), Axis 4.

## 7. Punish-the-mistake

**Symptom:** failures are framed as the player being wrong. Game-over screens. Permadeath. "You failed Elling" copy.

**Examples:**
- "Elling has given up. GAME OVER."
- A retry-from-day-1 prompt after refusal.
- "−10 trust permanently" with no recovery path.

**Floors:** Axis 4.

## 8. Tooltip-as-narrative

**Symptom:** narrative beats exist only in tooltips, achievement popups, or transitional screens. No texture in the moment-to-moment trace.

**Examples:**
- "Achievement unlocked: First Eye Contact."
- A loading screen that explains why this matters.
- Tooltip "Did you know? Norwegian welfare state…"

**Floors:** Axis 5, Axis 7.

## 9. Hidden-random shrug

**Symptom:** outcomes feel arbitrary. The player can't trace why something happened. Dice rolls or RNG buried with no surfaced explanation.

**Examples:**
- A Tiltak fails with no reason text.
- Two identical-looking states produce different outcomes with no explanation.
- "Bad luck this week!" as a status message.

**Floors:** Axis 6.

## 10. Locked forever

**Symptom:** late-game content gated on conditions that never trigger in normal play. Player ends arc without unlocking anything new. Loop never closes.

**Examples:**
- A Tiltak that requires 7 specific case-file entries that only appear in one rare branch.
- An end-of-arc summary that lists "0 of 12 milestones reached."
- Conditional observations that never fire because their require_state is impossible to enter.

**Floors:** Axis 7.

## Application

The evaluator, when scoring a sprint, must explicitly check for each of the 10 patterns above. If any pattern is detected, the relevant axis is floored regardless of other strengths. Cite the specific anti-pattern by number in the critique.
