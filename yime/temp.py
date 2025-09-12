data = {
    "keystrokesToCodepoints": {
    "ZHAAA": ["􀀎􀀩", "􀀎􀀩􀀩", "􀀎􀀩􀀩􀀩"],
    "CHAAA": ["􀀏􀀩", "􀀏􀀩􀀩", "􀀏􀀩􀀩􀀩"],
    "SHAAA": ["􀀐􀀩", "􀀐􀀩􀀩", "􀀐􀀩􀀩􀀩"],
    "RUUU": ["􀀑􀀣", "􀀑􀀣􀀣", "􀀑􀀣􀀣􀀣"],
    "ZHAA": ["􀀎􀀩", "􀀎􀀩􀀩", "􀀎􀀩􀀩􀀩"],
    "CHAA": ["􀀏􀀩", "􀀏􀀩􀀩", "􀀏􀀩􀀩􀀩"],
    "SHAA": ["􀀐􀀩", "􀀐􀀩􀀩", "􀀐􀀩􀀩􀀩"],
    "RUU": ["􀀑􀀣", "􀀑􀀣􀀣", "􀀑􀀣􀀣􀀣"],
    "ZHA": ["􀀎􀀩", "􀀎􀀩􀀩", "􀀎􀀩􀀩􀀩"],
    "CHA": ["􀀏􀀩", "􀀏􀀩􀀩", "􀀏􀀩􀀩􀀩"],
    "SHA": ["􀀐􀀩", "􀀐􀀩􀀩", "􀀐􀀩􀀩􀀩"],
    "RU": ["􀀑􀀣", "􀀑􀀣􀀣", "􀀑􀀣􀀣􀀣"]
  }
}

一个映射：
data1 ={
  "AAA": ["a", "aa", "aaa"],
  "AA": ["a", "aa", "aaa"],
  "A": ["a", "aa", "aaa"],
}
一个反向映射：
data2 ={
  "aaa": ["A", "AA", "AAA"],
  "aa": ["A", "AA", "AAA"],
  "a": ["A", "AA", "AAA"],
}

基础实现方案（直接映射）：
data = {
    "A": ["a", "aa", "aaa"],
    "AA": ["a", "aa", "aaa"],
    "AAA": ["a", "aa", "aaa"]
}

内存优化方案（引用相同列表对象）：
shared_list = ["a", "aa", "aaa"]
data = {
    "A": shared_list,
    "AA": shared_list,
    "AAA": shared_list
}

自动扩展方案（动态生成映射）：
from collections import defaultdict

def create_mapping(keys, values):
    mapping = defaultdict(list)
    for key in keys:
        mapping[key] = values.copy()  # 注意使用copy()避免引用同一对象
    return dict(mapping)

keys = ["A", "AA", "AAA"]
values = ["a", "aa", "aaa"]
data = create_mapping(keys, values)

类封装方案（更灵活的控制）：
class MultiKeyMapper:
    def __init__(self):
        self._mapping = {}
        self._value_pool = {}

    def add_mapping(self, keys, values):
        value_id = id(values)
        if value_id not in self._value_pool:
            self._value_pool[value_id] = values.copy()

        for key in keys:
            self._mapping[key] = self._value_pool[value_id]

    def get(self, key):
        return self._mapping.get(key, [])

# 使用示例
mapper = MultiKeyMapper()
mapper.add_mapping(["A", "AA", "AAA"], ["a", "aa", "aaa"])
print(mapper.get("A"))  # 输出: ['a', 'aa', 'aaa']

"""
CREATE TABLE hanzi (
    id INTEGER PRIMARY KEY,
    character TEXT NOT NULL UNIQUE,  -- 汉字字符
    unicode_hex TEXT NOT NULL,       -- Unicode编码(16进制)
    stroke_count INTEGER,            -- 笔画数
    radical TEXT,                    -- 部首
    is_common BOOLEAN DEFAULT 1,     -- 是否常用字
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE pinyin (
    id INTEGER PRIMARY KEY,
    pinyin TEXT NOT NULL UNIQUE,     -- 拼音字符串(如"zhong1")
    initial TEXT,                    -- 声母(如"zh")
    final TEXT,                      -- 韵母(如"ong")
    tone INTEGER,                    -- 声调(1-5)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE hanzi_pinyin (
    hanzi_id INTEGER REFERENCES hanzi(id),
    pinyin_id INTEGER REFERENCES pinyin(id),
    frequency FLOAT DEFAULT 1.0,     -- 相对频率(可基于语料库统计)
    is_primary BOOLEAN DEFAULT 0,    -- 是否主要读音
    PRIMARY KEY (hanzi_id, pinyin_id)
);
CREATE TABLE character_frequency (
    hanzi_id INTEGER PRIMARY KEY REFERENCES hanzi(id),
    absolute_freq INTEGER,           -- 绝对频率
    relative_freq FLOAT,             -- 相对频率(0-1)
    corpus_source TEXT,              -- 语料来源
    last_updated TIMESTAMP
);
CREATE TABLE vocabulary (
    id INTEGER PRIMARY KEY,
    phrase TEXT NOT NULL,            -- 词语/短语
    pinyin TEXT NOT NULL,            -- 完整拼音(如"zhong1 guo2")
    frequency FLOAT,                 -- 词频
    length INTEGER,                  -- 词长(字数)
    is_common BOOLEAN DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"""
