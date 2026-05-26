# Sprint List

## User intent
- Make day-one decisions diverge across optimizer vs neglect.
- Keep the first harness run small enough to read.

## Sprint 1 — Day-one decision divergence

### Goal
Make two early intervention choices produce visibly different case-file and trace outcomes by day 3.

### User-intent coverage
- Make day-one decisions diverge across optimizer vs neglect.

### Touch surface
- features/economy/
- features/case_file/
- test/harness/

### Rubric focus
- decision-density: primary
- sim-legibility: touched
- loop-closure: touched

### Optional
false

## Sprint 2 — Report readability polish

### Goal
Improve the trace excerpts in the final report without changing game behavior.

### User-intent coverage
- Keep the first harness run small enough to read.

### Touch surface
- harness/lib/report_renderer.py
- harness/test/

### Rubric focus
- sim-legibility: primary

### Optional
true
