import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('delivery', Path(__file__).with_name('verify_delivery.py'))
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class DeliveryTests(unittest.TestCase):
    def test_paths_cannot_escape_or_use_windows_streams(self):
        for path in ('../outside', '/outside', 'C:/outside', 'file:stream', 'a\\b', 'a//b'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                M.plain_child(Path('.'), path)

    def test_integrity_and_binding_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            identity = {'product': 'rime-pime', 'product_version': '1.4.0-dev.1',
                        'installed_acceptance_passed': False, 'public_release_admitted': False}
            manifest = dict(identity, schema_version='yime-rime-pime-executable-candidate-v1',
                            source_inventory_sha256=M.digest(b'inventory'))
            encode = lambda obj: json.dumps(obj).encode()
            data = {'installer': b'INERT', 'manifest': encode(manifest), 'source_inventory': b'inventory',
                    'static_payload': b'static', 'source_baseline': b'baseline'}
            receipt = dict(identity, schema_version='yime-rime-pime-executable-build-receipt-v1',
                           installer={'sha256': M.digest(data['installer']), 'bytes': 5},
                           manifest_sha256=M.digest(data['manifest']),
                           source_inventory_sha256=M.digest(data['source_inventory']),
                           static_payload={'tree_sha256': M.digest(data['static_payload'])})
            data['receipt'] = encode(receipt)
            index = dict(identity, schema_version='yime-rime-pime-executable-candidate-delivery-v1', artifacts={})
            for name, raw in data.items():
                (root / name).write_bytes(raw)
                index['artifacts'][name] = {'path': name, 'bytes': len(raw), 'sha256': M.digest(raw)}
            def save():
                raw = encode(index)
                (root / 'delivery-index.json').write_bytes(raw)
                return M.digest(raw)
            pin = save()
            self.assertTrue(M.verify(root, pin)['integrity_passed'])
            self.assertFalse(M.verify(root, pin)['execution_authorized'])
            with self.assertRaises(ValueError): M.verify(root, '0'*64)
            (root / 'installer').write_bytes(b'OTHER')
            with self.assertRaises(ValueError): M.verify(root, pin)
            (root / 'installer').write_bytes(data['installer'])
            receipt['manifest_sha256'] = '0'*64
            changed = encode(receipt)
            (root / 'receipt').write_bytes(changed)
            index['artifacts']['receipt'].update(bytes=len(changed), sha256=M.digest(changed))
            with self.assertRaises(ValueError): M.verify(root, save())


if __name__ == '__main__':
    unittest.main()
