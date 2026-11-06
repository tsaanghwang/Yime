import json
import subprocess
import sys
from pathlib import Path

root = Path('C:/dev/Yime')
build = root / '.generated/pr101-main-20261106'
evidence = Path(__file__).parent / 'pr101-main-verification'
evidence.mkdir(exist_ok=True)
commands = {
    'configure': ['cmake', '-S', str(root / 'YimeTextServiceExperiment'), '-B', str(build),
                  '-G', 'Visual Studio 17 2022', '-A', 'x64',
                  '-DYIME_TOUCH_PRODUCT=ON', '-DYIME_TOUCH_FRONTEND=ON'],
    'build': ['cmake', '--build', str(build), '--config', 'Release', '--target',
              'YimeTextService18u', 'YimeTextServiceExperiment', 'YimeTouchFrontendEditTests', '--parallel', '4'],
    'test': ['ctest', '--test-dir', str(build), '-C', 'Release', '-R',
             '^YimeTouchFrontendEditTests$', '--output-on-failure', '-V'],
}
stage = sys.argv[1]
if stage == 'configure':
    assert not build.exists(), 'Fresh build directory required'
command = commands[stage]
result = subprocess.run(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(evidence / (stage + '.log')).write_bytes(result.stdout)
(evidence / (stage + '.json')).write_text(json.dumps({
    'command': command, 'cwd': str(root), 'exit_code': result.returncode,
}, indent=2), encoding='utf-8')
print(result.stdout.decode('utf-8', errors='replace'))
print('Log:', evidence / (stage + '.log'))
sys.exit(result.returncode)
