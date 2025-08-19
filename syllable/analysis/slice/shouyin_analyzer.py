"""
首音分析
功能：确定首音音标和划分首音类别。
"""

import json
from indeterminate_pitch_yinyuan import ClearNoise, VoicedNoise
from ganyin_categorizer import GanyinCategorizer


# 根据语音事实预定浊音列表, 双隔音符表示浊零声母
VOICED_INITIALS = {
    'm', 'n', 'l', 'r', 'w', 'y', "''"
}


def create_indeterminate_pitch_pianyin(initial_ipa):
    """创建噪音对象并分类为清音和浊音"""
    voiceless = {}
    voiced = {}

    for initial, ipa_list in initial_ipa.items():
        # 判断是否为浊音
        if initial in VOICED_INITIALS:
            indeterminate_pitch_pianyin = VoicedNoise(quality=initial)
            if indeterminate_pitch_pianyin.is_valid():
                voiced[initial] = ipa_list
        else:
            indeterminate_pitch_pianyin = ClearNoise(quality=initial)
            if indeterminate_pitch_pianyin.is_valid():
                voiceless[initial] = ipa_list

    return {"unpitched_pianyin": voiceless, "unstable_pitch_pianyin": voiced}


def merge_shouyin_data(initial_ipa):
    """
    生成并合并首音数据
    1. 调用GanyinCategorizer生成首音数据
    2. 用initial_ipa中的音标列表替换匹配的声母音标
    """
    # 生成原始首音数据 - 创建一个模拟的拼音字典，只包含声母
    mock_pinyin_data = {initial: initial for initial in initial_ipa.keys()}
    shouyin_data = GanyinCategorizer.generate_shouyin_data(mock_pinyin_data)

    # 替换匹配的声母音标，保持原始列表形式
    for initial, ipa_list in initial_ipa.items():
        if initial in shouyin_data:
            shouyin_data[initial] = ipa_list  # 直接使用整个音标列表

    return shouyin_data

def main():
    # 1. 读取声母与音标的映射文件
    with open('yinyuan/initial_ipa.json', 'r', encoding='utf-8') as f:
        initial_ipa = json.load(f)

    # 2. 生成并合并首音数据
    shouyin_data = merge_shouyin_data(initial_ipa['initial'])

    # 3. 使用UnpitchedPianyin类验证噪音数据并分类
    classified_noise = create_indeterminate_pitch_pianyin(initial_ipa['initial'])

    # 4. 读取现有的噪音声母文件
    with open('yinyuan/pianyin_initial.json', 'r', encoding='utf-8') as f:
        pianyin_initial = json.load(f)

    # 5. 更新噪音部分并保留元数据
    output = {
        "name": pianyin_initial["name"],
        "description": pianyin_initial["description"],
        "note": pianyin_initial["note"],
        "initial": shouyin_data,
        "indeterminate_pitch_pianyin": classified_noise
    }

    # 6. 保存结果
    with open('yinyuan/pianyin_initial.json', 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print("首音和噪音声母映射已成功生成并更新在 pianyin_initial.json中")


if __name__ == '__main__':
    main()