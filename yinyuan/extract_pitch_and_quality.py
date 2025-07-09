import json

# 读取原始文件
with open('yinyuan/pitched_pianyin.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# 转换格式
converted_data = {}
for key, value in data.items():
    # 提取音质部分(去掉最后一个字符)
    quality = key[:-1]
    # 提取音高部分(最后一个字符)
    pitch = key[-1]
    # 创建新结构
    converted_data[key] = [quality, pitch]

# 写入新文件
with open('yinyuan\pitched_pianyin_attributes.json', 'w', encoding='utf-8') as f:
    json.dump(converted_data, f, ensure_ascii=False, indent=2)

print("转换完成，结果已保存到 yinyuan\pitched_pianyin_attributes.json")
