"""Synthetic PE packaging tests: no Windows compilation, signing or activation."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
import build_mycomputer_stage1_package as package


def pe(dll, machine=0x8664):
    data=bytearray(512);data[:2]=b'MZ';struct.pack_into('<I',data,60,64)
    data[64:68]=b'PE\0\0';struct.pack_into('<HHIIIHH',data,68,machine,1,0,0,0,112,2|(0x2000 if dll else 0))
    struct.pack_into('<H',data,88,0x20b)
    return bytes(data)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.paths={name:self.root/name for name in (*package.PE_NAMES,*package.SCRIPT_NAMES,'README.md')}
        for name,path in self.paths.items():path.write_bytes(pe(name.endswith('.dll')) if name in package.PE_NAMES else b'reviewed test fixture\n')
        self.signature_file=self.root/'signatures.json';self.rows=[]
        for name in package.PE_NAMES:
            self.rows.append(dict(name=name,sha256=package.digest(self.paths[name].read_bytes()),status='NotSigned',signerCertificateThumbprint=None,timestampCertificateThumbprint=None))
        self.save_signatures()
    def save_signatures(self):self.signature_file.write_text(json.dumps(dict(schema='mycomputer-authenticode-v1',files=self.rows)))
    def build(self, **kwargs):
        return package.build_package(self.paths[package.PE_NAMES[0]],self.paths[package.PE_NAMES[1]],'a'*40,
                                     self.paths['README.md'],self.paths[package.SCRIPT_NAMES[0]],self.paths[package.SCRIPT_NAMES[1]],
                                     self.signature_file,self.root/'out',**kwargs)

    def test_exact_members_roundtrip_hashes_and_unsigned_status(self):
        evidence=self.build();archive=self.root/'out'/evidence['zip']
        self.assertEqual(evidence['sha256'],hashlib.sha256(archive.read_bytes()).hexdigest())
        with zipfile.ZipFile(archive) as z:
            self.assertEqual(set(z.namelist()),set(package.PE_NAMES)|set(package.SCRIPT_NAMES)|{'README.zh-CN.md','manifest.json'})
            manifest=json.loads(z.read('manifest.json'))
            self.assertEqual(manifest['identity'],package.PRODUCT_IDENTITY)
            self.assertEqual(evidence['manifestSHA256'],package.digest(z.read('manifest.json')))
            for row in manifest['files']:
                data=z.read(row['path']);self.assertEqual(row['bytes'],len(data));self.assertEqual(row['sha256'],package.digest(data))
                if row['path'] in package.PE_NAMES:self.assertEqual(row['authenticode']['status'],'NotSigned')
            for key in ('userDesktopExecutionApproved','registrationExecutionApproved','brokerEditingVerified','physicalAcceptance'):
                self.assertIs(manifest[key],False)
        self.assertFalse(evidence['windowsActivationExecutedByBuilder'])

    def test_built_manifest_is_accepted_by_actual_readonly_collector(self):
        # Parse only; never invoke collect() or launch the synthetic PE fixtures.
        from collect_mycomputer_preflight import validate_package
        evidence=self.build();unpacked=self.root/'unpacked';unpacked.mkdir()
        with zipfile.ZipFile(self.root/'out'/evidence['zip']) as z:z.extractall(unpacked)
        validate_package(unpacked,evidence['manifestSHA256'])

    def test_v2_separate_seven_payload_package_and_collector_compatibility(self):
        from collect_mycomputer_preflight import validate_package, SCHEMA_V2, PAYLOAD_V2
        companions = []
        for name in package.V2_SCRIPT_NAMES:
            path = self.root / name
            path.write_text('# synthetic v2 fixture\n')
            companions.append(path)
        evidence = self.build(package_version='v2', registration_runner=companions[0], evidence_validator=companions[1])
        self.assertEqual(evidence['payloadCount'], 7)
        self.assertEqual(evidence['zip'], 'YimeMyComputerActivationProtected-v2-x64.zip')
        unpacked = self.root / 'unpacked'
        unpacked.mkdir()
        with zipfile.ZipFile(self.root / 'out' / evidence['zip']) as archive:
            archive.extractall(unpacked)
        manifest, files = validate_package(unpacked, evidence['manifestSHA256'])
        self.assertEqual(manifest['schema'], SCHEMA_V2)
        self.assertEqual(set(files), PAYLOAD_V2)
        self.assertEqual(manifest['defaultOperation'], 'read-only-preflight')
        self.assertFalse(manifest['registrationExecutionApproved'])

    def test_version_companion_mismatch_rejected_before_output(self):
        with self.assertRaises(ValueError): self.build(package_version='v2')
        with self.assertRaises(ValueError): self.build(registration_runner=self.root/'unreviewed.py')
        with self.assertRaises(ValueError): self.build(package_version='v3')
        self.assertFalse((self.root/'out').exists())

    def test_wrong_architecture_kind_and_truncated_pe_rejected(self):
        for data in (pe(True,0xaa64),pe(False),b'MZ',pe(True)[:200]):
            with self.subTest(data=data[:20]):
                self.paths[package.PE_NAMES[0]].write_bytes(data)
                with self.assertRaises(ValueError):self.build()
                self.assertFalse((self.root/'out').exists())

    def test_signature_hash_binding_and_missing_record(self):
        self.rows[0]['sha256']='b'*64;self.save_signatures()
        with self.assertRaises(ValueError):self.build()
        self.rows.pop();self.save_signatures()
        with self.assertRaises(ValueError):self.build()
        self.assertFalse((self.root/'out').exists())

    def test_signature_claims_cannot_be_invented(self):
        for status,signer in (('Valid',None),('invented',None),('NotSigned','A'*40)):
            self.rows[0]['status']=status;self.rows[0]['signerCertificateThumbprint']=signer;self.save_signatures()
            with self.subTest(status=status),self.assertRaises(ValueError):self.build()

    def test_actual_supplied_signature_status_preserved_not_promoted(self):
        self.rows[0]['status']='NotTrusted';self.rows[0]['signerCertificateThumbprint']='A'*40;self.save_signatures()
        evidence=self.build()
        self.assertEqual(evidence['authenticode'][package.PE_NAMES[0]]['status'],'NotTrusted')

    def test_fresh_output_only_and_duplicate_signature_json_rejected(self):
        (self.root/'out').mkdir()
        with self.assertRaises(FileExistsError):self.build()
        self.assertEqual(list((self.root/'out').iterdir()),[])
        with self.assertRaises(ValueError):package.unique_json(b'{"schema":1,"schema":2}')

if __name__=='__main__':unittest.main()
