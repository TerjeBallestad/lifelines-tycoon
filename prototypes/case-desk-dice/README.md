# Case Desk Dice Prototype

Disposable HTML prototype for Lifelines Tycoon.

## What it tests

1. **Decision bind:** when the player has rolled dice, do they pause over which die to assign?
2. **Legibility:** after assigning a die, do they understand why the result happened?

## Resource model under test

- **Knowledge** unlocks the action pool by diagnosing problems.
- **Trust** sets the baseline reliability / relational permission for vulnerable actions.
- **Dice** are daily rolled state capacity. Each die has a face value and can be assigned once.

## How to open

```sh
open prototypes/case-desk-dice/index.html
```

## Deliberate limits

- No production Godot code.
- No multi-client allocation.
- No persistence.
- No visual polish beyond readability.
- Outcomes are deterministic bands so the causal chain is easy to inspect.

The point is not to prove the final UI. The point is to see whether a Case Desk can make “which die goes where?” feel like welfare-state attention, not currency shopping.
