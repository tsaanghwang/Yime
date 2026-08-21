"""乐音片音到乐音音元的归并与格式转换。"""

from __future__ import annotations

import json
from pathlib import Path


class YueyinMapper:
    """封装乐音片音 -> 乐音音元的归并规则与调号样式转换。"""

    def __init__(self, config_path: Path):
        with config_path.open("r", encoding="utf-8") as file:
            self.config = json.load(file)
        self.quality_variables = self.config["quality_variables"]
        self.pitch_variables = self.config["pitch_variables"]

    def normalize_symbol(
        self,
        quality: str,
        pitch: str,
        model: str = "mid_high_median_model",
    ) -> str:
        """将乐音片音的音质/音高归并到乐音音元符号。"""
        if not self._is_valid_quality(quality) or not self._is_valid_pitch(pitch):
            return ""

        quality_unit = next(
            (key for key, values in self.quality_variables.items() if quality in values),
            None,
        )
        if not quality_unit:
            return ""

        final_pitch = self._normalize_pitch(pitch, model)
        if not final_pitch:
            return ""

        return quality_unit + final_pitch

    def normalize_pianyin_text(self, pianyin: str, model: str = "mid_high_median_model") -> str:
        """将片音字符串归并到乐音音元符号。"""
        if not pianyin:
            return ""

        primary = pianyin.split("/", 1)[0]
        if len(primary) <= 1:
            return ""

        return self.normalize_symbol(primary[:-1], primary[-1], model=model)

    def group_symbols(
        self,
        input_data: dict[str, tuple[str, str]] | dict[str, list[str]],
        model: str = "mid_high_median_model",
    ) -> dict[str, list[str]]:
        """按指定模型把片音集合归并为乐音音元集合。"""
        output: dict[str, list[str]] = {}
        for quality, pitch in input_data.values():
            symbol = self.normalize_symbol(quality, pitch, model=model)
            if not symbol:
                continue
            output.setdefault(symbol, []).append(f"{quality}{pitch}")
        return output

    def convert_pitch_style(
        self,
        input_data: dict[str, dict[str, dict[str, str]]],
    ) -> dict[str, dict[str, dict[str, str]]]:
        """把末尾数字调号改写为当前仓库约定的调号字符。"""
        result: dict[str, dict[str, dict[str, str]]] = {}
        pitch_marks = self.pitch_variables["pitch_marks"]

        for ganyin_type, ganyin_list in input_data.items():
            result[ganyin_type] = {}
            for ganyin_name, parts in ganyin_list.items():
                result[ganyin_type][ganyin_name] = {}
                for field in ["呼音", "主音", "末音"]:
                    result[ganyin_type][ganyin_name][field] = self._rewrite_pitch_marks(
                        parts.get(field, ""),
                        pitch_marks,
                    )
        return result

    def _normalize_pitch(self, pitch: str, model: str) -> str:
        pitch_class = self.pitch_variables[model]
        if pitch in pitch_class["H"]:
            return pitch if model == "mid_high_median_model" else pitch_class["H"][0]
        if pitch in pitch_class["M"]:
            return pitch
        if pitch in pitch_class["L"]:
            return pitch_class["L"][-1]
        return ""

    @staticmethod
    def _rewrite_pitch_marks(value: str, pitch_marks: dict[str, list[str]]) -> str:
        if not value:
            return value

        if "/" in value:
            left, right = value.split("/", 1)
            return "/".join(
                YueyinMapper._rewrite_pitch_marks(part, pitch_marks)
                for part in (left, right)
            )

        tail = value[-1]
        if tail not in pitch_marks:
            return value
        return value[:-1] + pitch_marks[tail][0]

    def _is_valid_pitch(self, pitch: str) -> bool:
        if not pitch:
            return False
        for model in ["mid_high_median_model", "mid_level_median_model"]:
            if model not in self.pitch_variables:
                continue
            for pitch_class in ["H", "M", "L"]:
                if pitch in self.pitch_variables[model].get(pitch_class, []):
                    return True
        return False

    def _is_valid_quality(self, quality: str) -> bool:
        if not quality:
            return False
        return any(quality in values for values in self.quality_variables.values())
