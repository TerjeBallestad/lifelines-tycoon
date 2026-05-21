#!/usr/bin/env python3
"""Tests for harness/lib/contract_lock.py."""
from __future__ import annotations
import os
import sys
import tempfile
import time
import unittest
from multiprocessing import Process, Queue
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
from contract_lock import (  # noqa: E402
    contract_lock,
    LockTimeoutError,
    LockPathError,
)


def _hold_lock(path: str, hold_seconds: float, q: Queue) -> None:
    try:
        with contract_lock(path, timeout=1.0):
            q.put("acquired")
            time.sleep(hold_seconds)
        q.put("released")
    except Exception as e:
        q.put(f"error:{type(e).__name__}")


class TestContractLock(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.mkdtemp()
        self.lock_path = os.path.join(self.tmpdir, "x.lock")

    def test_acquires_and_releases(self) -> None:
        with contract_lock(self.lock_path, timeout=0.5):
            self.assertTrue(os.path.exists(self.lock_path))

    def test_creates_parent_dir_if_missing(self) -> None:
        deep = os.path.join(self.tmpdir, "a", "b", "c", "x.lock")
        with contract_lock(deep, timeout=0.5):
            self.assertTrue(os.path.exists(deep))

    def test_concurrent_acquire_blocks_then_succeeds(self) -> None:
        q: Queue = Queue()
        # Hold the lock briefly in a child process.
        p = Process(target=_hold_lock, args=(self.lock_path, 0.3, q))
        p.start()
        # Wait for child to acquire.
        self.assertEqual(q.get(timeout=2.0), "acquired")
        # Now try to acquire from the parent — should block until child releases.
        t0 = time.monotonic()
        with contract_lock(self.lock_path, timeout=2.0):
            dt = time.monotonic() - t0
        # Should have waited roughly hold_seconds.
        self.assertGreater(dt, 0.2)
        p.join()
        self.assertEqual(q.get(timeout=1.0), "released")

    def test_timeout_raises(self) -> None:
        q: Queue = Queue()
        p = Process(target=_hold_lock, args=(self.lock_path, 2.0, q))
        p.start()
        self.assertEqual(q.get(timeout=2.0), "acquired")
        try:
            with self.assertRaises(LockTimeoutError):
                with contract_lock(self.lock_path, timeout=0.2):
                    pass
        finally:
            p.join()

    def test_empty_path_rejected(self) -> None:
        with self.assertRaises(LockPathError):
            with contract_lock("", timeout=0.1):
                pass


if __name__ == "__main__":
    unittest.main()
