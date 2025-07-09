import json
import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), 'pianyin')))
from pianyin.initial import Initial


def main():
    # 1. 读取声母表JSON文件
    with open('pinyin/initial.json', 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 获取声母字典
    consonant_table = data['initial']

    # 2. 生成首音映射
    initial_map = Initial.generate_from_consonant_table(consonant_table)

    # 3. 将结果保存为JSON (修改了保存路径)
    with open('syllable/initial_map.json', 'w', encoding='utf-8') as f:
        json.dump({k: str(v) for k, v in initial_map.items()},
                  f, ensure_ascii=False, indent=2)

    print("首音映射已成功生成并保存为 syllable/initial_map.json")


if __name__ == '__main__':
    main()
