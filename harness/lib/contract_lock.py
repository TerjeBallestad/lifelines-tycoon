"""flock-based advisory mutex around contract.md.

Use as a context manager:

    with contract_lock("/path/to/contract.lock", timeout=5.0):
        ... read/write contract.md ...

Releases automatically on exit (even on exception). Creates the lock file and any
missing parent directories. Subprocesses can share the same lock by opening the
same path under flock(LOCK_EX). The Bash side uses `flock` directly with -x -w N.
"""
from __future__ import annotations
import fcntl
import os
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


class LockTimeoutError(TimeoutError):
    """Raised if the lock could not be acquired within the timeout."""


class LockPathError(ValueError):
    """Raised if the lock path is empty or unusable."""


@contextmanager
def contract_lock(path: str, *, timeout: float = 5.0, poll_interval: float = 0.05) -> Iterator[int]:
    if not path:
        raise LockPathError("lock path must be non-empty")
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(p), os.O_CREAT | os.O_RDWR, 0o644)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise LockTimeoutError(f"could not acquire lock at {p} within {timeout}s")
                time.sleep(poll_interval)
        try:
            yield fd
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            except OSError:
                pass
    finally:
        os.close(fd)
