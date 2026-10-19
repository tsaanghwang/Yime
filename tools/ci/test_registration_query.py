"""Build and run only the isolated registration-query regression on x64/Win32."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    for architecture in ('x64', 'Win32'):
        build = ROOT / '.tmp' / 'registration-query-ci' / architecture
        commands = [
            ['cmake', '-S', str(ROOT / 'YimeTextServiceExperiment'), '-B', str(build),
             '-G', 'Visual Studio 17 2022', '-A', architecture, '-DYIME_LOCAL_PRODUCT=ON'],
            ['cmake', '--build', str(build), '--config', 'Release',
             '--target', 'YimeRegistrationQueryTests'],
            ['ctest', '--test-dir', str(build), '-C', 'Release',
             '-R', '^YimeRegistrationQueryTests$', '--no-tests=error', '--output-on-failure'],
        ]
        for command in commands:
            print(f'[{architecture}] {subprocess.list2cmdline(command)}', flush=True)
            subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
