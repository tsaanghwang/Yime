"""
乐音类音元(YueyinYinyuan)模块 - MusicalYinyuan 的别名及扩展实现

继承自 pitched_yinyuan.py 中的 MusicalYinyuan 类，提供中文语境下的专用方法。
"""

from typing import Literal, Union
from dataclasses import dataclass
from pitched_yinyuan import MusicalYinyuan
from pianyin import Pianyin, PitchedPianyin, UnpitchedPianyin
from pitched_yinyuan import PitchedYinyuan
import os
import json

PitchStyle = Literal['number', 'mark']


class YueyinYinyuan(MusicalYinyuan):
    """
    乐音类音元(YueyinYinyuan) - MusicalYinyuan 的中文别名类

    继承所有 MusicalYinyuan 的功能，并添加中文语境专用方法。
    """

    def __init__(self, quality: str, pitch: str, duration: str = 'neutral',
                 loudness: str = 'neutral', pitch_style: str = 'number'):
        super().__init__(
            quality=quality,
            pitch=pitch,
            duration=duration,
            loudness=loudness,
            pitch_style=pitch_style,
        )

        # 使用绝对路径加载配置文件
        config_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(
            config_dir, 'variables_of_pitch_and_quality.json')

        with open(config_path, 'r', encoding='utf-8') as f:
            self.config = json.load(f)
        self.quality_variables = self.config['quality_variables']
        self.pitch_variables = self.config['pitch_variables']

    @property
    def pitch(self) -> str:
        """实现抽象属性 pitch"""
        return self._pitch

    @pitch.setter
    def pitch(self, value: str):
        """设置 pitch 属性"""
        self._pitch = value

    def to_chinese_dict(self) -> dict:
        """转换为中文键名的字典表示"""
        return {
            '类型': '乐音',
            '音质': self.quality,
            '音调': self.pitch,
            'pitch_style': self.pitch_style,
            '音长': self.duration,
            '音强': self.loudness
        }

    @classmethod
    def from_pianyin(cls, pianyin: Union[PitchedPianyin, UnpitchedPianyin]) -> 'YueyinYinyuan':
        """从片音对象创建乐音类音元对象 (中文版)"""
        if isinstance(pianyin, PitchedPianyin):
            return cls(
                quality=pianyin.quality,
                pitch=pianyin.pitch,
                duration='neutral',
                loudness='neutral',
                pitch_style='number'
            )
        else:
            return cls(
                quality=pianyin.quality,
                pitch='4',  # 默认中性调
                duration='neutral',
                loudness='neutral',
                pitch_style='number'
            )

    def __str__(self) -> str:
        """中文友好的字符串表示"""
        return f"乐音类音元(音质={self.quality}, 音调={self.pitch})"

    def process_pitched_yinyuan(self, input_data, is_mid_level_median_model=False):
        """处理乐音类音元数据"""
        if is_mid_level_median_model:
            return self._process_mid_level_median_model_yueyin(input_data)
        else:
            return self._process_yueyin(input_data)

    def _process_yueyin(self, input_data):
        """处理音元系统的乐音类音元数据"""
        pitch_class = self.pitch_variables['mid_high_median_model']
        output = {}

        for key, (quality, pitch) in input_data.items():
            # 先检查音调和音质是否有效
            if not self._is_valid_pitch(pitch) or not self._is_valid_quality(quality):
                continue

            quality_unit = next(
                (k for k, v in self.quality_variables.items() if quality in v), None)

            if quality_unit:
                # mid_high_level_modal_median_model模式处理流程
                if pitch in pitch_class['H']:
                    final_pitch = pitch  # H类保持不变
                elif pitch in pitch_class['M']:
                    final_pitch = pitch  # M类保持不变
                elif pitch in pitch_class['L']:  # 半低平"˨"和"˩"
                    final_pitch = pitch_class['L'][-1]  # 取L类的最后一个值
                else:  # L类
                    continue  # 跳过无效音调

                final_key = quality_unit + final_pitch
                if final_key not in output:
                    output[final_key] = []
                output[final_key].append(quality + pitch)

        return output

    def _process_mid_level_median_model_yueyin(self, input_data):
        """处理mid_level_median_model的乐音类音元数据"""
        pitch_class = self.pitch_variables['mid_level_median_model']
        output = {}

        for key, (quality, pitch) in input_data.items():
            # 先检查音调和音质是否有效
            if not self._is_valid_pitch(pitch) or not self._is_valid_quality(quality):
                continue

            quality_unit = next(
                (k for k, v in self.quality_variables.items() if quality in v), None)

            if quality_unit:
                # mid_level_median_model模式处理流程
                if pitch in pitch_class['H']:  # 高平"˥"和半高平"˦"
                    final_pitch = pitch_class['H'][0]  # H类取第一个值高平"˥"
                elif pitch in pitch_class['M']:  # 中平"˧"
                    final_pitch = pitch  # M类保持不变
                elif pitch in pitch_class['L']:  # 半低平"˨"和"˩"
                    final_pitch = pitch_class['L'][-1]  # 取L类的最后一个值
                else:
                    continue  # 跳过无效音调

                final_key = quality_unit + final_pitch
                if final_key not in output:
                    output[final_key] = []
                output[final_key].append(quality + pitch)

        return output

    def _change_pitch_style(self, input_data: dict) -> dict:
        """转换音高标记风格

        参数:
            input_data: 包含原始音高标记的字典数据

        返回:
            转换后的字典数据，音高标记已替换为对应的标记符号
        """
        result = {}
        pitch_marks = self.config["pitch_variables"]["pitch_marks"]

        for ganyin_type, ganyin_list in input_data.items():
            result[ganyin_type] = {}
            for ganyin_name, parts in ganyin_list.items():
                result[ganyin_type][ganyin_name] = {}
                for field in ["呼音", "主音", "末音"]:
                    ipa = parts.get(field, "")
                    if not ipa:
                        result[ganyin_type][ganyin_name][field] = ipa
                        continue

                    # 处理"/"分隔的两部分
                    if "/" in ipa:
                        left, right = ipa.split("/", 1)
                        # 处理左边部分
                        if left and left[-1] in pitch_marks:
                            left = left[:-1] + pitch_marks[left[-1]][0]
                        # 处理右边部分
                        if right and right[-1] in pitch_marks:
                            right = right[:-1] + pitch_marks[right[-1]][0]
                        result[ganyin_type][ganyin_name][field] = f"{left}/{right}"
                    else:
                        # 处理没有"/"的情况
                        if ipa and ipa[-1] in pitch_marks:
                            ipa = ipa[:-1] + pitch_marks[ipa[-1]][0]
                        result[ganyin_type][ganyin_name][field] = ipa
        return result

    @classmethod
    def _define_variables_for_qualities(cls, quality: str) -> str:
        """根据音质返回对应的质元"""
        config_path = os.path.join(os.path.dirname(
            __file__), 'variables_of_pitch_and_quality.json')
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
            quality_variables = config['quality_variables']

        # 遍历所有质元，检查音质是否在对应的值列表中
        for variable_of_quality, values in quality_variables.items():
            if quality in values:
                return variable_of_quality
        return ""  # 如果没有匹配，返回空字符串

    @classmethod
    def _define_variables_for_pitches(cls, pitch: str) -> str:
        """根据音调返回对应的调元"""
        config_path = os.path.join(os.path.dirname(
            __file__), 'variables_of_pitch_and_quality.json')
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
            pitch_variables = config['pitch_variables']['mid_high_level_modal_median_model']

        # 检查音调属于哪一类(H/M/L)并返回对应的调元
        if pitch in pitch_variables['H']:
            return pitch_variables['H'][0]  # H类取第一个值
        elif pitch in pitch_variables['M']:
            return pitch_variables['M'][-1]  # M类取最后一个值
        elif pitch in pitch_variables['L']:
            return pitch_variables['L'][-1]  # L类取最后一个值
        return ""  # 如果没有匹配，返回空字符串

    def _is_valid_pitch(self, pitch: str) -> bool:
        """检查音调是否有效"""
        if not pitch:
            return False

        # 检查音调是否在任一调类中
        for model in ['mid_high_level_modal_median_model', 'mid_level_median_model']:
            if model in self.pitch_variables and model != 'pitch_marks':
                for pitch_class in ['H', 'M', 'L']:
                    if pitch in self.pitch_variables[model].get(pitch_class, []):
                        return True
        return False

    def _is_valid_quality(self, quality: str) -> bool:
        """检查音质是否有效"""
        if not quality:
            return False

        # 检查音质是否在任一质元的值列表中
        for values in self.quality_variables.values():
            if quality in values:
                return True
        return False
