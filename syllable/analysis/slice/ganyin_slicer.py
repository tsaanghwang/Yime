import json
from typing import Dict, List

class GanyinSlicer:
    # 干音分析系统
    # 干音是由声调与韵母构成的音段
    # 在通用现代汉语中，片音是由音质和音调构成的语音基本结构单元
    # 片音的音质用音标（phonetic symbol）来表示
    # 片音的音调用调号（tone mark）来表示
    # 干音分析系统将干音分析成由三个片音构成的序列

    def __init__(self):
        self.tone_patterns = {
            "first_tone": ["high level", "high level", "high level"],
            "second_tone": ["mid level", "mid-high level", "high level"],
            "third_tone": ["mid-low level", "low level", "low level"],
            "fourth_tone": ["high level", "mid-high level", "low level"]
        }
        self.tone_marks = {
            "high level": "˥",
            "mid-high level": "˦",
            "mid level": "˧",
            "mid-low level": "˨",
            "low level": "˩"
        }

    def slice_ganyin(self, ganyin_type: str, ganyin_data: Dict[str, Dict]) -> Dict:
        """
        按干音类型切分ganyin_enhanced.json中的数据（以ipa字段为主）
        """
        results = {}
        for key, value in ganyin_data.items():
            ipa = value["ipa"]
            if ganyin_type == "single quality ganyin":
                sliced = self._slice_single_quality(ipa)
            elif ganyin_type == "back long ganyin":
                sliced = self._slice_back_long(ipa)
            elif ganyin_type == "front long ganyin":
                sliced = self._slice_front_long(ipa)
            elif ganyin_type == "triple quality ganyin":
                sliced = self._slice_triple_quality(ipa)
            else:
                raise ValueError(f"未知的干音类型: {ganyin_type}")
            results[key] = sliced
        return results

    def _slice_single_quality(self, ipa: str) -> Dict:
        # 单质干音：音标重复三次
        chars = [c for c in ipa if c.isalpha() or c in ["ə", "ɚ", "ŋ", "ɪ", "ʊ", "ʌ", "ɔ", "y", "e", "o", "a", "m", "n", "i", "u"]]
        if len(chars) == 1:
            chars = chars * 3
        # Pad if too short
        if len(chars) < 3:
            chars += [None] * (3 - len(chars))
            return {"呼调": chars[0], "主调": chars[1], "末调": chars[2], "warning": f"IPA too short: {ipa}"}
        return {"呼调": chars[0], "主调": chars[1], "末调": chars[2]}

    def _slice_back_long(self, ipa: str) -> Dict:
        # 后长干音：音标长度2，第二个重复
        chars = [c for c in ipa if c.isalpha() or c in ["ə", "ɚ", "ŋ", "ɪ", "ʊ", "ʌ", "ɔ", "y", "e", "o", "a", "m", "n", "i", "u"]]
        if len(chars) == 2:
            chars = [chars[0], chars[1], chars[1]]
        # Pad if too short
        if len(chars) < 3:
            chars += [None] * (3 - len(chars))
            return {"呼调": chars[0], "主调": chars[1], "末调": chars[2], "warning": f"IPA too short: {ipa}"}
        return {"呼调": chars[0], "主调": chars[1], "末调": chars[2]}

    def _slice_front_long(self, ipa: str) -> Dict:
        # 前长干音：音标长度2，第一个重复
        chars = [c for c in ipa if c.isalpha() or c in ["ə", "ɚ", "ŋ", "ɪ", "ʊ", "ʌ", "ɔ", "y", "e", "o", "a", "m", "n", "i", "u"]]
        if len(chars) == 2:
            chars = [chars[0], chars[0], chars[1]]
        # Pad if too short
        if len(chars) < 3:
            chars += [None] * (3 - len(chars))
            return {"呼调": chars[0], "主调": chars[1], "末调": chars[2], "warning": f"IPA too short: {ipa}"}
        return {"呼调": chars[0], "主调": chars[1], "末调": chars[2]}

    def _slice_triple_quality(self, ipa: str) -> Dict:
        # 三质干音：音标长度3
        # 处理省略形式
        special_insert = None
        ipa_stripped = ipa.replace("˥","").replace("˦","").replace("˧","").replace("˨","").replace("˩","")
        if ipa_stripped in ["in", "un", "yn"]:
            # [iən], [uən], [yən] 省略形式
            chars = [ipa_stripped[0], "ə", ipa_stripped[1]]
        elif ipa_stripped in ["iŋ", "iʊ", "ʊŋ", "yŋ"]:
            # [iɤŋ], [iɤʊ], [ʊɤŋ], [yɤŋ] 省略形式
            chars = [ipa_stripped[0], "ɤ", ipa_stripped[1:]]
        elif ipa_stripped == "uɪ":
            # [ueɪ] 省略形式
            chars = ["u", "e", "ɪ"]
        else:
            chars = [c for c in ipa if c.isalpha() or c in ["ə", "ɚ", "ŋ", "ɪ", "ʊ", "ʌ", "ɔ", "y", "e", "o", "a", "m", "n", "i", "u"]]
            # Pad if too short
            if len(chars) < 3:
                chars += [None] * (3 - len(chars))
                return {"呼调": chars[0], "主调": chars[1], "末调": chars[2], "warning": f"IPA too short: {ipa}"}
        return {"呼调": chars[0], "主调": chars[1], "末调": chars[2]}

    def analyze_ganyin(self, final: Dict, tone: str, is_front_long: bool = False, is_back_long: bool = False, is_single_quality: bool = False) -> List[str]:
        """
        分析干音，生成片音序列

        参数:
            final: 韵母字典，必须包含"音标"字段，如{"音标": "uan", "拼音": "uan"}
            tone: 声调类型，必须是self.tone_patterns中的调型
            is_front_long: 是否为前长韵母
            is_back_long: 是否为后长韵母
            is_single_quality: 是否为单质韵母

        返回:
            片音列表，如["u˥", "a˥", "n˥"](三质韵母)或["a˥", "a˥", "n˥"](前长韵母)或["u˥", "o˥", "o˥"](后长韵母)或["o˥", "o˥", "o˥"](单质韵母)

        异常:
            ValueError: 如果输入数据格式不正确
        """
        # 预处理音标：仅针对特定音标例如"n̍"和"ŋ̩"移除附加符号
        def normalize_ipa(ipa: str) -> str:
            """规范化国际音标字符串，移除特定辅音上的附加符号。

            该函数专门处理附加在鼻音和边音上的附加符号，如音节性符号(◌̩)等。
            当前支持的替换规则：
                - "m̩" -> "m" (音节性双唇鼻音)
                - "n̍" -> "n" (音节性齿龈鼻音)
                - "ŋ̩" -> "ŋ" (音节性软腭鼻音)

            Args:
                ipa: 包含可能带有附加符号的国际音标字符串

            Returns:
                移除指定附加符号后的规范化音标字符串
            """
            # 定义需要处理的音标替换规则
            IPA_NORMALIZATION_RULES = {
                "m̩": "m",  # 音节性双唇鼻音
                "m̍": "m",  # 音节性齿龈鼻音
                "n̩": "n",  # 音节性齿龈鼻音
                "n̍": "n",  # 音节性齿龈鼻音
                "ŋ̩": "ŋ",  # 音节性软腭鼻音
                "ŋ̍": "ŋ",  # 音节性软腭鼻音
                "l̩": "l",  # 音节性齿龈边音
                "l̍": "l",  # 音节性齿龈边音
            }

            # 应用所有替换规则
            for pattern, replacement in IPA_NORMALIZATION_RULES.items():
                ipa = ipa.replace(pattern, replacement)

            return ipa

        # 验证输入字典结构
        required_fields = {"音标", "拼音"}
        if not all(field in final for field in required_fields):
            missing = required_fields - final.keys()
            raise ValueError(f"韵母数据缺少必要字段: {missing}")

        ipa = normalize_ipa(final["音标"])
        if not isinstance(ipa, str):
            raise ValueError(f"音标必须是字符串类型，当前值: {ipa} (类型: {type(ipa)})")

        # 对于单质韵母，不检查长度，因为可能包含组合字符
        if is_single_quality:
            pass
        elif is_front_long or is_back_long:
            if len(ipa) != 2:
                raise ValueError(f"前/后长韵母音标应为2个字符，当前值: {ipa}")
        else:  # 三质韵母
            if len(ipa) != 3:
                raise ValueError(f"三质韵母音标应为3个字符，当前值: {ipa}")

        if tone not in self.tone_patterns:
            valid_tones = list(self.tone_patterns.keys())
            raise ValueError(
                f"无效的声调类型: {tone}，有效值为: {valid_tones}"
            )

        # 处理前长韵母：将第一个音标重复
        if is_front_long:
            ipa = ipa[0] + ipa  # 如"an"变为"aan"
        # 处理后长韵母：将第二个音标重复
        elif is_back_long:
            ipa = ipa + ipa[1]  # 如"uo"变为"uoo"
        # 处理单质韵母：将音标重复三次
        elif is_single_quality:
            ipa = ipa * 3  # 如"o"变为"ooo"

        # 生成片音序列
        pitch_levels = self.tone_patterns[tone]
        try:
            return [
                f"{char}{self.tone_marks[level]}"
                for char, level in zip(ipa, pitch_levels)
            ]
        except Exception as e:
            raise ValueError(
                f"生成片音序列失败: {str(e)}，音标: {ipa}, 声调: {tone}"
            ) from e

    def analyze_all_finals(self, finals_data: Dict) -> Dict:
        """
        分析所有韵母的干音组合

        参数:
            finals_data: 包含韵母分类的字典

        返回:
            包含所有干音分析结果的字典

        异常:
            ValueError: 如果数据中缺少必要的韵母分类
        """
        required_categories = ["三质韵母", "前长韵母", "后长韵母", "单质韵母"]
        missing = [cat for cat in required_categories if cat not in finals_data]
        if missing:
            raise ValueError(f"输入数据必须包含以下分类: {missing}")

        # 分析三质韵母、前长韵母、后长韵母和单质韵母
        triphone_finals = finals_data["三质韵母"]
        front_long_finals = finals_data["前长韵母"]
        back_long_finals = finals_data["后长韵母"]
        single_quality_finals = finals_data["单质韵母"]

        results = {}
        for tone in self.tone_patterns:
            results[tone] = {
                "三质韵母": [
                    self.analyze_ganyin(final, tone)
                    for final in triphone_finals
                ],
                "前长韵母": [
                    self.analyze_ganyin(final, tone, is_front_long=True)
                    for final in front_long_finals
                ],
                "后长韵母": [
                    self.analyze_ganyin(final, tone, is_back_long=True)
                    for final in back_long_finals
                ],
                "单质韵母": [
                    self.analyze_ganyin(final, tone, is_single_quality=True)
                    for final in single_quality_finals
                ]
            }

            # 验证每个韵母分类都成功分析
            for category in ["三质韵母", "前长韵母", "后长韵母", "单质韵母"]:
                analyzed_count = len(results[tone][category])
                original_count = len(finals_data[category])
                if analyzed_count != original_count:
                    raise ValueError(
                        f"分析结果不完整({category}): 预期{original_count}个韵母, 实际分析{analyzed_count}个"
                    )

        return results


def load_ganyin_data() -> Dict:
    """从syllable/analysis/slice/ganyin_enhanced.json加载干音数据"""
    with open("syllable/analysis/slice/ganyin_enhanced.json", "r", encoding="utf-8") as f:
        return json.load(f)["ganyin"]


def main():
    slicer = GanyinSlicer()
    ganyin_data = load_ganyin_data()
    results = {}
    for ganyin_type in ["single quality ganyin", "front long ganyin", "back long ganyin", "triple quality ganyin"]:
        if ganyin_type in ganyin_data:
            results[ganyin_type] = slicer.slice_ganyin(ganyin_type, ganyin_data[ganyin_type])
    with open("syllable/analysis/slice/ganyin_slicer_output.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("干音分析完成，结果已保存到 syllable/analysis/slice/ganyin_slicer_output.json")

if __name__ == "__main__":
    main()
