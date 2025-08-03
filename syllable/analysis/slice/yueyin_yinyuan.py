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
            pitch_style=pitch_style
        )

        # 使用绝对路径加载配置文件
        config_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(config_dir, 'variables_of_pitch_and_quality.json')

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
            '显示风格': self.pitch_style,
            '音长': self.duration,
            '音强': self.loudness
        }

    @classmethod
    def from_pianyin(cls, pianyin: Union[PitchedPianyin, UnpitchedPianyin]) -> 'YueyinYinyuan':
        """从片音对象创建乐音音元对象 (中文版)"""
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
                pitch='3',  # 默认中平调
                duration='neutral',
                loudness='neutral',
                pitch_style='number'
            )

    def __str__(self) -> str:
        """中文友好的字符串表示"""
        return f"乐音音元(音质={self.quality}, 音调={self.pitch})"

    def process_pitched_yinyuan(self, input_data, is_isochronous_tonal_elements_model=False):
        """处理乐音类音元数据"""
        if is_isochronous_tonal_elements_model:
            return self._process_isochronous_tonal_elements_model(input_data)
        else:
            return self._process_dynamic_tonal_elements_model(input_data)

    def _process_dynamic_tonal_elements_model(self, input_data):
        """处理dynamic_tonal_elements_model的乐音类音元数据"""
        pitch_class = self.pitch_variables['dynamic_tonal_elements_model']
        output = {}

        for key, (quality, pitch) in input_data.items():
            # 先检查音调和音质是否有效
            if not self._is_valid_pitch(pitch) or not self._is_valid_quality(quality):
                continue

            quality_unit = next(
                (k for k, v in self.quality_variables.items() if quality in v), None)

            if quality_unit:
                # dynamic_tonal_elements_model模式处理流程
                if pitch in pitch_class['H']:
                    final_pitch = pitch  # H类保持不变
                elif pitch in pitch_class['M']:
                    final_pitch = pitch  # M类保持不变
                else:  # L类
                    final_pitch = '˩'  # 所有L类音调统一为˩

                final_key = quality_unit + final_pitch
                if final_key not in output:
                    output[final_key] = []
                output[final_key].append(quality + pitch)

        return output

    def _process_isochronous_tonal_elements_model(self, input_data):
        """处理isochronous_tonal_elements_model的乐音类音元数据"""
        pitch_class = self.pitch_variables['isochronous_tonal_elements_model']
        output = {}

        for key, (quality, pitch) in input_data.items():
            quality_unit = next(
                (k for k, v in self.quality_variables.items() if quality in v), None)

            if quality_unit:
                # isochronous_tonal_elements_model模式处理流程
                if pitch in pitch_class['H']:  # 高平"˥"和半高平"˦"
                    final_pitch = '˥'  # H类提升为˥
                elif pitch in pitch_class['M']:  # 中平"˧"
                    final_pitch = '˧'  # M类保持不变
                elif pitch in pitch_class['L']:  # 半低平"˨"和"˩"
                    final_pitch = '˩'  # L类保持为˩
                else:
                    continue  # 跳过无效音调

                final_key = quality_unit + final_pitch
                if final_key not in output:
                    output[final_key] = []
                output[final_key].append(quality + pitch)

        return output

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
            pitch_variables = config['pitch_variables']['dynamic_tonal_elements_model']

        # 检查音调属于哪一类(H/M/L)并返回对应的调元
        if pitch in pitch_variables['H']:
            return "˥"
        elif pitch in pitch_variables['M']:
            return "˦"
        elif pitch in pitch_variables['L']:
            return "˩"
        return ""  # 如果没有匹配，返回空字符串

    def _is_valid_pitch(self, pitch: str) -> bool:
        """检查音调是否有效"""
        if not pitch:
            return False

        # 检查音调是否在任一调类中
        for model in ['dynamic_tonal_elements_model', 'isochronous_tonal_elements_model']:
            if model in self.pitch_variables:
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