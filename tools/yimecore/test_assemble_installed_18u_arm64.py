"""Offline synthetic architecture-contract checks. No executable is run."""
import json
import struct
import unittest
import test_assemble_installed_18u as fixtures

a = fixtures.a

class Arm64AssemblyTests(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.PayloadTests()
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        x64 = self.f.repo / a.RESOURCES['source/tools/yimecore/18u-touch-product.json']
        desc = json.loads(x64.read_text())
        desc['scope'] = {'architecture': 'x64'}
        x64.write_text(json.dumps(desc))
        desc['scope'] = {'architecture': 'arm64'}
        dest = self.f.repo / 'tools/yimecore/18u-touch-product-arm64.json'
        dest.write_text(json.dumps(desc), encoding='utf-8')
        for kind, name in a.BINARIES.values():
            p = (self.f.native if kind == 'native' else self.f.go) / name
            data = bytearray(p.read_bytes())
            struct.pack_into('<H', data, 68, 0xaa64)
            p.write_bytes(data)

    def assemble(self):
        return a.assemble(self.f.repo, self.f.native, self.f.go, self.f.data,
                          self.f.out, 'b' * 40, 'arm64')

    def test_native_inventory_and_descriptor(self):
        result = self.assemble()
        names = {row['path'] for row in result['files']}
        self.assertEqual(result['architecture'], 'native-arm64')
        self.assertIn('arm64/YimeTextService18u.dll', names)
        self.assertIn('source/tools/yimecore/18u-touch-product-arm64.json', names)
        self.assertFalse(any(name.startswith('x64/') for name in names))
        self.assertEqual(len(names), 15)

    def test_reject_amd64_member_before_output(self):
        p = self.f.go / 'YimeBroker18u.exe'
        data = bytearray(p.read_bytes())
        struct.pack_into('<H', data, 68, 0x8664)
        p.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'ARM64'):
            self.assemble()
        self.assertFalse(self.f.out.exists())

    def test_reject_opposite_architecture_descriptor(self):
        p = self.f.repo / 'tools/yimecore/18u-touch-product-arm64.json'
        data = json.loads(p.read_text())
        data['scope']['architecture'] = 'x64'
        p.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'descriptor architecture'):
            self.assemble()
        self.assertFalse(self.f.out.exists())

    def test_reject_unknown_architecture(self):
        with self.assertRaisesRegex(ValueError, 'unsupported'):
            a.binary_map('arm64ec')

    def test_reject_other_product_changes(self):
        p = self.f.repo / 'tools/yimecore/18u-touch-product-arm64.json'
        data = json.loads(p.read_text())
        data['scope']['mode'] = 'full'
        p.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'beyond architecture'):
            self.assemble()
        self.assertFalse(self.f.out.exists())

if __name__ == '__main__':
    unittest.main()
