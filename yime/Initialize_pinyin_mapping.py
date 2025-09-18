import sqlite3
import logging
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional

# 配置常量
JSON_FILE = 'syllable_code.json'
DB_FILE = 'pinyin_hanzi.db'
BATCH_SIZE = 100  # 批量插入大小

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

def validate_pinyin(pinyin: str) -> bool:
    """验证拼音格式是否有效"""
    # 这里可以添加更复杂的验证逻辑
    return bool(pinyin.strip())

def 转换音节编码到数据库格式(连接: sqlite3.Connection) -> int:
    """从syllable_code.json加载数据并转换为数据库格式

    Args:
        连接: SQLite数据库连接

    Returns:
        成功导入的记录数

    Raises:
        FileNotFoundError: 当JSON文件不存在时
        ValueError: 当JSON格式或数据无效时
        sqlite3.Error: 数据库操作失败时
    """
    # 检查文件是否存在
    json_path = Path(JSON_FILE)
    if not json_path.is_file():
        raise FileNotFoundError(f"{JSON_FILE}文件不存在于{json_path.absolute()}")

    logger.info(f"开始加载JSON文件: {json_path}")

    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            原始数据 = json.load(f)
    except json.JSONDecodeError as e:
        raise ValueError(f"JSON解析失败: {e}")
    except UnicodeDecodeError as e:
        raise ValueError(f"文件编码错误: {e}")

    if not isinstance(原始数据, dict):
        raise ValueError("JSON文件格式不正确，应为字典类型")

    数据库格式数据: List[Dict[str, str]] = []
    valid_count = 0

    for 数字标调, 音元编码 in 原始数据.items():
        if not validate_pinyin(数字标调) or not validate_pinyin(音元编码):
            logger.warning(f"跳过无效数据项: {数字标调} -> {音元编码}")
            continue

        数据库格式数据.extend([
            {
                'source_type': '数字标调',
                'source_pinyin': 数字标调,
                'target_type': '音元拼音',
                'target_pinyin': 音元编码,
                'source': '音元输入法',
                'version': '0.1',
                'note': '数字标调转音元编码'
            },
            {
                'source_type': '音元拼音',
                'source_pinyin': 音元编码,
                'target_type': '数字标调',
                'target_pinyin': 数字标调,
                'source': '音元输入法',
                'version': '0.1',
                'note': '音元编码转数字标调'
            }
        ])
        valid_count += 1

    if not 数据库格式数据:
        raise ValueError("没有有效数据可导入")

    logger.info(f"准备导入 {len(数据库格式数据)} 条映射关系 (来自 {valid_count} 个原始映射)")

    try:
        游标 = 连接.cursor()

        logger.info(f"准备删除原有数据并插入 {len(数据库格式数据)} 条新记录")

        # 新增：清空表内容
        游标.execute("DELETE FROM 拼音映射关系 WHERE 数据来源 = '音元输入法'")
        logger.info("已清空原有音元输入法映射数据")

        # 批量插入数据
        for i in range(0, len(数据库格式数据), BATCH_SIZE):
            batch = 数据库格式数据[i:i+BATCH_SIZE]
            游标.executemany('''
                INSERT OR REPLACE INTO 拼音映射关系
                (原拼音类型, 原拼音, 目标拼音类型, 目标拼音, 数据来源, 版本号, 备注)
                VALUES(:source_type, :source_pinyin, :target_type,
                    :target_pinyin, :source, :version, :note)
            ''', batch)
            连接.commit()
            logger.debug(f"已提交批次 {i//BATCH_SIZE + 1} (共 {len(batch)} 条记录)")

        # 批量插入数据
        for i in range(0, len(数据库格式数据), BATCH_SIZE):
            batch = 数据库格式数据[i:i+BATCH_SIZE]
            游标.executemany('''
                INSERT OR REPLACE INTO 拼音映射关系
                (原拼音类型, 原拼音, 目标拼音类型, 目标拼音, 数据来源, 版本号, 备注)
                VALUES(:source_type, :source_pinyin, :target_type,
                      :target_pinyin, :source, :version, :note)
            ''', batch)
            连接.commit()
            logger.debug(f"已提交批次 {i//BATCH_SIZE + 1} (共 {len(batch)} 条记录)")

        logger.info(f"成功转换并加载 {len(数据库格式数据)} 条拼音映射关系")
        return len(数据库格式数据)

    except sqlite3.Error as e:
        连接.rollback()
        raise RuntimeError(f"数据库操作失败: {e}")

def main() -> int:
    """主函数"""
    try:
        logger.info("开始转换音节编码...")
        with sqlite3.connect(DB_FILE) as conn:
            count = 转换音节编码到数据库格式(conn)
        logger.info(f"转换完成，共处理 {count} 条记录")
        return 0
    except Exception as e:
        logger.error(f"程序执行出错: {str(e)}", exc_info=True)
        return 1

if __name__ == "__main__":
    sys.exit(main())