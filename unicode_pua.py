"""
创建一个模块检测字体中Unicode私用区(PUA)的占用情况。
1. 扫描字体文件中的所有字符
2. 检查每个字符是否在Unicode私用区(PUA)范围
3. 生成报告显示哪些码点被占用
"""

from typing import Dict, List
import argparse
import importlib.util
import os
import subprocess
import sys
from tqdm import tqdm


COMMON_WINDOWS_FONT_NAMES = [
    'seguisym.ttf',
    'SegoeIcons.ttf',
    'seguiemj.ttf',
    'segoeui.ttf',
    'SegUIVar.ttf',
    'consola.ttf',
    'calibri.ttf',
    'cambria.ttc',
    'arial.ttf',
    'times.ttf',
    'simsun.ttc',
    'simhei.ttf',
    'msyh.ttc',
    'msgothic.ttc',
    'malgun.ttf',
]


def is_pua_codepoint(codepoint: int) -> bool:
    """检查码点是否在Unicode私用区(PUA)范围内"""
    # Unicode PUA范围:
    # U+E000-U+F8FF (私用区)
    # U+F0000-U+FFFFD (补充私用区-A)
    # U+100000-U+10FFFD (补充私用区-B)
    return (0xE000 <= codepoint <= 0xF8FF or
            0xF0000 <= codepoint <= 0xFFFFD or
            0x100000 <= codepoint <= 0x10FFFD)


def scan_font_pua(font_path: str) -> Dict[str, List[int]]:
    """
    扫描字体文件中的PUA字符
    返回字典包含:
    - 'pua_codepoints': 所有PUA码点列表
    - 'pua_glyphs': 对应的字形名称列表
    """
    if _has_fonttools():
        pua_codepoints, pua_glyphs = _scan_font_with_fonttools(font_path)
    elif os.name == 'nt':
        pua_codepoints, pua_glyphs = _scan_font_with_powershell(font_path)
    else:
        raise RuntimeError(
            "未安装 fontTools，且当前平台不是 Windows，无法扫描字体。"
        )

    return {
        'pua_codepoints': pua_codepoints,
        'pua_glyphs': pua_glyphs
    }


def _scan_font_with_fonttools(font_path: str) -> tuple[List[int], List[str]]:
    """使用 fontTools 扫描字体 cmap。"""
    ttlib_module = importlib.import_module("fontTools.ttLib")
    ttfont_class = ttlib_module.TTFont

    font = ttfont_class(font_path)
    glyph_by_codepoint: Dict[int, str] = {}

    # 同一码点可能出现在多个 cmap 子表中，这里只保留首个结果。
    for cmap in font['cmap'].tables:
        for codepoint, glyph_name in cmap.cmap.items():
            if is_pua_codepoint(codepoint) and codepoint not in glyph_by_codepoint:
                glyph_by_codepoint[codepoint] = glyph_name

    pua_codepoints = sorted(glyph_by_codepoint)
    pua_glyphs = [glyph_by_codepoint[codepoint] for codepoint in pua_codepoints]
    return pua_codepoints, pua_glyphs


def _scan_font_with_powershell(font_path: str) -> tuple[List[int], List[str]]:
    """在 Windows 上通过 WPF GlyphTypeface 扫描字体 cmap。"""
    normalized_path = os.path.abspath(font_path).replace('\\', '/')
    powershell_script = f"""
Add-Type -AssemblyName PresentationCore
$font = New-Object System.Windows.Media.GlyphTypeface('file:///{normalized_path}')
$font.CharacterToGlyphMap.GetEnumerator() |
    ForEach-Object {{
        if ({_python_pua_filter_expression()}) {{
            '{{0:X}};gid{{1}}' -f $_.Key, $_.Value
        }}
    }}
""".strip()

    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", powershell_script],
        capture_output=True,
        text=True,
        check=True,
    )

    glyph_by_codepoint: Dict[int, str] = {}
    for line in completed.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        codepoint_hex, glyph_name = line.split(';', 1)
        codepoint = int(codepoint_hex, 16)
        glyph_by_codepoint[codepoint] = glyph_name

    pua_codepoints = sorted(glyph_by_codepoint)
    pua_glyphs = [glyph_by_codepoint[codepoint] for codepoint in pua_codepoints]
    return pua_codepoints, pua_glyphs


def _python_pua_filter_expression() -> str:
    """返回供 PowerShell 使用的 PUA 过滤表达式。"""
    return (
        "($_.Key -ge 0xE000 -and $_.Key -le 0xF8FF) -or "
        "($_.Key -ge 0xF0000 -and $_.Key -le 0xFFFFD) -or "
        "($_.Key -ge 0x100000 -and $_.Key -le 0x10FFFD)"
    )


