"""Source-attribution build checks using fixtures/mocks, never product execution."""
import json
from contextlib import chdir
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from touch_keyboard_build_environment import build_environment
import build_touch_keyboard_desktop as frontend
import build_installed_18u_arm64 as arm64


class BuildEnvironmentTests(unittest.TestCase):
    @staticmethod
    def x64_workflow_build_step():
        # Execute the actual caller, so a helper existing but unused by CI cannot
        # satisfy this regression. Only its compiler subprocess is replaced.
        text = (ROOT / '.github/workflows/installed-18u-compile.yml').read_text(encoding='utf-8')
        marker = '      - name: Compile Go runtimes and dedicated Broker without execution\n        run: |\n'
        code = text.split(marker, 1)[1].split('      - name:', 1)[0]
        return compile(textwrap.dedent(code), 'installed-18u-compile.yml:x64-go-build', 'exec')

    def assert_environment(self, env, architecture):
        for name, value in dict(GOENV='off', GOFLAGS='', GOWORK='off',
                                GOTOOLCHAIN='local', GOOS='windows',
                                GOARCH=architecture, CGO_ENABLED='0').items():
            self.assertEqual(env[name], value, name)

    def test_inherited_flags_refused_without_changing_parent_environment(self):
        for architecture in ('amd64', 'arm64'):
            for flags in ('-overlay=foreign.json', '-toolexec=foreign.exe', '-tags=foreign'):
                inherited = dict(GOFLAGS=flags, GOENV='foreign.env', GOWORK='foreign.work')
                before = dict(inherited)
                with self.subTest(architecture=architecture, flags=flags):
                    with self.assertRaisesRegex(ValueError, 'empty inherited GOFLAGS'):
                        build_environment(architecture, inherited)
                    self.assertEqual(inherited, before)

    def test_persisted_flags_and_workspaces_disabled_for_both_targets(self):
        with tempfile.TemporaryDirectory() as tmp:
            persisted = Path(tmp) / 'go.env'
            persisted.write_text('GOFLAGS=-overlay=foreign.json\nGOTOOLCHAIN=auto\n')
            inherited = dict(GOENV=str(persisted), GOWORK='foreign.work', PATH='kept')
            for architecture in ('amd64', 'arm64'):
                with self.subTest(architecture=architecture):
                    env = build_environment(architecture, inherited)
                    self.assert_environment(env, architecture)
                    self.assertEqual(env['PATH'], 'kept')
                    self.assertEqual(inherited['GOENV'], str(persisted))
                    self.assertEqual(persisted.read_text(), 'GOFLAGS=-overlay=foreign.json\nGOTOOLCHAIN=auto\n')

    def test_frontend_rejects_overlay_before_output_or_subprocess(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, GOFLAGS='-overlay=foreign.json'), \
                patch.object(frontend, 'generated') as generated, \
                patch.object(frontend, 'verify') as verify, \
                patch.object(frontend.subprocess, 'run') as run, \
                patch.object(frontend.subprocess, 'check_output') as read:
            output = Path(tmp) / 'output'
            for architecture in ('amd64', 'arm64'):
                with self.subTest(architecture=architecture), self.assertRaisesRegex(ValueError, 'GOFLAGS'):
                    frontend.build(output, architecture, Path(tmp) / 'data', installed_tsf=True)
            self.assertFalse(output.exists())
            generated.assert_not_called()
            verify.assert_not_called()
            run.assert_not_called()
            read.assert_not_called()

    def test_frontend_build_and_version_use_same_clean_environment(self):
        for architecture in ('amd64', 'arm64'):
            with self.subTest(architecture=architecture), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                output = root / 'output'
                lock = root / 'resources.lock.json'
                lock.write_text(json.dumps({'archiveSHA256': 'fixture'}))
                calls = []

                def run(command, **kwargs):
                    self.assertEqual(command[:2], ['go', 'build'])
                    self.assert_environment(kwargs['env'], architecture)
                    calls.append(('build', kwargs['env']))
                    (output / 'YimeTouchKeyboard.exe').write_bytes(b'synthetic file; never executed')
                    return subprocess.CompletedProcess(command, 0)

                def read(command, **kwargs):
                    if command == ['go', 'version']:
                        self.assert_environment(kwargs['env'], architecture)
                        calls.append(('version', kwargs['env']))
                        return 'go version fixture'
                    return 'b' * 40 if command[-2:] == ['rev-parse', 'HEAD'] else ''

                with patch.dict(os.environ, {'GOFLAGS': '', 'GOENV': str(root / 'persisted-go.env'),
                                             'GOWORK': str(root / 'foreign.work'), 'GITHUB_ACTIONS': 'false'}), \
                        patch.object(frontend, 'ROOT', root), patch.object(frontend, 'LOCK', lock), \
                        patch.object(frontend, 'generated', side_effect=lambda path: path), \
                        patch.object(frontend, 'verify'), patch.object(frontend, 'stage_resources'), \
                        patch.object(frontend.subprocess, 'run', side_effect=run), \
                        patch.object(frontend.subprocess, 'check_output', side_effect=read):
                    frontend.build(output, architecture, root / 'data')
                self.assertEqual([name for name, _ in calls], ['build', 'version'])
                self.assertIs(calls[0][1], calls[1][1])

    def test_arm64_wrapper_rejects_overlay_before_commands_or_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            output = root / '.generated' / 'output'
            args = ['builder', '--data', str(root / 'data'), '--output', str(output), '--source-commit', 'b' * 40]
            with patch.object(arm64, 'ROOT', root), patch.object(sys, 'argv', args), \
                    patch.dict(os.environ, GOFLAGS='-overlay=foreign.json'), \
                    patch.object(arm64.subprocess, 'run') as run, \
                    patch.object(arm64.subprocess, 'check_output') as read:
                with self.assertRaisesRegex(ValueError, 'GOFLAGS'):
                    arm64.main()
            self.assertFalse(output.exists())
            run.assert_not_called()
            read.assert_not_called()

    def test_arm64_wrapper_passes_clean_environment_to_go_and_frontend(self):
        class FrontendObserved(Exception):
            pass

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            output = root / '.generated' / 'output'
            args = ['builder', '--data', str(root / 'data'), '--output', str(output), '--source-commit', 'b' * 40]
            commands = []

            def run(command, **kwargs):
                self.assert_environment(kwargs['env'], 'arm64')
                commands.append(command)
                if 'tools/build_touch_keyboard_desktop.py' in command:
                    self.assertIn('--installed-tsf', command)
                    raise FrontendObserved
                return subprocess.CompletedProcess(command, 0)

            with patch.object(arm64, 'ROOT', root), patch.object(sys, 'argv', args), \
                    patch.dict(os.environ, {'GOFLAGS': '', 'GOENV': str(root / 'persisted-go.env'),
                                             'GOWORK': str(root / 'foreign.work')}), \
                    patch.object(arm64.shutil, 'which', side_effect=lambda name: str(root / name)), \
                    patch('touch_keyboard_resources.verify'), \
                    patch.object(arm64.subprocess, 'check_output', side_effect=['b' * 40, '']), \
                    patch.object(arm64.subprocess, 'run', side_effect=run):
                with self.assertRaises(FrontendObserved):
                    arm64.main()
            self.assertEqual(len(commands), 5)
            self.assertEqual([command[-1] for command in commands[2:4]],
                             ['./cmd/yimecore-trial-runtime', './cmd/yimebroker-18u'])

    def test_x64_workflow_refuses_overlay_before_output_or_compiler(self):
        code = self.x64_workflow_build_step()
        with tempfile.TemporaryDirectory() as tmp, chdir(tmp), \
                patch.dict(os.environ, GOFLAGS='-overlay=foreign.json'), \
                patch.object(subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'GOFLAGS'):
                exec(code, {})
            self.assertFalse(Path('.generated').exists())
            run.assert_not_called()

    def test_x64_workflow_builds_use_clean_environment(self):
        code = self.x64_workflow_build_step()
        calls = []

        def run(command, **kwargs):
            self.assertEqual(command[:2], ['go', 'build'])
            self.assert_environment(kwargs['env'], 'amd64')
            calls.append((command, kwargs['env']))
            return subprocess.CompletedProcess(command, 0)

        with tempfile.TemporaryDirectory() as tmp, chdir(tmp), \
                patch.dict(os.environ, {'GOFLAGS': '', 'GOENV': 'persisted-go.env', 'GOWORK': 'foreign.work'}), \
                patch.object(subprocess, 'run', side_effect=run):
            Path('.generated/installed-18u-evidence').mkdir(parents=True)
            exec(code, {})
        self.assertEqual([command[-1] for command, _ in calls],
                         ['./cmd/yimecore-trial-runtime', './cmd/yimecore-trial-runtime', './cmd/yimebroker-18u'])
        self.assertTrue(all(env is calls[0][1] for _, env in calls))


if __name__ == '__main__':
    unittest.main(verbosity=2)
