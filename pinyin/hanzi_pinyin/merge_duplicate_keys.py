import yaml
import json
import os
from pathlib import Path
from collections import defaultdict
import argparse


def merge_duplicate_keys(yaml_data, mode="single-char"):
    """合并YAML数据中的重复键，保留不同的值"""
    merged_data = defaultdict(list)
    duplicate_count = 0

    if mode == "single-char":
        for key, value in yaml_data.items():
            if key in merged_data:
                duplicate_count += 1
            if isinstance(value, list):
                merged_data[key].extend(value)
            else:
                merged_data[key].append(value)

    elif mode == "multi-char":
        for key, value in yaml_data.items():
            if isinstance(value, list):
                merged_data[key].extend([v for v in value])
            else:
                merged_data[key].append(value)

    elif mode == "strict":
        for key, value in yaml_data.items():
            if key in merged_data:
                raise ValueError(f"发现重复键: {key}")
            merged_data[key] = value
    else:
        raise ValueError(f"未知模式: {mode}")

    return dict(merged_data), duplicate_count


def load_yaml_file(file_path):
    """加载YAML文件，支持多种格式"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

        # 尝试处理Tab分隔的格式
        if '\t' in content:
            content = content.replace('\t', ': ')

        try:
            return yaml.safe_load(content) or {}
        except yaml.YAMLError as e:
            print(f"YAML解析错误: {e}")
            return {}


def save_output(data, output_file, output_format='json'):
    """保存输出文件，支持JSON和YAML格式"""
    output_dir = os.path.dirname(output_file)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)

    with open(output_file, 'w', encoding='utf-8') as f:
        if output_format == 'json':
            json.dump(data, f, ensure_ascii=False, indent=2)
        else:
            yaml.dump(data, f, allow_unicode=True, default_flow_style=False)


def process_file(input_file, output_file, mode="single-char", output_format='json'):
    """处理输入文件并生成输出"""
    if not os.path.exists(input_file):
        print(f"错误: 输入文件不存在: {input_file}")
        return False

    print(f"开始处理: {input_file} → {output_file}")
    print(f"模式: {mode}, 输出格式: {output_format}")

    yaml_data = load_yaml_file(input_file)
    if not yaml_data:
        print("警告: 输入文件为空或格式不正确")
        return False

    merged_data, duplicate_count = merge_duplicate_keys(yaml_data, mode)

    # 统计信息
    original_keys = len(yaml_data)
    merged_keys = len(merged_data)
    print(f"原始键数量: {original_keys}")
    print(f"合并后键数量: {merged_keys}")
    print(f"发现的重复键数量: {duplicate_count}")
    print(f"合并减少的键数量: {original_keys - merged_keys}")

    save_output(merged_data, output_file, output_format)
    print(f"处理完成，结果已保存到: {output_file}")
    return True


def menu_execute():
    """菜单执行模式，使用预设路径"""
    script_dir = Path(__file__).parent.absolute()
    input_file = script_dir / "hanzi_pinyin.yaml"
    output_file = script_dir / "merged_pinyin.json"

    print("="*50)
    print("合并重复键工具 - 菜单执行模式")
    print(f"输入文件: {input_file}")
    print(f"输出文件: {output_file}")
    print("="*50)

    if not input_file.exists():
        print(f"错误: 输入文件 {input_file} 不存在")
        return

    mode = input("请选择模式 (1=单字, 2=多字, 3=严格): ").strip()
    if mode == "1":
        mode = "single-char"
    elif mode == "2":
        mode = "multi-char"
    elif mode == "3":
        mode = "strict"
    else:
        print("无效选择，使用默认模式: 单字")
        mode = "single-char"

    format_choice = input("请选择输出格式 (1=JSON, 2=YAML): ").strip()
    output_format = "json" if format_choice == "1" else "yaml"

    process_file(input_file, output_file, mode, output_format)


def main():
    parser = argparse.ArgumentParser(description='合并YAML文件中的重复键')
    parser.add_argument('input', nargs='?', help='输入YAML文件路径')
    parser.add_argument('output', nargs='?', help='输出文件路径')
    parser.add_argument('--mode', choices=['single-char', 'multi-char', 'strict'],
                        default='single-char', help='处理模式')
    parser.add_argument('--format', choices=['json', 'yaml'],
                        default='json', help='输出格式')

    args = parser.parse_args()

    if not args.input or not args.output:
        menu_execute()
    else:
        process_file(args.input, args.output, args.mode, args.format)


if __name__ == "__main__":
    main()
