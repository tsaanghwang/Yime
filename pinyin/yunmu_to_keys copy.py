import json
from pathlib import Path

#     本字典收录《现代汉语词典》所有韵母，建立与每个韵母的标准拼音形式对应的主流输入法ASCII拼式的映射关系，并作少量调整。
#     1. 用 v 来代替韵母 ü 和韵头 ü，以便直接从键盘上输入韵母。
#     2. 用 ir 来代替韵母 -i([ɿ]/[ʅ])，以便区分韵母 i[i]和 i([ɿ]/[ʅ])。
#     3. 用 u 来代替韵母 ao 和 iao 的 o，以体现质位相同符号相同原则。
#      4. 用 o 来代替韵母 o[o] 和 e[ɤ]以及出现在韵母 eng 和 ueng 中的 e[ɤ]，以便用 e 来代替韵母  ê[ê]，避免质位交叉问题，体现前拼前（e与i和n相拼）后拼后（o与u和ng相拼）原则。
#     5. 用 ien 和 ven 来代替韵母 in 和  的 ün，以与en和uen一起体现同韵的韵母符号相同原则。
#     6. 用 vong 来代替韵母 iong，以体现这个韵母是撮口呼韵母的语音事实。
#      7. 在用 ong 和 uong 来代替韵母 eng 和 ueng 后，用 uong 来代替原来的韵母 ong ，亦即把原来的ueng和ong合并成为韵母 uong，以体现原来的韵母 ong 是合口呼韵母的语音事实。
#     8. 在用 vong 来代替韵母 iong后，用 iong 来代替韵母 ing，以与 ong 和 uong 一起体现同韵的韵母韵部相同原则。
#     9. 经过这些调整，从键盘上可以直接输入全部干质或韵母。

# 从yunmu字典开始
yunmu = {
    "i": "", "u": "", "ü": "", "a": "", "o": "", "e": "", "ê": "",
    "-i": "", "er": "", "m": "", "n": "", "ng": "", "ia": "", "ua": "",
    "io": "", "uo": "", "ie": "", "üe": "", "ai": "", "ei": "",
    "ao": "", "ou": "", "an": "", "en": "", "ang": "", "eng": "",
    "iao": "", "iou": "", "uai": "", "uei": "", "ian": "",
    "uan": "", "üan": "", "in": "", "uen": "", "ün": "",
    "iang": "", "uang": "", "ing": "", "ueng": "",
    "ong": "", "iong": ""
}


def update_value_with_key(dictionary, key, new_value):
    """
    用键修改字典中的值，保持键不变并用键名作为键对应的值

    参数:
        dictionary: 要修改的字典
        key: 要修改的键
        new_value: 新的值（在此实现中将被忽略）

    返回:
        修改后的字典
    """
    for k in dictionary:
        dictionary[k] = k  # 将值设置为键名本身
    return dictionary


# 调用 update_value_with_key 并返回字典 yunmu
yunmu = update_value_with_key(yunmu, None, None)
# print(yunmu)  # 输出: 所有键的值都等于键名本身的字典


def convert_yunmu(yunmu_dict):
    converted = {}

    for key, value in yunmu_dict.items():
        # 初始值设为键本身
        new_value = key

        # 规则1: 特殊韵母-i -> ir
        if "-i" in key:
            new_value = "ir"

        # 规则2: 在ao/iao中o -> u
        if key in ("ao", "iao"):
            new_value = new_value.replace("o", "u")

        # 规则3: iong -> üong
        if key == "iong":
            new_value = "üong"

        # 规则4: ing -> iong (注意顺序，先处理iong->üong)
        if key == "ing":
            new_value = "iong"

        # 规则5: 在e/eng/ueng中e->o
        if key in ("e", "eng", "ueng"):
            new_value = new_value.replace("e", "o")

        # 规则6: in -> ien, ün -> üen
        if key in ("in", "ün"):
            new_value = new_value.replace("n", "en")

        # 规则7: ong -> uong
        if key == "ong":
            new_value = "uong"

        # 规则8: ü -> v, 等等
        new_value = new_value.replace("ü", "v")

        # 规则9: ê->e
        if key == "e":
            continue  # 跳过不添加到新字典
        elif key == "ê":
            converted["e"] = "e"  # 使用新键"e"添加
        else:
            converted[key] = new_value

    return converted


# 执行转换
yunmu_to_keys = convert_yunmu(yunmu)

# 确保pinyin目录存在
output_path = Path("pinyin/yunmu_to_keys.json")
output_path.parent.mkdir(exist_ok=True)

# 保存结果
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(yunmu_to_keys, f, ensure_ascii=False, indent=2)

# 验证结果
print("转换完成，结果如下：")
for orig, converted in yunmu_to_keys.items():
    print(f"{orig} -> {converted}")

print(f"\n结果已保存到 {output_path}")
