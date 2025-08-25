"""
拼音按照声母分类
功能：从JSON格式的拼音映射字典导入数据对拼音按声母分类

处理流程：
1. 读取JSON文件，析取带调拼音（键）
2. 构建字典结构：以声母为键，以带调拼音为值
3. 按拼音首字母排序
4. 以a/o/e开头的音节（零声母音节）以a/e/o作键
5. 区分z, c, s 与 zh, ch, sh
6. 将分类结果以JSON格式保存到指定文件

输入文件格式：
- JSON字典，结构为{"pinyin": "pinyin"}
    - 输入格式示例：
    {
        "a1": "a1",
        "ba1": "ba1",
        ...,
        "zui4": "zui4"
    }

输出文件格式：
- JSON字典，结构为{"shengmu": ["pinyin1", "pinyin2",...]}
    - 输出格式示例：
    {
        "a": ["a1", "a2", ...],
        "b": ["ba1", "ba2", ...], 
        "c": [...],
        "ch": ["cha1", "cha2", ...],
        ...
    }
"""
import json
import os
from collections import defaultdict
from typing import Dict, List


def get_initial(pinyin: str) -> str:
    """
    获取拼音的声母

    参数:
        pinyin: 带调拼音字符串

    返回:
        声母分类键 (a/e/o 或 b/c/ch 等)
    """
    # 零声母处理
    if pinyin[0] in {'a', 'e', 'o'}:
        return pinyin[0]

    # 平翘舌音处理
    if len(pinyin) > 1:
        if pinyin.startswith('zh'):
            return 'zh'
        if pinyin.startswith('ch'):
            return 'ch'
        if pinyin.startswith('sh'):
            return 'sh'

    # 其他声母取第一个字母
    return pinyin[0]


def classify_pinyin(pinyin_dict: Dict[str, str]) -> Dict[str, List[str]]:
    """
    分类拼音到声母类别

    参数:
        pinyin_dict: 拼音到汉字的字典

    返回:
        按声母分类的字典
    """
    classified = defaultdict(list)

    for pinyin in pinyin_dict.keys():
        initial = get_initial(pinyin)
        classified[initial].append(pinyin)

    return classified


def save_classified_pinyin(classified: Dict[str, List[str]], output_path: str) -> None:
    """
    保存分类后的拼音到JSON文件

    参数:
        classified: 分类后的拼音字典
        output_path: 输出文件路径
    """
    # 按声母排序并排序每个声母下的拼音
    sorted_classified = {
        k: sorted(v)
        for k, v in sorted(classified.items())
    }

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(sorted_classified, f, ensure_ascii=False, indent=2)


def main():
    # 定义输入输出文件路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(script_dir, 'pinyin.json')
    output_file = os.path.join(script_dir, 'pinyin_classified.json')

    try:
        # 读取输入文件
        with open(input_file, 'r', encoding='utf-8') as f:
            pinyin_dict = json.load(f)

        # 分类拼音
        classified = classify_pinyin(pinyin_dict)

        # 保存结果
        save_classified_pinyin(classified, output_file)

        print(f"拼音分类完成，结果已保存到: {output_file}")

    except FileNotFoundError:
        print(f"错误: 输入文件 {input_file} 不存在")
    except json.JSONDecodeError:
        print(f"错误: 输入文件 {input_file} 不是有效的JSON格式")
    except Exception as e:
        print(f"处理过程中发生错误: {str(e)}")


if __name__ == '__main__':
    main()
