import re
import glob
from pathlib import Path

def check_files():
    error_count = 0
    for file in glob.glob('理论文件/**/*.md', recursive=True):
        with open(file, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # 检查中文标点使用英文标点的情况
        errors = re.findall(r'[，。；：？！“”‘’]', content)
        if errors:
            print(f"发现中文标点问题在 {file}:")
            print(" -> ".join(errors[:3]) + ("" if len(errors)<=3 else "..."))
            error_count += 1
            
    return error_count

if __name__ == '__main__':
    if check_files() > 0:
        raise SystemExit(1)