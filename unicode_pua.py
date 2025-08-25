"""
创建一个模块检测字体中unicode私用区(PUA)的占用情况
1. 扫描字体文件中的所有字符
2. 检查每个字符是否在Unicode私用区(PUA)范围
3. 生成报告显示哪些码点被占用
"""

from fontTools.ttLib import TTFont
from typing import List, Dict
import os


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
    font = TTFont(font_path)
    pua_codepoints = []
    pua_glyphs = []

    # 检查cmap表中的所有字符
    for cmap in font['cmap'].tables:
        for codepoint, glyph_name in cmap.cmap.items():
            if is_pua_codepoint(codepoint):
                pua_codepoints.append(codepoint)
                pua_glyphs.append(glyph_name)

    return {
        'pua_codepoints': pua_codepoints,
        'pua_glyphs': pua_glyphs
    }


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
        report_lines.append(f"U+{codepoint:04X} ({glyph_name})")

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


if __name__ == "__main__":
    import sys

    if len(sys.argv) == 1:
        # 如果没有参数，扫描所有系统字体
        font_files = get_system_fonts()
        for font_file in font_files:
            try:
                report = generate_pua_report(font_file)
                print(report)
                print("\n" + "="*50 + "\n")

                # 将报告追加到汇总文件
                with open("unicode_pua_used.txt", "a", encoding="utf-8") as summary_file:
                    summary_file.write(report + "\n" + "="*50 + "\n\n")
            except Exception as e:
                print(f"处理字体文件 {font_file} 时出错: {str(e)}")
    elif len(sys.argv) == 2:
        # 如果指定了字体文件路径，只扫描该文件
        font_file = sys.argv[1]
        report = generate_pua_report(font_file)
        print(report)

        # 将报告追加到汇总文件
        with open("unicode_pua_used.txt", "a", encoding="utf-8") as summary_file:
            summary_file.write(report + "\n" + "="*50 + "\n\n")
    else:
        print("用法: python unicode_pua.py [字体文件路径]")
        print("如果没有参数，将扫描所有系统字体")
        sys.exit(1)
