"""
声母分析
功能：确定声母音标和划分声母类别。
"""


import json
from pianyin.indeterminate_pitch_pianyin import UnpitchedPianyin, ClearPianyin, VoicedUnpitchedPianyin


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
            indeterminate_pitch_pianyin = VoicedUnpitchedPianyin(quality=initial)
            if indeterminate_pitch_pianyin.is_valid():
                voiced[initial] = ipa_list
        else:
            indeterminate_pitch_pianyin = ClearPianyin(quality=initial)
            if indeterminate_pitch_pianyin.is_valid():
                voiceless[initial] = ipa_list

    return {"unpitched_pianyin": voiceless, "unstable_pitch_pianyin": voiced}


def main():
    # 1. 读取声母与音标的映射文件
    with open('pianyin/initial_ipa.json', 'r', encoding='utf-8') as f:
        initial_ipa = json.load(f)

    # 2. 使用UnpitchedPianyin类验证噪音数据并分类
    classified_noise = create_indeterminate_pitch_pianyin(initial_ipa['initial'])

    # 3. 读取现有的噪音声母文件
    with open('pianyin/pianyin_initial.json', 'r', encoding='utf-8') as f:
        pianyin_initial = json.load(f)

    # 4. 更新噪音部分并保留元数据
    output = {
        "name": pianyin_initial["name"],
        "description": pianyin_initial["description"],
        "note": pianyin_initial["note"],
        "indeterminate_pitch_pianyin": classified_noise
    }

    # 5. 保存结果
    with open('pianyin/pianyin_initial.json', 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print("噪音声母映射已成功生成并更新在 pianyin/pianyin_initial.json中")


if __name__ == '__main__':
    main()