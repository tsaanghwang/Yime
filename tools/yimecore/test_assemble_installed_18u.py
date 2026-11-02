"""Synthetic offline tests only: no PE execution, registry, or installer invocation."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('assemble', Path(__file__).with_name('assemble_installed_18u.py'))
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)

class PayloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo, self.native, self.go, self.data, self.out = [self.root / x for x in ('repo','native','go','data','output')]
        for d in (self.repo,self.native,self.go,self.data): d.mkdir()
        pe = bytearray(128); pe[:2] = b'MZ'; struct.pack_into('<I',pe,60,64); pe[64:68]=b'PE\0\0';struct.pack_into('<H',pe,68,0x8664);struct.pack_into('<H',pe,88,0x20b)
        for _,(kind,name) in a.BINARIES.items(): (self.native if kind=='native' else self.go).joinpath(name).write_bytes(pe)
        self.layout = 'a'*64
        for name in a.DATA: (self.data/name).write_bytes(('synthetic:'+name).encode())
        self.dictionary = a.digest(self.data/'yime_variable.dict.yaml')['sha256']
        product={'identity':{'clsid':'{6DFACE1F-562E-4773-A9D6-D5753A314711}','profile':'{1BD904AC-3194-4419-B70A-5574100F18B3}'},'data':{'layout_sha256':self.layout,'dictionary_sha256':self.dictionary,'standard_index_fallback':False}}
        self.lock={'schemaVersion':1,'layoutProjectionSHA256':self.layout,'files':{n:a.digest(self.data/n) for n in a.DATA}}
        for dest,src in a.RESOURCES.items():
            p=self.repo/src;p.parent.mkdir(parents=True,exist_ok=True)
            value=product if src.endswith('18u-touch-product.json') else self.lock if src.endswith('resources.lock.json') else {'layoutId':self.layout}
            p.write_text(json.dumps(value))
        self.addCleanup(patch.stopall)
        patch.object(a,'LAYOUT_SHA',self.layout).start();patch.object(a,'DICTIONARY_SHA',self.dictionary).start()
    def run_build(self): return a.assemble(self.repo,self.native,self.go,self.data,self.out,'b'*40)
    def test_exact_files_hashes(self):
        m=self.run_build();self.assertEqual(len(m['files']),len(a.BINARIES)+len(a.RESOURCES)+len(a.DATA));self.assertFalse(m['autostart'])
        for row in m['files']: self.assertEqual(a.digest(self.out/row['path']),{k:row[k] for k in ('bytes','sha256')})
        self.assertEqual(sum(x.is_file() for x in self.out.rglob('*')),len(m['files'])+1)
    def test_no_overwrite(self):
        self.out.mkdir();(self.out/'keep').write_text('keep')
        with self.assertRaisesRegex(ValueError,'no overwrite'):self.run_build()
        self.assertEqual((self.out/'keep').read_text(),'keep')
    def test_wrong_arch_before_output(self):
        p=self.native/'YimeTextService18u.dll';raw=bytearray(p.read_bytes());struct.pack_into('<H',raw,68,0xaa64);p.write_bytes(raw)
        with self.assertRaisesRegex(ValueError,'AMD64'):self.run_build()
        self.assertFalse(self.out.exists())
    def test_wrong_product(self):
        p=self.repo/a.RESOURCES['source/tools/yimecore/18u-touch-product.json'];v=json.loads(p.read_text());v['identity']['clsid']='standard';p.write_text(json.dumps(v))
        with self.assertRaisesRegex(ValueError,'identity'):self.run_build()
    def test_wrong_data(self):
        (self.data/'yime_full.dict.yaml').write_text('wrong')
        with self.assertRaisesRegex(ValueError,'locked resource'):self.run_build()
    def test_incomplete_lock(self):
        p=self.repo/'prototypes/touch-terminal/desktop/resources.lock.json';v=json.loads(p.read_text());del v['files']['yime_full.dict.yaml'];p.write_text(json.dumps(v))
        with self.assertRaisesRegex(ValueError,'complete'):self.run_build()
    def test_wrong_layout(self):
        (self.repo/'prototypes/touch-terminal/data/physical-layout.json').write_text('{"layoutId":"wrong"}')
        with self.assertRaisesRegex(ValueError,'layout identity'):self.run_build()
    def test_duplicate_json(self):
        (self.repo/'prototypes/touch-terminal/desktop/resources.lock.json').write_text('{"schemaVersion":1,"schemaVersion":1}')
        with self.assertRaisesRegex(ValueError,'duplicate'):self.run_build()
    def test_missing_binary(self):
        (self.go/'YimeBroker18u.exe').unlink()
        with self.assertRaisesRegex(ValueError,'missing'):self.run_build()
    def test_linked_input(self):
        p=self.data/'yime_full.dict.yaml';p.unlink();p.symlink_to(self.data/'yime_variable.dict.yaml')
        with self.assertRaisesRegex(ValueError,'linked'):self.run_build()
    def test_source_commit(self):
        with self.assertRaisesRegex(ValueError,'source commit'): a.assemble(self.repo,self.native,self.go,self.data,self.out,'main')
    def test_fixed_source_locks(self):
        source=Path(a.__file__).read_text();self.assertIn('995f1a74f129249febbd09ca11a8266f6e0c94bac8c05c57754859fc3be3349c',source);self.assertIn('43a74f4e47c7100f222a744f487762f1c31222c5f80b9a34fd24cbebc7e96353',source)

class SetupContracts(unittest.TestCase):
    def test_owned_before_process_stop(self):
        s=Path(__file__).parents[2].joinpath('installer/simple/Setup.ps1').read_text(encoding='utf-8-sig')
        self.assertLess(s.index("@('check-owned'"),s.index("$stage='stop selected product"))
        self.assertLess(s.index("@('verify-absent')"),s.index("$stage='stop selected product"))
    def test_no_auto_acceptance_or_startup(self):
        s=Path(__file__).parents[2].joinpath('installer/simple/Setup.ps1').read_text(encoding='utf-8-sig')
        self.assertNotIn('once-installed-18u-host',s)
        self.assertIn("if($product.id -ne 'yimecore-18u'){Set-UserStartup",s)
        self.assertLess(s.index('No startup task or acceptance run'),s.index("$stage='start installed runtime'"))
    def test_data_preserved(self):
        s=Path(__file__).parents[2].joinpath('installer/simple/Setup.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("if($ResetData){throw '18u maintenance preserves user data",s)

if __name__=='__main__':unittest.main(verbosity=2)
