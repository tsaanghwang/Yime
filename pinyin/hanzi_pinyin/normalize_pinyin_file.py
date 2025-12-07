import sys
import os
import json
from pathlib import Path
from collections import OrderedDict

# 自动检测模块位置（按优先级尝试）
possible_paths = [
    Path(__file__).parent.parent / "utils",  # 当前实际位置
    Path(__file__).parent,  # 脚本所在目录
    Path.home() / "OneDrive" / "Yime" / "utils"  # 绝对路径
]

found_module = False
for path in possible_paths:
    module_file = path / "pinyin_normalizer.py"
    if module_file.exists():
        sys.path.insert(0, str(path))
        found_module = True
        break

if not found_module:
    print("错误: 未找到 pinyin_normalizer.py 模块，请检查路径设置。")
    print("已尝试以下路径：")
    for path in possible_paths:
        print(f"  {path}")
    sys.exit(1)

try:
    # 动态导入模块，确保路径已添加
    import importlib.util
    module_name = "pinyin_normalizer"
    module_spec = None
    for path in possible_paths:
        module_file = path / "pinyin_normalizer.py"
        if module_file.exists():
            module_spec = importlib.util.spec_from_file_location(module_name, str(module_file))
            break
    if module_spec is None:
        raise ImportError("未找到 pinyin_normalizer.py")
    pinyin_normalizer = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(pinyin_normalizer)
    PinyinNormalizer = pinyin_normalizer.PinyinNormalizer
except Exception as e:
    print("错误: 无法导入 pinyin_normalizer 模块。请确保该文件存在于上述路径之一。")
    print(str(e))
    sys.exit(1)

def get_absolute_path(input_path):
    """将相对路径转换为绝对路径"""
    if not os.path.isabs(input_path):
        # 获取脚本所在目录
        script_dir = Path(__file__).parent.absolute()
        return str(script_dir / input_path)
    return input_path

def main():
    """主处理函数"""
    # 交互式输入处理
    if len(sys.argv) == 1:  # 如果没有命令行参数
        print("请输入要处理的拼音JSON文件路径:")
        input_file = input().strip()
        print("请输入输出文件路径(可选，直接回车使用默认路径):") # pinyin.json
        output_file = input().strip() or None
    else:
        # 原有命令行参数处理逻辑
        import argparse
        parser = argparse.ArgumentParser(description='拼音标准化处理工具')
        parser.add_argument('input', help='输入JSON文件路径')
        parser.add_argument('-o', '--output', help='输出JSON文件路径')
        args = parser.parse_args()
        input_file = args.input
        output_file = args.output

    # 处理文件路径
    input_file = get_absolute_path(input_file)

    # 设置默认输出路径
    script_dir = Path(__file__).parent.absolute()
    if not output_file:
        output_file = str(script_dir / "pinyin_normalized.json")
    else:
        output_file = get_absolute_path(output_file)

    try:
        print(f"正在读取输入文件: {input_file}")
        with open(input_file, 'r', encoding='utf-8') as f:
            pinyin_dict = json.load(f)

        print("正在处理拼音字典...")
        normalized_dict, mismatch_count = PinyinNormalizer.process_pinyin_dict(pinyin_dict)

        # 对字典按键进行排序
        sorted_dict = OrderedDict(sorted(normalized_dict.items(), key=lambda x: x[0]))

        print(f"正在写入输出文件: {output_file}")
        # 确保输出目录存在
        output_dir = os.path.dirname(output_file)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir, exist_ok=True)
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(sorted_dict, f, ensure_ascii=False, indent=2)

        print(f"拼音标准化完成，结果已保存到: {output_file}")
        print(f"共处理 {len(sorted_dict)} 个拼音，其中 {mismatch_count} 个键值不匹配")

    except FileNotFoundError:
        print(f"错误: 输入文件 {input_file} 不存在")
        print("请检查文件路径是否正确，当前工作目录是:", os.getcwd())
    except json.JSONDecodeError:
        print(f"错误: 输入文件 {input_file} 不是有效的JSON格式")
    except Exception as e:
        print(f"处理过程中发生错误: {str(e)}")
        raise

if __name__ == "__main__":
    main()
