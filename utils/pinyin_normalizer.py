"""
拼音标准化处理模块
包含PinyinNormalizer类，提供拼音标调转换的核心功能
"""

import argparse
import json
from collections import OrderedDict
from pathlib import Path
from typing import Dict, Tuple

class PinyinNormalizer:
    """拼音标准化处理类"""

    # 特殊音质列表
    SPECIAL_QUALITIES = ["ê", "m", "n", "ng", "hm", "hn", "hng"]
    # 所有可能的声调
    TONES = ["1", "2", "3", "4", "5"]

    # 声调符号映射
    TONE_MARKS = {
        "1": "̄",  # 高调
        "2": "́",  # 升调
        "3": "̌",  # 低调
        "4": "̀",  # 降调
        "5": ""   # 轻声
    }

    @classmethod
    def normalize_special_pinyin(cls, syllabic_quality: str, tone: str) -> str:
        """标准化特殊音质拼音（ê, m, n, ng, hm, hn, hng）"""
        if not tone in cls.TONE_MARKS:
            return syllabic_quality

        if syllabic_quality == "ê":
            return "ê" + cls.TONE_MARKS[tone]
        elif syllabic_quality in ["m", "n"]:
            return syllabic_quality + cls.TONE_MARKS[tone]
        elif syllabic_quality == "ng":
            return "n" + cls.TONE_MARKS[tone] + "g"  # 标调在n上
        elif syllabic_quality in ["hm", "hn", "hng"]:
            if syllabic_quality == "hng":
                return "h" + "n" + cls.TONE_MARKS[tone] + "g"
            return "h" + syllabic_quality[1] + cls.TONE_MARKS[tone]
        return syllabic_quality

    @classmethod
    def supplement_special_pinyin(cls, pinyin_dict: Dict[str, str]) -> Dict[str, str]:
        """补充缺失的特殊音质拼音并返回新字典"""
        special_pinyin_list = [f"{sq}{tone}" for sq in cls.SPECIAL_QUALITIES for tone in cls.TONES]
        supplemented_dict = pinyin_dict.copy()

        for pinyin in special_pinyin_list:
            if pinyin not in supplemented_dict:
                supplemented_dict[pinyin] = pinyin

        print(f"新增补充的特殊拼音数量: {len(special_pinyin_list) - len(set(pinyin_dict) & set(special_pinyin_list))}")
        return supplemented_dict

    @classmethod
    def normalize_one(cls, pinyin_with_tone: str) -> str:
        """第一层 API：标准化单个数字标调拼音。"""
        if not pinyin_with_tone or not pinyin_with_tone[-1].isdigit():
            return pinyin_with_tone

        tone_num = pinyin_with_tone[-1]
        pinyin = pinyin_with_tone[:-1]

        if 'v' in pinyin:
            v_index = pinyin.index('v')
            if v_index > 0:
                prev_char = pinyin[v_index-1]
                if prev_char in ['j', 'q', 'x', 'y']:
                    pinyin = pinyin.replace('v', 'u')
                elif prev_char in ['l', 'n']:
                    pinyin = pinyin.replace('v', 'ü')
            else:
                pinyin = pinyin.replace('v', 'ü')

        for sq in cls.SPECIAL_QUALITIES:
            if pinyin == sq:
                return cls.normalize_special_pinyin(sq, tone_num)

        for vowel in ['a', 'o', 'e']:
            if vowel in pinyin:
                index = pinyin.index(vowel)
                return pinyin[:index] + vowel + cls.TONE_MARKS[tone_num] + pinyin[index+1:]

        if 'iu' in pinyin:
            index = pinyin.index('iu') + 1
            return pinyin[:index] + 'u' + cls.TONE_MARKS[tone_num] + pinyin[index+1:]
        if 'ui' in pinyin:
            index = pinyin.index('ui') + 1
            return pinyin[:index] + 'i' + cls.TONE_MARKS[tone_num] + pinyin[index+1:]

        for vowel in ['i', 'u', 'ü']:
            if vowel in pinyin:
                index = pinyin.index(vowel)
                return pinyin[:index] + vowel + cls.TONE_MARKS[tone_num] + pinyin[index+1:]

        return pinyin

    @classmethod
    def normalize_dict_existing_only(cls, input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
        """第二层 API：仅标准化现有键，不补充缺失的特殊拼音组合。"""
        normalized_dict: Dict[str, str] = {}
        mismatch_count = 0

        for key, value in input_dict.items():
            if key != value:
                mismatch_count += 1
            normalized_dict[key] = cls.normalize_one(key)

        return normalized_dict, mismatch_count

    @classmethod
    def normalize_dict_with_supplements(cls, input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
        """第三层 API：先补齐特殊拼音，再批量标准化。"""
        normalized_dict: Dict[str, str] = {}
        mismatch_count = 0

        supplemented_dict = cls.supplement_special_pinyin(input_dict)

        for key, value in supplemented_dict.items():
            if key != value:
                mismatch_count += 1
            normalized_dict[key] = cls.normalize_one(key)

        return normalized_dict, mismatch_count

    @classmethod
    def normalize_pinyin(cls, pinyin_with_tone: str) -> str:
        """兼容旧名：转发到第一层 API。"""
        return cls.normalize_one(pinyin_with_tone)

    @classmethod
    def normalize_existing_pinyin_dict(cls, input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
        """兼容旧名：转发到第二层 API。"""
        return cls.normalize_dict_existing_only(input_dict)

    @classmethod
    def process_pinyin_dict(cls, input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
        """兼容旧名：转发到第三层 API。"""
        return cls.normalize_dict_with_supplements(input_dict)


def normalize_pinyin(pinyin_with_tone: str) -> str:
    """兼容旧名：模块级单项标准化入口。"""
    return PinyinNormalizer.normalize_one(pinyin_with_tone)


def normalize_one(pinyin_with_tone: str) -> str:
    """第一层 API：模块级单项标准化入口。"""
    return PinyinNormalizer.normalize_one(pinyin_with_tone)


def process_pinyin_dict(input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
    """兼容旧名：模块级补齐后批量标准化入口。"""
    return PinyinNormalizer.normalize_dict_with_supplements(input_dict)


def normalize_existing_pinyin_dict(input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
    """兼容旧名：模块级现有键批量标准化入口。"""
    return PinyinNormalizer.normalize_dict_existing_only(input_dict)


def normalize_dict_existing_only(input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
    """第二层 API：模块级现有键批量标准化入口。"""
    return PinyinNormalizer.normalize_dict_existing_only(input_dict)


def normalize_dict_with_supplements(input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
    """第三层 API：模块级补齐后批量标准化入口。"""
    return PinyinNormalizer.normalize_dict_with_supplements(input_dict)


def normalize_pinyin_file(input_path: str | Path, output_path: str | Path | None = None) -> tuple[Path, int, int]:
    """读取 JSON 拼音字典，标准化后写回目标文件。"""
    resolved_input = Path(input_path).expanduser().resolve()
    if output_path is None:
        resolved_output = resolved_input.with_name("pinyin_normalized.json")
    else:
        resolved_output = Path(output_path).expanduser().resolve()

    with resolved_input.open("r", encoding="utf-8") as file:
        pinyin_dict = json.load(file)

    normalized_dict, mismatch_count = normalize_dict_with_supplements(pinyin_dict)
    sorted_dict = OrderedDict(sorted(normalized_dict.items(), key=lambda item: item[0]))

    resolved_output.parent.mkdir(parents=True, exist_ok=True)
    with resolved_output.open("w", encoding="utf-8") as file:
        json.dump(sorted_dict, file, ensure_ascii=False, indent=2)

    return resolved_output, len(sorted_dict), mismatch_count


def build_arg_parser() -> argparse.ArgumentParser:
    """构建模块 CLI 参数解析器。"""
    parser = argparse.ArgumentParser(description="拼音标准化处理工具")
    parser.add_argument("input", nargs="?", help="输入 JSON 文件路径")
    parser.add_argument("-o", "--output", help="输出 JSON 文件路径")
    return parser


def main(argv: list[str] | None = None) -> int:
    """模块唯一 CLI 入口。"""
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    input_path = args.input
    output_path = args.output

    if not input_path:
        print("请输入要处理的拼音JSON文件路径:")
        input_path = input().strip()
        print("请输入输出文件路径(可选，直接回车使用默认路径):")
        output_path = input().strip() or None

    if not input_path:
        raise ValueError("输入文件路径不能为空")

    resolved_output, item_count, mismatch_count = normalize_pinyin_file(input_path, output_path)

    print(f"拼音标准化完成，结果已保存到: {resolved_output}")
    print(f"共处理 {item_count} 个拼音，其中 {mismatch_count} 个键值不匹配")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
