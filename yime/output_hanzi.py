# output_hanzi.py
from convert_pinyin_to_hanzi import YinYuanInputConverter
from functools import lru_cache
import logging

# 配置基础日志格式
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@lru_cache(maxsize=1)
def get_converter():
    """缓存转换器实例"""
    logger.debug("获取/创建拼音转换器实例")
    return YinYuanInputConverter()

def get_hanzi_by_any_pinyin(pinyin_input):
    """
    使用YinYuanInputConverter处理输入
    """
    logger.debug(f"开始处理拼音输入: {pinyin_input}")
    converter = get_converter()

    # 修改为使用正确的数据库查询方法
    logger.debug(f"查询拼音映射: {pinyin_input}")
    mapping = converter._load_universal_mapping(pinyin_input)

    if mapping:
        logger.debug(f"找到映射结果: {mapping['汉字']}")
        return mapping['汉字']
    else:
        logger.debug("未找到匹配的汉字映射")

    # 其他处理逻辑...
    return []

if __name__ == '__main__':
    # 测试不同格式的拼音输入
    test_cases = ["zhong1", "zhōng", "ㄓㄨㄥ"]
    for case in test_cases:
        print(f"测试输入: {case}")
        result = get_hanzi_by_any_pinyin(case)
        print(f"结果: {result}\n")