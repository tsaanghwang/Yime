import json
from pianyin.unpitched_pianyin import UnpitchedPianyin, ClearPianyin, VoicedUnpitchedPianyin


# 根据语音事实预定浊音列表
VOICED_CONSONANTS = {
    'm', 'n', 'n̠', 'ŋ', 'l', 'ɾ', 'ʐ', 'ɻ', 'ɹ', 'z',
    'w', 'ʋ', 'j', 'ɥ', 'ɣ'
}


def create_unpitched_pianyin_individuals(unpitched_pianyin_data):
    """创建噪音对象并分类为清音和浊音"""
    voiceless = {}
    voiced = {}

    for unpitched_pianyin, initials in unpitched_pianyin_data.items():
        # 判断是否为浊音
        if unpitched_pianyin in VOICED_CONSONANTS:
            unpitched_pianyin_individual = VoicedUnpitchedPianyin(quality=unpitched_pianyin)
            if unpitched_pianyin_individual.is_valid():
                voiced[unpitched_pianyin] = initials
        else:
            unpitched_pianyin_individual = ClearPianyin(quality=unpitched_pianyin)
            if unpitched_pianyin_individual.is_valid():
                voiceless[unpitched_pianyin] = initials

    return {"voiceless": voiceless, "voiced": voiced}


def reverse_initial_mapping(initial_data):
    """反转声母-噪音映射关系"""
    reversed_mapping = {}
    for initial, unpitched_pianyin_list in initial_data.items():
        for unpitched_pianyin in unpitched_pianyin_list:
            if unpitched_pianyin not in reversed_mapping:
                reversed_mapping[unpitched_pianyin] = []
            reversed_mapping[unpitched_pianyin].append(initial)
    return reversed_mapping


def main():
    # 1. 读取声母-噪音映射文件
    with open('pianyin/initial_pianyin.json', 'r', encoding='utf-8') as f:
        initial_pianyin = json.load(f)

    # 2. 反转映射关系
    reversed_mapping = reverse_initial_mapping(initial_pianyin['initial'])

    # 3. 使用UnpitchedPianyin类验证噪音数据并分类
    classified_unpitched_pianyin = create_unpitched_pianyin_individuals(reversed_mapping)

    # 4. 读取现有的噪音-声母文件
    with open('pianyin/pianyin_initial.json', 'r', encoding='utf-8') as f:
        pianyin_initial = json.load(f)

    # 5. 更新噪音部分并保留元数据
    output = {
        "name": pianyin_initial["name"],
        "description": pianyin_initial["description"],
        "note": pianyin_initial["note"],
        "unpitched_pianyin": classified_unpitched_pianyin

    }

    # 6. 保存结果
    with open('pianyin/pianyin_initial.json', 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print("噪音-声母映射已成功生成并更新在 pianyin/pianyin_initial.json")


if __name__ == '__main__':
    main()
