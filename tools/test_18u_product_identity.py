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
        self.assertEqual(data['projection'], 'prototypes/touch-terminal/encoding/manual_key_layout.json')
        self.assertIs(data['standard_index_fallback'], False)

    def test_not_installation_or_multiplatform_acceptance(self):
        self.assertIs(self.product['installable'], False)
        scope = self.product['scope']
        self.assertEqual((scope['architecture'], scope['language'], scope['mode']), ('x64', 'CN', 'variable'))
        for key in ('persistent_learning', 'registration_validated', 'user_machine_execution_approved'):
            self.assertIs(scope[key], False)


if __name__ == '__main__':
    unittest.main()
