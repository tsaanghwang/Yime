from pathlib import Path
import re


"""Legacy diagnostic for the removed 理论文件 markdown tree."""


TARGET_DIR = Path("理论文件")


def check_files() -> int:
    if not TARGET_DIR.exists():
        print("未找到 理论文件/ 目录；该脚本仅保留作历史诊断参考。")
        return 0

    error_count = 0
    for file in TARGET_DIR.rglob("*.md"):
        with file.open('r', encoding='utf-8') as handle:
            content = handle.read()

        # 检查中文标点使用英文标点的情况
        errors = re.findall(r'[，。；：？！“”‘’]', content)
        if errors:
            print(f"发现中文标点问题在 {file}:")
            print(" -> ".join(errors[:3]) + ("" if len(errors) <= 3 else "..."))
            error_count += 1

    return error_count


def main() -> None:
    if check_files() > 0:
        raise SystemExit(1)


if __name__ == '__main__':
    main()