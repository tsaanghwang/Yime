import json
from pathlib import Path

# 完整韵母列表
FINALS = [
    # 单质韵母
    "i", "u", "ü", "a", "o", "e", "ê", "er", "m", "n", "ng",
    # 后长韵母
    "ia", "ua", "io", "uo", "ie", "üe",
    # 前长韵母
    "ai", "ei", "ao", "ou", "an", "en", "ang", "eng",
    # 三质韵母
    "uai", "ui", "iao", "iu", "ian", "uan", "üan", "in", "un", "ün", 
    "iang", "uang", "ing", "ueng", "ong", "iong"
]

TONES = ["1", "2", "3", "4"]  # 四声声调

def add_tone_to_final(final, tone):
    """根据优先级将调号标在韵母的适当位置"""
    # 特殊规则处理
    if final == "ui":
        vowel = "i"
    elif final == "iu":
        vowel = "u"
    elif final == "ng":
        vowel = "n"  # ng的调号标在n上
    elif final == "ê":
        # ê的特殊组合字符
        if tone == "1":
            return "ê̄"
        elif tone == "2":
            return "ế"
        elif tone == "3":
            return "ê̌"
        elif tone == "4":
            return "ề"
        return final
    else:
        # 默认优先级：a > o > e > u > ü > i
        for vowel in ["a", "o", "e", "u", "ü", "i"]:
            if vowel in final:
                break
        else:
            # 如果没有找到优先级元音，则标在最后一个字符上
            vowel = final[-1]

    # 预组合字符映射表
    precomposed_map = {
        ('a', '1'): 'ā', ('a', '2'): 'á', ('a', '3'): 'ǎ', ('a', '4'): 'à',
        ('e', '1'): 'ē', ('e', '2'): 'é', ('e', '3'): 'ě', ('e', '4'): 'è',
        ('i', '1'): 'ī', ('i', '2'): 'í', ('i', '3'): 'ǐ', ('i', '4'): 'ì',
        ('o', '1'): 'ō', ('o', '2'): 'ó', ('o', '3'): 'ǒ', ('o', '4'): 'ò',
        ('u', '1'): 'ū', ('u', '2'): 'ú', ('u', '3'): 'ǔ', ('u', '4'): 'ù',
        ('ü', '1'): 'ǖ', ('ü', '2'): 'ǘ', ('ü', '3'): 'ǚ', ('ü', '4'): 'ǜ'
    }
    
    # 获取元音位置
    index = final.index(vowel)
    
    # 优先使用预组合字符
    if (vowel, tone) in precomposed_map:
        return final[:index] + precomposed_map[(vowel, tone)] + final[index + 1:]
    # 无法预组合的保持原样
    if tone == "1":
        return final[:index] + vowel + "̄" + final[index + 1:]  # 第一声
    elif tone == "2":
        return final[:index] + vowel + "́" + final[index + 1:]  # 第二声
    elif tone == "3":
        return final[:index] + vowel + "̌" + final[index + 1:]  # 第三声
    elif tone == "4":
        return final[:index] + vowel + "̀" + final[index + 1:]  # 第四声
    return final

def generate_mapping():
    """生成完整的韵母声调映射表"""
    mapping = {}
    for final in FINALS:
        for tone in TONES:
            key = f"{final}{tone}"
            value = add_tone_to_final(final, tone)
            mapping[key] = value
    return mapping

def save_to_json(data, file_path):
    """保存为JSON文件"""
    # 确保目录存在
    file_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
    print(f"JSON文件已生成: {file_path}")

def main():
    # 生成完整映射表
    tone_mapping = generate_mapping()
    
    # 保存到指定目录
    output_path = Path("pinyin/ganyin_de_pinyin.json")
    save_to_json(tone_mapping, output_path)

if __name__ == "__main__":
    main()