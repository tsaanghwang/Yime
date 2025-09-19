from pathlib import Path
import json
from typing import Tuple, Any

class SyllableDecoder:
    # === 初始化相关 ===
    def __init__(self, code_file: str | Path | None = None):
        # 默认使用绝对路径，确保始终加载同一文件
        if code_file is None:
            self.code_file = Path(r"C:\Users\Freeman Golden\OneDrive\Yime\yime\syllable_code.json")
        else:
            self.code_file = Path(code_file)
        self.code_map = self._load_code_map()

    def _load_code_map(self) -> dict:
        if not self.code_file.exists():
            return {}
        with open(self.code_file, "r", encoding="utf-8") as f:
            try:
                return json.load(f)
            except Exception:
                return {}

    def _get_code(self, key: str) -> Any:
        """返回与拼音对应的编码（或 None）"""
        # 支持直接以全拼/PUA查找或以键查找
        if key in self.code_map:
            return self.code_map[key]
        # 反查：若 value 等于 key
        for k, v in self.code_map.items():
            if v == key:
                return v
        return None

    def split_encoded_syllable(self, encoded: str) -> Tuple[str, None, Tuple[str, str], Tuple[str, str]]:
        """
        返回符合导入器期望的结构：
        (initial, None, (ascender, yunyin), (peak, descender))
        这是简化实现，实际解析器可替换此逻辑。
        """
        s = encoded or ""
        initial = s[0] if len(s) > 0 else ""
        ascender = s[1] if len(s) > 1 else ""
        peak = s[2] if len(s) > 2 else ""
        descender = s[-1] if len(s) > 0 else ""
        # yunyin 与 ascender 的简化映射
        yunyin = descender
        return (initial, None, (ascender, yunyin), (peak, descender))

    def get_ganyin(self, code_or_input: str) -> str:
        """示例：返回干音（简化）"""
        c = self._get_code(code_or_input) or code_or_input
        return (c[0] if c else "") if isinstance(c, str) else ""

    def get_yunyin(self, code_or_input: str) -> str:
        """示例：返回韵音（简化）"""
        c = self._get_code(code_or_input) or code_or_input
        return (c[-1] if c else "") if isinstance(c, str) else ""

    def get_jianyin_code(self, code_or_input: str) -> str:
        """示例：返回简拼（非常简单的缩写）"""
        c = self._get_code(code_or_input) or code_or_input
        if not isinstance(c, str) or not c:
            return ""
        # 取前两个字符作为简拼示例
        return c[:2]

    # === 主程序示例 ===
    @staticmethod
    def run_example():
        """运行解码器示例"""
        decoder = SyllableDecoder()
        # 先生成 codes_dict 并传入 save_codes_dict
        codes_dict = decoder.generate_codes_mapping()
        decoder.save_codes_dict(codes_dict)

        examples = ["ma1", "ni3", "hao3", "shang4", "xia4"]
        for pinyin in examples:
            try:
                syllable = decoder.decode(pinyin)
                print(f"\n解码 '{pinyin}':")
                print(f"音节线性结构: {syllable}")
                noise, musical = syllable.classify_codes()
                print(f"噪音音元: {decoder._display_codes(noise)}")
                print(f"乐音音元: {decoder._display_codes(musical)}")
            except ValueError as e:
                print(f"解码 '{pinyin}' 时出错: {e}")

        all_syllable = decoder.decode_all()
        print(f"\n解码了 {len(all_syllable)} 个音节")
        decoder.map_key_to_code()

if __name__ == "__main__":
    SyllableDecoder.run_example()