def _has_fonttools() -> bool:
    """检查当前环境中是否可用 fontTools。"""
    return importlib.util.find_spec("fontTools") is not None


def _configure_stdio() -> None:
    """尽量统一为 UTF-8 输出，减少 Windows 终端乱码。"""
    for stream_name in ('stdout', 'stderr'):
        stream = getattr(sys, stream_name, None)
        reconfigure = getattr(stream, 'reconfigure', None)
        if callable(reconfigure):
            reconfigure(encoding='utf-8', errors='replace')


def _format_codepoint(codepoint: int) -> str:
    """格式化码点，BMP 用 4 位，其余按实际宽度输出。"""
    width = 4 if codepoint <= 0xFFFF else 6
    return f"U+{codepoint:0{width}X}"


def _build_ranges(codepoints: List[int]) -> List[tuple[int, int]]:
    """将码点列表压缩为连续区间。"""
    if not codepoints:
        return []

    sorted_codepoints = sorted(set(codepoints))
    ranges: List[tuple[int, int]] = []
    start = sorted_codepoints[0]
    prev = sorted_codepoints[0]

    for current in sorted_codepoints[1:]:
        if current == prev + 1:
            prev = current
            continue
        ranges.append((start, prev))
        start = current
        prev = current

    ranges.append((start, prev))
    return ranges


def _format_ranges(ranges: List[tuple[int, int]]) -> List[str]:
    """格式化区间列表。"""
    formatted_ranges = []
    for start, end in ranges:
        if start == end:
            formatted_ranges.append(_format_codepoint(start))
        else:
            formatted_ranges.append(f"{_format_codepoint(start)}-{_format_codepoint(end)}")
    return formatted_ranges


def _build_safe_pua_ranges(used_codepoints: List[int]) -> List[tuple[int, int]]:
    """基于 BMP PUA 已占用码点计算相对安全的空白区间。"""
    used_bmp_pua = sorted({codepoint for codepoint in used_codepoints if 0xE000 <= codepoint <= 0xF8FF})
    if not used_bmp_pua:
        return [(0xE000, 0xF8FF)]

    safe_ranges: List[tuple[int, int]] = []
    next_start = 0xE000
    for codepoint in used_bmp_pua:
        if codepoint > next_start:
            safe_ranges.append((next_start, codepoint - 1))
        next_start = max(next_start, codepoint + 1)

    if next_start <= 0xF8FF:
        safe_ranges.append((next_start, 0xF8FF))
    return safe_ranges


def generate_pua_report(font_path: str) -> str:
    """生成PUA占用情况报告"""
    result = scan_font_pua(font_path)
    if not result['pua_codepoints']:
        return f"字体文件: {font_path}\n未发现PUA码点"

    report_lines = [
        f"字体文件: {font_path}",
        f"PUA码点总数: {len(result['pua_codepoints'])}",
        "\n占用的PUA码点:"
    ]

    for codepoint, glyph_name in zip(result['pua_codepoints'], result['pua_glyphs']):
        report_lines.append(f"{_format_codepoint(codepoint)} ({glyph_name})")

    return "\n".join(report_lines)


def get_system_fonts() -> List[str]:
    """获取Windows系统字体目录中的所有字体文件"""
    font_dirs = [
        os.path.join(os.environ['WINDIR'], 'Fonts'),
        os.path.join(os.environ['LOCALAPPDATA'],
                     'Microsoft', 'Windows', 'Fonts')
    ]

    font_files = []
    for font_dir in font_dirs:
        if os.path.exists(font_dir):
            for file in os.listdir(font_dir):
                if file.lower().endswith(('.ttf', '.otf', '.ttc')):
                    font_files.append(os.path.join(font_dir, file))
    return font_files


def get_common_windows_fonts() -> List[str]:
    """获取会影响常见编辑器 fallback 的常用 Windows 字体。"""
    name_to_path = {
        os.path.basename(font_path).lower(): font_path
        for font_path in get_system_fonts()
    }
    return [
        name_to_path[font_name.lower()]
        for font_name in COMMON_WINDOWS_FONT_NAMES
        if font_name.lower() in name_to_path
    ]


