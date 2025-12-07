# yinjie_decoder.py
import json
from yinjie import Yinjie

class YinjieDecoder:
    # === 初始化相关 ===
    def __init__(self, code_file='yinjie_code.json'):
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

    def _display_phonemes(self, phonemes):
        """改进的音元列表显示方法"""
        if not phonemes:
            return "[]"
        return "[" + ", ".join(f"'{self._display_char(c)}'" for c in phonemes) + "]"

    # === 核心解码功能 ===
    def decode(self, pinyin):
        """解码单个拼音为Yinjie实例"""
        code = self.code_map.get(pinyin)
        if not code:
            raise ValueError(f"未找到拼音 '{pinyin}' 的编码")

        if len(code) != 4:
            raise ValueError(f"编码 '{code}' 长度不正确，应为4个字符")

        yinjie = Yinjie(
            initial=code[0],  # 首音
            ascender=code[1], # 呼音
            peak=code[2],     # 主音
            descender=code[3] # 末音
        )

        # 添加音元分类信息
        noise, musical = yinjie.classify_phonemes()
        yinjie.noise_phonemes = noise
        yinjie.musical_phonemes = musical

        return yinjie

    def decode_all(self):
        """解码所有拼音为Yinjie实例字典"""
        return {pinyin: self.decode(pinyin) for pinyin in self.code_map}

    # === 音元分类和映射生成 ===
    def generate_phoneme_mapping(self):
        """生成音元分类映射字典"""
        all_yinjie = self.decode_all()

        mapping = {
            "noise": set(),
            "musical": set()
        }

        for yinjie in all_yinjie.values():
            noise, musical = yinjie.classify_phonemes()
            mapping["noise"].update(noise)
            mapping["musical"].update(musical)

        return {
            "forward": {
                "noise": sorted(mapping["noise"]),
                "musical": sorted(mapping["musical"])
            },
            "reverse": {
                phoneme: "noise" for phoneme in mapping["noise"]
            }
        }

    # === 文件操作和保存 ===
    def save_phoneme_dict(self, output_file='phoneme_dict.json'):
        """将分类后的音元保存到JSON文件"""
        phoneme_dict = {
            "noise_phonemes": set(),
            "musical_phonemes": set()
        }

        all_yinjie = self.decode_all()

        for yinjie in all_yinjie.values():
            noise, musical = yinjie.classify_phonemes()
            phoneme_dict["noise_phonemes"].update(noise)
            phoneme_dict["musical_phonemes"].update(musical)

        phoneme_dict = {
            "noise_phonemes": sorted(phoneme_dict["noise_phonemes"]),
            "musical_phonemes": sorted(phoneme_dict["musical_phonemes"])
        }

        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(phoneme_dict, f, ensure_ascii=False, indent=2)

    def map_key_to_code(self, output_file='key_to_code.json'):
        """生成ASCII键到PUA字符的映射字典并保存到文件"""
        phoneme_mapping = self.generate_phoneme_mapping()
        all_phonemes = phoneme_mapping["forward"]["noise"] + phoneme_mapping["forward"]["musical"]

        key_to_code = {}
        ascii_start = 33  # 从可打印ASCII字符开始

        for phoneme in all_phonemes:
            if ascii_start <= 126:
                key_to_code[chr(ascii_start)] = phoneme
                ascii_start += 1
            else:
                print(f"警告：ASCII码不足，无法为字符 {phoneme} 分配键位")

        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(key_to_code, f, ensure_ascii=False, indent=2)

        print(f"已生成并保存键位映射到 {output_file}")
        return key_to_code

    # === 主程序示例 ===
    @staticmethod
    def run_example():
        """运行解码器示例"""
        decoder = YinjieDecoder()
        decoder.save_phoneme_dict()

        examples = ["ma1", "ni3", "hao3", "shang4", "xia4"]
        for pinyin in examples:
            try:
                yinjie = decoder.decode(pinyin)
                print(f"\n解码 '{pinyin}':")
                print(f"音节线性结构: {yinjie}")
                noise, musical = yinjie.classify_phonemes()
                print(f"噪音音元: {decoder._display_phonemes(noise)}")
                print(f"乐音音元: {decoder._display_phonemes(musical)}")
            except ValueError as e:
                print(f"解码 '{pinyin}' 时出错: {e}")

        all_yinjie = decoder.decode_all()
        print(f"\n解码了 {len(all_yinjie)} 个音节")
        decoder.map_key_to_code()

if __name__ == "__main__":
    YinjieDecoder.run_example()