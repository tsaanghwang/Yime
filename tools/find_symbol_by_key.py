import json
import os
import sys

# 定义 JSON 文件的相对路径（相对于项目根目录）
json_file_path = os.path.join("data_json_files", "key_symbol_mapping.json")

# 获取当前脚本所在的目录
script_dir = os.path.dirname(os.path.abspath(__file__))

# 获取项目根目录（假设项目根目录是脚本目录的上一级）
project_root = os.path.dirname(script_dir)

# 构建 JSON 文件的完整路径
full_json_path = os.path.join(project_root, json_file_path)

# 加载 JSON 文件
try:
    with open(full_json_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    print(f"错误：文件 {full_json_path} 未找到，请先运行生成 JSON 文件的代码。")
    exit()

# 检测终端是否支持 ANSI 转义码
def supports_ansi():
    """检测终端是否支持 ANSI 转义码"""
    if sys.platform == "win32":
        return False  # Windows 默认不支持
    return True

# 支持输入和显示各在一行
print("请输入字符（逐个输入或按回车输入一串，输入 'exit' 退出）：")
while True:
    # 获取用户输入
    user_input = input("输入: ").strip()

    # 退出条件
    if user_input.lower() == "exit":
        print("程序已退出。")
        break

    # 如果输入为空，提示重新输入
    if not user_input:
        if supports_ansi():
            print("\033[1A\033[K输入为空，请重新输入。")
        else:
            print("输入为空，请重新输入。")
        continue

    # 处理输入并显示结果
    symbol_sequence = []
    for char in user_input:
        if char in data:
            symbol_sequence.append(data[char])
        else:
            symbol_sequence.append(char)  # 如果字符不存在，直接显示原字符

    # 显示结果
    if supports_ansi():
        print(f"\033[1A\033[K输入: {user_input}  显示: {' '.join(symbol_sequence)}")
    else:
        print(f"输入: {user_input}  显示: {' '.join(symbol_sequence)}")