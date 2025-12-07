from utils_charfilter import is_allowed_code_char

def map_shouyin_to_code(shouyin: str) -> str:
    """将输入的大写声母映射为音元代码"""
    # 基础声母映射表
    shouyin_map = {
        'B': 'UPY_B',
        'P': 'UPY_P',
        'M': 'UPY_M',
        'F': 'UPY_F',
        # 其他声母...
        'SH': 'UPY_SH',
        'CH': 'UPY_CH',
        'ZH': 'UPY_ZH'
    }
    return shouyin_map.get(shouyin, 'UNKNOWN')  # 返回匹配的代码或未知标记

def get_shouyin_code(shouyin_input: str) -> str:
    """
    增强版声母到音元代码转换

    支持大小写不敏感输入
    添加容错处理
    支持复合声母(如zh/ch/sh)
    """
    shouyin = shouyin_input.upper().strip()

    # 优先处理复合声母
    compound_shouyin_list = ['ZH', 'CH', 'SH']
    for ci in compound_shouyin_list:
        if shouyin.startswith(ci):
            return f"UPY_{ci}"

    # 处理单声母
    if len(shouyin) == 1 and shouyin.isalpha():
        return f"UPY_{shouyin}"

    return 'INVALID_INPUT'

# 在需要简洁表示的场合添加转换函数
def get_short_code(full_code: str) -> str:
    """去除前缀的简写形式"""
    return full_code.replace("UPY_", "") if full_code.startswith("UPY_") else full_code

def normalize_key(s: str) -> str:
    # 旧： return "".join(ch for ch in s if ch.isalpha())
    return "".join(ch for ch in s if is_allowed_code_char(ch))
