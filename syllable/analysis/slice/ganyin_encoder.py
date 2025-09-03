import json
from typing import Dict, Any, Optional
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from syllable.analysis.slice.yueyin_yinyuan import YueyinYinyuan

class GanyinEncoder:
    """干音编码处理器，整合音元映射和音元序列生成功能"""

    # 类常量
    START_CODEPOINT = 0x100020
    SUBDIR = "yinyuan"
    ZAOYIN_FILENAME = "zaoyin_yinyuan.json"
    YUEYIN_FILENAME = "yueyin_yinyuan.json"
    YINYUAN_FILENAME = "yinyuan_codepoint.json"
    DINGCHANGMA_FILENAME = "ganyin_to_fixed_length_yinyuan_sequence.json"
    BIANCHANGMA_FILENAME = "ganyin_to_variable_length_yinyuan_sequence.json"

    def __init__(self):
        self.yueyin_yinyuan = YueyinYinyuan(quality="", pitch="")
        self.module_dir = Path(__file__).parent

        # 预加载固定长度编码字典
        self.fixed_length_encoding = self._load_fixed_length_encoding()

        # 修复路径 - 直接使用 yinyuan 子目录
        mapping_path = self.module_dir / self.SUBDIR / self.DINGCHANGMA_FILENAME
        with open(mapping_path, 'r', encoding='utf-8') as f:
            self.encoding_map = json.load(f)

    def _load_fixed_length_encoding(self) -> Dict[str, str]:
        """加载固定长度编码字典"""
        # 修复路径 - 直接使用 yinyuan 子目录
        encoding_path = self.module_dir / self.SUBDIR / self.DINGCHANGMA_FILENAME
        with encoding_path.open('r', encoding='utf-8') as f:
            return json.load(f)

    def encode_ganyin(self, ganyin: str) -> str:
        """
        编码干音字符串为音元序列

        参数:
            ganyin: 干音字符串，格式为"韵母+声调"，如"i1", "a2"等

        返回:
            对应的音元编码字符串

        异常:
            ValueError: 当输入不是有效的干音时抛出
        """
        # 输入验证
        if not self._is_valid_ganyin(ganyin):
            raise ValueError(f"无效的干音输入: '{ganyin}'")

        # 返回映射结果
        return self.encoding_map[ganyin]

    def _is_valid_ganyin(self, ganyin: str) -> bool:
        """检查输入是否是有效的干音格式"""
        if not isinstance(ganyin, str) or len(ganyin) < 2:
            return False

        # 检查是否在编码映射中
        return ganyin in self.encoding_map

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
        return {yinyuan: chr(cls.START_CODEPOINT + i)
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

        # 1. 生成音元编码映射
        yueyin_yinyuan_path = self.module_dir / self.SUBDIR / self.YUEYIN_FILENAME
        with open(yueyin_yinyuan_path, "r", encoding="utf-8") as f:
            yueyin_yinyuan_data = json.load(f)

        yueyin = self.map_yueyin_to_codepoint(list(yueyin_yinyuan_data.keys()))
        encoding_path = self.module_dir / self.SUBDIR / self.YINYUAN_FILENAME

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
        input_file = self.module_dir / self.SUBDIR / 'ganyin_to_pianyin_sequence.json'
        output_file = self.module_dir / self.SUBDIR / 'ganyin_to_yinyuan_sequence.json'
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
        fixed_length_encoding_output_path = output_file.with_name(self.DINGCHANGMA_FILENAME)
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
        variable_length_encoding_output_path = output_file.with_name(self.BIANCHANGMA_FILENAME)
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
