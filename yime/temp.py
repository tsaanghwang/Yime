data = {
    "keystrokesToCodepoints": {
    "ZHAAA": ["􀀎􀀩", "􀀎􀀩􀀩", "􀀎􀀩􀀩􀀩"],
    "CHAAA": ["􀀏􀀩", "􀀏􀀩􀀩", "􀀏􀀩􀀩􀀩"],
    "SHAAA": ["􀀐􀀩", "􀀐􀀩􀀩", "􀀐􀀩􀀩􀀩"],
    "RUUU": ["􀀑􀀣", "􀀑􀀣􀀣", "􀀑􀀣􀀣􀀣"],
    "ZHAA": ["􀀎􀀩", "􀀎􀀩􀀩", "􀀎􀀩􀀩􀀩"],
    "CHAA": ["􀀏􀀩", "􀀏􀀩􀀩", "􀀏􀀩􀀩􀀩"],
    "



    ": ["􀀐􀀩", "􀀐􀀩􀀩", "􀀐􀀩􀀩􀀩"],
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

from scipy.fft import dst

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
"""
CREATE TABLE 音元拼音 (
    id INTEGER PRIMARY KEY,
    全拼 TEXT NOT NULL UNIQUE,     -- 全拼字符串
    简拼 TEXT,                    -- 简拼字符串
    首音 TEXT,                    -- 第一个音元(含不必标注的虚首音)
    干音 TEXT,                    -- 除首音外的音元
    呼音 TEXT,                    -- 第二个音元
    主音 TEXT,                    -- 第三个音元
    末音 TEXT,                    -- 第四个音元
    间音 TEXT,                    -- 中间两音元
    韵音 TEXT,                    -- 后面两音元
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX 音元拼音_全拼 ON 音元拼音(全拼);
CREATE UNIQUE INDEX 'sqlite_autoindex_全拼_1' ON 音元拼音(全拼);
"""
"""
CREATE TABLE 音元拼音_数字标调拼音 (
    音元拼音id INTEGER REFERENCES 音元拼音(id),
    pinyin_id INTEGER REFERENCES pinyin(id),
    标准拼音 TEXT NOT NULL,     -- 标准拼音
    注音符号 TEXT NOT NULL,     -- 注音符号
    PRIMARY KEY (音元拼音id, pinyin_id)
);
"""
"""
CREATE INDEX 音元拼音_数字标调拼音_音元拼音id ON 音元拼音_数字标调拼音(音元拼音id);
CREATE INDEX 音元拼音_数字标调拼音_拼音_id ON 音元拼音_数字标调拼音(拼音_id);
CREATE UNIQUE INDEX '音元拼音_数字标调拼音_音元拼音id_拼音_id' ON 音元拼音_数字标调拼音(音元拼音id,拼音_id);
"""

"""
CREATE TABLE 音元拼音_数字标调拼音 (
    音元拼音id INTEGER REFERENCES 音元拼音(id),
    pinyin_id INTEGER REFERENCES pinyin(id),
    标准拼音 TEXT NOT NULL,     -- 标准拼音
    注音符号 TEXT NOT NULL,     -- 注音符号
    PRIMARY KEY (音元拼音id, pinyin_id)
);
"""
初始化这个表
CREATE TABLE IF NOT EXISTS "拼音映射关系" (
        "映射编号" INTEGER PRIMARY KEY AUTOINCREMENT,
        "原拼音类型" TEXT NOT NULL,
        "原拼音" TEXT NOT NULL,
        "目标拼音类型" TEXT NOT NULL,
        "目标拼音" TEXT NOT NULL,
        "数据来源" TEXT,
        "版本号" TEXT,
        "备注" TEXT,
        "创建时间" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE("原拼音类型", "原拼音", "目标拼音类型", "目标拼音", "数据来源")
    )

from typing import Dict, List, Any
records: List[Dict[str, str]] = []
records.append({
            '原拼音类型': '数字标调',
            '原拼音': src,
            '目标拼音类型': '音元拼音',
            '目标拼音': dst,
            '数据来源': '音元输入法',
            '版本号': '0.1',
            '备注': '数字标调转音元'
        })

PINYINTYPE = {'数字标调', '标准拼音', '注音符号', '音元拼音', '国际音标'}

from typing import Dict, List, Any

def add_pinyin_mapping(
    mappings: Dict[str, List[Dict[str, str]]],
    source_type: str,
    source_pinyin: str,
    target_type: str,
    target_pinyin: str,
    source: str,
    version: str,
    remark: str = ""
) -> None:
    """添加常用拼音与音元拼音间的映射关系"""
    if source_type in PINYINTYPE and source_type != '音元拼音' and target_type == '音元拼音':
        # 非音元拼音 → 音元拼音
        mappings["to_yinyuan"].append({
            '原拼音类型': source_type,
            '原拼音': source_pinyin,
            '目标拼音类型': target_type,
            '目标拼音': target_pinyin,
            '数据来源': source,
            '版本号': version,
            '备注': remark
        })
    elif source_type == '音元拼音' and target_type in PINYINTYPE and target_type != '音元拼音':
        # 音元拼音 → 非音元拼音
        mappings["from_yinyuan"].append({
            '原拼音类型': source_type,
            '原拼音': source_pinyin,
            '目标拼音类型': target_type,
            '目标拼音': target_pinyin,
            '数据来源': source,
            '版本号': version,
            '备注': remark
        })
    else:
        raise ValueError("不支持的拼音映射方向！")

# 初始化映射存储
pinyin_mappings: Dict[str, List[Dict[str, str]]] = {
    "to_yinyuan": [],
    "from_yinyuan": []
}

# 添加示例数据
add_pinyin_mapping(
    mappings=pinyin_mappings,
    source_type='数字标调',
    source_pinyin='ni3hao3',
    target_type='音元拼音',
    target_pinyin='nihao',
    source='音元输入法',
    version='0.1',
    remark='数字标调转音元'
)

add_pinyin_mapping(
    mappings=pinyin_mappings,
    source_type='音元拼音',
    source_pinyin='nihao',
    target_type='标准拼音',
    target_pinyin='nǐhǎo',
    source='音元输入法',
    version='0.1',
    remark='音元转标准拼音'
)

# 打印结果
print("非音元拼音 → 音元拼音:")
for record in pinyin_mappings["to_yinyuan"]:
    print(record)

print("\n音元拼音 → 非音元拼音:")
for record in pinyin_mappings["from_yinyuan"]:
    print(record)