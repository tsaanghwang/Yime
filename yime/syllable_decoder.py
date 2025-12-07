from pathlib import Path
import json
from typing import Tuple, Any
from utils_charfilter import is_allowed_code_char, is_pua_char

try:
    from yime.syllable_structure import SyllableStructure
except Exception:
    try:
        from syllable_structure import SyllableStructure
    except Exception:
        SyllableStructure = None

def _normalize_split(res):
    """把不同实现的返回值归一化为 (initial, None, (ascender,yunyin), (peak,descender))"""
    if not res:
        return None
    if isinstance(res, (list, tuple)):
        # 最常见的期望形状或子集
        if len(res) == 4:
            return tuple(res)
        # 某些实现可能返回 dict 或扁平结构，尝试适配常见情况
        if len(res) >= 3:
            initial = res[0]
            third = res[2] if len(res) > 2 else ("", "")
            fourth = res[3] if len(res) > 3 else ("", "")
            return (initial, None, tuple(third), tuple(fourth))
    # 不可识别的结构
    return None

def is_pua_string(s: str) -> bool:
    """判断是否全由 PUA 字符构成（仅用于区分 PUA，不据此拒绝其它编码）"""
    return bool(s) and all(is_pua_char(ch) for ch in s)

def is_valid_encoded_string(s: str) -> bool:
    """允许任意非控制字符；使用统一判定函数以兼容自定义音码"""
    return bool(s) and all(is_allowed_code_char(ch) for ch in s)
# 在需要“是否有效编码”的地方改为调用 is_valid_encoded_string

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

    def split_encoded_syllable(self, encoded: str) -> 'SyllableStructure':
        """
        统一入口：优先使用 SyllableStructure.split_encoded_syllable（若可用），
        否则本地解析并返回 SyllableStructure 实例。
        """
        if SyllableStructure is not None and hasattr(SyllableStructure, "split_encoded_syllable"):
            try:
                return SyllableStructure.split_encoded_syllable(encoded)
            except Exception:
                # 安静回退到本地实现
                pass

        # 本地解析（与 SyllableStructure.split_encoded_syllable 保持一致的分解规则）
        if not encoded:
            raise ValueError("encoded syllable required")
        initial = encoded[0] if len(encoded) > 0 else None
        ganyin = encoded[1:] if len(encoded) > 1 else ""
        ascender = ganyin[0] if len(ganyin) > 0 else None
        yunyin = ganyin[1:] if len(ganyin) > 1 else ""
        peak = yunyin[0] if len(yunyin) > 0 else None
        descender = yunyin[1:] if len(yunyin) > 1 else None

        # 构造并返回 SyllableStructure（若导入失败则返回简单命名空间）
        if SyllableStructure is not None:
            return SyllableStructure(
                initial=initial,
                ascender=ascender,
                peak=peak,
                descender=descender
            )
        else:
            # 轻量回退对象
            class _S:
                def __init__(self,i,a,p,d):
                    self.initial=i; self.ascender=a; self.peak=p; self.descender=d
                def get_full_code(self): return ''.join(x for x in (self.initial or '', self.ascender or '', self.peak or '', self.descender or ''))
                def get_ganyin_code(self): return (self.ascender or '') + (self.peak or '') + (self.descender or '')
                def get_jianyin_code(self): return (self.ascender or '') + (self.peak or '')
                def get_abbreviation(self): return (self.initial or '') + ((self.ascender or '')[:1] if (self.ascender or '') else '')
            return _S(initial, ascender, peak, descender)

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
