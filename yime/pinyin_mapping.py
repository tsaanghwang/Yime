# yime/pinyin_mapper.py
import sqlite3
from typing import Optional, Dict

class PinyinMapper:
    def __init__(self, db_path="pinyin_hanzi.db"):
        self.db_path = db_path
        self._create_tables_if_not_exist()

    def _create_tables_if_not_exist(self):
        """确保所有必要的表存在"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            # 表结构已在数据库中定义，无需重复创建
            pass

    def add_mapping(self, digital_pinyin: str, yinyuan_pinyin: str) -> bool:
        """添加数字标调拼音到音元拼音的映射"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()

            # 获取或创建数字标调拼音记录
            cursor.execute(
                'INSERT OR IGNORE INTO "数字标调拼音" ("全拼", "声母", "韵母", "声调") '
                'VALUES (?, ?, ?, ?)',
                (digital_pinyin, *self._parse_pinyin(digital_pinyin))
            )
            digital_id = cursor.lastrowid or self._get_pinyin_id(cursor, "数字标调拼音", digital_pinyin)

            # 获取或创建音元拼音记录
            cursor.execute(
                'INSERT OR IGNORE INTO "音元拼音" ("全拼") VALUES (?)',
                (yinyuan_pinyin,)
            )
            yinyuan_id = cursor.lastrowid or self._get_pinyin_id(cursor, "音元拼音", yinyuan_pinyin)

            # 创建映射关系
            cursor.execute(
                'INSERT OR REPLACE INTO "拼音映射" '
                '("音元拼音", "数字标调拼音", "标准拼音", "注音符号") '
                'VALUES (?, ?, ?)',
                (yinyuan_id, digital_id, digital_pinyin)
            )
            conn.commit()
            return True

    def get_mapping(self, digital_pinyin: str) -> Optional[str]:
        """根据数字标调拼音获取对应的音元拼音"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('''
                SELECT y."全拼"
                FROM "拼音映射" m
                JOIN "音元拼音" y ON m."音元拼音" = y."编号"
                JOIN "数字标调拼音" d ON m."数字标调拼音" = d."编号"
                WHERE d."全拼" = ?
            ''', (digital_pinyin,))
            result = cursor.fetchone()
            return result[0] if result else None

    def batch_add_mappings(self, mappings: Dict[str, str]) -> int:
        """批量添加映射关系"""
        success_count = 0
        with sqlite3.connect(self.db_path) as conn:
            for digital, yinyuan in mappings.items():
                try:
                    if self.add_mapping(digital, yinyuan):
                        success_count += 1
                except sqlite3.Error:
                    continue
            conn.commit()
        return success_count

    def _get_pinyin_id(self, cursor, table: str, pinyin: str) -> int:
        """获取拼音记录的ID"""
        cursor.execute(f'SELECT "编号" FROM "{table}" WHERE "全拼" = ?', (pinyin,))
        result = cursor.fetchone()
        return result[0] if result else None

    def _parse_pinyin(self, pinyin: str) -> tuple:
        """简单解析拼音为(声母, 韵母, 声调)"""
        # 这里实现您的拼音解析逻辑
        tone = pinyin[-1] if pinyin[-1].isdigit() else '1'
        base = pinyin[:-1] if pinyin[-1].isdigit() else pinyin
        initial = ''
        final = base
        # 简单声母识别逻辑，可根据需要完善
        initials = ['b','p','m','f','d','t','n','l','g','k','h',
                   'j','q','x','zh','ch','sh','r','z','c','s']
        for i in initials:
            if base.startswith(i):
                initial = i
                final = base[len(i):]
                break
        return (initial, final, int(tone))

# 使用示例
if __name__ == "__main__":
    mapper = PinyinMapper()

    # 添加单个映射
    mapper.add_mapping("zhong1", "zhong")  # 数字标调 -> 音元拼音

    # 批量添加映射
    mappings = {
        "zhong1": "zhong",
        "guo2": "guo",
        "ren2": "ren"
    }
    count = mapper.batch_add_mappings(mappings)
    print(f"成功添加 {count} 条映射")

    # 查询映射
    print(mapper.get_mapping("zhong1"))  # 输出: zhong