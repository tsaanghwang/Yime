import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

RUNNER = Path(__file__).with_name('run_checked.py')


class CheckedPowerShellTests(unittest.TestCase):
    def test_preflight_and_execution_in_each_edition(self):
        for edition in ('ps5', 'ps7'):
            with self.subTest(edition=edition), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                script = root / 'with spaces.ps1'
                marker = root / 'executed.txt'
                script.write_text("param([Parameter(Mandatory)][string]$OutputPath)\n"
                                  "[IO.File]::WriteAllText($OutputPath, 'executed')\n", encoding='utf-8')

                def run(*args):
                    return subprocess.run([sys.executable, str(RUNNER), '--edition', edition, *args],
                                          capture_output=True, text=True)

                missing = run('--script', str(script))
                self.assertEqual(missing.returncode, 2, missing.stderr)
                self.assertIn('Missing mandatory parameter', missing.stderr)
                self.assertFalse(marker.exists())
                params = json.dumps({'OutputPath': str(marker)})
                checked = run('--script', str(script), '--params', params, '--check-only')
                self.assertEqual(checked.returncode, 0, checked.stderr)
                self.assertFalse(marker.exists())
                unknown = run('--script', str(script), '--params', json.dumps({'OutputPath': str(marker), 'Typo': 1}))
                self.assertEqual(unknown.returncode, 2, unknown.stderr)
                self.assertFalse(marker.exists())
                parameter_file = root / 'parameters.json'
                parameter_file.write_text(params, encoding='utf-8-sig')
                actual = run('--script', str(script), '--params-file', str(parameter_file))
                self.assertEqual(actual.returncode, 0, actual.stderr)
                self.assertEqual(marker.read_text(), 'executed')
                invalid = run('--command', 'if (')
                self.assertEqual(invalid.returncode, 2, invalid.stderr)
                missing_file = run('--script', str(root / 'missing.ps1'))
                self.assertEqual(missing_file.returncode, 2, missing_file.stderr)
                failure = run('--command', 'exit 7')
                self.assertEqual(failure.returncode, 7, failure.stderr)
                quoted = run('--command', "Write-Output 'literal $variable ` value'")
                self.assertEqual(quoted.returncode, 0, quoted.stderr)
                self.assertIn('literal $variable ` value', quoted.stdout)


if __name__ == '__main__':
    unittest.main()
