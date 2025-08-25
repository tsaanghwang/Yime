# syllable/analysis/initial_final_with_tone/pinyin_validator.py
import json
from typing import Dict, List, Tuple, Optional, Union
from collections import defaultdict


class PinyinValidator:
    """拼音合规验证，检查拼音标注是否符合国家标准"""

    def __init__(self, pinyin_file='pinyin_normalized.json'):
        self.pinyin_file = pinyin_file
        self.standard_rules = {
            'tone_placement': {
                'priority': ['a', 'o', 'e', 'i', 'u', 'ü'],
                'compound_rules': {
                    'iu': 'u', 'ui': 'i',  # 特殊复合韵母规则
                    'hm': 'm', 'hn': 'n', 'hng': 'ng'  # 特殊音节规则
                }
            },
            'valid_initials': ['b', 'p', 'm', 'f', 'd', 't', 'n', 'l', 'g', 'k',
                             'h', 'j', 'q', 'x', 'zh', 'ch', 'sh', 'r', 'z', 'c', 's'],
            'valid_finals': [...]  # 完整韵母列表可补充
        }

    def load_pinyin_data(self) -> Dict[str, str]:
        """加载拼音JSON数据"""
        try:
            with open(self.pinyin_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"文件未找到: {self.pinyin_file}，请确保该文件存在于脚本目录下。")
            return {}

    def validate_all(self) -> Dict[str, List[Tuple[str, str, Optional[str]]]]:
        """
        执行完整验证流程
        返回结构: {
            'valid': [(pinyin, hanzi)],
            'invalid': [(pinyin, hanzi, reason)]
        }
        """
        pinyin_data = self.load_pinyin_data()
        results = {'valid': [], 'invalid': []}

        for pinyin, hanzi in pinyin_data.items():
            if not self._validate_tone_placement(pinyin):
                results['invalid'].append((pinyin, hanzi, '声调位置错误'))
            elif not self._validate_syllable_structure(pinyin):
                results['invalid'].append((pinyin, hanzi, '音节结构错误'))
            else:
                results['valid'].append((pinyin, hanzi))

        return results

    def _validate_tone_placement(self, pinyin: str) -> bool:
        """验证声调标注位置"""
        if not pinyin[-1].isdigit():  # 无数字声调
            return True
        if len(pinyin) < 2:
            return True

        # 首先检查hng系列拼音
        if pinyin.startswith('hng'):
            normalized = self._normalize_hng(pinyin)
            return normalized == self.load_pinyin_data().get(pinyin, '')

        tone = int(pinyin[-1])
        base = pinyin[:-1]

        # 处理单字符拼音（如 m, n, ng, ê）
        if len(base) <= 1 or base == 'ê':
            return True

        # 检查其他特殊复合韵母
        for pattern, target in self.standard_rules['tone_placement']['compound_rules'].items():
            if pattern in base and pattern != 'hng':  # 已单独处理hng
                return base.endswith(target)

        # 常规优先级检查
        vowels = self.standard_rules['tone_placement']['priority']
        for vowel in vowels:
            if vowel in base:
                last_vowel_pos = base.rfind(vowel)
                if last_vowel_pos >= 0:
                    return base[last_vowel_pos] == vowel
        return True

    def _normalize_hng(self, pinyin: str) -> str:
        """标准化hng系列拼音"""
        if not pinyin.startswith('hng'):
            return pinyin

        tone = pinyin[-1]
        if tone not in '12345':
            return pinyin

        tone_mark = {
            '1': '̄', '2': '́', '3': '̌', '4': '̀', '5': ''
        }[tone]

        return f"hn{tone_mark}g"

    def _validate_syllable_structure(self, pinyin: str) -> bool:
        """验证音节结构合法性"""
        if not pinyin:
            return False

        # 分离声调
        tone = pinyin[-1] if pinyin[-1].isdigit() else ''
        base = pinyin[:-1] if tone else pinyin

        # 检查特殊音节(hm, hn, hng, ê)
        if base.startswith('h') and base[1:] in ['m', 'n', 'ng']:
            return True
        if base == 'ê':  # 添加对ê的支持
            return True

        # 检查零声母(包括 w, y 开头的音节)
        if base[0] in {'a', 'o', 'e', 'w', 'y'}:
            return True

        # 检查声母有效性
        initial = base[:2] if len(base) > 1 and base[:2] in {
            'zh', 'ch', 'sh'} else base[0]
        return initial in self.standard_rules['valid_initials']

    def generate_report(self, results: Dict[str, List[Tuple[str, str, Optional[str]]]]) -> str:
        """生成验证报告"""
        report = []
        report.append(f"=== 拼音标准验证报告 ===")
        report.append(
            f"总检查项: {len(results['valid']) + len(results['invalid'])}")
        report.append(f"合规拼音: {len(results['valid'])}")
        report.append(f"问题拼音: {len(results['invalid'])}")

        if results['invalid']:
            report.append("\n问题详情:")
            for pinyin, hanzi, reason in results['invalid']:
                report.append(f"- {pinyin} ({hanzi}): {reason}")

        return '\n'.join(report)


# 使用示例
if __name__ == '__main__':
    validator = PinyinValidator()
    validation_results = validator.validate_all()
    print(validator.generate_report(validation_results))
