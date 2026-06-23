from __future__ import annotations

import argparse
from pathlib import Path
import unicodedata


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PATTERNS = ("*.md", "*.mdx")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Align pipe-style Markdown tables across the repository."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Files or directories to process. Defaults to the repository root.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Report files that would change without writing them.",
    )
    return parser.parse_args()


def iter_markdown_files(paths: list[Path]) -> list[Path]:
    if not paths:
        paths = [ROOT]

    files: list[Path] = []
    for raw_path in paths:
        path = raw_path if raw_path.is_absolute() else ROOT / raw_path
        if path.is_file() and path.suffix.lower() in {".md", ".mdx"}:
            files.append(path)
            continue
        if not path.exists():
            raise SystemExit(f"Path not found: {raw_path}")
        if path.is_dir():
            for pattern in DEFAULT_PATTERNS:
                files.extend(path.rglob(pattern))
    return sorted({file.resolve() for file in files})


def is_table_row(line: str) -> bool:
    stripped = line.strip()
    return stripped.startswith("|") and stripped.count("|") >= 2


def is_separator_row(line: str) -> bool:
    cells = parse_row(line)
    if not cells:
        return False
    for cell in cells:
        token = cell.strip()
        if not token:
            return False
        if any(ch not in "-: " for ch in token):
            return False
        if token.replace(":", "").strip("-"):
            return False
        if token.count("-") < 3:
            return False
    return True


def parse_row(line: str) -> list[str]:
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return []

    inner = stripped[1:-1]
    cells: list[str] = []
    current: list[str] = []
    escaped = False

    for char in inner:
        if escaped:
            current.append(char)
            escaped = False
            continue
        if char == "\\":
            current.append(char)
            escaped = True
            continue
        if char == "|":
            cells.append("".join(current).strip())
            current = []
            continue
        current.append(char)

    if escaped:
        escaped = False
    cells.append("".join(current).strip())
    return cells


def separator_alignment(cell: str) -> tuple[bool, bool]:
    token = cell.strip()
    return token.startswith(":"), token.endswith(":")


def display_width(text: str) -> int:
    width = 0
    for char in text:
        if unicodedata.combining(char):
            continue
        width += 2 if unicodedata.east_asian_width(char) in {"F", "W"} else 1
    return width


def pad_cell(text: str, width: int) -> str:
    padding = width - display_width(text)
    if padding <= 0:
        return text
    return text + (" " * padding)


def format_separator(width: int, left_aligned: bool, right_aligned: bool) -> str:
    dash_count = max(3, width)
    if left_aligned and right_aligned:
        if dash_count == 3:
            return ":-:"
        return ":" + ("-" * (dash_count - 2)) + ":"
    if left_aligned:
        return ":" + ("-" * (dash_count - 1))
    if right_aligned:
        return ("-" * (dash_count - 1)) + ":"
    return "-" * dash_count


def format_table(rows: list[str]) -> list[str]:
    parsed_rows = [parse_row(row) for row in rows]
    column_count = max(len(row) for row in parsed_rows)
    normalized_rows = [row + [""] * (column_count - len(row)) for row in parsed_rows]
    widths = [max(display_width(row[index]) for row in normalized_rows) for index in range(column_count)]

    separator_cells = normalized_rows[1]
    output: list[str] = []
    for row_index, row in enumerate(normalized_rows):
        if row_index == 1:
            cells = []
            for index, cell in enumerate(row):
                left_aligned, right_aligned = separator_alignment(separator_cells[index])
                cells.append(format_separator(widths[index], left_aligned, right_aligned))
            output.append("| " + " | ".join(cells) + " |")
            continue

        padded = [pad_cell(row[index], widths[index]) for index in range(column_count)]
        output.append("| " + " | ".join(padded) + " |")
    return output


def align_tables(text: str) -> str:
    lines = text.splitlines()
    updated: list[str] = []
    index = 0

    while index < len(lines):
        if (
            index + 1 < len(lines)
            and is_table_row(lines[index])
            and is_separator_row(lines[index + 1])
        ):
            block_end = index + 2
            while block_end < len(lines) and is_table_row(lines[block_end]):
                block_end += 1
            updated.extend(format_table(lines[index:block_end]))
            index = block_end
            continue

        updated.append(lines[index])
        index += 1

    suffix = "\n" if text.endswith("\n") else ""
    return "\n".join(updated) + suffix


def process_file(path: Path, check: bool) -> bool:
    original = path.read_text(encoding="utf-8")
    aligned = align_tables(original)
    if aligned == original:
        return False
    if not check:
        path.write_text(aligned, encoding="utf-8")
    return True


def main() -> None:
    args = parse_args()
    files = iter_markdown_files(args.paths)
    changed_files = [path for path in files if process_file(path, check=args.check)]

    for path in changed_files:
        print(path.relative_to(ROOT).as_posix())

    if args.check and changed_files:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
