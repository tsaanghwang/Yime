"""Exercise the real data bootstrap with a non-maintaining controller fixture."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RequestTests(unittest.TestCase):
    def test_long_values_and_fail_closed(self):
        with tempfile.TemporaryDirectory(prefix='yime-request-') as tmp:
            p = Path(tmp)
            bootstrap = p / 'invoke-rime-pime-candidate-request.ps1'
            bootstrap.write_bytes((ROOT / 'tools/dual-product' / bootstrap.name).read_bytes())
            controller = p / 'invoke-rime-pime-candidate.ps1'
            controller.write_text('''param($Mode,$InstallerPath,$AuthorizationPath,$TrustedApprovalSha256,$BoundaryPath,$ReceiptPath,$PreparedSha256,$ExpectedManifestSha256,$PackageRoot)
$PSBoundParameters | ConvertTo-Json -Compress
exit 0
''', encoding='utf-8')
            long_path = 'C:\\' + ('long path & literal apostrophe\'\\' * 8) + 'file.json'
            fields = ['Resume', long_path, long_path, 'a' * 64, long_path, long_path, 'b' * 64, 'c' * 64]
            request = p / 'request.txt'
            params = p / 'parameters.json'
            params.write_text(json.dumps({'RequestPath': str(request)}), encoding='utf-8')

            def run(values):
                request.write_bytes(('\r\n'.join(values) + '\r\n').encode('utf-16-le'))
                return subprocess.run([sys.executable, str(ROOT / 'tools/powershell/run_checked.py'),
                    '--script', str(bootstrap), '--edition', 'ps5', '--params-file', str(params)],
                    cwd=ROOT, capture_output=True, text=True)

            result = run(fields)
            self.assertEqual(result.returncode, 0, result.stderr)
            actual = json.loads(result.stdout)
            self.assertEqual(actual['PreparedSha256'], 'b' * 64)
            self.assertEqual(actual['AuthorizationPath'], long_path)
            self.assertEqual(actual['ReceiptPath'], long_path)
            initial = fields.copy(); initial[0] = 'Install'; initial[6] = ''
            self.assertEqual(run(initial).returncode, 0)
            malformed = fields.copy(); malformed[6] = 'b' * 20
            self.assertNotEqual(run(malformed).returncode, 0)
            self.assertNotEqual(run(fields + ['extra']).returncode, 0)
            malformed = fields.copy(); malformed[2] += '\nextra'
            self.assertNotEqual(run(malformed).returncode, 0)
            controller.write_text(controller.read_text().replace('exit 0', 'exit 51'), encoding='utf-8')
            failed = run(fields)
            # run_checked's outer script maps a failed script invocation to 1.
            self.assertNotEqual(failed.returncode, 0, failed.stdout + failed.stderr)

    def test_actual_nsis_argument_file(self):
        compiler = Path('C:/Program Files (x86)/NSIS/makensis.exe')
        if not compiler.exists():
            self.skipTest('NSIS compiler unavailable')
        source = (ROOT / 'installer/rime-pime-candidate.nsi').read_text(encoding='utf-8-sig')
        start = source.index('  FileOpen $0')
        end = source.index('  FileClose $0', start) + len('  FileClose $0')
        with tempfile.TemporaryDirectory(prefix='yime-nsis-request-') as tmp:
            p = Path(tmp)
            values = {'Mode': 'Resume', 'EXEPATH': 'C:\\'+'x'*220+'.exe',
                      'Authorization': 'C:\\'+'a'*220+'.json', 'Approval':'a'*64,
                      'Boundary': 'C:\\'+'d'*220+'.json', 'Receipt':'C:\\'+'r'*220+'.json',
                      'Prepared':'b'*64}
            block = source[start:end].replace('$PLUGINSDIR', str(p)).replace('$EXEPATH', '$SyntheticExe')
            block = block.replace('${CANDIDATE_MANIFEST_SHA256}', 'c'*64)
            declarations = '\n'.join('Var '+('SyntheticExe' if k=='EXEPATH' else k) for k in values)
            assignments = '\n'.join('StrCpy $'+('SyntheticExe' if k=='EXEPATH' else k)+' "'+v+'"' for k,v in values.items())
            nsi = p / 'test.nsi'
            nsi.write_text('Unicode true\nRequestExecutionLevel user\nSilentInstall silent\nAutoCloseWindow true\nOutFile "'+str(p/'test.exe')+'"\n'+declarations+'\nSection\n'+assignments+'\n'+block+'\nSectionEnd\n',encoding='utf-8')
            subprocess.run([str(compiler), '/V2', str(nsi)],check=True,capture_output=True)
            subprocess.run([str(p/'test.exe')],check=True)
            actual=(p/'candidate-request.txt').read_bytes().decode('utf-16-le')
            self.assertEqual(actual,'\r\n'.join(list(values.values())+['c'*64])+'\r\n')


if __name__ == '__main__':
    unittest.main()
