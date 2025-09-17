@staticmethod
def 导入拼音映射关系(连接: sqlite3.Connection, 数据文件: str) -> None:
    """从JSON文件导入拼音映射关系"""
    try:
        with open(数据文件, 'r', encoding='utf-8') as f:
            数据 = json.load(f)

        游标 = 连接.cursor()
        游标.executemany(
            '''INSERT OR REPLACE INTO 拼音映射关系
               (源拼音类型, 源拼音, 目标拼音类型, 目标拼音, 数据来源, 版本号, 备注)
               VALUES(?,?,?,?,?,?,?)''',
            [(记录['source_type'],
             记录['source_pinyin'],
             记录['target_type'],
             记录['target_pinyin'],
             记录.get('source'),
             记录.get('version'),
             记录.get('note')) for 记录 in 数据]
        )
        连接.commit()
        logger.info(f"成功导入 {len(数据)} 条拼音映射关系")
    except Exception as e:
        logger.error(f"导入拼音映射关系失败: {e}")
        raise
[
    {
        "source_type": "数字标调",
        "source_pinyin": "zhong1",
        "target_type": "音元拼音",
        "target_pinyin": "zh-ong",
        "source": "现代汉语词典",
        "version": "1.0",
        "note": "标准普通话发音"
    },
    {
        "source_type": "音元拼音",
        "source_pinyin": "zh-ong",
        "target_type": "标准拼音",
        "target_pinyin": "zhōng",
        "source": "音元输入法",
        "version": "2.1",
        "note": "音元转标准"
    }
]

# 转换示例
def 转换拼音(源类型: str, 源拼音: str, 目标类型: str) -> Optional[str]:
    """通用拼音转换函数"""
    return 连接.execute(
        'SELECT 目标拼音 FROM 拼音映射关系 '
        'WHERE 源拼音类型=? AND 源拼音=? AND 目标拼音类型=?',
        (源类型, 源拼音, 目标类型)
    ).fetchone()[0]

# 批量插入映射关系
初始数据 = [
    ('数字标调', 'zhong1', '标准拼音', 'zhōng', 'Unicode', '1.0', '阴平'),
    ('音元拼音', 'zho1', '标准拼音', 'zhō', '自定义', '1.2', None)
]
游标.executemany(
    'INSERT OR IGNORE INTO 拼音映射关系 VALUES '
    '(NULL,?,?,?,?,?,?,?,CURRENT_TIMESTAMP)',
    初始数据
)