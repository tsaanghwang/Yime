from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PACKAGE_DIR = ROOT / "releases" / "msklc-package"
DEFAULT_STAGE_DIR = Path(os.environ.get("ProgramData", r"C:\ProgramData")) / "Yinyuan-msklc-install"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Reset the local MSKLC install state so the system is ready for a clean reinstall or rebuild. "
            "This script separates cleanup from packaging and installation."
        )
    )
    parser.add_argument("--package-dir", type=Path, default=DEFAULT_PACKAGE_DIR)
    parser.add_argument(
        "--remove-machine-registration",
        choices=("ask", "always", "never"),
        default="always",
        help="Whether to remove the HKLM keyboard registration and system DLLs. Default: always",
    )
    parser.add_argument(
        "--restore-current-user",
        choices=("ask", "always", "never"),
        default="always",
        help="Whether to restore the current user to the default Chinese keyboard only. Default: always",
    )
    parser.add_argument(
        "--remove-stage-dir",
        choices=("ask", "always", "never"),
        default="ask",
        help="Whether to remove the staged MSI working directory under ProgramData. Default: ask",
    )
    parser.add_argument(
        "--stage-dir",
        type=Path,
        default=DEFAULT_STAGE_DIR,
        help=f"Stage directory to remove when requested. Default: {DEFAULT_STAGE_DIR}",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the planned cleanup actions without modifying the system.",
    )
    return parser.parse_args()


def ensure_windows() -> None:
    if sys.platform != "win32":
        raise SystemExit("This reset pipeline currently supports Windows only.")


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


def should_run(policy: str, prompt: str) -> bool:
    if policy == "always":
        return True
    if policy == "never":
        return False
    return prompt_yes_no(prompt)


def ensure_package_inputs(package_dir: Path) -> dict[str, Path]:
    required = {
        "restore_ps1": package_dir / "restore-default-chinese-keyboards.ps1",
        "unregister_ps1": package_dir / "unregister-yinyuan-machine.ps1",
    }
    missing = [str(path) for path in required.values() if not path.exists()]
    if missing:
        raise SystemExit("Missing required reset files:\n- " + "\n- ".join(missing))
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


def remove_stage_dir(stage_dir: Path, dry_run: bool) -> None:
    if not stage_dir.exists():
        print(f"Stage directory does not exist, skipping: {stage_dir}")
        return
    print(f"Removing stage directory: {stage_dir}")
    if dry_run:
        return
    shutil.rmtree(stage_dir)


def main() -> None:
    args = parse_args()
    ensure_windows()
    package_dir = args.package_dir.resolve()
    stage_dir = args.stage_dir.resolve()
    inputs = ensure_package_inputs(package_dir)

    print(f"Reset package directory: {package_dir}")

    if should_run(args.remove_machine_registration, "Remove machine-level Yinyuan registration and DLLs? [y/N]: "):
        exit_code = run_powershell_script(inputs["unregister_ps1"], args.dry_run)
        if exit_code != 0:
            raise SystemExit(f"Failed to remove machine-level Yinyuan registration. Exit code: {exit_code}")
    else:
        print("Skipping machine-level cleanup.")

    if should_run(args.restore_current_user, "Restore current user to the default Chinese keyboard only? [y/N]: "):
        exit_code = run_powershell_script(inputs["restore_ps1"], args.dry_run)
        if exit_code != 0:
            raise SystemExit(f"Failed to restore the current user keyboard state. Exit code: {exit_code}")
    else:
        print("Skipping current-user keyboard restore.")

    if should_run(args.remove_stage_dir, f"Remove staged MSI working directory {stage_dir}? [y/N]: "):
        remove_stage_dir(stage_dir, args.dry_run)
    else:
        print("Skipping staged MSI directory cleanup.")

    print("Reset pipeline completed.")
    print("Recommended next step: rerun the layout pipeline, then the packaging pipeline, then the install pipeline.")


if __name__ == "__main__":
    main()
