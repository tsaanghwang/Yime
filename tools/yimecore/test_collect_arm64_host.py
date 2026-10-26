import ctypes
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock

from collect_arm64_host import get_machine_architecture, read_pe_machine, write_new_baseline


class MachineDetectionTests(unittest.TestCase):
    @staticmethod
    def api(process_machine, native_machine, success=1):
        api = mock.Mock()
        api.GetCurrentProcess.return_value = 123

        def query(handle, process, native):
            process._obj.value = process_machine
            native._obj.value = native_machine
            return success

        api.IsWow64Process2.side_effect = query
        return api

    def test_arm64_is_detected_despite_amd64_environment(self):
        with mock.patch.dict(os.environ, {"PROCESSOR_ARCHITECTURE": "AMD64"}):
            result = get_machine_architecture(self.api(0x8664, 0xAA64))
        self.assertEqual(result["native_architecture"], "arm64")
        self.assertEqual(result["process_machine_architecture"], "x64")

    def test_zero_process_machine_does_not_assert_interpreter_architecture(self):
        result = get_machine_architecture(self.api(0, 0xAA64))
        self.assertEqual(result["native_machine"], "0xaa64")
        self.assertIsNone(result["process_machine_architecture"])

    def test_environment_cannot_turn_an_x64_host_into_arm64(self):
        with mock.patch.dict(os.environ, {"PROCESSOR_ARCHITECTURE": "ARM64"}):
            self.assertEqual(get_machine_architecture(self.api(0, 0x8664))["native_architecture"], "x64")

    def test_failed_or_unknown_api_result_does_not_fall_back(self):
        for api in (self.api(0, 0xAA64, success=0), self.api(0, 0xFFFF)):
            with self.subTest(api=api), self.assertRaises(OSError):
                get_machine_architecture(api)

    def test_current_process_handle_is_pointer_sized(self):
        api = self.api(0, 0xAA64)
        get_machine_architecture(api)
        self.assertIs(api.GetCurrentProcess.restype, ctypes.c_void_p)


class EvidenceTests(unittest.TestCase):
    def test_pe_machine_is_observed_without_loading_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.exe"
            data = bytearray(70)
            data[:2] = b"MZ"
            struct.pack_into("<I", data, 0x3C, 64)
            data[64:68] = b"PE\x00\x00"
            struct.pack_into("<H", data, 68, 0x8664)
            path.write_bytes(data)
            self.assertEqual(read_pe_machine(path), {"machine": "0x8664", "architecture": "x64"})
            path.write_bytes(b"not a PE")
            with self.assertRaises(ValueError):
                read_pe_machine(path)

    def test_repeated_output_never_overwrites_prior_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            write_new_baseline(path, {"model": "华硕"})
            original = path.read_bytes()
            with self.assertRaises(FileExistsError):
                write_new_baseline(path, {"model": "changed"})
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(json.loads(original), {"model": "华硕"})


if __name__ == "__main__":
    unittest.main()
