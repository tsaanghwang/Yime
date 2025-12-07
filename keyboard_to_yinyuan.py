def keystroke_to_yinyuan(input_str: str) -> list[str]:
    """将键盘输入转换为音元序列"""
    yunmu_sequence = []
    buffer = ""

    for char in input_str.lower():
        buffer += char
        if buffer in keystroke_to_yinyuan_mapping:  # 引用已存在的映射字典
            yunmu_sequence.extend(keystroke_to_yinyuan_mapping[buffer])
            buffer = ""

    if buffer:  # 处理剩余未匹配字符
        raise ValueError(f"无效输入序列: {buffer}")
    return yunmu_sequence