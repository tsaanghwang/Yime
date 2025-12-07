# split_md.py
# 修改后的脚本：专门针对当前目录下的“音元系统.md”进行拆分，
# 并将拆分后的文件存放在当前项目的“docs”目录下。
# 运行方式：直接执行 python split_md.py

import os
import re

def split_md(input_file, output_dir):
    # 确保输出目录存在
    os.makedirs(output_dir, exist_ok=True)

    # 读取输入文件（假设UTF-8编码）
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # 使用正则表达式按一级标题（#）拆分内容
    # 匹配 # 标题（忽略前后的空白），并保留标题
    sections = re.split(r'(?=^# )', content, flags=re.MULTILINE)

    # 移除空的部分
    sections = [sec.strip() for sec in sections if sec.strip()]

    for section in sections:
        # 提取标题（第一行，去掉# 和空白）
        lines = section.split('\n')
        title_line = lines[0].strip()
        if title_line.startswith('# '):
            title = title_line[2:].strip()  # 去掉# 和空格
            # 清理标题，使其适合作为文件名（移除特殊字符，替换空格为下划线）
            filename = re.sub(r'[^\w\s-]', '', title).replace(' ', '_') + '.md'
            filepath = os.path.join(output_dir, filename)

            # 写入文件
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(section)
            print(f"拆分文件已保存: {filepath}")
        else:
            # 如果没有标题，跳过或处理为其他方式（这里简单跳过）
            continue

if __name__ == "__main__":
    # 硬编码输入文件和输出目录
    input_file = "音元系统.md"
    output_dir = "docs"

    # 检查输入文件是否存在
    if not os.path.exists(input_file):
        print(f"错误：输入文件 '{input_file}' 不存在。")
        exit(1)

    # 执行拆分
    split_md(input_file, output_dir)
    print("拆分完成！")
