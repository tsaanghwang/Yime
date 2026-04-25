import json
from typing import Dict, Any
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from syllable.analysis.slice.yueyin_yinyuan import YueyinYinyuan

class GanyinEncoder:
    """干音编码处理器，整合音元映射和音元序列生成功能"""

    # 类常量
    SUBDIR = "yinyuan"
    YUEYIN_SOURCE_FILENAME = "yueyin_yinyuan_enhanced.json"
    YUEYIN_COMPAT_FILENAME = "yueyin_yinyuan.json"
    YINYUAN_FILENAME = "yinyuan_codepoint.json"
    DINGCHANGMA_FILENAME = "ganyin_to_fixed_length_yinyuan_sequence.json"
    BIANCHANGMA_FILENAME = "ganyin_to_variable_length_yinyuan_sequence.json"

    def __init__(self):
        self.yueyin_yinyuan = YueyinYinyuan(quality="", pitch="")
        self.module_dir = Path(__file__).parent
        self.yueyin_source = self._load_yueyin_source()
        self.yueyin_codepoints = self._load_yueyin_codepoints()
        self.ganyin_part_map = self._load_ganyin_part_map()

    def _load_yueyin_source(self) -> Dict[str, Any]:
        source_path = self.module_dir / self.SUBDIR / self.YUEYIN_SOURCE_FILENAME
        with source_path.open('r', encoding='utf-8') as f:
            return json.load(f)

    def process_yueyin_source(self, source_data: Dict[str, Any]) -> Dict[str, Any]:
        entries = source_data.get("entries", {})
        if not entries:
            raise ValueError("干音真源缺少 entries")

        runtime_map: Dict[str, str] = {}
        aliases_map: Dict[str, list[str]] = {}
        semantic_codes: Dict[str, str] = {}
        layout_slots: Dict[str, str] = {}

        for canonical_symbol, entry in entries.items():
            runtime_char = entry.get("runtime_char", "")
            semantic_code = entry.get("semantic_code", "")
            layout_slot = entry.get("layout_slot", "")
            aliases = entry.get("aliases", [])

            if not runtime_char:
                raise ValueError(f"乐音 `{canonical_symbol}` 缺少 runtime_char")
            if not semantic_code:
                raise ValueError(f"乐音 `{canonical_symbol}` 缺少 semantic_code")
            if not layout_slot:
                raise ValueError(f"乐音 `{canonical_symbol}` 缺少 layout_slot")
            if not isinstance(aliases, list):
                raise ValueError(f"乐音 `{canonical_symbol}` 的 aliases 必须是数组")

            runtime_map[canonical_symbol] = runtime_char
            aliases_map[canonical_symbol] = aliases
            semantic_codes[canonical_symbol] = semantic_code
            layout_slots[canonical_symbol] = layout_slot

        return {
            "yueyin": runtime_map,
            "aliases": aliases_map,
            "semantic_codes": semantic_codes,
            "layout_slots": layout_slots,
        }

    def _load_yueyin_codepoints(self) -> Dict[str, str]:
        """从音元定义生成单码点映射，并展开所有别名写法。"""
        processed_source = self.process_yueyin_source(self.yueyin_source)
        yueyin_data = processed_source["aliases"]
        canonical_codepoints = processed_source["yueyin"]

        expanded_codepoints: Dict[str, str] = {}

        for canonical_symbol, aliases in yueyin_data.items():
            codepoint = canonical_codepoints[canonical_symbol]
            expanded_codepoints[canonical_symbol] = codepoint
            for alias in aliases:
                expanded_codepoints[alias] = codepoint

        return expanded_codepoints

    def _load_ganyin_part_map(self) -> Dict[str, Dict[str, str]]:
        """加载干音到片音序列的原始映射。"""
        parts_path = self.module_dir / self.SUBDIR / 'ganyin_to_pianyin_sequence.json'
        with parts_path.open('r', encoding='utf-8') as f:
            grouped_parts = json.load(f)

        return {
            ganyin_name: parts
            for ganyin_group in grouped_parts.values()
            for ganyin_name, parts in ganyin_group.items()
        }

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
        normalized_ganyin = self._normalize_ganyin_name(ganyin)

        # 输入验证
        if not self._is_valid_ganyin(normalized_ganyin):
            raise ValueError(f"无效的干音输入: '{ganyin}'")

        return self._encode_from_parts(normalized_ganyin)

    def _normalize_ganyin_name(self, ganyin: str) -> str:
        """将带 h 的特殊鼻音干音归并到基础干音键名。"""
        if not isinstance(ganyin, str):
            return ""

        for source, target in (("hng", "ng"), ("hm", "m"), ("hn", "n")):
            if ganyin.startswith(source) and len(ganyin) >= len(source) + 1:
                return f"{target}{ganyin[-1]}"

        return ganyin

    def _encode_from_parts(self, ganyin: str) -> str:
        """按呼音/主音/末音序列即时生成三码编码。"""
        parts = self.ganyin_part_map[ganyin]
        yinyuan_symbols = [
            self.convert_pianyin_to_yinyuan(parts.get("呼音", "")),
            self.convert_pianyin_to_yinyuan(parts.get("主音", "")),
            self.convert_pianyin_to_yinyuan(parts.get("末音", "")),
        ]

        return "".join(self._resolve_yinyuan_codepoint(symbol) for symbol in yinyuan_symbols)

    def _resolve_yinyuan_codepoint(self, symbol: str) -> str:
        """把音元符号解析到当前仓库使用的单码点字符。"""
        if symbol in self.yueyin_codepoints:
            return self.yueyin_codepoints[symbol]

        normalized_symbol = self._convert_pitch_number_to_mark(symbol)
        if normalized_symbol in self.yueyin_codepoints:
            return self.yueyin_codepoints[normalized_symbol]

        raise KeyError(symbol)

    def _convert_pitch_number_to_mark(self, symbol: str) -> str:
        """将末尾的音高符号改写为仓库当前使用的调号写法。"""
        if not symbol:
            return symbol

        pitch_marks = self.yueyin_yinyuan.config["pitch_variables"]["pitch_marks"]
        pitch = symbol[-1]
        if pitch not in pitch_marks:
            return symbol

        return symbol[:-1] + pitch_marks[pitch][0]

    def _is_valid_ganyin(self, ganyin: str) -> bool:
        """检查输入是否是有效的干音格式"""
        if not isinstance(ganyin, str) or len(ganyin) < 2:
            return False

        return ganyin in self.ganyin_part_map

    def load_ganyin_data(self, input_path: Path) -> Dict[str, Any]:
        """加载干音数据"""
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
        processed_source = self.process_yueyin_source(self.yueyin_source)
        yueyin = processed_source["yueyin"]
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

        compat_path = self.module_dir / self.SUBDIR / self.YUEYIN_COMPAT_FILENAME
        with open(compat_path, "w", encoding="utf-8") as f:
            json.dump(processed_source["aliases"], f, ensure_ascii=False, indent=2)


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
        print(f"- 兼容乐音清单: {compat_path}")
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
