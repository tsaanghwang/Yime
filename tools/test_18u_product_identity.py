"""Descriptor-only regression; does not register or load any product."""
import json
from pathlib import Path
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]


def read(relative):
    return json.loads((ROOT / relative).read_text(encoding='utf-8'))


class ProductIdentityTests(unittest.TestCase):
    def setUp(self):
        self.product = read('tools/yimecore/18u-touch-product.json')
        self.standard = read('tools/yimecore/local-product.json')

    def test_independent_product_identity(self):
        identity = self.product['identity']
        for key in ('clsid', 'profile'):
            value = str(uuid.UUID(identity[key].strip('{}')))
            others = [self.standard['identity'][key], self.standard['identity']['legacy_' + key]]
            # Existing PIME product IDs: installer/simple/Product.psm1 Get-Product; not an exhaustive Windows profile census.
            others += ['{35F67E9D-A54D-4177-9697-8B0AB71A9E04}', '{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}']
            self.assertNotIn(value, [str(uuid.UUID(x.strip('{}'))) for x in others])
        self.assertNotEqual(identity['clsid'], identity['profile'])
        for key in ('product_key', 'state_directory', 'install_directory', 'model_source_id'):
            self.assertNotEqual(identity[key], self.standard['identity'][key])
        self.assertNotIn('YimeCoreTrial', identity['endpoint_family'])

    def test_exact_dedicated_resource_identity(self):
        lock = read('prototypes/touch-terminal/desktop/resources.lock.json')
        physical = read('prototypes/touch-terminal/data/physical-layout.json')
        data = self.product['data']
        self.assertEqual(data['layout_sha256'], lock['layoutProjectionSHA256'])
        self.assertEqual(data['layout_sha256'], physical['layoutId'])
        self.assertEqual(data['dictionary_sha256'], lock['files']['yime_variable.dict.yaml']['sha256'])
        self.assertEqual(data['dictionary_sha256_by_mode'], {
            mode: lock['files']['yime_' + mode + '.dict.yaml']['sha256']
            for mode in ('full', 'variable', 'shorthand')
        })
        self.assertEqual(data['dictionary_sha256_legacy_role'], 'controlled_host_variable_identity')
        self.assertEqual(data['projection'], 'prototypes/touch-terminal/encoding/manual_key_layout.json')
        self.assertIs(data['standard_index_fallback'], False)

    def test_full_frontend_scope_is_distinct_from_acceptance(self):
        self.assertEqual(self.product['schema_version'], 'yimecore-18u-touch-product-v2')
        self.assertIs(self.product['installable'], True)
        scope = self.product['scope']
        self.assertEqual(scope['architecture'], 'x64')
        self.assertEqual(scope['languages'], ['CN', 'EN'])
        self.assertEqual(scope['modes'], ['full', 'variable', 'shorthand'])
        self.assertEqual(scope['capabilities'], ['installed-tsf-frontend', 'composition', 'candidates', 'literal', 'host-editing'])
        self.assertIs(scope['installed_frontend'], True)
        for key in ('persistent_learning', 'registration_validated'):
            self.assertIs(scope[key], False)
        for key in ('language', 'mode', 'user_machine_execution_approved'):
            self.assertNotIn(key, scope)

    def test_legacy_check_is_explicit_and_never_the_resident_default(self):
        self.assertEqual(self.product['controlled_host_scope'], {
            'language': 'CN', 'mode': 'variable', 'persistent_learning': False,
            'entry': 'installed-18u-check', 'default': False,
        })
        runtime = self.product['runtime']
        self.assertEqual(runtime['entry'], 'bin/Yime18uInstalledRuntime.exe')
        self.assertEqual(runtime['argument'], '--installed-18u-run')
        self.assertEqual(runtime['frontend'], 'bin/YimeTouchKeyboard.exe')
        self.assertEqual(runtime['broker'], 'bin/YimeBroker18u.exe')
        self.assertEqual(runtime['manifest_schema'], 'installed-18u-product-v2')
        self.assertIs(runtime['initiating_user'], True)
        self.assertIs(runtime['autostart'], True)
        self.assertIs(runtime['changes_default_profile'], False)

    def test_arm64_descriptor_changes_only_native_architecture(self):
        arm = read('tools/yimecore/18u-touch-product-arm64.json')
        expected = json.loads(json.dumps(self.product))
        expected['scope']['architecture'] = 'arm64'
        self.assertEqual(arm, expected)


if __name__ == '__main__':
    unittest.main()
