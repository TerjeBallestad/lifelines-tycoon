#!/usr/bin/env bash
# Pre-commit guard: reject staged content containing TODO/FIXME/stub/empty-body
# placeholders — half-finished implementations are forbidden (spec §6.3).
#
# Scans only the *added/modified hunks* via `git diff --cached -U0`, not whole files,
# so legitimate unchanged code is never touched.
#
# Exit codes:
#   0 — clean
#   1 — at least one forbidden pattern found; report on stderr

set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "check_no_placeholders: not inside a git work tree" >&2
    exit 2
fi

# Pull staged hunks. `-U0` minimizes surrounding context.
diff=$(git diff --cached -U0)
if [ -z "$diff" ]; then
    exit 0
fi

# Iterate added lines (those starting with '+', but not the '+++' file header).
added=$(printf '%s\n' "$diff" | awk '/^\+\+\+ /{next} /^\+/{print substr($0,2)}')

if [ -z "$added" ]; then
    exit 0
fi

violations=""

# Forbidden literal tokens (case-sensitive).
while IFS= read -r line; do
    case "$line" in
        *TODO*|*FIXME*|*XXX*|*HACK*)
            violations+=$'\n'"  placeholder token: $line"
            ;;
    esac
done <<< "$added"

# Word 'stub' anywhere, case-insensitive.
if printf '%s\n' "$added" | grep -iqE '(^|[^a-zA-Z_])stub([^a-zA-Z_]|$)'; then
    matched=$(printf '%s\n' "$added" | grep -iE '(^|[^a-zA-Z_])stub([^a-zA-Z_]|$)')
    violations+=$'\n'"  'stub' token found in:"$'\n'"$(printf '    %s\n' "$matched")"
fi

# Python raise NotImplementedError (anywhere in added lines).
if printf '%s\n' "$added" | grep -qE 'raise[[:space:]]+NotImplementedError'; then
    violations+=$'\n'"  Python raise NotImplementedError in added lines"
fi

# Python function with pass-only body OR ellipsis-only body.
# We scan the cached file contents of every staged .py file for `def foo(...):\n    (pass|...)` immediately followed by end-of-file or another def/blank.
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in *.py)
        body=$(git show ":$f" 2>/dev/null || true)
        if [ -z "$body" ]; then continue; fi
        if printf '%s\n' "$body" | python3 -c '
import sys, re
src = sys.stdin.read()
# def ...():\n<indent>(pass|...)\n  followed by newline-or-EOF
if re.search(r"^def\s+\w+\s*\([^)]*\)[^:]*:\s*\n(?:\s*[\"\x27].*[\"\x27]\s*\n)?(\s+)(?:pass|\.\.\.)\s*$", src, re.MULTILINE):
    sys.exit(0)
sys.exit(1)
'; then
            violations+=$'\n'"  python placeholder body in $f"
        fi
    ;; esac
done < <(git diff --cached --name-only)

# GDScript function with pass-only body. `func foo() -> X:\n\tpass\n` (and no body lines beyond it).
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in *.gd)
        body=$(git show ":$f" 2>/dev/null || true)
        if [ -z "$body" ]; then continue; fi
        if printf '%s\n' "$body" | python3 -c '
import sys, re
src = sys.stdin.read()
if re.search(r"^func\s+\w+\s*\([^)]*\)[^:]*:\s*\n(?:\s*#[^\n]*\n)?\s+pass\s*$", src, re.MULTILINE):
    sys.exit(0)
sys.exit(1)
'; then
            violations+=$'\n'"  gdscript pass-only body in $f"
        fi
    ;; esac
done < <(git diff --cached --name-only)

if [ -n "$violations" ]; then
    echo "check_no_placeholders: forbidden patterns in staged content:" >&2
    printf '%s\n' "$violations" >&2
    exit 1
fi

exit 0
