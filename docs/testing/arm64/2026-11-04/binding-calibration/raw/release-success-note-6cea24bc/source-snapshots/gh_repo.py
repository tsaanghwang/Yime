"""Use the repository's existing credential helper without persisting or printing credentials."""
import os
import subprocess
import sys

env = os.environ.copy()
env.update(GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never')
git = r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'
credential = subprocess.run([git, 'credential', 'fill'], input='protocol=https\nhost=github.com\npath=tsaanghwang/Yime.git\n\n',
                            text=True, capture_output=True, env=env)
fields = dict(line.split('=', 1) for line in credential.stdout.splitlines() if '=' in line)
if credential.returncode or not fields.get('password'):
    raise SystemExit('No existing repository credential available to the release tool.')
env['GH_TOKEN'] = fields['password']
gh = r'C:\dev\Yime\.generated\arm64-toolchain\gh-2.103.2\bin\gh.exe'
raise SystemExit(subprocess.run([gh, *sys.argv[1:]], env=env).returncode)
