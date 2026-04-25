from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PACKAGE_DIR = ROOT / "releases" / "msklc-package"
DEFAULT_STAGE_DIR = Path(os.environ.get("ProgramData", r"C:\ProgramData")) / "Yinyuan-msklc-install"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the MSKLC install-stage controller: install from the packaged MSI output "
            "and optionally enable Yinyuan for the current user."
        )
    )
    parser.add_argument("--package-dir", type=Path, default=DEFAULT_PACKAGE_DIR)
    parser.add_argument(
        "--install-mode",
        choices=("auto", "msi"),
        default="auto",
        help="Install strategy. Both supported modes use the packaged MSI. Default: auto",
    )
    parser.add_argument(
        "--enable-current-user",
        choices=("ask", "always", "never"),
        default="ask",
        help="Whether to add Yinyuan as a current-user keyboard entry after machine-level install. Default: ask",
    )
    parser.add_argument(
        "--stage-dir",
        type=Path,
        default=DEFAULT_STAGE_DIR,
        help=f"Local staging directory for MSI install. Default: {DEFAULT_STAGE_DIR}",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the planned actions without modifying the system.",
    )
    return parser.parse_args()


def prompt_yes_no(prompt: str, default_no: bool = True) -> bool:
    if not sys.stdin.isatty():
        return False
    while True:
        answer = input(prompt).strip().lower()
        if not answer:
            return not default_no
        if answer in {"y", "yes"}:
            return True
        if answer in {"n", "no"}:
            return False
        print("Please answer 'y' / 'yes' or 'n' / 'no'.")


def ensure_windows() -> None:
    if sys.platform != "win32":
        raise SystemExit("This install pipeline currently supports Windows only.")


def ensure_package_inputs(package_dir: Path) -> dict[str, Path]:
    required = {
        "msi": package_dir / "Yinyuan_amd64.msi",
        "enable_ps1": package_dir / "enable-yinyuan-for-current-user.ps1",
        "restore_ps1": package_dir / "restore-default-chinese-keyboards.ps1",
        "unregister_ps1": package_dir / "unregister-yinyuan-machine.ps1",
    }
    missing = [str(path) for path in required.values() if not path.exists()]
    if missing:
        raise SystemExit("Missing required package files:\n- " + "\n- ".join(missing))
    return required


def run_command(command: list[str], dry_run: bool) -> int:
    print(" ".join(str(part) for part in command))
    if dry_run:
        return 0
    completed = subprocess.run(command, cwd=ROOT)
    return completed.returncode


def run_powershell_script(script_path: Path, dry_run: bool) -> int:
    command = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script_path),
    ]
    return run_command(command, dry_run)


def build_msi_installer_script() -> str:
    return r'''param(
    [string]$PackageDir,
    [string]$StageDir,
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Administrator {
    if (Test-IsAdministrator) {
        return
    }

    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $PSCommandPath)
        '-PackageDir'
        ('"{0}"' -f $PackageDir)
        '-StageDir'
        ('"{0}"' -f $StageDir)
        '-LogPath'
        ('"{0}"' -f $LogPath)
    )

    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($arguments -join ' ') -Wait -PassThru
    if ($null -eq $process) {
        throw 'Failed to launch the elevated MSI installer process.'
    }

    exit $process.ExitCode
}

Ensure-Administrator

$msiPath = Join-Path $PackageDir 'Yinyuan_amd64.msi'
$stagedMsiPath = Join-Path $StageDir 'Yinyuan_amd64.msi'
$stagedLogPath = Join-Path $StageDir 'install-amd64-admin.log'

if (-not (Test-Path -Path $msiPath)) {
    throw "MSI not found: $msiPath"
}

if (Test-Path -Path $StageDir) {
    Remove-Item -Path $StageDir -Recurse -Force
}

New-Item -Path $StageDir -ItemType Directory -Force | Out-Null
Copy-Item -Path (Join-Path $PackageDir '*') -Destination $StageDir -Recurse -Force

& icacls $StageDir /grant '*S-1-5-18:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null

& msiexec.exe /i $stagedMsiPath /l*v $stagedLogPath
$exitCode = $LASTEXITCODE

if (Test-Path -Path $stagedLogPath) {
    Copy-Item -Path $stagedLogPath -Destination $LogPath -Force
}

exit $exitCode
'''


def run_msi_install(package_dir: Path, stage_dir: Path, dry_run: bool) -> int:
    log_path = package_dir / "install-amd64-admin.log"
    with tempfile.NamedTemporaryFile("w", suffix=".ps1", encoding="utf-8", delete=False) as handle:
        handle.write(build_msi_installer_script())
        temp_script = Path(handle.name)

    command = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(temp_script),
        "-PackageDir",
        str(package_dir),
        "-StageDir",
        str(stage_dir),
        "-LogPath",
        str(log_path),
    ]

    try:
        return run_command(command, dry_run)
    finally:
        temp_script.unlink(missing_ok=True)


def maybe_enable_current_user(enable_policy: str, enable_script: Path, dry_run: bool) -> None:
    if enable_policy == "never":
        print("Skipping current-user keyboard enable step.")
        return

    if enable_policy == "ask":
        if not prompt_yes_no("Add Yinyuan as a current-user keyboard entry now? [y/N]: "):
            print("Current-user keyboard enable step skipped.")
            return

    exit_code = run_powershell_script(enable_script, dry_run)
    if exit_code != 0:
        raise SystemExit(f"Failed to enable Yinyuan for the current user. Exit code: {exit_code}")


def print_next_steps(package_dir: Path) -> None:
    print("Install pipeline completed.")
    print(f"Package directory: {package_dir}")
    print(f"Recommended rollback script: {package_dir / 'restore-default-chinese-keyboards.ps1'}")
    print(f"Recommended cleanup script before a full reinstall: {package_dir / 'unregister-yinyuan-machine.ps1'}")
    print("If the layout does not appear immediately, sign out and sign back in before concluding that install failed.")


def main() -> None:
    args = parse_args()
    ensure_windows()
    package_dir = args.package_dir.resolve()
    stage_dir = args.stage_dir.resolve()
    inputs = ensure_package_inputs(package_dir)

    print(f"Install mode: {args.install_mode}")
    print(f"Package directory: {package_dir}")

    if args.install_mode == "msi":
        exit_code = run_msi_install(package_dir, stage_dir, args.dry_run)
        if exit_code not in {0, 3010}:
            raise SystemExit(f"MSI install failed. Exit code: {exit_code}. Check {package_dir / 'install-amd64-admin.log'}")
    else:
        exit_code = run_msi_install(package_dir, stage_dir, args.dry_run)
        if exit_code in {0, 3010}:
            print("MSI install completed successfully.")
        else:
            raise SystemExit(f"MSI install failed. Exit code: {exit_code}. Check {package_dir / 'install-amd64-admin.log'}")

    maybe_enable_current_user(args.enable_current_user, inputs["enable_ps1"], args.dry_run)
    print_next_steps(package_dir)


if __name__ == "__main__":
    main()
