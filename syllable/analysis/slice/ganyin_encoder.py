import json
from pathlib import Path
from typing import Dict, Any, Optional
# from syllable.analysis.slice.yueyin_yinyuan import YueyinYinyuan
from yueyin_yinyuan import YueyinYinyuan

class GanyinEncoder:
    """干音编码处理器，整合音元映射和音元序列生成功能"""

    def __init__(self):
        self.yueyin_yinyuan = YueyinYinyuan(quality="", pitch="")
        # 预加载固定长度编码字典
        self.fixed_length_encoding = self._load_fixed_length_encoding()

    def _load_fixed_length_encoding(self) -> Dict[str, str]:
        """加载固定长度编码字典"""
        encoding_path = Path(__file__).parent / "yinyuan" / "ganyin_to_yinyuan_seq_fixed_length_encoding.json"
        with encoding_path.open('r', encoding='utf-8') as f:
            return json.load(f)


    def encode_ganyin(self, ganyin_name: str) -> Optional[str]:
        """对单个干音进行编码的接口方法(基于预加载编码字典)"""
        if not ganyin_name or not isinstance(ganyin_name, str) or len(ganyin_name) < 2:
            return None

        # 处理特殊干音(如ng5, hm3, hn4, hng2等)
        for prefix in ["ng", "hm", "hn", "hng"]:
            if ganyin_name.startswith(prefix):
                tone = ganyin_name[-1]
                ganyin_name = f"{prefix}{tone}"
                break

        # 从映射表中查找编码
        return self.fixed_length_encoding.get(ganyin_name)

    def load_ganyin_data(self, input_path: Path) -> Dict[str, Any]:
        """加载干音数据"""
        with input_path.open('r', encoding='utf-8') as f:
            return json.load(f)

    def save_yinyuan_data(self, output_path: Path, data: Dict[str, Any]) -> None:
        """保存音元数据"""
        with output_path.open('w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    @classmethod
    def map_yueyin_to_codepoint(cls, yueyin_list):
        """根据音元列表创建由音元到单编码点的映射(类方法)

        Args:
            yueyin_list: 音元符号列表(如从yueyin_yinyuan.json的keys获取)

        Returns:
            返回一个字典，key是音元符号(如"ɪ́")，value是对应的单编码点字符
        """
        start_codepoint = 0x100020  # 从补充私用区开始
        return {yinyuan: chr(start_codepoint + i)
            for i, yinyuan in enumerate(yueyin_list)}

    def convert_pianyin_to_yinyuan(self, pianyin: str) -> str:
        """将片音转换为音元"""
        if not pianyin:
            return ""
        pianyin = pianyin.split("/")[0]  # 处理多值情况
        quality = pianyin[:-1] if len(pianyin) > 1 else pianyin
        pitch = pianyin[-1] if len(pianyin) > 1 else ""
        processed = self.yueyin_yinyuan._process_mid_high_model(
            {"temp": (quality, pitch)})
        return next(iter(processed.keys())) if processed else ""

    def process_ganyin(self, ganyin_data: Dict[str, Any]) -> Dict[str, Any]:
        """处理干音数据生成音元序列"""
        result = {}
        for ganyin_type, ganyin_list in ganyin_data.items():
            result[ganyin_type] = {
                ganyin_name: {
                    "呼音": self.convert_pianyin_to_yinyuan(parts.get("呼音", "")),
                    "主音": self.convert_pianyin_to_yinyuan(parts.get("主音", "")),
                    "末音": self.convert_pianyin_to_yinyuan(parts.get("末音", ""))
                }
                for ganyin_name, parts in ganyin_list.items()
            }
        return result

    def generate_encoding_files(self):
        """生成所有编码相关文件"""
        base_dir = Path(__file__).parent

        # 1. 生成音元编码映射
        yueyin_yinyuan_path = base_dir / "yinyuan" / "yueyin_yinyuan.json"
        with open(yueyin_yinyuan_path, "r", encoding="utf-8") as f:
            yueyin_yinyuan_data = json.load(f)

        yueyin = self.map_yueyin_to_codepoint(list(yueyin_yinyuan_data.keys()))
        encoding_path = base_dir / "yinyuan" / "yinyuan.json"

        # 修改后的文件保存逻辑：检查文件是否为空
        encoding_data = {"yueyin": yueyin}
        try:
            if encoding_path.exists():
                with open(encoding_path, "r", encoding="utf-8") as f:
                    content = f.read()
                    if content.strip():  # 检查文件内容是否非空
                        existing_data = json.loads(content)
                        existing_data["yueyin"] = yueyin
                        encoding_data = existing_data
        except json.JSONDecodeError:
            # 如果文件内容不是有效的JSON，仍然使用新数据覆盖
            pass

        with open(encoding_path, "w", encoding="utf-8") as f:
            json.dump(encoding_data, f, ensure_ascii=False, indent=2)


        # 2. 生成音元序列数据
        input_file = base_dir / 'yinyuan' / 'ganyin_to_pianyin_sequence.json'
        output_file = base_dir / 'yinyuan' / 'ganyin_to_yinyuan_sequence.json'
        ganyin_data = self.load_ganyin_data(input_file)
        yinyuan_data = self.process_ganyin(ganyin_data)
        self.save_yinyuan_data(output_file, yinyuan_data)

        # 3. 生成音调标记格式数据
        marks_data = self.yueyin_yinyuan._change_pitch_style(yinyuan_data)
        marks_output_path = output_file.with_name("ganyin_to_yinyuan_seq_marks.json")
        self.save_yinyuan_data(marks_output_path, marks_data)

        # 4. 生成干音音符格式数据
        notes_data = {
            ganyin_type: {
                ganyin_name: {
                    part: yueyin.get(symbol, symbol)
                    for part, symbol in parts.items()
                }
                for ganyin_name, parts in marks_data[ganyin_type].items()
            }
            for ganyin_type in marks_data
        }
        notes_output_path = output_file.with_name("ganyin_to_yinyuan_seq_notes.json")
        self.save_yinyuan_data(notes_output_path, notes_data)

        # 5. 生成简化版干音音符数据
        simplified_notes_data = {
            ganyin_name: "".join(parts.values())
            for ganyin_type in notes_data
            for ganyin_name, parts in notes_data[ganyin_type].items()
        }
        fixed_length_encoding_output_path = output_file.with_name("ganyin_to_yinyuan_seq_fixed_length_encoding.json")
        self.save_yinyuan_data(fixed_length_encoding_output_path, simplified_notes_data)

        # 6. 生成干音简式拼式字典
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
            ganyin_name: [value, simplify_consecutive_chars(value)]
            for ganyin_name, value in simplified_notes_data.items()
        }
        variable_length_encoding_output_path = output_file.with_name("ganyin_to_yinyuan_seq_variable_length_encoding.json")
        self.save_yinyuan_data(variable_length_encoding_output_path, simplified_dict)

        print(f"音元编码文件已生成:")
        print(f"- 音元符号映射: {encoding_path}")
        print(f"- 音元序列数据: {output_file}")
        print(f"- 干音组合字符字典: {marks_output_path}")
        print(f"- 干音音元字典详版: {notes_output_path}")
        print(f"- 干音完整拼式字典: {fixed_length_encoding_output_path}")
        print(f"- 干音简式拼式字典: {variable_length_encoding_output_path}")



def main():
    encoder = GanyinEncoder()
    encoder.generate_encoding_files()

if __name__ == "__main__":
    main()
