"""Failure-propagation tests for native offline evidence, without Go execution."""
import json
import unittest

import verify_18u_broker_offline as verifier


class NativeEvidenceTests(unittest.TestCase):
    def events(self, architecture='arm64', accepted='true', machine='0xaa64', process='0x0'):
        package = verifier.MODULE + '/cmd/yimebroker-18u'
        result = []
        for name in verifier.GROUPS['cmd/yimebroker-18u']:
            result.append(dict(Action='run', Package=package, Test=name))
            if name == verifier.NATIVE_TEST:
                result.append(dict(Action='output', Package=package, Test=name,
                                   Output=f'GOARCH={architecture} process={process} native={machine} accepted={accepted}\n'))
            result.append(dict(Action='pass', Package=package, Test=name))
        result.append(dict(Action='pass', Package=package))
        return result

    def validate(self, events, architecture='arm64'):
        return verifier.validate_events('\n'.join(json.dumps(event) for event in events),
                                        verifier.MODULE + '/cmd/yimebroker-18u',
                                        verifier.GROUPS['cmd/yimebroker-18u'], architecture, True)

    def test_both_native_architectures_require_actual_acceptance(self):
        for architecture, machine in [('arm64', '0xaa64'), ('amd64', '0x8664')]:
            with self.subTest(architecture=architecture):
                result = self.validate(self.events(architecture, machine=machine), architecture)
                self.assertTrue(result['nativeArchitecture']['accepted'])

    def test_passing_emulation_rejection_is_not_native_acceptance(self):
        with self.assertRaisesRegex(ValueError, 'Native acceptance refused'):
            self.validate(self.events('amd64', 'false', '0xaa64', '0x8664'), 'amd64')

    def test_old_initialization_evidence_cannot_replace_ready_regressions(self):
        events = [event for event in self.events()
                  if event.get('Test') not in verifier.READY_TESTS]
        with self.assertRaisesRegex(ValueError, 'incomplete or duplicated'):
            self.validate(events)

    def test_each_ready_regression_must_execute_and_pass_without_skip(self):
        for name in verifier.READY_TESTS:
            for action in ('missing', 'skip', 'fail'):
                events = self.events()
                if action == 'missing':
                    events = [event for event in events if event.get('Test') != name]
                else:
                    for event in events:
                        if event.get('Test') == name and event['Action'] == 'pass':
                            event['Action'] = action
                with self.subTest(test=name, action=action), self.assertRaises(ValueError):
                    self.validate(events)

    def test_forged_acceptance_cannot_hide_foreign_machine(self):
        for changes in [dict(machine='0x8664'), dict(process='0xaa64'), dict(architecture='amd64')]:
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, 'Native acceptance refused'):
                self.validate(self.events(**changes))

    def test_skips_and_failures_are_rejected_even_with_package_pass(self):
        for action in ('skip', 'fail'):
            events = self.events()
            events[1]['Action'] = action
            with self.subTest(action=action), self.assertRaises(ValueError):
                self.validate(events)

    def test_missing_duplicate_and_wrong_package_evidence_rejected(self):
        for kind in ('missing-test', 'duplicate-pass', 'missing-package-pass', 'wrong-package', 'missing-native', 'duplicate-native'):
            events = self.events()
            if kind == 'missing-test':
                events = events[2:]
            elif kind == 'duplicate-pass':
                events.append(dict(events[1]))
            elif kind == 'missing-package-pass':
                events.pop()
            elif kind == 'wrong-package':
                events[0]['Package'] = 'foreign/package'
            elif kind == 'missing-native':
                events = [event for event in events if event['Action'] != 'output']
            else:
                events += [dict(event) for event in events if event['Action'] == 'output']
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                self.validate(events)

    def test_inherited_overlay_or_exec_flags_refused(self):
        for flags in ('-overlay=foreign.json', '-exec=emulator', '-run=Missing'):
            with self.subTest(flags=flags), self.assertRaisesRegex(ValueError, 'GOFLAGS'):
                verifier.test_environment('arm64', 'data', {'GOFLAGS': flags})

    def test_target_is_process_local_and_persisted_environment_disabled(self):
        inherited = {'GOOS': 'linux', 'GOARCH': '386', 'GOENV': 'foreign.env'}
        actual = verifier.test_environment('arm64', 'data', inherited)
        self.assertEqual(inherited['GOOS'], 'linux')
        self.assertEqual(actual['GOOS'], 'windows')
        self.assertEqual(actual['GOARCH'], 'arm64')
        self.assertEqual(actual['GOENV'], 'off')
        self.assertEqual(actual['YIME_18U_FULL_DATA'], 'data')

    def test_effective_go_environment_must_match(self):
        info = dict(GOOS='windows', GOARCH='arm64', GOHOSTOS='windows',
                    CGO_ENABLED='0', GOTOOLCHAIN='local', GOFLAGS='')
        verifier.validate_go_environment(info, 'arm64')
        for key in info:
            with self.subTest(key=key), self.assertRaises(ValueError):
                verifier.validate_go_environment(dict(info, **{key: 'wrong'}), 'arm64')


if __name__ == '__main__':
    unittest.main(verbosity=2)
