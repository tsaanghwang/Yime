"""
    1. 在pinyin_hanzi.db中创建一个表：
    - 表名：yinjie_code
        - 字段：code, pinyin
    2. 加载yinjie_code.json字典文件：
    - 将字典中的键（用数字标调的拼音）作为表yinjie_code的pinyin字段
    - 将字典中值（拼音对应的编码）作为表yinjie_code的code字段
    3. 暂不合并重复的 code 字段
    """