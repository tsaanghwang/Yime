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
import sys
from pathlib import Path

# 添加项目根目录到 Python 路径
project_root = Path(__file__).parent.parent  # 注意这里改为.parent.parent
sys.path.append(str(project_root))

# 然后进行其他导入
sys.path.append(str(Path(__file__).parent / "syllable" / "analysis" / "slice"))
from syllable.analysis.slice.run_analyzer import analyze_syllable
from syllable.analysis.slice.ganyin_categorizer import GanyinCategorizer
from syllable.analysis.slice.ganyin_encoder import GanyinEncoder
from syllable.analysis.slice.shouyin_encoder import ShouyinEncoder

sys.path.append(str(Path(__file__).parent.parent.parent))  # Adjust the path as needed
from pianyin import pitched_yinyuan
# from pinyin.hanzi_pinyin import pinyin_normalizer

# 步骤1：定义读取音节数据的路径
sys.path.append(str(Path(__file__).parent / "pinyin" / "hanzi_pinyin"))
# import pinyin_normalizer
# PINYIN_JSON_PATH = Path(__file__).parent / "pinyin" / "hanzi_pinyin" / "pinyin_normalized.json"

# 步骤2-4：导入音节切分和编码相关模块

def encode_single_yinjie(syllable: str) -> str:
    """
    对单个音节进行编码，返回编码字符串
    """
    # 切分音节为首音和干音
    shouyin, ganyin = analyze_syllable(syllable)
    # 编码首音
    shouyin_code = ShouyinEncoder.encode_shouyin('', shouyin = Dict)
    # 编码干音
    ganyin_code = GanyinEncoder.encode_ganyin('', ganyin_data = Dict)
    # 拼接编码
    yinjie = shouyin_code["首音"] + ganyin_code["呼音"] + ganyin_code["主音"] + ganyin_code["末音"]
    # 返回编码
    return yinjie

def encode_all_yinjie():
    """
    读取音节数据，批量编码所有音节，写入文件/数据库/redis
    """
    # 步骤1：读取音节数据
    with open(Path(__file__) / "pinyin_normalized.json", "r", encoding="utf-8") as f:
        pinyin_data = json.load(f)
    yinjie_list = list(pinyin_data.keys())

    # 生成音节编码字典
    yinjie_code_dict = {}
    for yinjie in yinjie_list:
        try:
            code = encode_single_yinjie(yinjie)
            yinjie_code_dict[yinjie] = code
        except Exception as e:
            # 可以记录日志或跳过异常音节
            continue
        except Exception:
            # 可以记录日志或跳过异常音节
            continue
    output_path = Path(__file__).parent / "yinyuan" / "yinjie_code.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(yinjie_code_dict, f, ensure_ascii=False, indent=2)

def map_yinjie_to_codepoint(yinjie_list):
    """从音节列表创建音节到单编码点的映射

    Args:
        yinjie_list: 音节列表

    Returns:
        返回一个字典，key是音节，value是对应的单编码点字符
    """
    start_codepoint = 0x100800  # 从补充私用区U+100800开始
    return {yinjie: chr(start_codepoint + i)
           for i, yinjie in enumerate(yinjie_list)}

class YinjieEncoder:
    """音节编码处理器，整合音元映射和音元序列生成功能"""

    def __init__(self):
        """初始化音节编码器"""
        pass

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
        base_dir = Path(__file__).parent

        # 1. 生成音节编码映射
        yinjie_path = base_dir / "yinyuan" / "yinjie.json"
        with open(yinjie_path, "r", encoding="utf-8") as f:
            yinjie_data = json.load(f)

        yinjie_list = list(yinjie_data.get("yinjie", {}).keys())
        codepoint_mapping = map_yinjie_to_codepoint(yinjie_list)

        # 简化输出结构，只保留编码映射部分
        encoding_data = {
            "yinjie": codepoint_mapping
        }

        encoding_path = base_dir / "yinyuan" / "yinjie_encoding.json"

        # 处理空文件或不存在的情况
        existing_data = {}
        if encoding_path.exists():
            try:
                with open(encoding_path, "r", encoding="utf-8") as f:
                    content = f.read()
                    if content.strip():  # 检查文件是否非空
                        existing_data = json.loads(content)
            except json.JSONDecodeError:
                # 如果文件内容不是有效的JSON，创建新文件
                existing_data = {}

        # 更新数据
        existing_data.update(encoding_data)
        encoding_data = existing_data

        self.save_yinyuan_data(encoding_path, encoding_data)

        # 2. 生成音节符号映射
        input_file = base_dir / 'yinyuan' / 'yinjie.json'
        output_file = base_dir / 'yinyuan' / 'yinjie_yinyuan.json'

        yinjie_data = self.load_yinjie_data(input_file)
        yinyuan_data = self.process_yinjie(yinjie_data)

        # 获取音节列表并映射为编码点
        yinjie_list = yinyuan_data.get("音节", [])
        codepoint_mapping = map_yinjie_to_codepoint(yinjie_list)

        # 保存结果
        result_data = {
            "音节": {yinjie: codepoint for yinjie, codepoint in codepoint_mapping.items()}
        }
        self.save_yinyuan_data(output_file, result_data)

        print(f"音节编码字典:")
        print(f"- 音节码元映射: {encoding_path}")
        print(f"- 音节音元映射: {output_file}")

def main():
    """主函数"""
    encoder = YinjieEncoder()
    encoder.generate_encoding_files()

if __name__ == "__main__":
    main()
