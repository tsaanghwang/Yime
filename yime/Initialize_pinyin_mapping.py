import sqlite3
import logging
import json
import sys
from pathlib import Path

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
logger.addHandler(handler)


def 转换音节编码到数据库格式(连接: sqlite3.Connection) -> None:
    """从syllable_code.json加载数据并转换为数据库格式"""
    try:
        # 检查文件是否存在
        if not Path('syllable_code.json').is_file():
            raise FileNotFoundError("syllable_code.json文件不存在")

        with open('syllable_code.json', 'r', encoding='utf-8') as f:
            try:
                原始数据 = json.load(f)
                if not isinstance(原始数据, dict):
                    raise ValueError("JSON文件格式不正确，应为字典类型")
            except json.JSONDecodeError as e:
                raise ValueError(f"JSON解析失败: {e}")

        数据库格式数据 = []
        for 数字标调, 音元编码 in 原始数据.items():
            # 验证数据格式
            if not isinstance(数字标调, str) or not isinstance(音元编码, str):
                logger.warning(f"跳过无效数据项: {数字标调} -> {音元编码}")
                continue

            数据库格式数据.append({
                'source_type': '数字标调',
                'source_pinyin': 数字标调,
                'target_type': '音元拼音',
                'target_pinyin': 音元编码,
                'source': '音元输入法',
                'version': '0.1',
                'note': '数字标调转音元编码'
            })
            数据库格式数据.append({
                'source_type': '音元拼音',
                'source_pinyin': 音元编码,
                'target_type': '数字标调',
                'target_pinyin': 数字标调,
                'source': '音元输入法',
                'version': '0.1',
                'note': '音元编码转数字标调'
            })

        if not 数据库格式数据:
            raise ValueError("没有有效数据可导入")

        try:
            游标 = 连接.cursor()
            游标.executemany(
                '''INSERT OR REPLACE INTO 拼音映射关系
                   (原拼音类型, 原拼音, 目标拼音类型, 目标拼音, 数据来源, 版本号, 备注)
                   VALUES(:source_type, :source_pinyin, :target_type,
                         :target_pinyin, :source, :version, :note)''',
                数据库格式数据
            )
            连接.commit()
            logger.info(f"成功转换并加载 {len(数据库格式数据)} 条拼音映射关系")
        except sqlite3.Error as e:
            连接.rollback()
            raise RuntimeError(f"数据库操作失败: {e}")

    except Exception as e:
        logger.error(f"转换音节编码失败: {str(e)}", exc_info=True)
        raise

if __name__ == "__main__":
    conn = None
    try:
        # 创建数据库连接
        conn = sqlite3.connect('pinyin_hanzi.db')
        logger.info("开始转换音节编码...")
        转换音节编码到数据库格式(conn)
        logger.info("转换完成")
    except Exception as e:
        logger.error(f"程序执行出错: {str(e)}", exc_info=True)
        sys.exit(1)
    finally:
        if conn:
            try:
                conn.close()
            except sqlite3.Error as e:
                logger.error(f"关闭数据库连接时出错: {e}")