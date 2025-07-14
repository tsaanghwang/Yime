# pinyin/hanzi_pinyin/right_click_converter.py
import os
from pathlib import Path
from danzi_converter import process_file


def main():
    # 自动确定输入输出路径
    script_dir = Path(__file__).parent
    input_file = script_dir / "danzi_pinyin.yaml"
    output_file = script_dir / "danzi_pinyin.json"

    if not input_file.exists():
        print(f"错误：输入文件 {input_file} 不存在")
        return

    if process_file(str(input_file), str(output_file)):
        print(f"转换成功！JSON文件已保存到: {output_file}")
    else:
        print("转换失败")


if __name__ == "__main__":
    main()
