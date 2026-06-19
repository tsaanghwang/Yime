from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
WORKSPACE_SETTINGS = ROOT / ".vscode" / "settings.json"
DEFAULT_EXTENSIONS_DIR = Path.home() / ".vscode" / "extensions"
EXTENSION_GLOB = "zknpr.sqlite-explorer-*"

ORIGINAL_BODY_FONT = (
    "var(--vscode-font-family, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif)"
)
PATCHED_BODY_FONT = (
    "var(--vscode-editor-font-family, var(--vscode-font-family, -apple-system, "
    "BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif))"
)
HTML_OVERRIDE = (
    'body{font-family:var(--vscode-editor-font-family, '
    'var(--vscode-font-family, -apple-system, BlinkMacSystemFont, "Segoe UI", '
    'Roboto, sans-serif))!important}'
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Patch the installed SQLite Explorer extension so its table/view webview "
            "inherits the VS Code editor font family."
        )
    )
    parser.add_argument(
        "--extensions-dir",
        type=Path,
        default=Path(os.environ.get("VSCODE_EXTENSIONS", DEFAULT_EXTENSIONS_DIR)),
        help="VS Code extensions directory. Default: %(default)s",
    )
    parser.add_argument(
        "--workspace-settings",
        type=Path,
        default=WORKSPACE_SETTINGS,
        help="Workspace settings JSON used for validation output. Default: %(default)s",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would change without writing files.",
    )
    return parser.parse_args()


def load_editor_font(settings_path: Path) -> str | None:
    if not settings_path.exists():
        return None
    payload = json.loads(settings_path.read_text(encoding="utf-8"))
    font_value = payload.get("editor.fontFamily")
    if isinstance(font_value, str):
        return font_value
    return None


def find_latest_extension_dir(extensions_dir: Path) -> Path:
    candidates = sorted(
        (path for path in extensions_dir.glob(EXTENSION_GLOB) if path.is_dir()),
        key=lambda path: path.name,
    )
    if not candidates:
        raise SystemExit(f"SQLite Explorer extension not found under: {extensions_dir}")
    return candidates[-1]


def patch_viewer_css(path: Path, dry_run: bool) -> str:
    content = path.read_text(encoding="utf-8")
    if PATCHED_BODY_FONT in content:
        return "already-patched"
    if ORIGINAL_BODY_FONT not in content:
        raise SystemExit(f"Unexpected viewer.css format, patch anchor not found: {path}")

    updated = content.replace(ORIGINAL_BODY_FONT, PATCHED_BODY_FONT, 1)
    if not dry_run:
        path.write_text(updated, encoding="utf-8")
    return "patched"


def patch_viewer_html(path: Path, dry_run: bool) -> str:
    content = path.read_text(encoding="utf-8")
    if HTML_OVERRIDE in content:
        return "already-patched"
    anchor = "\n    </style>"
    if anchor not in content:
        raise SystemExit(f"Unexpected viewer.html format, patch anchor not found: {path}")

    updated = content.replace(anchor, f"\n{HTML_OVERRIDE}{anchor}", 1)
    if not dry_run:
        path.write_text(updated, encoding="utf-8")
    return "patched"


def main() -> None:
    args = parse_args()
    extension_dir = find_latest_extension_dir(args.extensions_dir)
    viewer_css = extension_dir / "core" / "ui" / "viewer.css"
    viewer_html = extension_dir / "core" / "ui" / "viewer.html"

    if not viewer_css.exists() or not viewer_html.exists():
        raise SystemExit(f"SQLite Explorer UI assets not found under: {extension_dir}")

    editor_font = load_editor_font(args.workspace_settings)
    if editor_font:
        print(f"workspace_editor_font={editor_font}")
    else:
        print("workspace_editor_font=<missing>")

    print(f"sqlite_explorer_extension_dir={extension_dir}")
    css_status = patch_viewer_css(viewer_css, args.dry_run)
    html_status = patch_viewer_html(viewer_html, args.dry_run)
    print(f"viewer_css={css_status}")
    print(f"viewer_html={html_status}")

    if args.dry_run:
        print("font_patch_result=dry-run")
        return

    print("font_patch_result=ok")


if __name__ == "__main__":
    main()
