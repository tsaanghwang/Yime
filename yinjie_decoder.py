# yinjie_decoder.py
import json
from yinjie import Yinjie

class YinjieDecoder:
    def __init__(self, code_file='yinjie_code.json'):
        """
        初始化解码器，加载编码文件
        """
        self.code_file = code_file
        self.code_map = self._load_code_map()

    def _load_code_map(self):
        """
        从JSON文件加载编码映射
        """
        with open(self.code_file, 'r', encoding='utf-8') as f:
            return json.load(f)

    def _display_char(self, char):
        """
        辅助函数：直接返回字符本身而不是Unicode转义序列
        """
        return char if char else ''

    def _display_phonemes(self, phonemes):
        """
        改进的音元列表显示方法
        返回: 格式化的音元字符串
        """
        if not phonemes:
            return "[]"
        return "[" + ", ".join(f"'{self._display_char(c)}'" for c in phonemes) + "]"

    def decode(self, pinyin):
        """
        解码单个拼音为Yinjie实例
        """
        code = self.code_map.get(pinyin)
        if not code:
            raise ValueError(f"未找到拼音 '{pinyin}' 的编码")

        # 假设编码是4个Unicode字符，分别对应initial, ascender, peak, descender
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
        """
        解码所有拼音为Yinjie实例字典
        """
        return {pinyin: self.decode(pinyin) for pinyin in self.code_map}

    def save_phoneme_dict(self, output_file='phoneme_dict.json'):
        """
        将分类后的音元保存到JSON文件
        参数:
            output_file: 输出文件路径，默认为'phoneme_dict.json'
        返回:
            无
        """
        phoneme_dict = {
            "noise_phonemes": set(),
            "musical_phonemes": set()
        }

        # 假设已有解码方法获取所有音节
        all_yinjie = self.decode_all()

        for yinjie in all_yinjie.values():
            noise, musical = yinjie.classify_phonemes()
            phoneme_dict["noise_phonemes"].update(noise)
            phoneme_dict["musical_phonemes"].update(musical)

        # 转换为列表以便JSON序列化
        phoneme_dict = {
            "noise_phonemes": sorted(phoneme_dict["noise_phonemes"]),
            "musical_phonemes": sorted(phoneme_dict["musical_phonemes"])
        }

        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(phoneme_dict, f, ensure_ascii=False, indent=2)

# 使用示例
if __name__ == "__main__":
    decoder = YinjieDecoder()
    # ... 其他操作 ...
    decoder.save_phoneme_dict()  # 保存到默认文件
    # 或指定文件名
    decoder.save_phoneme_dict("custom_phoneme_dict.json")
    # 解码多个示例拼音
    examples = ["ma1", "ni3", "hao3", "shang4", "xia4"]
    for pinyin in examples:
        try:
            yinjie = decoder.decode(pinyin)
            print(f"\n解码 '{pinyin}':")
            print(f"音节线性结构: {yinjie}")

            # 打印音元分类结果 - 使用改进的显示方法
            noise, musical = yinjie.classify_phonemes()
            print(f"噪音音元: {decoder._display_phonemes(noise)}")
            print(f"乐音音元: {decoder._display_phonemes(musical)}")

            print(f"音节层次结构: [首音: {decoder._display_char(yinjie.initial)}, [干音：[呼音: {decoder._display_char(yinjie.ascender)}, [韵音: [主音: {decoder._display_char(yinjie.peak)}, 末音: {decoder._display_char(yinjie.descender)}]]]]]")
            print(f"干音层次结构: {{呼音: {decoder._display_char(yinjie.ascender)}, 韵音: {{主音: {decoder._display_char(yinjie.peak)}, 末音: {decoder._display_char(yinjie.descender)}}}}}")
            print(f"韵音线性结构: {{主音: {decoder._display_char(yinjie.peak)}, 末音: {decoder._display_char(yinjie.descender)}}}")
            print(f"首音: {decoder._display_char(yinjie.initial)}")
            print(f"呼音: {decoder._display_char(yinjie.ascender)}")
            print(f"主音: {decoder._display_char(yinjie.peak)}")
            print(f"末音: {decoder._display_char(yinjie.descender)}")
            print(f"音节: {decoder._display_char(yinjie.initial)}{decoder._display_char(yinjie.ascender)}{decoder._display_char(yinjie.peak)}{decoder._display_char(yinjie.descender)}")
        except ValueError as e:
            print(f"解码 '{pinyin}' 时出错: {e}")

    # 解码所有拼音
    all_yinjie = decoder.decode_all()
    print(f"\n解码了 {len(all_yinjie)} 个音节")
    print("前5个音节示例:")
    for i, (pinyin, yinjie) in enumerate(list(all_yinjie.items())[:5]):
        noise, musical = yinjie.classify_phonemes()
        print(f"{i+1}. {pinyin}: {yinjie}")
        print(f"   噪音音元: {decoder._display_phonemes(noise)}, 乐音音元: {decoder._display_phonemes(musical)}")

    # 新增键位映射生成和保存
    phonemes = {
        'noise': ['\U00100015', '\U00100016'],
        'musical': ['\U00100029', '\U00100030']
    }

    key_mapping = Yinjie.generate_key_mapping(phonemes)

    # 保存到文件
    with open('key_mapping.json', 'w', encoding='utf-8') as f:
        json.dump(key_mapping, f, ensure_ascii=False, indent=2)
    print("\n已生成并保存键位映射到 key_mapping.json")