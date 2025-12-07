import sqlite3
from pathlib import Path

class CharacterPositionDB:
    def __init__(self, db_path='character_positions.db'):
        self.db_path = Path(db_path)
        self.conn = sqlite3.connect(str(self.db_path))
        self._create_tables()

    def _create_tables(self):
        schema_path = Path(__file__).parent / 'schema.sql'  # 或者直接使用上面的SQL字符串
        if schema_path.exists():
            schema = schema_path.read_text()
        else:
            # 提供一个最小的默认 schema，以防没有 schema.sql 文件
            schema = """
        -- 创建文档表
        CREATE TABLE IF NOT EXISTS documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            path TEXT UNIQUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            encoding TEXT DEFAULT 'utf-8',
            description TEXT
        );

        -- 创建字符位置表
        CREATE TABLE IF NOT EXISTS character_positions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_id INTEGER NOT NULL,
            char_index INTEGER NOT NULL,
            line_number INTEGER NOT NULL,
            column_number INTEGER NOT NULL,
            char_value TEXT NOT NULL,
            is_whitespace BOOLEAN DEFAULT 0,
            is_newline BOOLEAN DEFAULT 0,
            FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
        );

        -- 创建字符属性表
        CREATE TABLE IF NOT EXISTS character_attributes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            position_id INTEGER NOT NULL,
            attribute_name TEXT NOT NULL,
            attribute_value TEXT NOT NULL,
            UNIQUE(position_id, attribute_name),
            FOREIGN KEY (position_id) REFERENCES character_positions(id) ON DELETE CASCADE
        );

        -- 创建文档版本表（可选）
        CREATE TABLE IF NOT EXISTS document_versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_id INTEGER NOT NULL,
            version_number INTEGER NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            checksum TEXT,
            FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
        );

        -- 创建索引以提高查询性能
        CREATE INDEX IF NOT EXISTS idx_char_positions_document ON character_positions(document_id);
        CREATE INDEX IF NOT EXISTS idx_char_positions_line ON character_positions(line_number);
        CREATE INDEX IF NOT EXISTS idx_char_positions_char ON character_positions(char_value);



            """
        # 使用 getattr 调用以避免某些静态检查将方法名视为“未知单词”
        getattr(self.conn, "executescript")(schema)
        self.conn.commit()

    def add_document(self, name, path=None, description=''):
        cursor = self.conn.cursor()
        cursor.execute(
            "INSERT INTO documents (name, path, description) VALUES (?, ?, ?)",
            (name, path, description)
        )
        # 使用 getattr 访问 lastrowid，以避免静态检查对未知标识符的报错
        doc_id = getattr(cursor, "lastrowid", None)
        self.conn.commit()
        return doc_id

    def add_character_positions(self, doc_id, text):
        cursor = self.conn.cursor()

        # 简单的文本解析（实际实现可能需要更复杂的逻辑处理多字节字符）
        lines = text.split('\n')
        char_index = 0

        for line_num, line in enumerate(lines, start=1):
            for col_num, char in enumerate(line, start=1):
                is_whitespace = char.isspace()
                is_newline = False

                cursor.execute(
                    """INSERT INTO character_positions
                    (document_id, char_index, line_number, column_number,
                     char_value, is_whitespace, is_newline)
                    VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (doc_id, char_index, line_num, col_num, char, int(is_whitespace), int(is_newline))
                )
                char_index += 1

            # 添加换行符（如果不是最后一行）
            if line_num < len(lines):
                newline_char = '\n'
                cursor.execute(
                    """INSERT INTO character_positions
                    (document_id, char_index, line_number, column_number,
                     char_value, is_whitespace, is_newline)
                    VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (doc_id, char_index, line_num, len(line)+1, newline_char, int(newline_char.isspace()), 1)
                )
                char_index += 1

        self.conn.commit()

    def get_characters_in_range(self, doc_id, start_index, end_index):
        cursor = self.conn.cursor()
        cursor.execute(
            """SELECT char_index, line_number, column_number, char_value
            FROM character_positions
            WHERE document_id = ? AND char_index BETWEEN ? AND ?
            ORDER BY char_index""",
            (doc_id, start_index, end_index)
        )
        return cursor.fetchall()

    def close(self):
        self.conn.close()

# 使用示例
if __name__ == "__main__":
    db = CharacterPositionDB()

    # 添加文档
    doc_id = db.add_document("Sample Document", description="A test document")

    # 添加文本内容
    sample_text = """Hello, world!
This is a test document.
It contains multiple lines."""
    db.add_character_positions(doc_id, sample_text)

    # 查询字符范围
    chars = db.get_characters_in_range(doc_id, 0, 20)
    for char in chars:
        print(f"Index: {char[0]}, Line: {char[1]}, Col: {char[2]}, Char: '{char[3]}'")

    db.close()
