"""Ordinary CI builds must stay complete without uploading full delivery packages."""
from pathlib import Path
import json
import os
import re
import tempfile
import unittest
from unittest.mock import patch

from package_delivery import main, select_request, uploaded_receipt


ROOT = Path(__file__).resolve().parents[2]
SHA = 'a' * 40
DIGEST = 'b' * 64
WORKFLOWS = {
    'installed-18u': 'installed-18u-compile.yml',
    'touch-terminal': 'touch-terminal.yml',
}
PACKAGE_PATHS = {
    'installed-18u': {
        'x64': '.generated/installed-18u-package/*.zip',
        'arm64': '.generated/installed-18u-arm64/package/*.zip',
    },
    'touch-terminal': {
        'x64': '.generated/touch-keyboard-desktop/',
        'arm64': '.generated/touch-keyboard-desktop-arm64/',
    },
}


def validate_workflow(text, product):
    if re.search(r'^    if:', text, re.M):
        raise ValueError('Package upload selection must not skip compilation jobs')
    purpose = re.search(r'^      package_purpose:\n(.*?)(?=^      \w+:)', text, re.M | re.S)
    if not purpose or 'default: checks-only' not in purpose[1]:
        raise ValueError('Manual runs default to checks without delivery uploads')
    for required in ('workflow_dispatch:', 'package_architecture:', 'package_reason:',
                     'PACKAGE_PURPOSE: ${{ inputs.package_purpose }}',
                     'PACKAGE_ARCHITECTURE: ${{ inputs.package_architecture }}',
                     'PACKAGE_REASON: ${{ inputs.package_reason }}',
                     'tools/ci/package_delivery.py'):
        if required not in text:
            raise ValueError('Explicit selection request validation missing')
    steps = re.findall(r'^      - .*?(?=^      - |\Z)', text, re.M | re.S)
    uploads = [step for step in steps if 'uses: actions/upload-artifact@' in step]
    identity = '${{ github.sha }}-attempt-${{ github.run_attempt }}'
    selected_prefix = 'name: selected-${{ inputs.package_purpose }}-' + product + '-'
    for arch, path in PACKAGE_PATHS[product].items():
        matching = [step for step in uploads if 'path: ' + path + '\n' in step]
        if len(matching) != 1:
            raise ValueError('Each architecture needs exactly one complete package upload')
        step = matching[0]
        for required in ('id: package-' + arch,
                         "if: steps.package-request.outputs.upload_" + arch + " == 'true'",
                         selected_prefix + arch + '-' + identity,
                         'retention-days: 14'):
            if required not in step:
                raise ValueError('Full packages require validated explicit selection and attempt identity')
    for step in uploads:
        if selected_prefix in step:
            if 'retention-days: 14' not in step:
                raise ValueError('Selected package and receipt must allow time for archival')
        elif 'retention-days: 5' not in step:
            raise ValueError('Ordinary evidence has a five-day retention period')
        if identity not in step:
            raise ValueError('Retry uploads must not collide with prior attempt artifacts')
    receipts = ('receipt-x64', 'receipt-arm64') if product == 'installed-18u' else ('receipt',)
    for kind in receipts:
        if not any(selected_prefix + kind + '-' + identity in step for step in uploads):
            raise ValueError('Selected package identity receipt missing')
    for arch in ('x64', 'arm64'):
        receipt_steps = [step for step in steps
                         if 'ARTIFACT_ID: ${{ steps.package-' + arch + '.outputs.artifact-id }}' in step]
        if len(receipt_steps) != 1:
            raise ValueError('Each selected package needs its original uploaded artifact identity')
        for field in ('artifact-digest', 'artifact-url'):
            if 'steps.package-' + arch + '.outputs.' + field not in receipt_steps[0]:
                raise ValueError('Receipt must include the actual uploaded digest and URL')


