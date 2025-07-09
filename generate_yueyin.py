import json


def generate_simple_yueyin_dict(qualities, pitches):
    """生成简化的乐音字典，格式为{"i˥": "i5"}"""
    yueyin_dict = {}
    
    # 生成所有组合
    for quality in qualities:
        for pitch_mark, pitch_num in pitches.items():
            # 创建键值对
            key = f"{quality}{pitch_mark}"
            value = f"{quality}{pitch_num}"
            yueyin_dict[key] = value
    
    return yueyin_dict


def main():
    # 1. 读取乐音属性JSON文件
    with open('internal_data/yueyin_attributes.json', 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 获取音质和音调数据
    qualities = data['qualities']
    pitches = data['pitches']

    # 2. 生成简化乐音字典
    yueyin_dict = generate_simple_yueyin_dict(qualities, pitches)

    # 3. 将结果保存为字典
    with open('internal_data/yueyin_dict.json', 'w', encoding='utf-8') as f:
        json.dump(yueyin_dict, f, ensure_ascii=False, indent=2)

    print("简化乐音字典已成功生成并保存为 yueyin_dict.json")


if __name__ == '__main__':
    main()