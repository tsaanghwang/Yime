"""Offline synthetic packaging tests: PowerShell/product executables never run."""
import json
from pathlib import Path
import shutil
import unittest
from unittest.mock import patch
import zipfile

import package_installed_18u as p
import test_assemble_installed_18u as fixtures

class PackageTests(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.PayloadTests()
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        self.work = self.f.root / 'work'
        self.sig = self.f.root / 'signatures.json'
        self.source = 'b' * 40
        self.calls = []
        # Fixture factory uses a separate import of the real assembler; patch only
        # synthetic hashes, never substitute the assembly algorithm.
        for name in ('LAYOUT_SHA', 'DICTIONARY_SHA'):
            self.addCleanup(patch.stopall)
            patch.object(p.a, name, getattr(fixtures.a, name)).start()
        for name in p.INSTALLER:
            file = self.f.repo / 'installer/simple' / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('synthetic build-only source ' + name)
        rows=[]
        for rel, (kind, name) in p.a.BINARIES.items():
            binary = (self.f.native if kind == 'native' else self.f.go) / name
            rows.append({'path': 'payload/' + rel, **p.a.digest(binary), 'status': 'NotSigned', 'signerThumbprint': None})
        self.signature = {'schema':'installed-18u-signatures-v1','sourceCommit':self.source,'files':rows}
        self.write_signature()

    def write_signature(self):
        self.sig.write_text(json.dumps(self.signature))

    def runner(self, command, **kwargs):
        self.calls.append(command)
        self.assertEqual(command[2:4], ['--script', str(self.f.repo / 'installer/simple/Build-Package.ps1')])
        self.assertEqual(command[4:6], ['--edition', 'ps7'])
        self.assertTrue(command[1].endswith('tools/powershell/run_checked.py'))
        self.assertTrue(kwargs['check']); self.assertEqual(kwargs['timeout'],180)
        args=json.loads(Path(command[-1]).read_text())
        self.assertEqual(args['Product'],'yimecore-18u');self.assertEqual(args['Version'],p.VERSION)
        out=Path(args['OutputRoot']);shutil.copytree(args['PayloadRoot'],out/'payload')
        for name in p.INSTALLER:shutil.copyfile(self.f.repo/'installer/simple'/name,out/name)
        rows=[{'path':name, **value} for name,value in p.inventory(out/'payload').items()]
        (out/'product-package.json').write_text(json.dumps({'format':'yime-simple-package-18u-1','product':'yimecore-18u','version':p.VERSION,'target':'windows-amd64','host_architecture':'amd64','tsf64_architecture':'x64','files':rows}))

    def build(self, runner=None):
        return p.build(self.f.repo,self.f.native,self.f.go,self.f.data,self.work,self.sig,self.source,runner=runner or self.runner)

    def test_exact_zip_and_receipt(self):
        result=self.build();self.assertEqual(len(self.calls),1)
        archive=self.work/p.ZIP_NAME
        self.assertEqual({k:result[k] for k in ('sha256','bytes')},p.a.digest(archive))
        with zipfile.ZipFile(archive) as z:
            expected={'payload/'+name for name in (*p.a.BINARIES,*p.a.RESOURCES,*('data/'+n for n in p.a.DATA),'installed-18u-product.json')}
            expected.update((*p.INSTALLER,'product-package.json','README.zh-CN.md','signatures.json','package-evidence.json'))
            self.assertEqual(set(z.namelist()),expected)
            evidence=json.loads(z.read('package-evidence.json'))
            self.assertEqual(set(evidence['files']),expected-{'package-evidence.json'})
            self.assertFalse(evidence['registrationExecuted']);self.assertFalse(evidence['installedHostAcceptance'])
        self.assertTrue((self.work/'package-receipt.json').is_file())

    def test_existing_work_no_execution(self):
        self.work.mkdir()
        with self.assertRaisesRegex(ValueError,'fresh'):self.build()
        self.assertFalse(self.calls)

    def test_bad_lock_no_execution(self):
        (self.f.data/'yime_variable.dict.yaml').write_text('wrong')
        with self.assertRaisesRegex(ValueError,'locked resource'):self.build()
        self.assertFalse(self.calls)

    def test_extra_package_file_rejected(self):
        def run(*args,**kwargs):
            self.runner(*args,**kwargs);(self.work/'package/extra.exe').write_text('extra')
        with self.assertRaisesRegex(ValueError,'exact assembled'):self.build(run)
        self.assertFalse((self.work/p.ZIP_NAME).exists())

    def test_changed_copied_payload_rejected(self):
        def run(*args,**kwargs):
            self.runner(*args,**kwargs);(self.work/'package/payload/profile-icon.ico').write_text('changed')
        with self.assertRaisesRegex(ValueError,'exact assembled'):self.build(run)

    def test_manifest_identity_rejected(self):
        def run(*args,**kwargs):
            self.runner(*args,**kwargs);q=self.work/'package/product-package.json';v=json.loads(q.read_text());v['product']='yimecore';q.write_text(json.dumps(v))
        with self.assertRaisesRegex(ValueError,'manifest identity'):self.build(run)

    def test_signature_source_mismatch(self):
        self.signature['sourceCommit']='c'*40;self.write_signature()
        with self.assertRaisesRegex(ValueError,'signature source'):self.build()

    def test_signature_hash_mismatch(self):
        self.signature['files'][0]['sha256']='0'*64;self.write_signature()
        with self.assertRaisesRegex(ValueError,'payload mismatch'):self.build()

    def test_signature_duplicate_inventory(self):
        self.signature['files'][1]=self.signature['files'][0];self.write_signature()
        with self.assertRaisesRegex(ValueError,'signature inventory'):self.build()

    def test_unsigned_cannot_claim_signer(self):
        self.signature['files'][0]['signerThumbprint']='a'*40;self.write_signature()
        with self.assertRaisesRegex(ValueError,'claim inconsistent'):self.build()

    def test_valid_requires_signer(self):
        self.signature['files'][0]['status']='Valid';self.write_signature()
        with self.assertRaisesRegex(ValueError,'claim inconsistent'):self.build()

    def test_ps_failure_never_zips(self):
        def fail(*args,**kwargs):raise RuntimeError('checked build failed')
        with self.assertRaisesRegex(RuntimeError,'checked build'):self.build(fail)
        self.assertFalse((self.work/p.ZIP_NAME).exists())

if __name__=='__main__':unittest.main(verbosity=2)
