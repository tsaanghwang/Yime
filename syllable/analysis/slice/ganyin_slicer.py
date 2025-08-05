import json
from typing import Dict, List
from ganyin import Ganyin
from pathlib import Path
from pitched_pianyin import YueyinPianyin


class GanyinSlicer:
    def __init__(self):
        self.tone_patterns = {
            "high_tone": ["5", "5", "5"],  # 高平调
            "rising_tone": ["3", "4", "5"],  # 上升调
            "low_tone": ["2", "1", "1"],  # 低平调
            "falling_tone": ["5", "4", "1"],  # 下降调
            "neutral_tone": ["4", "4", "4"]  # 中性调(轻声调)
        }
        self.pitch_levels = {
            "5": "˥",
            "4": "˦",
            "3": "˧",
            "2": "˨",
            "1": "˩"
        }

    def slice_ganyin(self, ganyin_type: str, ganyin_data: Dict[str, Dict]) -> Dict:
        """
        按干音类型切分干音，返回乐音类片音
        """
        results = {}
        for key, value in ganyin_data.items():
            # 保留原始 IPA 用于后续处理
            ipa = value["ipa"]
            # 仅用于创建 Ganyin 对象时取第一个变体
            first_ipa = ipa.split("/")[0] if "/" in ipa else ipa
            ganyin = Ganyin(
                final=value.get("ime", ""),
                pitch_style=first_ipa.split("˥")[0].split("˦")[0].split("˧")[
                    0].split("˨")[0].split("˩")[0]
            )

            # 获取调型模式 - 从IPA中提取调号
            tone_num = "5"  # 默认中性调(轻声调)
            if "˥˥" in value["ipa"]:
                tone_num = "1"
            elif "˧˥" in value["ipa"]:
                tone_num = "2"
            elif "˨˩" in value["ipa"]:
                tone_num = "3"
            elif "˥˩" in value["ipa"]:
                tone_num = "4"
            tone_pattern = self._get_tone_pattern(tone_num)

            if ganyin_type == "single quality ganyin":
                sliced = self._slice_single_quality(
                    ipa, tone_pattern)  # 传入完整 IPA 而不是处理后的 pitch_style
            elif ganyin_type == "back long ganyin":
                sliced = self._slice_back_long(
                    ganyin.pitch_style, tone_pattern)
            elif ganyin_type == "front long ganyin":
                sliced = self._slice_front_long(
                    ganyin.pitch_style, tone_pattern)
            elif ganyin_type == "triple quality ganyin":
                sliced = self._slice_triple_quality(
                    ganyin.pitch_style, tone_pattern)
            else:
                raise ValueError(f"未知的干音类型: {ganyin_type}")

            results[key] = sliced
        return results

    def _get_tone_pattern(self, tone_num: str) -> List[str]:
        """根据调号获取对应的调型模式"""
        if tone_num == "1":
            return self.tone_patterns["high_tone"]
        elif tone_num == "2":
            return self.tone_patterns["rising_tone"]
        elif tone_num == "3":
            return self.tone_patterns["low_tone"]
        elif tone_num == "4":
            return self.tone_patterns["falling_tone"]
        else:
            return self.tone_patterns["neutral_tone"]  # 默认使用中性调

    def _create_yueyin(self, quality: str, pitch: str) -> str:
        """创建乐音表示字符串"""
        # 使用 YueyinPianyin.create_yueyin 工厂方法创建实例
        yueyin = YueyinPianyin.create_yueyin(
            quality=quality,
            pitch=pitch,
            representation="pianyin",
            pitch_style="mark"
        )
        return str(yueyin)

    def _is_valid_phoneme(self, char: str) -> bool:
        """检查字符是否为有效音素"""
        valid_phonemes = ["ə", "ɚ", "ŋ", "ɪ", "ʊ", "ʌ",
                          "ɔ", "y", "e", "o", "a", "m", "n", "i", "u"]
        return char.isalpha() or char in valid_phonemes

    def _slice_single_quality(self, ipa: str, tone_pattern: List[str]) -> Dict:
        """切分单质干音"""
        # 处理双变体 IPA (如 "ɿ˥˥/ʅ˥˥")
        first_ipa = ipa.split("/")[0] if "/" in ipa else ipa
        first_ipa = first_ipa.split("˥")[0].split("˦")[0].split("˧")[
            0].split("˨")[0].split("˩")[0]

        # 提取有效音素
        chars = [c for c in first_ipa if self._is_valid_phoneme(c)]

        # 处理音素不足情况
        if len(chars) == 1:
            chars = chars * 3
        if len(chars) < 3:
            chars += [None] * (3 - len(chars))
            return {
                "呼音": str(YueyinPianyin.create_yueyin(
                    quality=chars[0],
                    pitch=tone_pattern[0],
                    representation="pianyin",
                    pitch_style="mark"
                )) if chars[0] else None,
                "主音": str(YueyinPianyin.create_yueyin(
                    quality=chars[1],
                    pitch=tone_pattern[1],
                    representation="pianyin",
                    pitch_style="mark"
                )) if chars[1] else None,
                "末音": str(YueyinPianyin.create_yueyin(
                    quality=chars[2],
                    pitch=tone_pattern[2],
                    representation="pianyin",
                    pitch_style="mark"
                )) if chars[2] else None,
                "warning": f"IPA too short: {ipa}"
            }

        return {
            "呼音": str(YueyinPianyin.create_yueyin(chars[0], tone_pattern[0], "pianyin", "mark")),
            "主音": str(YueyinPianyin.create_yueyin(chars[1], tone_pattern[1], "pianyin", "mark")),
            "末音": str(YueyinPianyin.create_yueyin(chars[2], tone_pattern[2], "pianyin", "mark"))
        }

    def _slice_back_long(self, ipa: str, tone_pattern: List[str]) -> Dict:
        """切分后长干音"""
        chars = [c for c in ipa if self._is_valid_phoneme(c)]
        if len(chars) == 2:
            chars = [chars[0], chars[1], chars[1]]
        if len(chars) < 3:
            chars += [None] * (3 - len(chars))
            return {
                "呼音": str(YueyinPianyin.create_yueyin(
                    quality=chars[0],
                    pitch=tone_pattern[0],
                    representation="pianyin",
                    pitch_style="mark"
                )) if chars[0] else None,
                "主音": str(YueyinPianyin.create_yueyin(
                    quality=chars[1],
                    pitch=tone_pattern[1],
                    representation="pianyin",
                    pitch_style="mark"
                )) if chars[1] else None,
                "末音": str(YueyinPianyin.create_yueyin(
                    quality=chars[2],
                    pitch=tone_pattern[2],
                    representation="pianyin",
                    pitch_style="mark"
                )) if chars[2] else None,
                "warning": f"IPA too short: {ipa}"
            }
        return {
            "呼音": str(YueyinPianyin.create_yueyin(chars[0], tone_pattern[0], "pianyin", "mark")),
            "主音": str(YueyinPianyin.create_yueyin(chars[1], tone_pattern[1], "pianyin", "mark")),
            "末音": str(YueyinPianyin.create_yueyin(chars[2], tone_pattern[2], "pianyin", "mark"))
        }

    def _slice_front_long(self, ipa: str, tone_pattern: List[str]) -> Dict:
        """切分前长干音"""
        chars = [c for c in ipa if self._is_valid_phoneme(c)]
        if len(chars) == 2:
            chars = [chars[0], chars[0], chars[1]]
        if len(chars) < 3:
            chars += [None] * (3 - len(chars))
            return {
                "呼音": str(YueyinPianyin.create_yueyin(
                    quality=chars[0],
                    pitch=tone_pattern[0],
                    representation="pianyin",
                    pitch_style="mark"
                )) if chars[0] else None,
                "主音": str(YueyinPianyin.create_yueyin(
                    quality=chars[1],
                    pitch=tone_pattern[1],
                    representation="pianyin",
                    pitch_style="mark"
                )) if chars[1] else None,
                "末音": str(YueyinPianyin.create_yueyin(
                    quality=chars[2],
                    pitch=tone_pattern[2],
                    representation="pianyin",
                    pitch_style="mark"
                )) if chars[2] else None,
                "warning": f"IPA too short: {ipa}"
            }
        return {
            "呼音": str(YueyinPianyin.create_yueyin(chars[0], tone_pattern[0], "pianyin", "mark")),
            "主音": str(YueyinPianyin.create_yueyin(chars[1], tone_pattern[1], "pianyin", "mark")),
            "末音": str(YueyinPianyin.create_yueyin(chars[2], tone_pattern[2], "pianyin", "mark"))
        }

    def _slice_triple_quality(self, ipa: str, tone_pattern: List[str]) -> Dict:
        """切分三质干音"""
        ipa_stripped = ipa.split("˥")[0].split("˦")[0].split("˧")[
            0].split("˨")[0].split("˩")[0]
        if ipa_stripped in ["in", "un", "yn"]:
            chars = [ipa_stripped[0], "ə", ipa_stripped[1]]
        elif ipa_stripped in ["iŋ", "iʊ", "ʊŋ", "yŋ"]:
            chars = [ipa_stripped[0], "ɤ", ipa_stripped[1:]]
        elif ipa_stripped == "uɪ":
            chars = ["u", "e", "ɪ"]
        else:
            chars = [c for c in ipa if c.isalpha() or c in [
                "ə", "ɚ", "ŋ", "ɪ", "ʊ", "ʌ", "ɔ", "y", "e", "o", "a", "m", "n", "i", "u"]]
            if len(chars) < 3:
                chars += [None] * (3 - len(chars))
                return {
                    "呼音": self._create_yueyin(chars[0], tone_pattern[0]) if chars[0] else None,
                    "主音": self._create_yueyin(chars[1], tone_pattern[1]) if chars[1] else None,
                    "末音": self._create_yueyin(chars[2], tone_pattern[2]) if chars[2] else None,
                    "warning": f"IPA too short: {ipa}"
                }
        return {
            "呼音": str(YueyinPianyin.create_yueyin(chars[0], tone_pattern[0], "pianyin", "mark")),
            "主音": str(YueyinPianyin.create_yueyin(chars[1], tone_pattern[1], "pianyin", "mark")),
            "末音": str(YueyinPianyin.create_yueyin(chars[2], tone_pattern[2], "pianyin", "mark"))
        }


