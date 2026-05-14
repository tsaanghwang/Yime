"""Thin wrapper for the archived legacy-compatible import runner."""

try:
    from yime.legacy.run_full_import import run
except ImportError:
    from legacy.run_full_import import run


if __name__ == "__main__":
    run()
