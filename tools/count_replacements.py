import re
import sys

def count_replacements(filepath, old_str, new_str):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    matches = re.findall(re.escape(old_str), content)
    count = len(matches)
    
    if count > 0:
        new_content = content.replace(old_str, new_str)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
    
    return count

if __name__ == "__main__":
    filepath = sys.argv[1] if len(sys.argv) > 1 else "tools/orchestrator.py"
    old_str = "音元分类器"
    new_str = "韵母分类法"
    
    count = count_replacements(filepath, old_str, new_str)
    print(f"成功替换了 {count} 处 '{old_str}' 为 '{new_str}'")