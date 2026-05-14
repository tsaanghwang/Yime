"""Thin wrapper for the archived legacy-compatible mapping consolidation script."""

try:
    from yime.legacy.consolidate_mappings import main
except ImportError:
    from legacy.consolidate_mappings import main


if __name__ == "__main__":
    main()
