# 查询示例
from universal_mapping import get_hanzi_by_any_pinyin

def get_hanzi_by_any_pinyin(pinyin_input):
    #优化查询性能（如使用内存缓存）

    with open('yime/universal_mapping.json', 'r', encoding='utf-8') as f:
        mapping = json.load(f)

    if pinyin_input in mapping:
        return mapping[pinyin_input]['汉字']
    return "未找到对应汉字"

# 无论输入哪种拼音格式都能找到汉字
print(get_hanzi_by_any_pinyin("zhong1"))  # 数字标调
print(get_hanzi_by_any_pinyin("zhōng"))   # 调号标调
print(get_hanzi_by_any_pinyin("ㄓㄨㄥ"))  # 注音符号