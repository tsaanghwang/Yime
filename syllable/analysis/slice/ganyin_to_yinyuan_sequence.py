"""
干音的音元表示法
功能：生成干音的音元序列
流程：读取干音与片音序列的映射数据，并将其转换为干音与音元序列的映射数据。
"""
import json
from pathlib import Path
from typing import Dict, Any
from yueyin_yinyuan import YueyinYinyuan

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent))
from syllable import Syllable  # When run directly as a

class GanyinToYinyuanSequence:
    """将干音转换为音元序列的处理器"""

    def __init__(self):
        self.yueyin_yinyuan = YueyinYinyuan(quality="", pitch="")

    def load_ganyin_data(self, input_path: Path) -> Dict[str, Any]:
        """加载干音数据"""
        with input_path.open('r', encoding='utf-8') as f:
            return json.load(f)

    def save_yinyuan_data(self, output_path: Path, data: Dict[str, Any]) -> None:
        """保存音元数据"""
        with output_path.open('w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False,
                      indent=2, separators=(',', ': '))

    def convert_pianyin_to_yinyuan(self, pianyin: str) -> str:
        """将片音转换为音元"""
        if not pianyin:
            return ""
        pianyin = pianyin.split("/")[0]  # 处理多值情况
        quality = pianyin[:-1] if len(pianyin) > 1 else pianyin
        pitch = pianyin[-1] if len(pianyin) > 1 else ""
        processed = self.yueyin_yinyuan._process_yueyin(
            {"temp": (quality, pitch)})
        return next(iter(processed.keys())) if processed else ""

    def process_ganyin(self, ganyin_data: Dict[str, Any]) -> Dict[str, Any]:
        """处理干音数据"""
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

    def run(self, input_path: Path, output_path: Path) -> Dict[str, Any]:
        """执行转换流程"""
        ganyin_data = self.load_ganyin_data(input_path)
        yinyuan_data = self.process_ganyin(ganyin_data)
        self.save_yinyuan_data(output_path, yinyuan_data)
        return yinyuan_data


def main():
    converter = GanyinToYinyuanSequence()
    base_dir = Path(__file__).parent
    input_file = base_dir / "ganyin_to_pianyin_sequence.json"
    output_file = base_dir / "ganyin_to_yinyuan_sequence.json"
    result = converter.run(input_file, output_file)

    # 转换音调标记方式并保存新格式结果
    marks_data = converter.yueyin_yinyuan._change_pitch_style(result)
    marks_output_path = output_file.with_name(
        "ganyin_to_yinyuan_seq_marks.json")
    converter.save_yinyuan_data(marks_output_path, marks_data)

    print(f"转换完成，结果已保存到 {output_file}")
    print(f"音调标记转换结果已保存到 {marks_output_path}")


if __name__ == "__main__":
    main()
