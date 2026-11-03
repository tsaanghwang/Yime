import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

import package_native_maintenance as package


class NativeMaintenancePackageTests(unittest.TestCase):
    def test_rejects_windows_ambiguous_or_escaping_member_names(self):
        for name in ('../pwsh.exe','maintenance//pwsh.exe','C:/pwsh.exe','x\\pwsh.exe',
                     'NUL.dll','COM1/a','x./a','a:stream','x\ny','a/*.dll'):
            with self.subTest(name=name):
                self.assertFalse(package.valid_member(name))
        self.assertTrue(package.valid_member('maintenance/powershell/zh-CN/about_Aliases.help.txt'))

    def test_formal_archive_refuses_dirty_or_different_source(self):
        commit='a'*40
        with patch.object(package.subprocess,'check_output',side_effect=[commit+'\n',' M source.go\n']):
            with self.assertRaisesRegex(ValueError,'clean committed'):
                package.source_state(Path('.'),commit,False,'git')
        with patch.object(package.subprocess,'check_output',return_value='b'*40+'\n'):
            with self.assertRaisesRegex(ValueError,'current HEAD'):
                package.source_state(Path('.'),commit,True,'git')

    def test_shared_shell_cache_rejects_changed_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            shell=root/'powershell';shell.mkdir()
            (shell/'pwsh.exe').write_bytes(b'original')
            package.write_json(root/'shell-lock.json',{'files':package.inventory(shell)})
            (shell/'pwsh.exe').write_bytes(b'changed')
            args=SimpleNamespace(repo=root,cache=root,source_pshome=root/'source')
            with self.assertRaisesRegex(ValueError,'differs from its lock'):
                package.prepare_shell(args)

    def test_zip_roundtrip_and_prior_evidence_keep_exact_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'package';source.mkdir()
            (source/'package-evidence.json').write_bytes(b'{"old":true}\n')
            (source/'signatures.json').write_bytes(b'original signatures\n')
            (source/'payload').mkdir();(source/'payload/file.bin').write_bytes(bytes(range(256)))
            maintenance=source/'maintenance';maintenance.mkdir()
            old=package.preserve_assembly_metadata(source,maintenance)
            self.assertEqual(len(old),2)
            self.assertFalse((source/'package-evidence.json').exists())
            self.assertEqual((maintenance/'prior-assembly/package-evidence.json').read_bytes(),b'{"old":true}\n')
            records=package.zip_package(source,root/'package.zip')
            with zipfile.ZipFile(root/'package.zip') as archive:
                self.assertEqual(sorted(archive.namelist()),sorted(records))
                self.assertEqual(archive.read('payload/file.bin'),bytes(range(256)))


if __name__=='__main__':
    unittest.main()