def generate_common_windows_pua_report() -> str:
    """生成常见 Windows 字体的 PUA 占用和 BMP 安全区间报告。"""
    font_paths = get_common_windows_fonts()
    if not font_paths:
        return "未找到预设的常见 Windows 字体。"

    per_font_reports = []
    used_codepoints: List[int] = []

    for font_path in font_paths:
        scan_result = scan_font_pua(font_path)
        pua_codepoints = scan_result['pua_codepoints']
        used_codepoints.extend(pua_codepoints)
        ranges = _format_ranges(_build_ranges(pua_codepoints))
        per_font_reports.append(
            "\n".join([
                f"字体文件: {font_path}",
                f"PUA码点总数: {len(pua_codepoints)}",
                "占用区间: " + (", ".join(ranges) if ranges else "无"),
            ])
        )

    used_range_strings = _format_ranges(_build_ranges(used_codepoints))
    safe_range_strings = _format_ranges(_build_safe_pua_ranges(used_codepoints))

    summary_lines = [
        "常见 Windows 字体 BMP PUA 占用汇总",
        f"字体数量: {len(font_paths)}",
        f"BMP PUA 并集码点数: {len(set(codepoint for codepoint in used_codepoints if 0xE000 <= codepoint <= 0xF8FF))}",
        "已占用区间:",
        ", ".join(used_range_strings) if used_range_strings else "无",
        "",
        "相对安全区间:",
        ", ".join(safe_range_strings) if safe_range_strings else "无",
        "",
        "各字体详情:",
        "",
        "\n\n".join(per_font_reports),
    ]
    return "\n".join(summary_lines)


def append_report(output_path: str, report: str) -> None:
    """以 UTF-8 追加写入报告。"""
    with open(output_path, 'a', encoding='utf-8') as summary_file:
        summary_file.write(report + "\n" + "=" * 50 + "\n\n")


def prompt_scan_mode() -> str | None:
    """无参数运行时提示用户选择扫描模式。"""
    prompt_lines = [
        "请选择扫描模式:",
        "1. 输入指定字体文件路径",
        "2. 扫描所有字体文件",
        "3. 退出，不扫描",
    ]

    while True:
        print("\n".join(prompt_lines))
        try:
            choice = input("请输入选项编号(1/2/3): ").strip()
        except EOFError:
            print("未检测到终端输入，已退出，未执行扫描。", file=sys.stderr)
            return None

        if choice == '1':
            try:
                font_path = input("请输入字体文件路径: ").strip().strip('"')
            except EOFError:
                print("未检测到字体路径输入，已退出，未执行扫描。", file=sys.stderr)
                return None
            if font_path:
                return font_path
            print("字体文件路径不能为空，请重新输入。", file=sys.stderr)
        elif choice == '2':
            return '__SCAN_ALL__'
        elif choice == '3':
            return None
        else:
            print("无效选项，请输入 1、2 或 3。", file=sys.stderr)


def scan_all_system_fonts(output_path: str) -> None:
    """扫描所有系统字体并写入报告。"""
    font_files = get_system_fonts()
    for font_file in tqdm(font_files, desc="Scanning system fonts"):
        try:
            report = generate_pua_report(font_file)
            if "未发现PUA码点" not in report:
                print(report)
                append_report(output_path, report)
        except Exception as e:
            error_message = f"Error scanning {font_file}: {e}"
            print(error_message, file=sys.stderr)
            append_report(output_path, error_message)


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(
        description='扫描字体中的 Unicode 私用区(PUA)码点占用情况。'
    )
    parser.add_argument(
        'font_file',
        nargs='?',
        help='指定单个字体文件路径；省略时在终端中提示选择扫描模式。',
    )
    parser.add_argument(
        '--common-windows',
        action='store_true',
        help='扫描常见 Windows 字体并输出 BMP PUA 已占用区间和相对安全区间。',
    )
    parser.add_argument(
        '--output',
        default='unicode_pua_used.txt',
        help='报告输出文件，默认写入 unicode_pua_used.txt。',
    )
    return parser.parse_args()


if __name__ == "__main__":
    _configure_stdio()
    args = parse_args()

    if args.common_windows:
        report = generate_common_windows_pua_report()
        print(report)
        append_report(args.output, report)
    elif args.font_file is None:
        selection = prompt_scan_mode()
        if selection is None:
            print("已退出，未执行扫描。")
        elif selection == '__SCAN_ALL__':
            scan_all_system_fonts(args.output)
        else:
            report = generate_pua_report(selection)
            print(report)
            append_report(args.output, report)
    else:
        # 如果指定了字体文件路径，只扫描该文件
        font_file = args.font_file
        report = generate_pua_report(font_file)
        print(report)
        append_report(args.output, report)
