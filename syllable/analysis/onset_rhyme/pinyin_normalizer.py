import json
from pathlib import Path
import os

# 声调符号映射
TONE_MARKS = {
    "1": "̄",  # 高平调
    "2": "́",  # 升调
    "3": "̌",  # 低平调
    "4": "̀",  # 降调
    "5": ""   # 轻声
}


def normalize_pinyin(pinyin_with_tone):
    """将带数字调号的拼音转换为带声调符号的标准拼音"""
    if not pinyin_with_tone[-1].isdigit():
        return pinyin_with_tone  # 没有调号，直接返回

    tone_num = pinyin_with_tone[-1]
    pinyin = pinyin_with_tone[:-1].replace("v", "ü")  # 处理v->ü转换

    # 规则1：优先标在a/o/e上
    for vowel in ['a', 'o', 'e']:
        if vowel in pinyin:
            index = pinyin.index(vowel)
            return pinyin[:index] + pinyin[index] + TONE_MARKS[tone_num] + pinyin[index+1:]

    # 规则2：处理ü的情况
    if 'ü' in pinyin:
        index = pinyin.index('ü')
        return pinyin[:index] + pinyin[index] + TONE_MARKS[tone_num] + pinyin[index+1:]

    # 规则3：处理i和u的情况
    if 'i' in pinyin and 'u' in pinyin:
        # 标在后面的那个上
        i_pos = pinyin.rfind('i')
        u_pos = pinyin.rfind('u')
        index = max(i_pos, u_pos)
    elif 'i' in pinyin:
        index = pinyin.rfind('i')
    elif 'u' in pinyin:
        index = pinyin.rfind('u')
    else:
        # 没有元音可标，返回原拼音(不带调号)
        return pinyin

    return pinyin[:index] + pinyin[index] + TONE_MARKS[tone_num] + pinyin[index+1:]


def process_pinyin_dict(input_dict):
    """处理拼音字典，转换为新的结构"""
    result = {}
    unmarked_pinyins = []

    for initial, pinyin_list in input_dict.items():
        normalized_dict = {}
        for pinyin in pinyin_list:
            if pinyin[-1].isdigit():
                normalized = normalize_pinyin(pinyin)
                normalized_dict[pinyin] = normalized
            else:
                unmarked_pinyins.append(pinyin)

        result[initial] = normalized_dict

    return result, unmarked_pinyins


def main():
    # 使用绝对路径确保文件能被找到
    script_dir = Path(__file__).parent.absolute()
    input_path = script_dir / "pinyin_classified.json"
    output_path = script_dir / "pinyin_normalized.json"

    try:
        with open(input_path, 'r', encoding='utf-8') as f:
            pinyin_dict = json.load(f)

        normalized_dict, unmarked_pinyins = process_pinyin_dict(pinyin_dict)

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(normalized_dict, f, ensure_ascii=False, indent=2)

        if unmarked_pinyins:
            print(f"警告: 发现 {len(unmarked_pinyins)} 个未标调的拼音:")
            print(", ".join(unmarked_pinyins))
        else:
            print("所有拼音都已成功标调并转换")
    except FileNotFoundError as e:
        print(f"错误: 文件 {input_path} 未找到")
        print(f"当前工作目录: {os.getcwd()}")
        print(f"请确保文件存在于: {script_dir}")


if __name__ == "__main__":
    main()
