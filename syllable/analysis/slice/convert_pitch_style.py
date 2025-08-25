import json
import os
from pathlib import Path
from yueyin_yinyuan import YueyinYinyuan

# 获取当前脚本所在目录
script_dir = Path(__file__).parent

# 输入输出文件路径（使用绝对路径）
input_path = script_dir / 'yinyuan' / 'pitched_yinyuan_of_mid_high_median_model.json'
output_path = script_dir / 'yinyuan' / 'yueyin_yinyuan.json'

# 确保输出目录存在
output_path.parent.mkdir(parents=True, exist_ok=True)

# 读取输入数据
try:
    with open(input_path, 'r', encoding='utf-8') as f:
        input_data = json.load(f)
except FileNotFoundError:
    print(f"错误：找不到输入文件 {input_path}")
    print(f"当前工作目录：{os.getcwd()}")
    exit(1)

# 创建 YueyinYinyuan 实例
yueyin = YueyinYinyuan(
    quality='neutral',
    pitch='4',
    duration='neutral',
    loudness='neutral',
    pitch_style='number'
)

# 转换音高风格
converted_data = {
    "ganyin_type": {
        key: {
            "呼音": key,
            "主音": key,
            "末音": key
        } for key in input_data.keys()
    }
}

symbol_data = yueyin._change_pitch_style(converted_data)

# 提取转换后的音高标记
result = {}
for ganyin_type, ganyin_dict in symbol_data.items():
    for key, value in ganyin_dict.items():
        new_key = value["呼音"]
        result[new_key] = input_data[key]

# 保存结果
with open(output_path, 'w', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

print(f"音高风格转换完成，结果已保存到: {output_path}")