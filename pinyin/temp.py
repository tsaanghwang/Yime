# 在pinyin\hanzi_pinyin\danzi_converter.py中：
# 将pinyin\hanzi_pinyin\danzi_pinyin.yaml转换为pinyin\hanzi_pinyin\danzi_pinyin.json
# 1.当yaml文件的条目中的汉字不重复时，将键值对存入json文件中，键为汉字，值为拼音列表
# 2.当yaml文件的条目中的汉字重复时，将键值对存入json文件中，键为汉字，值为拼音列表
# 3.字典结构：
"""
{
    "汉字": ["拼音1", "拼音2", ...],
}
"""