class PackageRequestTests(unittest.TestCase):
    def request(self, event='workflow_dispatch', purpose='delivery', architecture='both', reason='fixed delivery'):
        return select_request(event, purpose, architecture, reason, SHA, SHA)

    def test_ordinary_runs_cannot_select_packages(self):
        for event in ('push', 'pull_request', 'schedule'):
            with self.subTest(event=event):
                request = self.request(event=event)
                self.assertEqual(request['purpose'], 'checks-only')
                self.assertFalse(request['upload_x64'])
                self.assertFalse(request['upload_arm64'])

    def test_dispatch_checks_only_does_not_upload(self):
        request = self.request(purpose='checks-only', reason='')
        self.assertFalse(request['upload_x64'])
        self.assertFalse(request['upload_arm64'])

    def test_selected_purpose_and_architecture(self):
        for purpose in ('delivery', 'reproduction'):
            for arch in ('x64', 'arm64', 'both'):
                with self.subTest(purpose=purpose, arch=arch):
                    request = self.request(purpose=purpose, architecture=arch)
                    self.assertEqual(request['upload_x64'], arch in ('x64', 'both'))
                    self.assertEqual(request['upload_arm64'], arch in ('arm64', 'both'))
                    self.assertEqual(request['purpose'], purpose)
                    self.assertEqual(request['source_sha'], SHA)

    def test_selected_request_needs_supported_values_and_reason(self):
        for overrides in ({'purpose': 'ordinary'}, {'architecture': 'amd64'},
                          {'reason': ''}, {'reason': ' \n '}, {'reason': 'a' * 1001}):
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                self.request(**overrides)

    def test_source_identity_must_match_actual_checkout(self):
        for recorded, actual in ((SHA, 'c' * 40), ('a' * 7, 'a' * 7), ('A' * 40, 'A' * 40)):
            with self.subTest(recorded=recorded), self.assertRaises(ValueError):
                select_request('workflow_dispatch', 'delivery', 'both', 'fixed delivery', recorded, actual)

    def test_receipt_records_original_upload_identity_without_claiming_archive(self):
        receipt = uploaded_receipt(self.request(), 'x64', '123', 'sha256:' + DIGEST,
                                   'https://example.invalid/artifact/123', '456', '2')
        self.assertEqual(receipt['source_sha'], SHA)
        self.assertEqual(receipt['purpose'], 'delivery')
        self.assertEqual(receipt['reason'], 'fixed delivery')
        self.assertEqual(receipt['artifact_id'], 123)
        self.assertEqual(receipt['sha256'], DIGEST)
        self.assertEqual(receipt['run_id'], 456)
        self.assertEqual(receipt['run_attempt'], 2)
        self.assertFalse(receipt['external_archive_verified'])

    def test_receipt_rejects_unselected_architecture_or_missing_upload_identity(self):
        request = self.request(architecture='x64')
        for arch, artifact_id, digest, run_id, attempt in (
                ('arm64', '123', DIGEST, '456', '1'),
                ('x64', '', DIGEST, '456', '1'),
                ('x64', '0', DIGEST, '456', '1'),
                ('x64', '123', '', '456', '1'),
                ('x64', '123', DIGEST, '', '1'),
                ('x64', '123', DIGEST, '456', '0')):
            with self.subTest(arch=arch, artifact_id=artifact_id, run_id=run_id, attempt=attempt), self.assertRaises(ValueError):
                uploaded_receipt(request, arch, artifact_id, digest, '', run_id, attempt)

    def test_runner_request_outputs_and_uploaded_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            request_path = directory / 'request.json'
            outputs = directory / 'outputs.txt'
            summary = directory / 'summary.md'
            env = {
                'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_SHA': SHA,
                'PACKAGE_PURPOSE': 'reproduction', 'PACKAGE_ARCHITECTURE': 'arm64',
                'PACKAGE_REASON': 'Issue 123 reproduction', 'GITHUB_OUTPUT': str(outputs),
                'ARTIFACT_ID': '123', 'ARTIFACT_DIGEST': DIGEST,
                'ARTIFACT_URL': 'https://example.invalid/artifact/123',
                'GITHUB_RUN_ID': '456', 'GITHUB_RUN_ATTEMPT': '2',
                'GITHUB_STEP_SUMMARY': str(summary),
            }
            with patch.dict(os.environ, env, clear=True), patch('package_delivery.subprocess.check_output', return_value=SHA + '\n') as checkout:
                with patch('sys.argv', ['package_delivery.py', 'request', '--request', str(request_path)]):
                    main()
                checkout.assert_called_once_with(['git', 'rev-parse', 'HEAD'], text=True)
                self.assertEqual(outputs.read_text(encoding='utf-8'), 'upload_x64=false\nupload_arm64=true\n')
                with patch('sys.argv', ['package_delivery.py', 'receipt', '--request', str(request_path),
                                        '--architecture', 'arm64', '--output-dir', str(directory / 'receipts')]):
                    main()
            receipt = json.loads((directory / 'receipts/arm64.json').read_text(encoding='utf-8'))
            self.assertEqual(receipt['source_sha'], SHA)
            self.assertEqual(receipt['purpose'], 'reproduction')
            self.assertEqual(receipt['artifact_id'], 123)
            self.assertIn(DIGEST, summary.read_text(encoding='utf-8'))


class PackageWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflows = {product: (ROOT / '.github/workflows' / name).read_text(encoding='utf-8')
                          for product, name in WORKFLOWS.items()}

    def test_current_upload_contracts(self):
        for product, text in self.workflows.items():
            with self.subTest(product=product):
                validate_workflow(text, product)

    def test_ordinary_upload_regression_is_rejected(self):
        for product, text in self.workflows.items():
            for arch in ('x64', 'arm64'):
                gate = "if: steps.package-request.outputs.upload_" + arch + " == 'true'"
                with self.subTest(product=product, arch=arch), self.assertRaises(ValueError):
                    validate_workflow(text.replace(gate, 'if: success()'), product)

    def test_manual_default_cannot_select_packages(self):
        for product, text in self.workflows.items():
            with self.subTest(product=product), self.assertRaises(ValueError):
                validate_workflow(text.replace('default: checks-only', 'default: delivery'), product)

    def test_retry_identity_missing_from_small_report_is_rejected(self):
        text = self.workflows['touch-terminal']
        prefix = 'touch-keyboard-package-verification-${{ github.sha }}'
        text = text.replace(prefix + '-attempt-${{ github.run_attempt }}', prefix)
        with self.assertRaises(ValueError):
            validate_workflow(text, 'touch-terminal')

    def test_package_selection_cannot_skip_compilation_job(self):
        for product, text in self.workflows.items():
            with self.subTest(product=product), self.assertRaises(ValueError):
                validate_workflow(text.replace('    runs-on:', "    if: github.event_name == 'workflow_dispatch'\n    runs-on:", 1), product)


if __name__ == '__main__':
    unittest.main()
