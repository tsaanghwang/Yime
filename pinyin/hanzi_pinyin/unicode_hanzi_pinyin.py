"""
转换文件格式
功能：将txt文件转换为字典

- 输入文件格式：
- 每行包括三项:
- 一个unicode编码, 由冒号 ":"与其后的一个或多个拼音分隔
- 一个或多个拼音, 内部由逗号","分隔,  拼音后由空格与"#"号分隔
- 一个汉字, 其前由空格与"#"号分隔
例如：
U+3007: líng,yuán,xīng  # 〇
U+3400: qiū  # 㐀
U+3401: tiàn  # 㐁
U+3404: kuà  # 㐄
U+3405: wǔ  # 㐅
U+3406: yǐn  # 㐆
...

- 输出文件格式：
{"unicode": {"汉字": ["pinyin1", "pinyin2", ...]}}
例如：
{
        "U+3007": {"〇": ["líng", "yuán", "xīng"]},
        "U+3400": {"㐀": ["qiū"]},
        "U+3401": {"㐁": ["tiàn"]},
        "U+3404": {"㐄": ["kuà"]},
        "U+3405": {"㐅": ["wǔ"]},
        "U+3406": {"㐆": ["yǐn"]},
        ...
}
"""

import os
import json

# 定义输入输出文件路径 - 使用os.path.join确保跨平台兼容性
module_dir = os.path.dirname(os.path.abspath(__file__))
input_file = os.path.join(module_dir, 'unicode_pinyin_hanzi.txt')
output_file = os.path.join(module_dir, 'unicode_hanzi_pinyin.json')

def convert_file(input_file, output_file):
    """
    将输入文件转换为JSON格式并保存
    :param input_file: 输入文件路径
    :param output_file: 输出文件路径
    """
    result = {}

    # 读取输入文件内容
    with open(input_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # 分割unicode编码和拼音部分
            unicode_part, rest = line.split(':', 1)
            unicode_code = unicode_part.strip()

            # 分割拼音和汉字部分
            pinyin_part, hanzi_part = rest.split('#', 1)

            # 处理拼音部分
            pinyin_str = pinyin_part.strip()
            pinyin_list = [p.strip() for p in pinyin_str.split(',')]

           # 处理汉字部分
            hanzi = hanzi_part.strip()

            # 验证汉字是否与unicode_code对应
            try:
                expected_hanzi = chr(int(unicode_code[2:], 16))  # 去掉U+前缀并转换为整数
                if hanzi != expected_hanzi:
                    print(f"警告: Unicode编码 {unicode_code} 对应的汉字应为 '{expected_hanzi}'，但文件中是 '{hanzi}'")
            except ValueError:
                print(f"错误: 无效的Unicode编码格式 {unicode_code}")

            # 构建结果字典
            result[unicode_code] = {hanzi: pinyin_list}

    # 将结果写入JSON文件
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=4)

    return result

# 执行转换
if __name__ == '__main__':
    convert_file(input_file, output_file)
    print(f"转换完成，结果已保存到 {output_file}")