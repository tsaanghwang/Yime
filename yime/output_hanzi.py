# output_hanzi.py
from convert_pinyin_to_hanzi import YinYuanInputConverter
from functools import lru_cache

@lru_cache(maxsize=1)
def get_converter():
    """缓存转换器实例"""
    return YinYuanInputConverter()

def get_hanzi_by_any_pinyin(pinyin_input):
    """
    使用YinYuanInputConverter处理输入
    """
    converter = get_converter()

    # 直接查询通用映射表
    if pinyin_input in converter.universal_map:
        return converter.universal_map[pinyin_input]['汉字']

    # 其他处理逻辑...
    return []

if __name__ == '__main__':
    print(get_hanzi_by_any_pinyin("zhong1"))
    print(get_hanzi_by_any_pinyin("zhōng"))
    print(get_hanzi_by_any_pinyin("ㄓㄨㄥ"))