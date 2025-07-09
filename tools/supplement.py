import json

# 加载现有文件
with open('pinyin/yunmu_de_IPA.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# 需要补充的键位映射
keystrokes = {
    "ue": "ʏᴇ",  # üe的键位
    "ve": "ʏᴇ",  # 拼音输入法中常见的替代写法
    "vn": "ʏᵊn",  # ün的键位
    "van": "ʏæn"  # üan的键位
}

# 只添加不存在的条目
for keystroke, ipa in keystrokes.items():
    if keystroke not in data:
        data[keystroke] = ipa

# 保存文件（保持原有格式和顺序）
with open('pinyin/yunmu_de_IPA.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

# 验证补充结果
with open('pinyin/yunmu_de_IPA.json', 'r', encoding='utf-8') as f:
    updated = json.load(f)

print("新增的键位：")
for keystroke in keystrokes:
    if keystroke in updated:
        print(f"{keystroke}: {updated[keystroke]}")
