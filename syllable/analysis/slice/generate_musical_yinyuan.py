from pathlib import Path
import json
from yueyin_yinyuan import YueyinYinyuan  # 使用具体的子类
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))


def generate_musical_yinyuan():
    """生成乐音类音元(Musical Yinyuan/Yueyin)数据文件"""
    base_dir = Path(__file__).parent
    input_path = base_dir / 'pitched_pianyin.json'
    output_path = base_dir / 'musical_yinyuan.json'

    # 读取输入数据
    with open(input_path, 'r', encoding='utf-8') as f:
        pinyin_data = json.load(f)

    # 处理数据并创建MusicalYinyuan实例
    musical_yinyuan_data = {}
    for pinyin, details in pinyin_data.items():
        # 分离音质和音调
        quality = pinyin[:-1]
        pitch = pinyin[-1]

        # 创建MusicalYinyuan实例
    yueyin = YueyinYinyuan(
        quality='neutral',
        pitch='4',
        duration='neutral',
        loudness='neutral',
        pitch_style='number'
    )

    # 转换为字典格式
    musical_yinyuan_data[pinyin] = yueyin.to_dict()

    # 保存结果
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(musical_yinyuan_data, f, ensure_ascii=False, indent=2)

    print(f"处理完成，结果已保存到: {output_path}")


if __name__ == '__main__':
    generate_musical_yinyuan()
