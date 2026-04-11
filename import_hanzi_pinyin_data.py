#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
导入汉字拼音数据到数据库
"""
import sqlite3
import json
import logging
from pathlib import Path

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def 导入汉字拼音数据():
    """导入汉字拼音数据到数据库"""

    # 数据库路径
    db_path = Path(__file__).parent / "yime" / "pinyin_hanzi.db"
    data_path = Path(__file__).parent / "pinyin" / "hanzi_pinyin" / "hanzi_to_pinyin.json"

    logger.info(f"数据库路径: {db_path}")
    logger.info(f"数据文件路径: {data_path}")

    # 检查文件是否存在
    if not data_path.exists():
        logger.error(f"数据文件不存在: {data_path}")
        return

    # 加载数据
    logger.info("加载数据文件...")
    with open(data_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    logger.info(f"加载数据: {len(data)} 条")

    # 连接数据库
    conn = sqlite3.connect(str(db_path))
    cursor = conn.cursor()

    # 检查表是否存在
    cursor.execute("""
        SELECT name FROM sqlite_master
        WHERE type='table' AND name='汉字拼音初始数据'
    """)
    if not cursor.fetchone():
        logger.error("表 '汉字拼音初始数据' 不存在")
        conn.close()
        return

    # 清空表
    logger.info("清空表...")
    cursor.execute('DELETE FROM "汉字拼音初始数据"')
    conn.commit()

    # 准备数据
    logger.info("准备导入数据...")
    导入数据 = []
    统计 = {
        '总数': 0,
        '单字': 0,
        '多字': 0,
        '跳过': 0
    }

    for 汉字, 拼音列表 in data.items():
        统计['总数'] += 1

        # 跳过非单字
        if len(汉字) != 1:
            统计['多字'] += 1
            continue

        统计['单字'] += 1

        # 处理拼音列表
        if isinstance(拼音列表, str):
            拼音列表 = [拼音列表]

        for i, 拼音 in enumerate(拼音列表):
            # 确定是否为常用读音
            常用读音 = 1 if i == 0 else 0

            # 添加到导入数据
            导入数据.append((
                汉字,
                拼音,
                1.0,  # 频率
                常用读音,
                'hanzi_to_pinyin.json'  # 来源
            ))

    logger.info(f"准备导入: {len(导入数据)} 条")
    logger.info(f"统计: {统计}")

    # 批量导入
    logger.info("开始导入数据...")
    批量大小 = 1000
    已导入 = 0

    for i in range(0, len(导入数据), 批量大小):
        批量 = 导入数据[i:i+批量大小]
        cursor.executemany('''
            INSERT OR REPLACE INTO "汉字拼音初始数据"
            ("汉字", "拼音", "频率", "常用读音", "来源")
            VALUES (?, ?, ?, ?, ?)
        ''', 批量)
        conn.commit()
        已导入 += len(批量)
        logger.info(f"已导入: {已导入}/{len(导入数据)}")

    # 验证导入
    cursor.execute('SELECT COUNT(*) FROM "汉字拼音初始数据"')
    最终数量 = cursor.fetchone()[0]

    logger.info(f"导入完成! 总数: {最终数量}")

    # 显示示例数据
    cursor.execute('SELECT * FROM "汉字拼音初始数据" LIMIT 5')
    示例 = cursor.fetchall()
    logger.info("示例数据:")
    for row in 示例:
        logger.info(f"  {row}")

    conn.close()
    logger.info("数据库连接已关闭")

if __name__ == '__main__':
    导入汉字拼音数据()
