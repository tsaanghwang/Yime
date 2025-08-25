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

        return Yinjie(
            initial=code[0],  # 首音
            ascender=code[1], # 呼音
            peak=code[2],     # 主音
            descender=code[3] # 末音
        )

    def decode_all(self):
        """
        解码所有拼音为Yinjie实例字典
        """
        return {pinyin: self.decode(pinyin) for pinyin in self.code_map}

# 使用示例
if __name__ == "__main__":
    decoder = YinjieDecoder()

    # 解码多个示例拼音
    examples = ["ma1", "ni3", "hao3", "shang4", "xia4"]
    for pinyin in examples:
        try:
            yin = decoder.decode(pinyin)
            print(f"\n解码 '{pinyin}':")
            print(f"音节线性结构: {yin}")
            print(f"音节层次结构: [首音: {yin.initial}, [干音：[呼音: {yin.ascender}, [韵音: [主音: {yin.peak}, 末音: {yin.descender}]]]]]")
            print(f"干音层次结构: {{呼音: {yin.ascender}, 韵音: {{主音: {yin.peak}, 末音: {yin.descender}}}}}")
            print(f"韵音线性结构: {{主音: {yin.peak}, 末音: {yin.descender}}}")
            print(f"首音: {yin.initial}")
            print(f"呼音: {yin.ascender}")
            print(f"主音: {yin.peak}")
            print(f"末音: {yin.descender}")
            print(f"音节: {yin.initial}{yin.ascender}{yin.peak}{yin.descender}")
        except ValueError as e:
            print(f"解码 '{pinyin}' 时出错: {e}")

    # 解码所有拼音
    all_yinjie = decoder.decode_all()
    print(f"\n解码了 {len(all_yinjie)} 个音节")
    print("前5个音节示例:")
    for i, (pinyin, yin) in enumerate(list(all_yinjie.items())[:5]):
        print(f"{i+1}. {pinyin}: {yin}")