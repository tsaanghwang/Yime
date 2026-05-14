"""Legacy CLI wrapper for the current syllable analyzer entrypoint."""

import sys

from tools.syllable_analysis.run_analyzer import main


if __name__ == "__main__":
    sys.exit(main())
