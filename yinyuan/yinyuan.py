# yinyuan/yinyuan.py
import json
import os  # 添加os模块导入
from typing import Optional, Union
from pianyin.pianyin import Pianyin, PitchedPianyin, UnpitchedPianyin


class Yinyuan:
    """音元(Yinyuan)类是片音类的另一种符号化表示形式"""

    def __init__(self, code: int = None, notation: str = "", config_path=None):
        """初始化音元对象"""
        self.notation = notation
        if code is not None and not isinstance(code, int):
            raise ValueError("Yinyuan code must be an integer")
        self.code = code

        # 使用绝对路径加载配置文件
        if config_path is None:
            config_path = os.path.join(os.path.dirname(
                __file__), 'variables_of_pitch_and_quality.json')

        with open(config_path, 'r', encoding='utf-8') as f:
            self.config = json.load(f)
        self.quality_variables = self.config['quality_variables']
        self.pitch_variables = self.config['pitch_variables']

    # 添加验证方法
    def _is_valid_pitch(self, pitch: str) -> bool:
        """验证音调是否有效"""
        return any(pitch in values for values in self.pitch_variables['dynamic_tonal_elements_model'].values())

    def _is_valid_quality(self, quality: str) -> bool:
        """验证音质是否有效"""
        return any(quality in values for values in self.quality_variables.values())

    # 其余方法保持不变...
    def __str__(self) -> str:
        """返回音元的字符串表示"""
        return f"Yinyuan(code={self.code}, notation='{self.notation}')"

    def __repr__(self) -> str:
        """返回音元的正式表示，可用于eval"""
        return f"Yinyuan(code={self.code}, notation='{self.notation}')"

    @classmethod
    def from_pianyin(cls, pianyin: 'Pianyin') -> 'Yinyuan':
        """
        从片音对象创建音元对象

        参数:
            pianyin (Pianyin): 片音对象(必须是PitchedPianyin或UnpitchedPianyin实例)

        返回:
            Yinyuan: 转换后的音元对象

        异常:
            ValueError: 如果音质或音调无效，或传入抽象Pianyin类
        """
        if not isinstance(pianyin, (PitchedPianyin, UnpitchedPianyin)):
            raise ValueError(
                "Cannot instantiate from abstract Pianyin class - use PitchedPianyin or UnpitchedPianyin")

        if not pianyin.is_valid():
            raise ValueError("Invalid Pianyin: missing required attributes")

        # 定义噪音类片音的音元
        if isinstance(pianyin, UnpitchedPianyin):
            variable_of_quality = cls._define_variables_for_qualities(pianyin.quality)
            if not variable_of_quality:
                raise ValueError(
                    f"Unsupported unpitched_yinyuan quality '{pianyin.quality}'")

            notation = variable_of_quality
            if pianyin.duration != "neutral":
                notation += f"_{pianyin.duration}"
            if pianyin.loudness != "neutral":
                notation += f"^{pianyin.loudness}"

            # 噪音的特殊代码处理
            code = 0  # 假设0是噪音的特殊代码
            return cls(code=code, notation=notation)

        # 定义乐音类片音的属性变量
        variable_of_quality = cls._define_variables_for_qualities(pianyin.quality)
        variable_of_pitch = cls._define_variables_for_pitches(pianyin.pitch)

        if not variable_of_quality or not variable_of_pitch:
            raise ValueError(
                f"Unsupported quality '{pianyin.quality}' or pitch '{pianyin.pitch}'")

        # 构建音元符号
        notation = f"{variable_of_quality}{variable_of_pitch}"
        if pianyin.duration != "neutral":
            notation += f"_{pianyin.duration}"
        if pianyin.loudness != "neutral":
            notation += f"^{pianyin.loudness}"

        # 获取音元代码
        base_notation = f"{variable_of_quality}{variable_of_pitch}"
        code = cls._get_yinyuan_code(base_notation)
        if code is None:
            raise ValueError(
                f"No code mapping found for notation: {base_notation}")

        return cls(code=code, notation=notation)

    def to_pianyin(self) -> Union[PitchedPianyin, UnpitchedPianyin]:
        """
        将音元对象转换回片音对象

        返回:
            Pianyin: 转换后的片音对象(可能是PitchedPianyin或UnpitchedPianyin)

        异常:
            ValueError: 如果音元代码无效
        """
        if self.code is None:
            raise ValueError("Yinyuan code is required for conversion")

        # 从片音代码获取音质和音调
        base_notation = self._get_base_notation_from_code(self.code)
        if not base_notation:
            raise ValueError(f"Invalid Yinyuan code: {self.code}")

        quality = base_notation[0]
        pitch = base_notation[1:] if len(base_notation) > 1 else None

        # 解析音长和音强
        duration = "neutral"
        loudness = "neutral"

        if "_" in self.notation:
            parts = self.notation.split("_")
            duration = parts[1].split("^")[0] if len(parts) > 1 else "neutral"
        if "^" in self.notation:
            parts = self.notation.split("^")
            loudness = parts[1] if len(parts) > 1 else "neutral"

        # 根据是否有音调决定返回乐音还是噪音
        if pitch:
            return PitchedPianyin(quality=quality, pitch=pitch, duration=duration, loudness=loudness)
        else:
            return UnpitchedPianyin(quality=quality, duration=duration, loudness=loudness)

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

    @staticmethod
    def _define_variables_for_qualities(quality: str) -> str:
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

    @staticmethod
    def _define_variables_for_pitches(pitch: str) -> str:
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

    @staticmethod
    def _get_yinyuan_code(notation: str) -> Optional[int]:
        """根据音元符号获取对应的代码"""
        config_path = os.path.join(os.path.dirname(
            __file__), 'variables_of_pitch_and_quality.json')
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
            quality_variables = config['quality_variables']
            pitch_variables = config['pitch_variables']['dynamic_tonal_elements_model']
            pitch_levels = config['pitch_levels']

        # 特殊处理噪音代码0
        if notation == "m":
            return 0

        # 调试信息
        print(f"Debug - processing notation: {notation}")  # 添加调试输出

        # 解析音质和音调
        if len(notation) < 2:
            print(f"Debug - notation too short: {notation}")  # 添加调试输出
            return None

        quality = notation[0]
        pitch = notation[1:]

        # 获取质元
        quality_unit = None
        for quality, values in quality_variables.items():
            if quality in values:
                quality_unit = quality
                break
        if not quality_unit:
            print(f"Debug - quality not found: {quality}")  # 添加调试输出
            return None

        # 获取调元
        variable_of_pitch = None
        if pitch in pitch_variables['H']:
            variable_of_pitch = "˥"
        elif pitch in pitch_variables['M']:
            variable_of_pitch = "˦"
        elif pitch in pitch_variables['L']:
            variable_of_pitch = "˩"
        if not variable_of_pitch:
            print(f"Debug - pitch not found: {pitch}")  # 添加调试输出
            return None

        # 组合生成代码: 质元序号 * 10 +调元序号
        quality_index = list(quality_variables.keys()).index(quality_unit) + 1
        pitch_value = pitch_levels.get(variable_of_pitch, 0)

        return quality_index * 10 + pitch_value

    @staticmethod
    def _get_base_notation_from_code(code: int) -> str:
        """根据音元代码获取基础符号表示"""
        config_path = os.path.join(os.path.dirname(
            __file__), 'variables_of_pitch_and_quality.json')
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
            quality_variables = config['quality_variables']
            pitch_levels = config['pitch_levels']

        # 特殊处理噪音代码0
        if code == 0:
            return "m"

        # 解析质元和调元
        quality_index = code // 10
        pitch_value = code % 10

        # 获取质元
        if quality_index < 1 or quality_index > len(quality_variables):
            raise ValueError(f"Invalid quality index in code: {code}")

        quality_unit = list(quality_variables.keys())[quality_index - 1]

        # 获取调元
        variable_of_pitch = None
        for p, val in pitch_levels.items():
            if val == pitch_value:
                variable_of_pitch = p
                break
        if not variable_of_pitch:
            raise ValueError(f"Invalid pitch value in code: {code}")

        # 返回组合符号
        return f"{quality_unit}{variable_of_pitch}"
