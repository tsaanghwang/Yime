# 干音分析器类
# 功能：分析拼音数据并生成分类后的干音数据

from ganyin_categorizer import GanyinCategorizer
from typing import Dict
import json
import sys
import os

class GanyinAnalyzer:
    def __init__(self, file):
        # 修正输入文件路径
        base_dir = os.path.dirname(os.path.dirname(
            os.path.dirname(os.path.dirname(file))))
        self.input_path = os.path.join(
            base_dir, 'pinyin', 'hanzi_pinyin', 'pinyin_normalized.json')
        self.shouyin_path = os.path.join(
            os.path.dirname(file), 'yinyuan', 'shouyin.json')
        self.ganyin_path = os.path.join(
            os.path.dirname(file), 'yinyuan', 'ganyin.json')

        # 打印路径用于调试
        print(f"输入文件路径: {self.input_path}")
        print(f"首音输出路径: {self.shouyin_path}")
        print(f"干音输出路径: {self.ganyin_path}")

    def analyze_and_save(self):
        """分析拼音数据并保存分类后的结果"""
        try:
            # 检查输入文件是否存在
            if not os.path.exists(self.input_path):
                raise FileNotFoundError(f"输入文件不存在: {self.input_path}")

            # 读取并验证JSON数据
            with open(self.input_path, 'r', encoding='utf-8') as f:
                pinyin_data = json.load(f)

            if not isinstance(pinyin_data, dict):
                raise ValueError("输入JSON数据格式不正确，应为字典类型")

            if not pinyin_data:
                raise ValueError("输入JSON数据为空")

            # 生成首音数据
            shouyin_data = GanyinCategorizer.generate_shouyin_data(pinyin_data)
            if not shouyin_data:
                raise ValueError("生成的首音数据为空")

            # 生成干音数据并分类
            ganyin_data = self._generate_ganyin_data(pinyin_data)
            if not ganyin_data:
                raise ValueError("生成的干音数据为空")

            categorized_ganyin = self.categorize_ganyin_data(ganyin_data)

            # 转换为要求的输出格式
            output_shouyin = {"shouyin": dict(sorted(shouyin_data.items()))}
            output_ganyin = {"ganyin": categorized_ganyin}

            # 确保输出目录存在
            os.makedirs(os.path.dirname(self.shouyin_path), exist_ok=True)
            os.makedirs(os.path.dirname(self.ganyin_path), exist_ok=True)

            # 保存文件
            with open(self.shouyin_path, 'w', encoding='utf-8') as f:
                json.dump(output_shouyin, f, ensure_ascii=False, indent=2)

            with open(self.ganyin_path, 'w', encoding='utf-8') as f:
                json.dump(output_ganyin, f, ensure_ascii=False, indent=2)

            print("音节分析完成，结果已保存到:")
            print(f"- 首音数据: {self.shouyin_path}")
            print(f"- 干音数据: {self.ganyin_path}")
            return True

        except Exception as e:
            print(f"分析过程中出错: {str(e)}", file=sys.stderr)
            return False

    def categorize_ganyin_data(self, ganyin_data: Dict[str, str]) -> Dict[str, Dict[str, str]]:
        """
        按干音分类整理干音数据

        参数:
            ganyin_data: {数字标调干音: 调号标调干音}

        返回:
            分类后的干音数据 {分类名: {数字标调干音: 调号标调干音}}
        """
        categorized = {
            "single quality ganyin": {},
            "front long ganyin": {},
            "back long ganyin": {},
            "triple quality ganyin": {}
        }
        category_map = {
            "单质干音": "single quality ganyin",
            "前长干音": "front long ganyin",
            "后长干音": "back long ganyin",
            "三质干音": "triple quality ganyin"
        }

        for num_final, tone_final in ganyin_data.items():
            # 提取韵母仅用于分类，不影响存储的键值对
            final = GanyinCategorizer._remove_tone_from_ganyin(num_final)
            category_cn = GanyinCategorizer.categorize(final)
            category_en = category_map.get(
                category_cn, "single quality ganyin")
            categorized[category_en][num_final] = tone_final

        # 对每个分类中的条目按拼音排序
        for category in categorized:
            categorized[category] = dict(sorted(categorized[category].items()))

        return categorized

    def _generate_ganyin_data(self, pinyin_data: Dict[str, str]) -> Dict[str, str]:
        """生成干音数据

        参数:
            pinyin_data: {数字标调拼音: 调号标调拼音}

        返回:
            {数字标调干音: 调号标调干音}
        """
        ganyin_data = {}
        tongue_tip_initials = {'z', 'c', 's', 'zh', 'ch', 'sh', 'r'}

        for num_pinyin, tone_pinyin in pinyin_data.items():
            # 处理特殊音节（不包括 "_i" 相关的）
            if GanyinCategorizer._is_special_syllable(num_pinyin):
                ganyin_data[num_pinyin] = GanyinCategorizer.SPECIAL_SYLLABLES.get(
                    num_pinyin, tone_pinyin)
                continue

            # 从数字标调拼音中提取干音部分
            initial, num_final = GanyinCategorizer.split_syllable(num_pinyin)
            # 从调号标调拼音中提取干音部分
            _, tone_final = GanyinCategorizer.split_syllable(tone_pinyin)

            # 处理舌尖音：当声母为 z, c, s, zh, ch, sh, r 且韵母为"i"时，添加占位符"_"
            if num_final and tone_final:
                if initial in tongue_tip_initials and num_final == 'i':
                    num_final = '_' + num_final
                    # 处理调号标调的情况
                    if tone_final[0] in {'i', 'ī', 'í', 'ǐ', 'ì'}:
                        tone_final = '_' + tone_final
                ganyin_data[num_final] = tone_final

        return ganyin_data
