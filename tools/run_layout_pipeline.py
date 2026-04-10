from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"

CONSISTENCY_SCRIPT = TOOLS / "check_layout_runtime_consistency.py"
RESOLVE_SCRIPT = TOOLS / "resolve_manual_key_layout.py"
GENERATE_KLC_SCRIPT = TOOLS / "generate_klc_from_manual_layout.py"
EXPORT_VISUAL_SCRIPT = TOOLS / "export_klc_visual_table.py"

DEFAULT_LAYOUT = ROOT / "internal_data" / "manual_key_layout.json"
DEFAULT_SYMBOLS = ROOT / "internal_data" / "key_to_symbol.json"
DEFAULT_RESOLVED_LAYOUT = ROOT / "internal_data" / "manual_key_layout.resolved.json"
DEFAULT_CONSISTENCY_REPORT = ROOT / "internal_data" / "layout_runtime_consistency_report.json"
DEFAULT_KLC_PATH = ROOT / "yinyuan.klc"
DEFAULT_MSKLC_PATH = Path(r"C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\MSKLC.exe")


def run_step(title: str, command: list[str]) -> None:
    print(f"[{title}] {' '.join(str(part) for part in command)}")
    subprocess.run(command, check=True, cwd=ROOT)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_warning_policy(args: argparse.Namespace) -> str:
    if args.fail_on_warning:
        return "stop"
    return args.on_warning


def prompt_on_warning(notes: list[str]) -> None:
    print("Consistency check reported warning status.")
    for note in notes:
        print(f"- {note}")

    if not sys.stdin.isatty():
        print("Warning policy is 'ask', but no interactive terminal is available. Pipeline stopped.")
        raise SystemExit(1)

    while True:
        answer = input("Warnings found. Continue anyway? [c]ontinue / [s]top: ").strip().lower()
        if answer in {"c", "continue"}:
            return
        if answer in {"s", "stop", "n", "no"}:
            print("Pipeline stopped by user after warning prompt.")
            raise SystemExit(1)
        print("Please answer 'c' / 'continue' or 's' / 'stop'.")


def resolve_open_policy(args: argparse.Namespace) -> str:
    return args.open_msklc


def prompt_open_msklc(klc_path: Path, msklc_path: Path) -> bool:
    print(f"Next step available: open {klc_path.name} in MSKLC.")
    print(f"MSKLC path: {msklc_path}")

    if not sys.stdin.isatty():
        print("Open policy is 'ask', but no interactive terminal is available. Skipping MSKLC launch.")
        return False

    while True:
        answer = input("Open the generated .klc in MSKLC now? [y/N]: ").strip().lower()
        if answer in {"", "n", "no"}:
            return False
        if answer in {"y", "yes"}:
            return True
        print("Please answer 'y' / 'yes' or 'n' / 'no'.")


def maybe_open_msklc(klc_path: Path, msklc_path: Path, open_policy: str) -> None:
    if open_policy == "never":
        print(f"Generated KLC is ready at {klc_path}")
        print(f"Next step: open it in MSKLC manually with {msklc_path}")
        return

    if sys.platform != "win32":
        print("MSKLC auto-open is only supported on Windows. Skipping launch.")
        print(f"Generated KLC is ready at {klc_path}")
        return

    if not klc_path.exists():
        raise SystemExit(f"Expected generated KLC file not found: {klc_path}")

    if not msklc_path.exists():
        message = f"MSKLC executable not found: {msklc_path}"
        if open_policy == "always":
            raise SystemExit(message)
        print(message)
        print(f"Generated KLC is ready at {klc_path}")
        return

    if open_policy == "ask" and not prompt_open_msklc(klc_path, msklc_path):
        print(f"Generated KLC is ready at {klc_path}")
        return

    subprocess.Popen([str(msklc_path), str(klc_path)], cwd=ROOT)
    print(f"Opened {klc_path.name} in MSKLC.")


