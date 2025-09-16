import json
from syllable_structure import SyllableStructure

class SyllableDecoder:
    # === 初始化相关 ===
    def __init__(self, code_file='syllable_code.json'):
        """初始化解码器，加载编码文件"""
        self.code_file = code_file
        self.code_map = self._load_code_map()

    def _load_code_map(self):
        """从JSON文件加载编码映射"""
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

    # === 核心解码功能 ===
    def decode(self, pinyin):
        """解码单个拼音为SyllableStructure实例"""
        code = self.code_map.get(pinyin)
        if not code:
            raise ValueError(f"未找到拼音 '{pinyin}' 的编码")

        if len(code) != 4:
            raise ValueError(f"编码 '{code}' 长度不正确，应为4个字符")

        syllable = SyllableStructure(
            initial=code[0],  # 首音
            ascender=code[1], # 呼音
            peak=code[2],     # 主音
            descender=code[3] # 末音
        )

        # 添加音元分类信息
        noise, musical = syllable.classify_codes()
        syllable.noise_codes = noise
        syllable.musical_codes = musical

        return syllable

    def decode_all(self):
        """解码所有拼音为SyllableStructure实例字典"""
        return {pinyin: self.decode(pinyin) for pinyin in self.code_map}

    # === 音元分类和映射生成 ===
    def generate_codes_mapping(self):
        """生成音元分类映射字典"""
        all_syllable = self.decode_all()

        mapping = {
            "noise": set(),
            "musical": set()
        }

        for syllable in all_syllable.values():
            noise, musical = syllable.classify_codes()
            mapping["noise"].update(noise)
            mapping["musical"].update(musical)

        return {
            "forward": {
                "noise": sorted(mapping["noise"]),
                "musical": sorted(mapping["musical"])
            },
            "reverse": {
                codes: "noise" for codes in mapping["noise"]
            }
        }

    # === 文件操作和保存 ===
    def save_codes_dict(self, output_file='codes_dict.json'):
        """将分类后的音元保存到JSON文件"""
        codes_dict = {
            "noise_codes": set(),
            "musical_codes": set()
        }

        all_syllable = self.decode_all()

        for syllable in all_syllable.values():
            noise, musical = syllable.classify_codes()
            codes_dict["noise_codes"].update(noise)
            codes_dict["musical_codes"].update(musical)

        codes_dict = {
            "noise_codes": sorted(codes_dict["noise_codes"]),
            "musical_codes": sorted(codes_dict["musical_codes"])
        }

        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(codes_dict, f, ensure_ascii=False, indent=2)

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

    # === 主程序示例 ===
    @staticmethod
    def run_example():
        """运行解码器示例"""
        decoder = SyllableDecoder()
        decoder.save_codes_dict()

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