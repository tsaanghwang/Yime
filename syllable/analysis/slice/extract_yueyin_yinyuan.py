"""
析取乐音类音元 - 使用具体的音元类生成音元数据文件
"""

import json
import  sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from yueyin_yinyuan import YueyinYinyuan


def extract_yueyin_yinyuan():
    """生成乐音类音元数据文件"""

    base_dir = Path(__file__).parent

    # 输入输出文件路径
    input_path = base_dir / 'yinyuan' / 'pitched_pianyin.json'
    output_mid_high_median_model_path = base_dir / 'yinyuan' / \
        'pitched_yinyuan_of_mid_high_median_model.json'
    output_mid_level_median_model_path = base_dir / 'yinyuan' / \
        'pitched_yinyuan_of_mid_level_median_model.json'

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
    mid_high_median_model = yueyin._process_mid_high_model(
        converted_data)
    output_mid_level_median_model = yueyin._process_mid_level_model(
        converted_data)

    # 保存结果
    with open(output_mid_high_median_model_path, 'w', encoding='utf-8') as f:
        json.dump(mid_high_median_model, f, ensure_ascii=False, indent=2)

    with open(output_mid_level_median_model_path, 'w', encoding='utf-8') as f:
        json.dump(output_mid_level_median_model,
                  f, ensure_ascii=False, indent=2)

    print("处理完成，结果已保存到:")
    print(f"- {output_mid_high_median_model_path}")
    print(f"- {output_mid_level_median_model_path}")


if __name__ == '__main__':
    extract_yueyin_yinyuan()
