"""
    音节编码
    功能：根据Yinjie类定义的音节结构将音节编码为字符串
    流程：
    1. 读取音节pinyin\hanzi_pinyin\pinyin_normalized.json
    2. 调用syllable\analysis\slice\run_analyzer.py将音节切分为首音和干音两段
    3. 调用syllable\analysis\slice\shouyin_encoder.py将shouyin类对象转换为code
    4. 调用syllable\analysis\slice\ganyin_encoder.py将干音类对象转换为code序列
    5. 将shouyin_code和ganyin_code序列拼接为音节code
    6. 将音节code写入文件
"""
from typing import Dict, Any
import json
import os
import sys
import datetime
from pathlib import Path

# 添加项目根目录到 Python 路径
project_root = Path(__file__).parent.parent.parent.parent  # 注意这里改为.parent.parent
sys.path.append(str(project_root))

# 然后进行其他导入
sys.path.append(str(Path(__file__).parent / "syllable" / "analysis" / "slice"))
# from .run_analyzer import analyze_syllable
from .run_analyzer import analyze_syllable
# from syllable.analysis.slice.shouyin_encoder import ShouyinEncoder
from .shouyin_encoder import ShouyinEncoder
# from syllable.analysis.slice.ganyin_encoder import GanyinEncoder
from .ganyin_encoder import GanyinEncoder
# from syllable.analysis.slice.ganyin_categorizer import GanyinCategorizer

sys.path.append(str(Path(__file__).parent.parent.parent))  # Adjust the path as needed
# from syllable.analysis.slice.pianyin import PitchedPianyin

class YinjieEncoder:
    """音节编码处理器，整合音元映射和音元序列生成功能"""

    def __init__(self):
        """初始化音节编码器"""
        pass

    def encode_single_yinjie(syllable: str) -> str:
        """
        对单个音节进行编码，返回编码字符串
        """
        # 切分音节为首音和干音
        shouyin, ganyin = analyze_syllable(syllable)
        # 编码首音
        shouyin_code = ShouyinEncoder.encode_shouyin('', shouyin=shouyin)  # 传递实际shouyin对象
        # 编码干音
        ganyin_code = GanyinEncoder.encode_ganyin('', ganyin_data=ganyin)  # 传递实际ganyin对象
        # 拼接编码
        yinjie = shouyin_code["首音"] + ganyin_code["呼音"] + ganyin_code["主音"] + ganyin_code["末音"]
        # 返回编码
        return yinjie

    def encode_all_yinjie(self):
        """
        读取音节数据，批量编码所有音节，写入文件/数据库/redis
        """
        # 步骤1：读取音节数据
        with open(Path(__file__).parent / "pinyin_normalized.json", "r", encoding="utf-8") as f:
            pinyin_data = json.load(f)
        yinjie_list = list(pinyin_data.keys())

        # 生成音节编码字典
        yinjie_code_dict = {}
        for yinjie in yinjie_list:
            try:
                code = self.encode_single_yinjie(yinjie)
                yinjie_code_dict[yinjie] = code
            except Exception as e:
                # 可以记录日志或跳过异常音节
                continue
            except Exception:
                # 可以记录日志或跳过异常音节
                continue

        output_path = Path(__file__).parent / "yinyuan" / "yinjie_code.json"
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(yinjie_code_dict, f, ensure_ascii=False, indent=2)

    def map_yinjie_to_codepoint(self, yinjie_list):
        """从音节列表创建音节到单编码点的映射

        Args:
            yinjie_list: 音节列表

        Returns:
            返回一个字典，key是音节，value是对应的单编码点字符
        """
        start_codepoint = 0x100800  # 从补充私用区U+100800开始
        return {yinjie: chr(start_codepoint + i)
               for i, yinjie in enumerate(yinjie_list)}

    def load_yinjie_data(self, input_path: Path) -> Dict[str, Any]:
        """加载音节数据

        Args:
            input_path: 输入文件路径

        Returns:
            返回加载的音节数据字典
        """
        with input_path.open('r', encoding='utf-8') as f:
            return json.load(f)

    def save_yinyuan_data(self, output_path: Path, data: Dict[str, Any]) -> None:
        """保存音元数据到文件

        Args:
            output_path: 输出文件路径
            data: 要保存的音元数据
        """
        with output_path.open('w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def process_yinjie(self, yinjie_data: Dict[str, Any]) -> Dict[str, Any]:
        """处理音节数据，生成音元序列

        Args:
            yinjie_data: 输入的音节数据

        Returns:
            处理后的音元序列数据
        """
        result = {}

        # 情况1：处理带有codes字段的结构
        if "codes" in yinjie_data:
            codes = yinjie_data.get("codes", {})
            return {"音节": list(codes.keys())}

        # 情况2：处理带有yinjie字段的结构
        elif "yinjie" in yinjie_data:
            yinjie = yinjie_data.get("yinjie", {})
            return {"音节": list(yinjie.keys())}

        # 其他情况返回空字典
        return result

    def generate_encoding_files(self):
        """生成所有编码相关文件"""
        # 1. 定义输入输出文件路径

        # 获取当前脚本的绝对路径
        current_dir = os.path.dirname(os.path.abspath(file))

        # 构建输入文件路径 - 使用 os.path 确保跨平台兼容性
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(current_dir)))
        self.input_path = os.path.normpath(os.path.join(
            project_root,
            'pinyin',
            'hanzi_pinyin',
            'pinyin_normalized.json'
        ))
        input_path = current_dir / "pinyin" / "hanzi_pinyin" / "pinyin_normalized.json"
        output_path = current_dir / "yinjie.json"

        # 2. 检查输入文件是否存在
        if not input_path.exists():
            raise FileNotFoundError(f"输入文件不存在: {input_path}")

        # 3. 加载输入数据
        try:
            with open(input_path, "r", encoding="utf-8") as f:
                pinyin_data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"输入文件格式错误: {input_path}") from e

        # 4. 处理数据并生成编码
        yinjie_list = list(pinyin_data.keys())  # 假设pinyin_data的键就是音节列表
        codepoint_mapping = self.map_yinjie_to_codepoint(yinjie_list)

        # 5. 保存结果到yinjie.json
        result_data = {
            "yinjie": codepoint_mapping,
            "metadata": {
                "source": str(input_path),
                "generated_at": datetime.datetime.now().isoformat()
            }
        }

        # 确保输出目录存在
        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(result_data, f, ensure_ascii=False, indent=2)

        print(f"成功生成音节编码文件: {output_path}")

def main():
    """主函数"""
    encoder = YinjieEncoder()
    # 可以选择调用哪个功能
    encoder.generate_encoding_files()
    # 或者调用 encoder.encode_all_yinjie()

if __name__ == "__main__":
    main()