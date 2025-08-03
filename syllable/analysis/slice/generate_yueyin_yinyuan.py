"""
乐音类音元生成器 - 使用具体的音元类生成音元数据文件
"""

import json
from pathlib import Path
from yueyin_yinyuan import YueyinYinyuan  # 使用具体的子类


def generate_yueyin_yinyuan():
    """生成乐音类音元数据文件"""

    base_dir = Path(__file__).parent

    # 输入输出文件路径
    input_path = base_dir / 'pitched_pianyin.json'
    output_dynamic_path = base_dir / 'pitched_yinyuan_of_dynamic_model.json'
    output_isochronous_path = base_dir / 'pitched_yinyuan_of_isochronous_model.json'

    # 读取输入数据
    with open(input_path, 'r', encoding='utf-8') as f:
        input_data = json.load(f)

    # 转换数据格式: {"key": "value"} -> {"key": ["quality", "pitch"]}
    converted_data = {key: [key[:-1], key[-1]] for key in input_data.keys()}

    # 创建音元实例
    yueyin = YueyinYinyuan(
        quality='neutral',
        pitch='4',
        duration='neutral',
        loudness='neutral',
        pitch_style='number'
    )

    # 处理数据 - 使用实例方法
    output_dynamic = yueyin._process_dynamic_tonal_elements_model(
        converted_data)
    output_isochronous = yueyin._process_isochronous_tonal_elements_model(
        converted_data)

    # 保存结果
    with open(output_dynamic_path, 'w', encoding='utf-8') as f:
        json.dump(output_dynamic, f, ensure_ascii=False, indent=2)

    with open(output_isochronous_path, 'w', encoding='utf-8') as f:
        json.dump(output_isochronous, f, ensure_ascii=False, indent=2)

    print("处理完成，结果已保存到:")
    print(f"- {output_dynamic_path}")
    print(f"- {output_isochronous_path}")


if __name__ == '__main__':
    generate_yueyin_yinyuan()
