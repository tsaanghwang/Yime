from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

DEFAULT_KLC_PATH = ROOT / "yinyuan.klc"
DEFAULT_MSKLC_PATH = Path(r"C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\MSKLC.exe")
DEFAULT_PACKAGE_DIR = ROOT / "releases" / "msklc-package"
DEFAULT_AMD64_DIR = ROOT / "releases" / "msklc-amd64"
DEFAULT_WOW64_DIR = ROOT / "releases" / "msklc-wow64"

EXPECTED_FILES = [
    "setup.exe",
    "Yinyuan_amd64.msi",
    "Yinyuan_i386.msi",
    "Yinyuan_ia64.msi",
]
EXPECTED_DIRS = ["amd64", "i386", "ia64", "wow64"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the MSKLC packaging-stage controller: optionally open the generated .klc in MSKLC, "
            "guide the GUI packaging step, then sync package outputs back into releases/."
        )
    )
    parser.add_argument("--klc", type=Path, default=DEFAULT_KLC_PATH)
    parser.add_argument("--msklc-path", type=Path, default=DEFAULT_MSKLC_PATH)
    parser.add_argument(
        "--open-msklc",
        choices=("ask", "always", "never"),
        default="ask",
        help="What to do with the .klc before packaging. Default: ask",
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=None,
        help="MSKLC GUI output folder containing setup.exe/MSI/DLLs. If omitted, the script will try common locations or ask.",
    )
    parser.add_argument("--package-dir", type=Path, default=DEFAULT_PACKAGE_DIR)
    parser.add_argument("--amd64-dir", type=Path, default=DEFAULT_AMD64_DIR)
    parser.add_argument("--wow64-dir", type=Path, default=DEFAULT_WOW64_DIR)
    return parser.parse_args()


def existing_source_candidates() -> list[Path]:
    candidates = [
        ROOT / "yinyuan",
        ROOT / "releases" / "msklc-package",
        ROOT.parent / "文档" / "yinyuan",
        Path.home() / "Documents" / "yinyuan",
        Path.home() / "OneDrive" / "Documents" / "yinyuan",
        Path.home() / "OneDrive" / "文档" / "yinyuan",
    ]
    seen = []
    for candidate in candidates:
        if candidate not in seen:
            seen.append(candidate)
    return seen


def package_source_looks_valid(path: Path) -> bool:
    if not path.exists() or not path.is_dir():
        return False
    return all((path / name).exists() for name in EXPECTED_FILES) and all((path / name).is_dir() for name in EXPECTED_DIRS)


def describe_manual_steps(klc_path: Path) -> None:
    print("Next packaging steps in MSKLC:")
    print(f"1. Open {klc_path}")
    print("2. In MSKLC, verify the layout visually")
    print("3. Click 'Project' -> 'Build DLL and Setup Package'")
    print("4. Wait for setup.exe, MSI files, and amd64/wow64 DLL folders to appear")


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


def maybe_open_msklc(klc_path: Path, msklc_path: Path, open_policy: str) -> None:
    if open_policy == "never":
        return

    if sys.platform != "win32":
        print("MSKLC auto-open is only supported on Windows. Skipping launch.")
        return

    if not msklc_path.exists():
        raise SystemExit(f"MSKLC executable not found: {msklc_path}")

    if open_policy == "ask":
        should_open = prompt_yes_no("Open the .klc in MSKLC now? [y/N]: ")
        if not should_open:
            return

    subprocess.Popen([str(msklc_path), str(klc_path)], cwd=ROOT)
    print(f"Opened {klc_path.name} in MSKLC.")


def resolve_source_dir(args: argparse.Namespace) -> Path:
    if args.source_dir is not None:
        source_dir = args.source_dir.resolve()
        if not package_source_looks_valid(source_dir):
            raise SystemExit(f"Specified source directory does not look like an MSKLC package output folder: {source_dir}")
        return source_dir

    for candidate in existing_source_candidates():
        if package_source_looks_valid(candidate):
            print(f"Using detected MSKLC package source: {candidate}")
            return candidate

    if not sys.stdin.isatty():
        raise SystemExit(
            "No MSKLC package source directory was found automatically. Re-run with --source-dir <path> after GUI packaging finishes."
        )

    while True:
        raw = input("Enter the MSKLC package output folder path (or leave empty to stop): ").strip()
        if not raw:
            raise SystemExit("Packaging pipeline stopped before syncing outputs.")
        candidate = Path(raw).expanduser().resolve()
        if package_source_looks_valid(candidate):
            return candidate
        print("That folder does not look like a complete MSKLC package output. Expected setup.exe/MSI files and amd64/i386/ia64/wow64 subfolders.")


def copy_tree_contents(source_dir: Path, target_dir: Path) -> None:
    target_dir.mkdir(parents=True, exist_ok=True)
    for child in source_dir.iterdir():
        destination = target_dir / child.name
        if child.is_dir():
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(child, destination)
        else:
            shutil.copy2(child, destination)


def sync_outputs(source_dir: Path, package_dir: Path, amd64_dir: Path, wow64_dir: Path) -> None:
    if source_dir.resolve() != package_dir.resolve():
        copy_tree_contents(source_dir, package_dir)
        print(f"Synced package directory to {package_dir}")
    else:
        print(f"Package directory already points at {package_dir}; skipping full directory copy.")

    amd64_dir.mkdir(parents=True, exist_ok=True)
    wow64_dir.mkdir(parents=True, exist_ok=True)

    shutil.copy2(source_dir / "amd64" / "Yinyuan.dll", amd64_dir / "Yinyuan.dll")
    print(f"Synced amd64 DLL to {amd64_dir / 'Yinyuan.dll'}")

    shutil.copy2(source_dir / "wow64" / "Yinyuan.dll", wow64_dir / "Yinyuan.dll")
    print(f"Synced wow64 DLL to {wow64_dir / 'Yinyuan.dll'}")


def main() -> None:
    args = parse_args()
    klc_path = args.klc.resolve()
    if not klc_path.exists():
        raise SystemExit(f"KLC file not found: {klc_path}")

    maybe_open_msklc(klc_path, args.msklc_path, args.open_msklc)
    describe_manual_steps(klc_path)

    if args.source_dir is None and not any(package_source_looks_valid(candidate) for candidate in existing_source_candidates()):
        if sys.stdin.isatty():
            ready = prompt_yes_no("Have you finished 'Build DLL and Setup Package' in MSKLC? [y/N]: ")
            if not ready:
                raise SystemExit("Packaging pipeline stopped before syncing outputs.")

    source_dir = resolve_source_dir(args)
    sync_outputs(source_dir, args.package_dir.resolve(), args.amd64_dir.resolve(), args.wow64_dir.resolve())

    print("MSKLC packaging pipeline completed.")
    print(f"Package output: {args.package_dir.resolve()}")
    print(f"Recommended next step: run {ROOT / 'tools' / 'run_msklc_install_pipeline.py'} to install from the packaged MSI output.")


if __name__ == "__main__":
    main()
