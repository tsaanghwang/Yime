"""
首音分析
功能：确定首音音标和划分首音类别。
"""
import os
import json
from zaoyin_yinyuan import ClearNoise, VoicedNoise
from syllable.analysis.slice.syllable_categorizer import GanyinCategorizer


# 根据语音事实预定浊音列表, 双隔音符表示浊零声母
VOICED_INITIALS = {
    'm', 'n', 'l', 'r', 'w', 'y', "''"
}


def map_shouyin_to_ipa(initial=None):
    """
    将首音映射到对应的音标
    参数:
        initial: (可选)首音字符串，如果为None则返回完整映射字典
    返回:
        对应的音标列表或完整映射字典
    """
    try:
        # 尝试从配置文件中读取映射关系
        with open('yinyuan/initial_ipa.json', 'r', encoding='utf-8') as f:
            initial_ipa_mapping = json.load(f).get('initial', {})
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        # 如果文件不存在或格式不正确，使用内置的默认映射
        initial_ipa_mapping = {
            'b': ['p'],
            'p': ['pʰ'],
            'f': ['f'],
            'm': ['m'],
            'd': ['t'],
            't': ['tʰ'],
            'l': ['l'],
            'n': ['n'],
            'g': ['k'],
            'k': ['kʰ'],
            'h': ['x'],
            'z': ['ts'],
            'c': ['tsʰ'],
            's': ['s'],
            'zh': ['tʂ'],
            'ch': ['tʂʰ'],
            'sh': ['ʂ'],
            'r': ['ʐ'],
            'j': ['tɕ'],
            'q': ['tɕʰ'],
            'x': ['ɕ'],
            'w': ['w'],
            'y': ['j'],
            "''": ['ʔ']
        }

    if initial is None:
        return initial_ipa_mapping
    return initial_ipa_mapping.get(initial, [])


def create_indeterminate_pitch_pianyin():
    """创建噪音对象并分类为清音和浊音"""
    voiceless = {}
    voiced = {}

    # 获取所有可能的声母
    initial_ipa_mapping = map_shouyin_to_ipa()
    all_initials = VOICED_INITIALS.union(set(initial_ipa_mapping.keys()))

    for initial in all_initials:
        ipa_list = initial_ipa_mapping.get(initial, [])
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

def merge_shouyin_data():
    """
    生成并合并首音数据
    1. 调用GanyinCategorizer生成首音数据
    2. 用map_shouyin_to_ipa中的音标列表替换匹配的声母音标
    """
    # 获取所有可能的声母
    initial_ipa_mapping = map_shouyin_to_ipa()
    initials = VOICED_INITIALS.union(set(initial_ipa_mapping.keys()))

    # 生成原始首音数据 - 创建一个模拟的拼音字典，只包含声母
    mock_pinyin_data = {initial: initial for initial in initials}
    shouyin_data = GanyinCategorizer.generate_shouyin_data(mock_pinyin_data)

    # 替换匹配的声母音标，保持原始列表形式
    for initial in initials:
        ipa_list = initial_ipa_mapping.get(initial, [])
        if initial in shouyin_data:
            shouyin_data[initial] = ipa_list

    return shouyin_data


def main():
    """主函数，执行首音分析流程"""
    try:
        # 1. 生成并合并首音数据
        shouyin_data = merge_shouyin_data()

        # 2. 使用UnpitchedPianyin类验证噪音数据并分类
        classified_noise = create_indeterminate_pitch_pianyin()

        # 3. 读取现有的噪音声母文件

        base_dir = os.path.dirname(__file__)
        pianyin_initial_path = os.path.join(base_dir, 'yinyuan', 'pianyin_initial.json')

        with open(pianyin_initial_path, 'r', encoding='utf-8') as f:
            pianyin_initial = json.load(f)

        # 4. 更新噪音部分并保留元数据
        output = {
            "name": pianyin_initial["name"],
            "description": pianyin_initial["description"],
            "note": pianyin_initial["note"],
            "indeterminate_pitch_pianyin": classified_noise
        }

        # 5. 保存结果
        with open(pianyin_initial_path, 'w', encoding='utf-8') as f:
            json.dump(output, f, ensure_ascii=False, indent=2)

        print("首音和噪音声母映射已成功生成并更新在 pianyin_initial.json中")

    except Exception as e:
        print(f"处理过程中发生错误: {str(e)}")


if __name__ == '__main__':
    main()
