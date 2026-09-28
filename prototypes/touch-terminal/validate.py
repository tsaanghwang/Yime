"""Repeatable offline checks. Validated with repository Python 3.14 and Node 24."""
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
node = shutil.which('node')
if not node:
    raise SystemExit('Node.js 20+ is required for the pure JavaScript checks.')
commands = [
    [sys.executable, '-X', 'utf8', 'kle_layout.py', 'design/touch-terminal-60.kle.json'],
    [sys.executable, '-X', 'utf8', 'generate_data.py', '--check'],
    [sys.executable, '-X', 'utf8', '-m', 'unittest', 'discover', '-s', '.', '-p', 'test_*.py', '-v'],
    [node, '--test', 'core.test.mjs', 'geometry.test.mjs'],
    [node, '--check', 'app.mjs'],
    [node, '--check', 'browser-smoke.js'],
]
for command in commands:
    print('RUN ' + ' '.join(command), flush=True)
    subprocess.run(command, cwd=HERE, check=True)
print('PASS: KLE template, source provenance, offline protocol, geometry and syntax. Physical touch/IME acceptance not run.')
