from pathlib import Path
import json
from syllable_structure import SyllableStructure

class SyllableDecoder:
    # === 初始化相关 ===
    def __init__(self, code_file: str | Path | None = None):
        # 如果未传入路径，默认使用模块目录下的 syllable_code.json
        if code_file is None:
            self.code_file = Path(__file__).parent / "syllable_code.json"
        else:
            self.code_file = Path(code_file)
        self.code_map = self._load_code_map()

    def _load_code_map(self):
        if not self.code_file.exists():
            raise FileNotFoundError(f"代码映射文件不存在: {self.code_file}")
        with open(self.code_file, 'r', encoding='utf-8') as f:
            return json.load(f)

    # === 显示辅助方法 ===
    def _display_char(self, char):
        """辅助函数：直接返回字符本身而不是Unicode转义序列"""
        return char if char else ''

    def _display_codes(self, codes):
        """改进的音元列表显示方法"""
        if not codes:
            return "[]"
        return "[" + ", ".join(f"'{self._display_char(c)}'" for c in codes) + "]"

    def split_encoded_syllable(self, encoded_syllable):
        """将编码音节分割为完整的音元结构

        参数:
            encoded_syllable: 编码后的音节字符串(如"abcd")

        返回:
            tuple: (initial, ganyin, (ascender, yunyin), (peak, descender))
        """
        if not encoded_syllable:
            raise ValueError("编码音节不能为空")

        # 分割首音和干音
        initial = encoded_syllable[0] if len(encoded_syllable) > 0 else None
        ganyin = encoded_syllable[1:] if len(encoded_syllable) > 1 else ""

        # 分割呼音和韵音
        ascender = ganyin[0] if len(ganyin) > 0 else None
        yunyin = ganyin[1:] if len(ganyin) > 1 else ""

        # 分割韵音为主音和末音
        peak = yunyin[0] if len(yunyin) > 0 else None
        descender = yunyin[1:] if len(yunyin) > 1 else None

        return (initial, ganyin, (ascender, yunyin), (peak, descender))

    # === 音节分割方法 ===
    def split_syllable(self, encoded_syllable):
        """将编码音节分割为首音和干音两部分

        参数:
            encoded_syllable: 编码后的音节字符串(如"abcd")

        返回:
            tuple: (initial, ganyin) 首音和干音部分

        异常:
            ValueError: 如果输入无效或长度不足
        """
        if not encoded_syllable:
            raise ValueError("编码音节不能为空")
        if len(encoded_syllable) < 2:
            raise ValueError("编码音节长度不足，至少需要2个字符")

        return encoded_syllable[0], encoded_syllable[1:]

    def _get_code(self, pinyin):
        """从code_map中获取拼音对应的编码

        参数:
            pinyin: 拼音字符串

        返回:
            str: 对应的编码字符串，如果找不到则返回None
        """
        return self.code_map.get(pinyin)


    # === 核心解码功能 ===
    def decode(self, pinyin_or_code):
        """解码拼音或直接处理编码字符串"""
        # 扩展PUA字符检测范围(包含Supplementary PUA)
        if any(0xE000 <= ord(c) <= 0xF8FF or  # 基本PUA
            0xF0000 <= ord(c) <= 0xFFFFF or  # Supplementary PUA-A
            0x100000 <= ord(c) <= 0x10FFFF for c in pinyin_or_code):  # Supplementary PUA-B
            try:
                return SyllableStructure(*self.split_encoded_syllable(pinyin_or_code))
            except Exception as e:
                raise ValueError(f"无效的PUA编码格式: {pinyin_or_code}") from e

        # 原有拼音解码逻辑保持不变
        code = self._get_code(pinyin_or_code)
        if not code:
            raise ValueError(f"未找到拼音 '{pinyin_or_code}' 的编码")
        return SyllableStructure(*self.split_encoded_syllable(code))

    def decode_all(self):
        """解码所有拼音为SyllableStructure实例字典"""
        return {pinyin: self.decode(pinyin) for pinyin in self.code_map}

    # === 音元分类和映射生成 ===
    def generate_codes_mapping(self):
        """生成音元分类映射字典（返回字符串列表，避免 tuple/str 混合导致排序/JSON 错误）"""
        all_syllable = self.decode_all()

        mapping = {
            "noise": set(),
            "musical": set()
        }

        for syllable in all_syllable.values():
            noise, musical = syllable.classify_codes()
            mapping["noise"].update(noise)
            mapping["musical"].update(musical)

        # 规范化代码项为字符串：如果是 tuple/list 就拼接其元素为字符串，否则直接 str()
        def _norm(item):
            if isinstance(item, (tuple, list)):
                return ''.join(str(x) for x in item)
            return str(item)

        noise_list = sorted({_norm(i) for i in mapping["noise"]})
        musical_list = sorted({_norm(i) for i in mapping["musical"]})

        return {
            "forward": {
                "noise": noise_list,
                "musical": musical_list
            },
            "reverse": {
                k: "noise" for k in noise_list
            }
        }

    # === 文件操作和保存 ===
    def save_codes_dict(self, codes_dict: dict, out_path: str | Path = None) -> None:
        """
        将 codes_dict 保存为 JSON，确保可排序的字符串列表用于 musical_codes
        """
        if out_path is None:
            out_path = Path(__file__).parent / "syllable_code.json"
        else:
            out_path = Path(out_path)

        # 把 musical_codes 中的元素统一为字符串再排序，避免 tuple 与 str 混合导致排序失败
        musical_codes_normalized = [str(item) for item in codes_dict.get("musical_codes", [])]
        musical_codes_normalized = sorted(musical_codes_normalized)

        to_save = {
            "version": codes_dict.get("version"),
            "musical_codes": musical_codes_normalized,
            "other": codes_dict.get("other")
        }

        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(to_save, f, ensure_ascii=False, indent=2)

    def map_key_to_code(self, output_file='key_to_code.json'):
        """生成ASCII键到PUA字符的映射字典并保存到文件"""
        codes_mapping = self.generate_codes_mapping()
        all_codes = codes_mapping["forward"]["noise"] + codes_mapping["forward"]["musical"]

        key_to_code = {}
        ascii_start = 33  # 从可打印ASCII字符开始

        for codes in all_codes:
            if ascii_start <= 126:
                key_to_code[chr(ascii_start)] = codes
                ascii_start += 1
            else:
                print(f"警告：ASCII码不足，无法为字符 {codes} 分配键位")

        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(key_to_code, f, ensure_ascii=False, indent=2)

        print(f"已生成并保存键位映射到 {output_file}")
        return key_to_code

    def get_ganyin(self, encoded_syllable):
        """获取干音部分"""
        _, ganyin, _, _ = self.split_encoded_syllable(encoded_syllable)
        return ganyin

    def get_yunyin(self, encoded_syllable):
        """获取韵音部分"""
        _, _, (_, yunyin), _ = self.split_encoded_syllable(encoded_syllable)
        return yunyin

    def get_jianyin_code(self, encoded_syllable):
        """获取间音部分编码(首音和末音之间的音元)

        参数:
            encoded_syllable: 编码后的音节字符串(如"abcd")

        返回:
            str: 由呼音和主音组成的字符串，如果不存在则返回空字符串
        """
        _, _, (ascender, _), (peak, _) = self.split_encoded_syllable(encoded_syllable)
        return (ascender or '') + (peak or '')

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
