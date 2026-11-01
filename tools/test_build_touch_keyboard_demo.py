import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import build_touch_keyboard_demo as demo
import check_touch_keyboard_demo as checker


class DemoPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name); self.host=self.root/'.generated/native/host.exe'
        self.host.parent.mkdir(parents=True)
        raw=bytearray(128);raw[:2]=b'MZ';struct.pack_into('<I',raw,60,80);raw[80:84]=b'PE\0\0';struct.pack_into('<H',raw,84,0x8664)
        self.host.write_bytes(raw)
        self.patcher=patch.object(demo,'ROOT',self.root);self.patcher.start();self.addCleanup(self.patcher.stop)

    def test_host_rejects_wrong_arch_and_external_source(self):
        self.assertEqual(demo.validate_host(self.host),self.host)
        raw=bytearray(self.host.read_bytes());struct.pack_into('<H',raw,84,0xaa64);self.host.write_bytes(raw)
        with self.assertRaises(ValueError):demo.validate_host(self.host)
        outside=self.root/'outside.exe';outside.write_bytes(raw)
        with self.assertRaises(ValueError):demo.validate_host(outside)

    def test_bound_host_and_no_ordinary_launchers(self):
        out=self.root/'.generated/demo';data=self.root/'verified-data'
        def stage(dst,src):
            for name in demo.LAUNCHERS:(dst/name).write_text('old external target launcher')
            (dst/'USER_GUIDE.zh-CN.md').write_text('old SendInput instructions')
        def compile(args,**kwargs):
            self.assertIn('-X main.ownTSFDemoPackage=1',args[3])
            (out/'YimeTouchKeyboard.exe').write_bytes(b'isolated synthetic build fixture')
        with patch.object(demo,'generated',side_effect=lambda p:p),patch.object(demo,'verify') as verify,patch.object(demo,'stage_resources',side_effect=stage),patch.object(demo.subprocess,'check_output',side_effect=['a'*40+'\n','']),patch.object(demo.subprocess,'run',side_effect=compile),patch.dict(demo.os.environ,{'GITHUB_ACTIONS':'false'}):
            demo.build(out,data,self.host)
        verify.assert_called_once_with(data)
        m=json.loads((out/'manifest.json').read_text());r=json.loads((out/'resources.json').read_text())
        self.assertEqual(m['scope'],demo.SCOPE)
        self.assertEqual(r['files'][demo.HOST],demo.digest(self.host))
        self.assertEqual(m['portableResourcesSHA256'],demo.digest(out/'resources.json'))
        self.assertFalse(m['userDesktopExecutionApproved'])
        for name in demo.LAUNCHERS:self.assertFalse((out/name).exists())
        self.assertNotIn('old SendInput',(out/'USER_GUIDE.zh-CN.md').read_text())
        for name,want in m['files'].items():self.assertEqual(demo.digest(out/name),want)
        with patch.object(checker,'verify'):
            checker.verify_inventory(out)
            m['physicalAcceptance']=True
            (out/'manifest.json').write_text(json.dumps(m))
            with self.assertRaises(ValueError):checker.verify_inventory(out)
            m['physicalAcceptance']=False
            (out/'manifest.json').write_text(json.dumps(m))
            (out/'unexpected.bin').write_bytes(b'extra')
            with self.assertRaises(ValueError):checker.verify_inventory(out)
            (out/'unexpected.bin').unlink()
            (out/demo.HOST).write_bytes(b'changed')
            with self.assertRaises(ValueError):checker.verify_inventory(out)

    def test_locked_resource_verification_failure_stops_before_output(self):
        out=self.root/'.generated/demo'
        with patch.object(demo,'generated',side_effect=lambda p:p),patch.object(demo,'verify',side_effect=ValueError('wrong data')):
            with self.assertRaises(ValueError):demo.build(out,self.root/'fixture',self.host)
        self.assertFalse(out.exists())

if __name__=='__main__':unittest.main()
