import json
from pathlib import Path
from typing import Dict, Any
from zaoyin_yinyuan import NoiseYinyuan

def map_shouyin_to_codepoint(shouyin_list):
    """从音元符号列表创建音元到编码点的映射

    Args:
        shouyin_list: 音元符号列表(如从noise_yinyuan.json的keys获取)

    Returns:
        返回一个字典，key是音元符号(如"ɪ́")，value是对应的编码点字符
    """
    start_codepoint = 0x100000  # 从补充私用区开始
    return {yinyuan: chr(start_codepoint + i)
           for i, yinyuan in enumerate(shouyin_list)}

class ShouyinEncoder:
    """首音编码处理器，整合音元映射和音元序列生成功能"""

    def __init__(self):
        self.noise_yinyuan = NoiseYinyuan(quality="")

    def load_shouyin_data(self, input_path: Path) -> Dict[str, Any]:
        """加载首音数据"""
        with input_path.open('r', encoding='utf-8') as f:
            return json.load(f)

    def save_yinyuan_data(self, output_path: Path, data: Dict[str, Any]) -> None:
        """保存音元数据"""
        with output_path.open('w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def convert_pianyin_to_yinyuan(self, pianyin: str) -> str:
        """将片音转换为音元"""
        if not pianyin:
            return ""
        try:
            pianyin = pianyin.split("/")[0]  # 处理多值情况
            quality = pianyin[:-1] if len(pianyin) > 1 else pianyin
            pitch = bool(pianyin[-1]) if len(pianyin) > 1 else False
            processed = self.noise_yinyuan._process_mid_high_model(
                {"temp": (quality, pitch)})
            return next(iter(processed.values())) if processed else ""
        except Exception as e:
            print(f"转换片音到音元时出错: {e}")
            return ""

    def process_shouyin(self, shouyin_data: Dict[str, Any]) -> Dict[str, Any]:
        """处理首音数据生成音元序列"""
        result = {}
        for shouyin_type, shouyin_list in shouyin_data.items():
            if isinstance(shouyin_list, dict):  # 如果是字典结构
                result[shouyin_type] = {
                    shouyin_name: {
                        "首音": self.convert_pianyin_to_yinyuan(parts.get("首音", "")) if isinstance(parts, dict) else self.convert_pianyin_to_yinyuan(parts),
                    }
                    for shouyin_name, parts in shouyin_list.items()
                }
            else:  # 如果是列表或其他结构
                result[shouyin_type] = {
                    shouyin_name: {
                        "首音": self.convert_pianyin_to_yinyuan(shouyin_name),
                    }
                    for shouyin_name in shouyin_list
                }
        return result

    def generate_encoding_files(self):
        """生成所有编码相关文件"""
        base_dir = Path(__file__).parent

        # 1. 生成音元编码映射
        noise_yinyuan_path = base_dir / "yinyuan" / "noise_yinyuan.json"
        with open(noise_yinyuan_path, "r", encoding="utf-8") as f:
            noise_yinyuan_data = json.load(f)

        yinyuan_symbols = map_shouyin_to_codepoint(list(noise_yinyuan_data.keys()))
        encoding_data = {"yinyuan_symbols": yinyuan_symbols}
        encoding_path = base_dir / "yinyuan" / "noise_yinyuan_encoding.json"
        self.save_yinyuan_data(encoding_path, encoding_data)

        # 2. 生成音元序列数据
        input_file = base_dir / 'yinyuan' / 'shouyin.json'
        output_file = base_dir / 'yinyuan' / 'shouyin_to_yinyuan_sequence.json'
        shouyin_data = self.load_shouyin_data(input_file)
        yinyuan_data = self.process_shouyin(shouyin_data)
        self.save_yinyuan_data(output_file, yinyuan_data)

        # 3. 生成音调标记格式数据
        marks_data = self.noise_yinyuan._change_pitch_style(yinyuan_data)
        marks_output_path = output_file.with_name("shouyin_to_yinyuan_seq_marks.json")
        self.save_yinyuan_data(marks_output_path, marks_data)

        # 4. 生成首音音符格式数据
        notes_data = {
            shouyin_type: {
                shouyin_name: {
                    part: yinyuan_symbols.get(symbol, symbol)
                    for part, symbol in parts.items()
                }
                for shouyin_name, parts in marks_data[shouyin_type].items()
            }
            for shouyin_type in marks_data
        }
        notes_output_path = output_file.with_name("shouyin_to_yinyuan_seq_notes.json")
        self.save_yinyuan_data(notes_output_path, notes_data)

        # 5. 生成简化版首音音符数据
        simplified_notes_data = {
            shouyin_name: "".join(parts.values())
            for shouyin_type in notes_data
            for shouyin_name, parts in notes_data[shouyin_type].items()
        }
        fixed_length_encoding_output_path = output_file.with_name("shouyin_to_yinyuan_seq_fixed_length_encoding.json")
        self.save_yinyuan_data(fixed_length_encoding_output_path, simplified_notes_data)

        # 6. 生成首音简式拼式字典
        def simplify_consecutive_chars(s):
            """合并连续相同的音元字符"""
            if not s:
                return s
            result = [s[0]]
            for char in s[1:]:
                if char != result[-1]:
                    result.append(char)
            return "".join(result)

        simplified_dict = {
            shouyin_name: [value, simplify_consecutive_chars(value)]
            for shouyin_name, value in simplified_notes_data.items()
        }
        variable_length_encoding_output_path = output_file.with_name("shouyin_to_yinyuan_seq_variable_length_encoding.json")
        self.save_yinyuan_data(variable_length_encoding_output_path, simplified_dict)

        print(f"首音编码文件已生成:")
        print(f"- 音元符号映射: {encoding_path}")
        print(f"- 音元序列数据: {output_file}")
        print(f"- 首音组合字符字典: {marks_output_path}")
        print(f"- 首音音元字典详版: {notes_output_path}")
        print(f"- 首音完整拼式字典: {fixed_length_encoding_output_path}")
        print(f"- 首音简式拼式字典: {variable_length_encoding_output_path}")

def main():
    encoder = ShouyinEncoder()
    encoder.generate_encoding_files()

if __name__ == "__main__":
    main()