"""Validate and run PowerShell in one process; no model call or product probe."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--script', type=Path)
    source.add_argument('--command')
    parameters = parser.add_mutually_exclusive_group()
    parameters.add_argument('--params', default='{}', help='Named script parameters as a JSON object')
    parameters.add_argument('--params-file', type=Path, help='UTF-8 JSON parameter file; avoids shell quoting')
    parser.add_argument('--edition', choices=['ps5', 'ps7'], default='ps7')
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    try:
        params = json.loads(args.params_file.read_text(encoding='utf-8-sig') if args.params_file else args.params)
        if not isinstance(params, dict):
            raise ValueError('--params must be a JSON object')
        if args.command is not None and params:
            raise ValueError('--params applies only to --script')
        shell = (str(Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe')
                 if args.edition == 'ps5' else shutil.which('pwsh'))
        if not shell or not Path(shell).is_file():
            raise ValueError(f'{args.edition} executable unavailable; select an installed edition explicitly')
        request = {'script': str(args.script.resolve()) if args.script else None,
                   'command': args.command, 'parameters': params, 'check_only': args.check_only}
        # JSON travels through stdin, never through shell interpolation or an
        # encoded command. Output and exit code are preserved without retries.
        result = subprocess.run([shell, '-NoLogo', '-NoProfile', '-NonInteractive',
                                 '-ExecutionPolicy', 'Bypass', '-File',
                                 str(Path(__file__).with_name('preflight.ps1'))],
                                input=json.dumps(request, ensure_ascii=True), text=True)
        return result.returncode
    except (ValueError, OSError, KeyError) as error:
        print(f'PowerShell preflight: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