def enforce_consistency_status(report_path: Path, warning_policy: str) -> None:
    report = load_json(report_path)
    status = report.get("status")
    notes = report.get("notes", [])
    issues = report.get("issues", [])

    if status == "error":
        print("Consistency check reported error status. Pipeline stopped.")
        for issue in issues:
            print(f"- {issue}")
        raise SystemExit(1)

    if status != "warning":
        return

    if warning_policy == "continue":
        print("Consistency check reported warning status. Continuing because --on-warning=continue.")
        for note in notes:
            print(f"- {note}")
        return

    if warning_policy == "stop":
        print("Consistency check reported warning status. Pipeline stopped.")
        for note in notes:
            print(f"- {note}")
        raise SystemExit(1)

    prompt_on_warning(notes)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the layout pipeline in order: consistency check, resolve manual layout, "
            "generate .klc, and optionally export the visual table."
        )
    )
    parser.add_argument("--layout", type=Path, default=DEFAULT_LAYOUT)
    parser.add_argument("--symbols", type=Path, default=DEFAULT_SYMBOLS)
    parser.add_argument("--resolved-layout", type=Path, default=DEFAULT_RESOLVED_LAYOUT)
    parser.add_argument(
        "--consistency-report",
        type=Path,
        default=DEFAULT_CONSISTENCY_REPORT,
        help=(
            "Path for the JSON report emitted by the consistency checker. "
            f"Default: {DEFAULT_CONSISTENCY_REPORT}"
        ),
    )
    parser.add_argument(
        "--ignore-stale-artifacts",
        action="store_true",
        help="Pass through to the consistency checker.",
    )
    parser.add_argument(
        "--symbol-mode",
        choices=("bmp-trial", "canonical"),
        default="bmp-trial",
        help="Pass through to the KLC generator. Default: bmp-trial",
    )
    parser.add_argument(
        "--ligature-mode",
        choices=("clean", "legacy"),
        default="clean",
        help="Pass through to the KLC generator. Default: clean",
    )
    parser.add_argument(
        "--keyboard-name",
        default="Yinyuan",
        help="Pass through to the KLC generator.",
    )
    parser.add_argument(
        "--keyboard-description",
        default="Chinese (Simplified) - Yinyuan",
        help="Pass through to the KLC generator.",
    )
    parser.add_argument(
        "--export-visual-table",
        action="store_true",
        help="Also export internal_data/klc_layout_visual_table.md after generating the KLC file.",
    )
    parser.add_argument(
        "--fail-on-warning",
        action="store_true",
        help="Legacy alias for --on-warning=stop.",
    )
    parser.add_argument(
        "--on-warning",
        choices=("continue", "stop", "ask"),
        default="continue",
        help="How to handle warning status from the consistency report. Default: continue",
    )
    parser.add_argument(
        "--open-msklc",
        choices=("ask", "always", "never"),
        default="ask",
        help="What to do with the generated .klc after the pipeline finishes. Default: ask",
    )
    parser.add_argument(
        "--msklc-path",
        type=Path,
        default=DEFAULT_MSKLC_PATH,
        help=f"Path to MSKLC.exe. Default: {DEFAULT_MSKLC_PATH}",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    python_executable = Path(sys.executable)
    warning_policy = resolve_warning_policy(args)
    open_policy = resolve_open_policy(args)

    consistency_command = [
        str(python_executable),
        str(CONSISTENCY_SCRIPT),
        "--layout",
        str(args.layout),
        "--symbols",
        str(args.symbols),
        "--resolved-layout",
        str(args.resolved_layout),
        "--json-output",
        str(args.consistency_report),
    ]
    if args.ignore_stale_artifacts:
        consistency_command.append("--ignore-stale-artifacts")

    resolve_command = [
        str(python_executable),
        str(RESOLVE_SCRIPT),
        "--layout",
        str(args.layout),
        "--symbols",
        str(args.symbols),
        "--output",
        str(args.resolved_layout),
    ]

    generate_klc_command = [
        str(python_executable),
        str(GENERATE_KLC_SCRIPT),
        "--symbol-mode",
        args.symbol_mode,
        "--ligature-mode",
        args.ligature_mode,
        "--keyboard-name",
        args.keyboard_name,
        "--keyboard-description",
        args.keyboard_description,
    ]

    run_step("1/4 consistency", consistency_command)
    enforce_consistency_status(args.consistency_report, warning_policy)
    run_step("2/4 resolve", resolve_command)
    run_step("3/4 generate-klc", generate_klc_command)

    if args.export_visual_table:
        export_visual_command = [str(python_executable), str(EXPORT_VISUAL_SCRIPT)]
        run_step("4/4 export-visual", export_visual_command)
    else:
        print("[4/4 export-visual] skipped")

    maybe_open_msklc(DEFAULT_KLC_PATH, args.msklc_path, open_policy)

    print("Layout pipeline completed.")


if __name__ == "__main__":
    main()
