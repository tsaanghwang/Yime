"""音节分析器实现与兼容公开入口。"""

from pathlib import Path
from typing import Any, Dict, cast
import json
import os
import sys

from .ganyin_categorizer import GanyinCategorizer
from .syllable_splitter import SyllableSplitter


def _remove_tone_from_ganyin(value: str) -> str:
    """移除干音中的声调信息（数字与拼音音调符号）。"""
    tone_map = str.maketrans(
        "āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜü",
        "aaaaeeeeiiiioooouuuuvvvvu",
    )
    cleaned = value.translate(tone_map)
    if cleaned and cleaned[-1].isdigit():
        cleaned = cleaned[:-1]
    return cleaned


def _find_repo_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "pyproject.toml").exists():
            return candidate
    raise FileNotFoundError(f"无法从 {start} 推断仓库根目录")


class GanyinAnalyzer:
    """分析拼音数据并输出首音与干音映射。"""

    def __init__(self, file: str):
        root = _find_repo_root(Path(file).resolve())
        runtime_dir = root / 'syllable' / 'yinyuan'

        self.input_path = os.path.normpath(str(
            root / 'internal_data' / 'pinyin_source_db' / 'lexicon_exports' / 'pinyin_normalized.json'
        ))

        self.output_dir = os.path.normpath(str(runtime_dir))
        self.shouyin_path = os.path.normpath(str(runtime_dir / 'shouyin.json'))
        self.ganyin_path = os.path.normpath(str(runtime_dir / 'ganyin.json'))

        print(f"输入文件路径: {self.input_path}")
        print(f"输出目录: {self.output_dir}")
        print(f"首音输出路径: {self.shouyin_path}")
        print(f"干音输出路径: {self.ganyin_path}")

    def analyze_and_save(self) -> bool:
        """分析拼音数据并保存分类后的结果。"""
        try:
            if not os.path.exists(self.input_path):
                raise FileNotFoundError(f"输入文件不存在: {self.input_path}")

            with open(self.input_path, 'r', encoding='utf-8') as file:
                pinyin_data_raw: Any = json.load(file)

            if not isinstance(pinyin_data_raw, dict):
                raise ValueError("输入JSON数据格式不正确，应为字典类型")

            pinyin_data = cast(Dict[str, str], pinyin_data_raw)

            if not pinyin_data:
                raise ValueError("输入JSON数据为空")

            shouyin_data = SyllableSplitter.generate_shouyin_data(pinyin_data)
            if not shouyin_data:
                raise ValueError("生成的首音数据为空")

            ganyin_data = self._generate_ganyin_data(pinyin_data)
            if not ganyin_data:
                raise ValueError("生成的干音数据为空")

            categorized_ganyin = self.categorize_ganyin_data(ganyin_data)

            output_shouyin = {"shouyin": shouyin_data}
            output_ganyin = {"ganyin": categorized_ganyin}

            os.makedirs(os.path.dirname(self.shouyin_path), exist_ok=True)
            os.makedirs(os.path.dirname(self.ganyin_path), exist_ok=True)

            with open(self.shouyin_path, 'w', encoding='utf-8') as file:
                json.dump(output_shouyin, file, ensure_ascii=False, indent=2)

            with open(self.ganyin_path, 'w', encoding='utf-8') as file:
                json.dump(output_ganyin, file, ensure_ascii=False, indent=2)

            print("音节分析完成，结果已保存到:")
            print(f"- 首音数据: {self.shouyin_path}")
            print(f"- 干音数据: {self.ganyin_path}")
            return True

        except Exception as error:
            print(f"分析过程中出错: {str(error)}", file=sys.stderr)
            return False

    def categorize_ganyin_data(self, ganyin_data: Dict[str, str]) -> Dict[str, Dict[str, str]]:
        """按干音分类整理干音数据。"""
        categorized: Dict[str, Dict[str, str]] = {
            "single quality ganyin": {},
            "front long ganyin": {},
            "back long ganyin": {},
            "triple quality ganyin": {},
        }
        category_map = {
            "单质干音": "single quality ganyin",
            "前长干音": "front long ganyin",
            "后长干音": "back long ganyin",
            "三质干音": "triple quality ganyin",
        }

        for num_final, tone_final in ganyin_data.items():
            final = _remove_tone_from_ganyin(num_final)
            category_cn = GanyinCategorizer.categorize(final)
            category_en = category_map.get(category_cn, "single quality ganyin")
            categorized[category_en][num_final] = tone_final

        sorted_finals = GanyinCategorizer.sort_finals_by_category(GanyinCategorizer.get_all_finals())

        for category_en, finals in zip(categorized.keys(), sorted_finals.values()):
            sorted_ganyin = sorted(
                categorized[category_en].items(),
                key=lambda item: (
                    finals.index(_remove_tone_from_ganyin(item[0]))
                    if _remove_tone_from_ganyin(item[0]) in finals
                    else len(finals)
                ),
            )
            categorized[category_en] = dict(sorted_ganyin)

        return categorized

    def _generate_ganyin_data(self, pinyin_data: Dict[str, str]) -> Dict[str, str]:
        """生成干音数据。"""
        ganyin_data: Dict[str, str] = {}
        tongue_tip_initials = {'z', 'c', 's', 'zh', 'ch', 'sh', 'r'}

        for num_pinyin, tone_pinyin in pinyin_data.items():
            if num_pinyin in GanyinCategorizer.SPECIAL_SYLLABLES:
                ganyin_data[num_pinyin] = GanyinCategorizer.SPECIAL_SYLLABLES.get(
                    num_pinyin, tone_pinyin,
                )
                continue

            initial, num_final = SyllableSplitter.split_syllable(num_pinyin)
            _, tone_final = SyllableSplitter.split_syllable(tone_pinyin)

            if num_final and tone_final:
                if initial in tongue_tip_initials and num_final == 'i':
                    num_final = '_' + num_final
                    if tone_final[0] in {'i', 'ī', 'í', 'ǐ', 'ì'}:
                        tone_final = '_' + tone_final
                ganyin_data[num_final] = tone_final

        return ganyin_data


class YinjieAnalyzer(GanyinAnalyzer):
    """Backward-compatible public entrypoint for the syllable analyzer."""


__all__ = ["GanyinAnalyzer", "YinjieAnalyzer"]
