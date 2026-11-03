"""Offline source contracts only. This never runs the native probe."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parent


class SourceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cmake = (ROOT / "CMakeLists.txt").read_text(encoding="utf-8")
        cls.probe = (ROOT / "Probe.cpp").read_text(encoding="utf-8")
        cls.tool = (ROOT / "SyntheticTool.cpp").read_text(encoding="utf-8")
        cls.module = (ROOT / "SyntheticModule.cpp").read_text(encoding="utf-8")

    def test_standalone_arm64_project(self):
        self.assertIn("project(YimeArm64HandleProbe", self.cmake)
        self.assertIn('CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64"', self.cmake)
        self.assertNotIn("add_subdirectory(../../", self.cmake)

    def test_synthetic_a_b_targets(self):
        for target in ("YimeSyntheticToolA", "YimeSyntheticToolB"):
            self.assertIn(target, self.cmake)
        self.assertIn("foreach(marker IN ITEMS A B)", self.cmake)
        self.assertIn("add_library(YimeSyntheticModule${marker}", self.cmake)
        self.assertIn("SYNTHETIC_MARKER=${marker}", self.cmake)
        self.assertIn("SyntheticMarker", self.module)

    def test_exact_cli_and_no_path_search(self):
        for token in ('argc != 7', 'L"--pwsh"', 'L"--output"', 'L"--case"',
                      'L"probe-"', 'fs::exists(output)', 'L"pwsh.exe"'):
            self.assertIn(token, self.probe)
        self.assertIn("CreateProcessW(exe.c_str()", self.probe)
        self.assertNotIn("SearchPathW", self.probe)

    def test_native_pe_process_and_ntfs_guards(self):
        for token in ("IMAGE_FILE_MACHINE_ARM64", "IsWow64Process2", "DRIVE_FIXED",
                      'L"NTFS"', "FILE_ATTRIBUTE_REPARSE_POINT", "requireArm64Pe(pwsh)"):
            self.assertIn(token, self.probe)

    def test_one_handle_supplies_identity_and_hash(self):
        for token in ("FileIdInfo", "VolumeSerialNumber", "FileId.Identifier",
                      "GetFinalPathNameByHandleW", "sha256(h)"):
            self.assertIn(token, self.probe)
        self.assertRegex(self.probe, r"Handle h = openRead\(path, directory\);\s*return identify\(h\.value, directory\)")

    def test_share_conflicts_and_same_byte_replacement(self):
        self.assertIn("GENERIC_READ, FILE_SHARE_READ", self.probe)
        for token in ("MOVEFILE_WRITE_THROUGH",
                      "before.hash != after.hash", "before.fileId == after.fileId"):
            self.assertIn(token, self.probe)
        for token in ("ERROR_SHARING_VIOLATION", "GENERIC_WRITE", "DELETE", "MoveFileExW", "WRITE_ERROR=", "DELETE_ERROR="):
            self.assertIn(token, self.tool)

    def test_fresh_native_process_and_markers(self):
        for token in ("-NoProfile -NonInteractive -File", "Import-Module -LiteralPath",
                      "MODULE_MARKER=A", "MODULE_MARKER=B", "DLL_MARKER=A", "DLL_MARKER=B",
                      "TOOL_MARKER=A", "TOOL_MARKER=B", "nativeArm64(process.value)"):
            self.assertIn(token, self.probe)
        self.assertIn("LoadLibraryExW", self.tool)
        self.assertIn("GetMappedFileNameW", self.tool)

    def test_no_product_or_maintenance_apis(self):
        combined = self.probe + self.tool + self.module + self.cmake
        for forbidden in ("YimeTextService", "Product.psm1", "YimeRegistrar",
                          "RegSetValue", "RegDelete", "ShellExecute", "runas"):
            self.assertNotIn(forbidden, combined)


if __name__ == "__main__":
    unittest.main()
