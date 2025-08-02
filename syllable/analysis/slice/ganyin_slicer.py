import json
from typing import Dict, List
from ganyin import Ganyin
from pathlib import Path


class GanyinSlicer:
    def __init__(self):
        self.tone_patterns = {
            "high_tone": ["5", "5", "5"],  # 高平调
            "rising_tone": ["3", "4", "5"],  # 上升调
            "low_tone": ["2", "1", "1"],  # 低平调
            "falling_tone": ["5", "4", "1"],  # 下降调
            "neutral_tone": ["4", "4", "4"]  # 中性调
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
        按干音类型切分干音，返回片音
        """
        results = {}
        for key, value in ganyin_data.items():
            ganyin = Ganyin(
                final=value.get("numeric_tone", ""),
                gandiao=value.get("ipa", "")
            )

            # 获取调型模式
            tone_num = key[-1]  # 从key中提取调号(1-5)
            tone_pattern = self._get_tone_pattern(tone_num)

            if ganyin_type == "single quality ganyin":
                sliced = self._slice_single_quality(
                    ganyin.gandiao, tone_pattern)
            elif ganyin_type == "back long ganyin":
                sliced = self._slice_back_long(
                    ganyin.gandiao, tone_pattern)
            elif ganyin_type == "front long ganyin":
                sliced = self._slice_front_long(
                    ganyin.gandiao, tone_pattern)
            elif ganyin_type == "triple quality ganyin":
                sliced = self._slice_triple_quality(
                    ganyin.gandiao, tone_pattern)
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
        return f"{quality}{self.pitch_levels.get(pitch, '')}"

    def _slice_single_quality(self, ipa: str, tone_pattern: List[str]) -> Dict:
        chars = [c for c in ipa if c.isalpha() or c in ["ə", "ɚ", "ŋ",
                                                        "ɪ", "ʊ", "ʌ", "ɔ", "y", "e", "o", "a", "m", "n", "i", "u"]]
        if len(chars) == 1:
            chars = chars * 3
        if len(chars) < 3:
            chars += [None] * (3 - len(chars))
            return {
                "呼音": self._create_yueyin(chars[0], tone_pattern[0]) if chars[0] else None,
                "主音": self._create_yueyin(chars[1], tone_pattern[1]) if chars[1] else None,
                "末音": self._create_yueyin(chars[2], tone_pattern[2]) if chars[2] else None,
                "warning": f"IPA too short: {ipa}"
            }
        return {
            "呼音": self._create_yueyin(chars[0], tone_pattern[0]),
            "主音": self._create_yueyin(chars[1], tone_pattern[1]),
            "末音": self._create_yueyin(chars[2], tone_pattern[2])
        }

    def _slice_back_long(self, ipa: str, tone_pattern: List[str]) -> Dict:
        chars = [c for c in ipa if c.isalpha() or c in ["ə", "ɚ", "ŋ",
                                                        "ɪ", "ʊ", "ʌ", "ɔ", "y", "e", "o", "a", "m", "n", "i", "u"]]
        if len(chars) == 2:
            chars = [chars[0], chars[1], chars[1]]
        if len(chars) < 3:
            chars += [None] * (3 - len(chars))
            return {
                "呼音": self._create_yueyin(chars[0], tone_pattern[0]) if chars[0] else None,
                "主音": self._create_yueyin(chars[1], tone_pattern[1]) if chars[1] else None,
                "末音": self._create_yueyin(chars[2], tone_pattern[2]) if chars[2] else None,
                "warning": f"IPA too short: {ipa}"
            }
        return {
            "呼音": self._create_yueyin(chars[0], tone_pattern[0]),
            "主音": self._create_yueyin(chars[1], tone_pattern[1]),
            "末音": self._create_yueyin(chars[2], tone_pattern[2])
        }

    def _slice_front_long(self, ipa: str, tone_pattern: List[str]) -> Dict:
        chars = [c for c in ipa if c.isalpha() or c in ["ə", "ɚ", "ŋ",
                                                        "ɪ", "ʊ", "ʌ", "ɔ", "y", "e", "o", "a", "m", "n", "i", "u"]]
        if len(chars) == 2:
            chars = [chars[0], chars[0], chars[1]]
        if len(chars) < 3:
            chars += [None] * (3 - len(chars))
            return {
                "呼音": self._create_yueyin(chars[0], tone_pattern[0]) if chars[0] else None,
                "主音": self._create_yueyin(chars[1], tone_pattern[1]) if chars[1] else None,
                "末音": self._create_yueyin(chars[2], tone_pattern[2]) if chars[2] else None,
                "warning": f"IPA too short: {ipa}"
            }
        return {
            "呼音": self._create_yueyin(chars[0], tone_pattern[0]),
            "主音": self._create_yueyin(chars[1], tone_pattern[1]),
            "末音": self._create_yueyin(chars[2], tone_pattern[2])
        }

    def _slice_triple_quality(self, ipa: str, tone_pattern: List[str]) -> Dict:
        ipa_stripped = ipa.replace("˥", "").replace("˦", "").replace(
            "˧", "").replace("˨", "").replace("˩", "")
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
            "呼音": self._create_yueyin(chars[0], tone_pattern[0]),
            "主音": self._create_yueyin(chars[1], tone_pattern[1]),
            "末音": self._create_yueyin(chars[2], tone_pattern[2])
        }


def load_ganyin_data() -> Dict:
    """加载干音数据"""
    base_dir = Path(__file__).parent
    file_path = base_dir / "ganyin_enhanced.json"
    with open(file_path, "r", encoding="utf-8") as f:
        return json.load(f)["ganyin"]


def main():
    slicer = GanyinSlicer()
    ganyin_data = load_ganyin_data()
    results = {}
    for ganyin_type in ["single quality ganyin", "front long ganyin", "back long ganyin", "triple quality ganyin"]:
        if ganyin_type in ganyin_data:
            results[ganyin_type] = slicer.slice_ganyin(
                ganyin_type, ganyin_data[ganyin_type])
    with open("ganyin_slicer_output.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("干音分析完成，结果已保存到 syllable/analysis/slice/ganyin_slicer_output.json")


if __name__ == "__main__":
    main()
