#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
从 8105.dict.yaml 导入字频数据到数据库
修复拼音匹配问题：YAML中的拼音没有声调数字
"""
import sqlite3
import yaml
import logging
from pathlib import Path

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def 解析yaml文件(文件路径):
    """解析 YAML 文件，提取汉字、拼音和频率数据"""
    数据列表 = []

    with open(文件路径, 'r', encoding='utf-8') as f:
        内容 = f.read()

    # 找到数据部分（在 ... 之后）
    数据开始 = 内容.find('...')
    if 数据开始 == -1:
        logger.error("未找到数据开始标记")
        return []

    数据部分 = 内容[数据开始 + 3:].strip()

    # 逐行解析
    for 行 in 数据部分.split('\n'):
        行 = 行.strip()

        # 跳过注释和空行
        if not 行 or 行.startswith('#'):
            continue

        # 解析数据行：汉字 拼音 频率
        部分 = 行.split('\t')
        if len(部分) >= 3:
            汉字 = 部分[0]
            拼音 = 部分[1]  # 没有声调数字
            try:
                频率 = int(部分[2])
                数据列表.append((汉字, 拼音, 频率))
            except ValueError:
                continue
        elif len(部分) == 2:
            # 没有频率数据，跳过
            continue

    return 数据列表

def 修改表结构(连接):
    """修改表结构：将'频率'改为'初始频率'，添加'相对频率'字段"""
    游标 = 连接.cursor()

    # 检查表结构
    游标.execute("PRAGMA table_info('汉字拼音初始数据')")
    列信息 = 游标.fetchall()
    列名列表 = [列[1] for 列 in 列信息]

    logger.info(f"当前表结构: {列名列表}")

    # 如果'频率'字段存在，重命名为'初始频率'
    if '频率' in 列名列表 and '初始频率' not in 列名列表:
        logger.info("重命名'频率'为'初始频率'...")
        # SQLite 不支持直接重命名列，需要重建表
        游标.execute('''
            CREATE TABLE "汉字拼音初始数据_new" (
                "汉字" TEXT NOT NULL,
                "拼音" TEXT NOT NULL,
                "初始频率" INTEGER,
                "相对频率" INTEGER,
                "常用读音" BOOLEAN DEFAULT 0,
                "来源" TEXT,
                PRIMARY KEY ("汉字", "拼音")
            )
        ''')

        # 复制数据
        游标.execute('''
            INSERT INTO "汉字拼音初始数据_new"
            ("汉字", "拼音", "初始频率", "常用读音", "来源")
            SELECT "汉字", "拼音", "频率", "常用读音", "来源"
            FROM "汉字拼音初始数据"
        ''')

        # 删除旧表
        游标.execute('DROP TABLE "汉字拼音初始数据"')

        # 重命名新表
        游标.execute('ALTER TABLE "汉字拼音初始数据_new" RENAME TO "汉字拼音初始数据"')

        连接.commit()
        logger.info("表结构修改完成")

    # 如果'相对频率'字段不存在，添加它
    if '相对频率' not in 列名列表:
        logger.info("添加'相对频率'字段...")
        try:
            游标.execute('ALTER TABLE "汉字拼音初始数据" ADD COLUMN "相对频率" INTEGER')
            连接.commit()
            logger.info("'相对频率'字段添加完成")
        except sqlite3.OperationalError as e:
            if "duplicate column name" in str(e):
                logger.info("'相对频率'字段已存在")
            else:
                raise

def 导入字频数据(连接, 数据列表):
    """导入字频数据并计算相对频率"""
    游标 = 连接.cursor()

    if not 数据列表:
        logger.error("没有数据可导入")
        return

    # 找到最大频率
    最大频率 = max(数据[2] for 数据 in 数据列表)
    logger.info(f"最大频率: {最大频率}")

    # 更新数据
    更新计数 = 0
    未找到计数 = 0
    多音字计数 = 0

    for 汉字, 拼音, 频率 in 数据列表:
        # 计算相对频率（万以内）
        相对频率 = int((频率 / 最大频率) * 10000) if 最大频率 > 0 else 0

        # 查找匹配的记录（拼音可能没有声调数字）
        # 例如：YAML中的"de"需要匹配数据库中的"de5", "di2", "di4"等
        游标.execute('''
            SELECT "汉字", "拼音" FROM "汉字拼音初始数据"
            WHERE "汉字" = ? AND ("拼音" = ? OR "拼音" LIKE ? || '%')
        ''', (汉字, 拼音, 拼音))

        匹配记录 = 游标.fetchall()

        if 匹配记录:
            for 记录 in 匹配记录:
                # 更新记录
                游标.execute('''
                    UPDATE "汉字拼音初始数据"
                    SET "初始频率" = ?, "相对频率" = ?
                    WHERE "汉字" = ? AND "拼音" = ?
                ''', (频率, 相对频率, 记录[0], 记录[1]))
                更新计数 += 1

            # 如果有多个匹配，说明是多音字
            if len(匹配记录) > 1:
                多音字计数 += 1
        else:
            未找到计数 += 1

    连接.commit()

    logger.info(f"更新记录: {更新计数}")
    logger.info(f"未找到记录: {未找到计数}")
    logger.info(f"多音字: {多音字计数}")

def 验证数据(连接):
    """验证导入的数据"""
    游标 = 连接.cursor()

    # 统计数据
    游标.execute('SELECT COUNT(*) FROM "汉字拼音初始数据" WHERE "初始频率" IS NOT NULL')
    有频率数量 = 游标.fetchone()[0]

    游标.execute('SELECT COUNT(*) FROM "汉字拼音初始数据" WHERE "相对频率" IS NOT NULL')
    有相对频率数量 = 游标.fetchone()[0]

    游标.execute('SELECT MAX("初始频率") FROM "汉字拼音初始数据"')
    最大频率 = 游标.fetchone()[0]

    游标.execute('SELECT MAX("相对频率") FROM "汉字拼音初始数据"')
    最大相对频率 = 游标.fetchone()[0]

    logger.info(f"有初始频率的记录: {有频率数量}")
    logger.info(f"有相对频率的记录: {有相对频率数量}")
    logger.info(f"最大初始频率: {最大频率}")
    logger.info(f"最大相对频率: {最大相对频率}")

    # 显示示例数据
    游标.execute('''
        SELECT "汉字", "拼音", "初始频率", "相对频率"
        FROM "汉字拼音初始数据"
        WHERE "初始频率" IS NOT NULL
        ORDER BY "初始频率" DESC
        LIMIT 10
    ''')
    示例 = 游标.fetchall()

    logger.info("频率最高的10个汉字:")
    for 行 in 示例:
        logger.info(f"  {行[0]} ({行[1]}): 初始频率={行[2]}, 相对频率={行[3]}")

def 主函数():
    """主函数"""
    # 路径
    yaml路径 = Path(__file__).parent / "external_data" / "8105.dict.yaml"
    db路径 = Path(__file__).parent / "yime" / "pinyin_hanzi.db"

    logger.info(f"YAML文件路径: {yaml路径}")
    logger.info(f"数据库路径: {db路径}")

    # 检查文件
    if not yaml路径.exists():
        logger.error(f"YAML文件不存在: {yaml路径}")
        return

    if not db路径.exists():
        logger.error(f"数据库不存在: {db路径}")
        return

    # 解析YAML文件
    logger.info("解析YAML文件...")
    数据列表 = 解析yaml文件(yaml路径)
    logger.info(f"解析到 {len(数据列表)} 条数据")

    if not 数据列表:
        logger.error("没有解析到数据")
        return

    # 连接数据库
    连接 = sqlite3.connect(str(db路径))

    try:
        # 修改表结构
        logger.info("修改表结构...")
        修改表结构(连接)

        # 导入数据
        logger.info("导入字频数据...")
        导入字频数据(连接, 数据列表)

        # 验证数据
        logger.info("验证数据...")
        验证数据(连接)

    finally:
        连接.close()
        logger.info("数据库连接已关闭")

if __name__ == '__main__':
    主函数()
