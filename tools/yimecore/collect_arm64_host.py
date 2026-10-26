"""Collect a read-only Windows ARM64 host baseline; never run product binaries.

The native machine reported by IsWow64Process2 is authoritative here. Environment
variables and platform.machine() are observations only: x64 emulation can expose
AMD64 on an ARM64 Windows host. A zero processMachine does not prove that the
interpreter's executable is ARM64; its PE header is recorded separately.
"""

import argparse
import ctypes
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import sys


MACHINE_NAMES = {0x014C: "x86", 0x8664: "x64", 0xAA64: "arm64", 0xA641: "arm64ec"}


def get_machine_architecture(kernel32=None):
    """Return native Windows architecture, failing closed if the API is unavailable.

    Callers may gate ARM64 execution on native_architecture == "arm64". Do not
    use process_machine == "0x0000" as proof of native executable architecture.
    The optional API object allows deterministic tests without probing a host.
    """
    if kernel32 is None:
        if os.name != "nt":
            raise NotImplementedError("Native machine detection requires Windows")
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.GetCurrentProcess.argtypes = []
    kernel32.GetCurrentProcess.restype = ctypes.c_void_p
    kernel32.IsWow64Process2.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_ushort),
        ctypes.POINTER(ctypes.c_ushort),
    ]
    kernel32.IsWow64Process2.restype = ctypes.c_int
    process_machine = ctypes.c_ushort()
    native_machine = ctypes.c_ushort()
    if not kernel32.IsWow64Process2(
        kernel32.GetCurrentProcess(), ctypes.byref(process_machine), ctypes.byref(native_machine)
    ):
        raise OSError("IsWow64Process2 failed; native architecture is unverified")
    if native_machine.value not in MACHINE_NAMES:
        raise OSError(f"Unrecognized native machine: 0x{native_machine.value:04x}")
    return {
        "source": "IsWow64Process2",
        "native_machine": f"0x{native_machine.value:04x}",
        "native_architecture": MACHINE_NAMES[native_machine.value],
        "process_machine": f"0x{process_machine.value:04x}",
        "process_machine_architecture": MACHINE_NAMES.get(process_machine.value),
        "process_machine_note": "A zero processMachine does not establish the executable's PE architecture.",
    }


def read_pe_machine(path):
    """Read just DOS/PE headers; do not load or execute the binary."""
    with Path(path).open("rb") as stream:
        dos = stream.read(64)
        if len(dos) != 64 or dos[:2] != b"MZ":
            raise ValueError("Invalid DOS header")
        offset = struct.unpack_from("<I", dos, 0x3C)[0]
        if offset < 64 or offset > 16 * 1024 * 1024:
            raise ValueError("Invalid PE header offset")
        stream.seek(offset)
        header = stream.read(6)
        if len(header) != 6 or header[:4] != b"PE\x00\x00":
            raise ValueError("Invalid PE signature")
        machine = struct.unpack_from("<H", header, 4)[0]
    return {"machine": f"0x{machine:04x}", "architecture": MACHINE_NAMES.get(machine, "unknown")}


def read_registry_baseline():
    import winreg

    fields = {
        "hardware": (r"HARDWARE\DESCRIPTION\System\BIOS", {
            "manufacturer": "SystemManufacturer", "model": "SystemProductName",
            "family": "SystemFamily",
        }),
        "cpu": (r"HARDWARE\DESCRIPTION\System\CentralProcessor\0", {
            "name": "ProcessorNameString", "identifier": "Identifier",
            "vendor": "VendorIdentifier",
        }),
        "windows": (r"SOFTWARE\Microsoft\Windows NT\CurrentVersion", {
            "product_name": "ProductName", "display_version": "DisplayVersion",
            "build_number": "CurrentBuildNumber", "update_build_revision": "UBR",
            "edition": "EditionID", "installation_type": "InstallationType",
        }),
    }
    result = {}
    errors = []
    for section, (key_name, values) in fields.items():
        result[section] = {}
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key_name, 0,
                                winreg.KEY_READ | winreg.KEY_WOW64_64KEY) as key:
                for name, value_name in values.items():
                    try:
                        result[section][name] = winreg.QueryValueEx(key, value_name)[0]
                    except OSError as error:
                        result[section][name] = None
                        errors.append(f"{section}.{name}: {type(error).__name__}")
        except OSError as error:
            errors.append(f"{section}: {type(error).__name__}")
    result["read_errors"] = errors
    return result


def total_physical_memory():
    class MemoryStatus(ctypes.Structure):
        _fields_ = [("length", ctypes.c_uint32), ("load", ctypes.c_uint32)] + [
            (name, ctypes.c_uint64) for name in (
                "total_physical", "available_physical", "total_page_file",
                "available_page_file", "total_virtual", "available_virtual", "available_extended_virtual",
            )
        ]

    status = MemoryStatus()
    status.length = ctypes.sizeof(status)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.GlobalMemoryStatusEx.argtypes = [ctypes.POINTER(MemoryStatus)]
    kernel32.GlobalMemoryStatusEx.restype = ctypes.c_int
    if not kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
        raise OSError("GlobalMemoryStatusEx failed")
    return status.total_physical