def load_ganyin_data() -> Dict:
    """加载干音数据"""
    base_dir = Path(__file__).parent
    file_path = base_dir / "ganyin_enhanced.json"
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
        return data["ganyin"] if "ganyin" in data else data


def enhance_i_variants(ganyin_dict: dict) -> dict:
    """
    将所有 _i* 项的 '呼音'/'主音'/'末音' 字段中的 'ɿX' 或 'ʅX' 替换为 'ɿX/ʅX'
    """
    for key, value in ganyin_dict.items():
        if key.startswith("_i"):
            for field in ["呼音", "主音", "末音"]:
                ipa = value.get(field, "")
                if ipa and (ipa.startswith("ɿ") or ipa.startswith("ʅ")):
                    tone = ipa[1:]
                    value[field] = f"ɿ{tone}/ʅ{tone}"
    return ganyin_dict

def main():
    slicer = GanyinSlicer()
    ganyin_data = load_ganyin_data()
    results = {}
    for ganyin_type in ["single quality ganyin", "front long ganyin", "back long ganyin", "triple quality ganyin"]:
        if ganyin_type in ganyin_data:
            sliced = slicer.slice_ganyin(ganyin_type, ganyin_data[ganyin_type])
            if ganyin_type == "single quality ganyin":
                sliced = enhance_i_variants(sliced)
            results[ganyin_type] = sliced
    with open("ganyin_to_pianyin_sequence.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("干音分析完成，结果已保存到 syllable/analysis/slice/ganyin_to_pianyin_sequence.json")


if __name__ == "__main__":
    main()
