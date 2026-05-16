"""Legacy shim for the old db_manager schema bootstrap.

The real compatibility implementation now lives alongside the rest of the
pending-removal database helpers in ``yime.legacy.pending_removal``.
"""

from yime.legacy.pending_removal.run_db_setup import main

__all__ = ["main"]


if __name__ == "__main__":
    raise SystemExit(main())