def discover_tools():
    """Check PATH and explicit conventional install locations; no recursive search."""
    roots = {Path("C:/Program Files"), Path("C:/Program Files (x86)")}
    for name in ("ProgramFiles", "ProgramFiles(x86)", "ProgramW6432"):
        if os.environ.get(name):
            roots.add(Path(os.environ[name]))
    specifications = {
        "go": [root / "Go/bin/go.exe" for root in roots],
        "cmake": [root / "CMake/bin/cmake.exe" for root in roots],
        "git": [root / "Git/cmd/git.exe" for root in roots],
        "pwsh": [root / "PowerShell/7/pwsh.exe" for root in roots],
        "vswhere": [root / "Microsoft Visual Studio/Installer/vswhere.exe" for root in roots],
        "cl": [],
    }
    arm64_compilers = []
    windows_sdk_headers = []
    for root in sorted(roots):
        for year in ("2022", "2026", "18"):
            for edition in ("BuildTools", "Community", "Professional", "Enterprise"):
                visual_studio = root / "Microsoft Visual Studio" / year / edition
                specifications["cmake"].append(
                    visual_studio / "Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe"
                )
                for host in ("Hostarm64", "Hostx64"):
                    arm64_compilers.extend(
                        visual_studio.glob(f"VC/Tools/MSVC/*/bin/{host}/arm64/cl.exe")
                    )
        windows_sdk_headers.extend((root / "Windows Kits/10/Include").glob("*/um/Windows.h"))
    found = {}
    for name, candidates in specifications.items():
        path_match = shutil.which(name)
        matches = {str(path) for path in candidates if path.is_file()}
        if path_match:
            matches.add(path_match)
        found[name] = {"path_match": path_match, "found_paths": sorted(matches)}
    return {
        "discovery_scope": "PATH plus explicit standard install directories; absence is not proof that no custom installation exists.",
        "executed_tools": [],
        "commands": found,
        "arm64_compiler_paths": sorted(str(path) for path in arm64_compilers if path.is_file()),
        "windows_sdk_header_paths": sorted(str(path) for path in windows_sdk_headers if path.is_file()),
    }


def collect_baseline(source_commit=None):
    architecture = get_machine_architecture()
    registry = read_registry_baseline()
    version = sys.getwindowsversion()
    return {
        "schema_version": "yimecore-arm64-host-baseline-v1",
        "observed_at_utc": datetime.now(timezone.utc).isoformat(),
        "affected_product": "YimeCore",
        "source_commit_supplied_by_caller": source_commit,
        "computer_name": platform.node(),
        "architecture": architecture,
        "process_observations": {
            "platform_machine": platform.machine(),
            "processor_architecture_environment": os.environ.get("PROCESSOR_ARCHITECTURE"),
            "processor_architew6432_environment": os.environ.get("PROCESSOR_ARCHITEW6432"),
            "python_executable": sys.executable,
            "python_pe": read_pe_machine(sys.executable),
            "note": "Process observations do not override the nativeMachine API result.",
        },
        "hardware": registry["hardware"],
        "cpu": {**registry["cpu"], "logical_processor_count": os.cpu_count()},
        "total_physical_memory_bytes": total_physical_memory(),
        "windows": {
            **registry["windows"],
            "getwindowsversion": {"major": version.major, "minor": version.minor, "build": version.build},
            "note": "Registry product_name may retain a legacy Windows product label; record build separately.",
        },
        "registry_read_errors": registry["read_errors"],
        "tools": discover_tools(),
        "evidence": {
            "arm64_host_identified": architecture["native_architecture"] == "arm64",
            "current_source_build_passed": None,
            "native_product_contracts_passed": None,
            "target_package_passed": None,
            "installed_registered_host_passed": None,
            "physical_live_host_passed": None,
            "daily_use_and_sealing_passed": None,
            "product_binaries_executed": False,
            "installation_performed": False,
            "registration_changed": False,
            "default_input_changed": False,
            "user_data_changed": False,
            "release_ready": False,
        },
    }


def write_new_baseline(path, baseline):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as output:
        json.dump(baseline, output, ensure_ascii=False, indent=2)
        output.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="New JSON file; existing evidence is never overwritten")
    parser.add_argument("--source-commit", help="Optional full 40-character source commit supplied by the caller")
    args = parser.parse_args()
    if args.source_commit and not re.fullmatch(r"[0-9a-fA-F]{40}", args.source_commit):
        parser.error("--source-commit must be a full 40-character hexadecimal commit")
    if args.output.exists():
        parser.error("output already exists; use a new evidence path")
    try:
        baseline = collect_baseline(args.source_commit)
        write_new_baseline(args.output, baseline)
    except (OSError, ValueError, NotImplementedError, AttributeError) as error:
        print(f"ARM64 host collection failed: {error}", file=sys.stderr)
        return 1
    print(f"Collected {baseline['computer_name']} native {baseline['architecture']['native_architecture']}: {args.output}")
    print("Host identification only; no product build, execution, registration, or installation acceptance.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
