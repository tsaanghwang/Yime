import json
from pathlib import Path

# 定义规则常量
SPECIAL_RULE_I = "-i"  # 特殊韵母
REPLACEMENT_I = "ir"   # 替换值
Y = "ü"   # 带分音符的u
U_DI_REPLACEMENT = "v"  # 替换值
CODA_O = "o"          # 韵尾o
CODA_U = "u"          # 韵尾u
ROUNDED_O = "o"          # 普通o
UNROUNDED_O = "e"
FRONT_E = "e"          # 普通e
E_CIRCUMFLEX = "ê"    # 带扬抑符的e
RIME_N = "n"          # 弱化或脱落[ə]的en[ᵊn]
RIME_EN = "en"        # en组合
FINAL_ONG = "ong"      # ong组合
FINAL_IONG = "iong"    # iong组合
ING_FINAL = "ing"      # ing组合
FINAL_VONG = "üong"    # üong组合
UENG_FINAL = "ueng"    # ueng组合
FINAL_UONG = "uong"    # uong组合
ENG_FINAL = "eng"      # eng组合
FINAL_AO = "ao"        # ao组合
FINAL_IAO = "iao"      # iao组合
ING_FINAL = "in"        # in组合
YN_FINAL = "ün"        # ün组合

# 本字典收录《现代汉语词典》所有韵母，建立与每个韵母的标准拼音形式对应的主流输入法ASCII拼式的映射关系，并根据要求作少量调整。
# 1. 用 ir 来代替韵母 -i([ɿ]/[ʅ])，以便区分韵母 i[i]和 i([ɿ]/[ʅ])。
# 2. 用 u 来代替韵母 ao 和 iao 的韵尾 o，以体现质位相同符号相同原则。
# 3. 用 üong 来代替韵母 iong，以体现这个韵母是撮口呼韵母的语音事实。
# 4. 在用 üong 来代替 iong 后，用 iong 来代替韵母 ing，以与 ong 和 uong 一起体现同韵基的韵母韵基相同原则。
# 5. 用 o 来代替韵母 e[ɤ] 和出现在韵母 eng 和 ueng 中的 e[ɤ]。
# 6. 用 ien 和 ven 来代替韵母 in 和 ün，以与 en 和 uen 一起体现同韵基的韵母韵基相同原则。
# 7. 在用 ong 和 uong 来代替韵母 eng 和 ueng 后，用 uong 来代替原来的韵母 ong ，亦即把原来的 ueng 和 ong 合并成为韵母 uong，以体现原来的韵母 ong 是合口呼韵母的语音事实。
# 8. 用 v 来代替韵母 ü 和韵头 ü，以便直接从键盘上输入撮口呼韵母。
# 9.  在用 o 来代替韵母 e[ɤ] 后，用 e 来代替韵母 ê[ê]，避免质位交叉问题，体现前拼前（e 与 i 和 n 相拼）后拼后（o 与 u 和 ng相拼）原则。
# 经过这些调整，从键盘上可以直接输入全部干质或韵母。

# 从yunmu字典开始
yunmu = {
    "i": "", "u": "", Y: "", "a": "", ROUNDED_O: "", UNROUNDED_O: "", E_CIRCUMFLEX: "",
    SPECIAL_RULE_I: "", "er": "", "m": "", "n": "", "ng": "", "ia": "", "ua": "",
    "io": "", "uo": "", "ie": "", "üe": "", "ai": "", "ei": "",
    FINAL_AO: "", "ou": "", "an": "", "en": "", "ang": "", ENG_FINAL: "",
    FINAL_IAO: "", "iou": "", "uai": "", "uei": "", "ian": "",
    "uan": "", "üan": "", ING_FINAL: "", "uen": "", YN_FINAL: "",
    "iang": "", "uang": "", ING_FINAL: "", UENG_FINAL: "",
    FINAL_ONG: "", FINAL_IONG: ""
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


def convert_yunmu(yunmu_dict):
    converted = {}

    for key, value in yunmu_dict.items():
        # 初始值设为键本身
        new_value = key

        # 规则1: 特殊韵母-i -> ir
        if SPECIAL_RULE_I in key:
            new_value = REPLACEMENT_I

        # 规则2: 在ao/iao中o -> u
        if key in (FINAL_AO, FINAL_IAO):
            new_value = new_value.replace(CODA_O, CODA_U)

        # 规则3: iong -> üong
        if key == FINAL_IONG:
            new_value = FINAL_VONG

        # 规则4: ing -> iong (注意顺序，先处理iong->üong)
        if key == ING_FINAL:
            new_value = FINAL_IONG

        # 规则5: 在e/eng/ueng中e->o
        if key in (UNROUNDED_O, ENG_FINAL, UENG_FINAL):
            new_value = new_value.replace(UNROUNDED_O, ROUNDED_O)

        # 规则6: in -> ien, ün -> üen
        if key in (IN_FINAL, YN_FINAL):
            new_value = new_value.replace(RIME_N, RIME_EN)

        # 规则7: ong -> uong
        if key == FINAL_ONG:
            new_value = FINAL_UONG

        # 规则8: ü -> v
        new_value = new_value.replace(Y, U_DI_REPLACEMENT)

        # 规则9: ê->e
        if key == FRONT_E:
            continue  # 跳过不添加到新字典
        elif key == E_CIRCUMFLEX:
            converted[FRONT_E] = FRONT_E  # 使用新键"e"添加
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
