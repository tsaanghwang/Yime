"""
duplicate_checker.py - 列表查重工具

功能：
1. 检查列表中的重复元素
2. 返回重复元素及其所有出现位置
3. 提供格式化输出
4. 支持多种数据类型检查
"""

from typing import Any, Dict, List


def find_duplicates(input_list: List[Any]) -> Dict[Any, List[int]]:
    """
    查找列表中的重复元素及其位置
    
    参数:
        input_list: 要检查的列表，可包含任意可哈希类型
        
    返回:
        字典，键为重复元素，值为包含所有出现位置的列表
        
    异常:
        TypeError: 当输入不是列表时抛出
    """
    if not isinstance(input_list, list):
        raise TypeError("输入必须是列表类型")
    
    element_indices = {}
    
    for index, element in enumerate(input_list):
        if element not in element_indices:
            element_indices[element] = []
        element_indices[element].append(index)
    
    return {k: v for k, v in element_indices.items() if len(v) > 1}


def print_duplicates(duplicates: Dict[Any, List[int]]) -> None:
    """
    格式化打印重复元素信息
    
    参数:
        duplicates: find_duplicates函数的返回结果
    """
    if not duplicates:
        print("✅ 没有发现重复元素")
        return
    
    print("⚠️ 发现以下重复元素:")
    for item, positions in duplicates.items():
        print(f"  元素 '{item}' 出现在位置: {', '.join(map(str, positions))}")


def test_example() -> None:
    """测试示例"""
    test_cases = [
        ["a", "b", "c", "a", "b", "d", "e", "f", "e"],  # 字符串列表
        [1, 2, 3, 1, 2, 4, 5, 6, 5],  # 数字列表
        [True, False, True, False, True],  # 布尔值列表
        ["apple", "banana", "apple", "orange"],  # 单词列表
        [],  # 空列表
        ["i","u","ü","ɑ","o","e","ê", "er","m","n","nɡ","iɑ","uɑ","io","uo","ie","üe","ɑi","ei","ɑo","ou","ɑn","en","ɑnɡ","enɡ","iɑo","iu","uɑi","ui","iɑn","uɑn","üɑn","in","un","ün","iɑnɡ","uɑnɡ","inɡ","uenɡ","onɡ","ionɡ"]
    ]
    
    for case in test_cases:
        print(f"\n测试列表: {case}")
        duplicates = find_duplicates(case)
        print_duplicates(duplicates)


if __name__ == "__main__":
    test_example()