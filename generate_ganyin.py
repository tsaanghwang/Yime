import json

# 原始数据
data = {
  "description": "干音编码系统。干音是由声调与韵母构成的音段的统称，俗名带调韵母。这套编码系统使用三个音元组合表示不同干音。在通用现代汉语中，音元特指音高特征或音质特征不同的短音，是语音的基本结构单元。",
  "encoding_rules": {
    "general_pattern": {
      "first_tone_ganyin": "三个高调音元的组合",
      "second_tone_ganyin": "低调音元、中调音元、高调音元的组合",
      "third_tone_ganyin": "三个低调音元的组合",
      "fourth_tone_ganyin": "高调音元、中调音元、低调音元的组合"
    }
  },
  "yinyuan_symbols": {
    "high_tone_i": "󰌠",
    "mid_tone_i": "󰌡",
    "low_tone_i": "󰌤",
    "high_tone_u": "󰌪",
    "mid_tone_u": "󰌫",
    "low_tone_u": "󰌮",
    "high_tone_ü": "󰌴",
    "mid_tone_ü": "󰌵",
    "low_tone_ü": "󰌸",
    "high_tone_a": "󰌾",
    "mid_tone_a": "󰌿",
    "low_tone_a": "󰍂",
    "high_tone_o": "󰍒",
    "mid_tone_o": "󰍓",
    "low_tone_o": "󰍖",
    "high_tone_e": "󰍡",
    "mid_tone_e": "󰍢",
    "low_tone_e": "󰍥",
    "high_tone_-i": "󰍵",
    "mid_tone_-i": "󰍶",
    "low_tone_-i": "󰍹",
    "high_tone_er": "󰎄",
    "mid_tone_er": "󰎅",
    "low_tone_er": "󰎈",
    "high_tone_m": "󰎎",
    "mid_tone_m": "󰎏",
    "low_tone_m": "󰎒",
    "high_tone_n": "󰎓",
    "mid_tone_n": "󰎔",
    "low_tone_n": "󰎗",
    "high_tone_ng": "󰎘",
    "mid_tone_ng": "󰎙",
    "low_tone_ng": "󰎜"
  },
  "pattern_rules": {
    "first_tone": ["high", "high", "high"],
    "second_tone": ["low", "mid", "high"],
    "third_tone": ["low", "low", "low"],
    "fourth_tone": ["high", "mid", "low"]
  },
  "notes": "此编码系统暂不扩展到其他干音。其它干音的编码遵循不同模式规则。"
}

finals_tone_mapping = {
    # 单质韵母 (12个) - ng调号标在n上
    "single_quality_finals": {
        "i": {"base": "i", "diacritics": ["ī", "í", "ǐ", "ì"]},
        "u": {"base": "u", "diacritics": ["ū", "ú", "ǔ", "ù"]},
        "ü": {"base": "ü", "diacritics": ["ǖ", "ǘ", "ǚ", "ǜ"]},
        "a": {"base": "a", "diacritics": ["ā", "á", "ǎ", "à"]},
        "o": {"base": "o", "diacritics": ["ō", "ó", "ǒ", "ò"]},
        "e": {"base": "e", "diacritics": ["ē", "é", "ě", "è"]},
        "-i": {"base": "-i", "diacritics": ["-ī", "-í", "-ǐ", "-ì"]},
        "er": {"base": "er", "diacritics": ["ēr", "ér", "ěr", "èr"]},
        "m": {"base": "m", "diacritics": ["ḿ", "m̄", "m̌", "m̀"]},
        "n": {"base": "n", "diacritics": ["n̄", "ń", "ň",  "ǹ"]},  
        "ng": {"base": "ng", "diacritics": ["n̄g", "ńg", "ňg", "ǹg"]}  # 特殊处理
    },
    
    # 后长韵母 (6个) - 调号标在后面的a/o/e上
    "post_long_finals": {
        "ia": {"base": "ia","diacritics": ["iā", "iá", "iǎ", "ià"]},
        "ua": {"base": "ua","diacritics": ["uā", "uá", "uǎ", "uà"]},
        "io": {"base": "io","diacritics": ["iō", "ió", "iǒ", "iò"]},
        "uo": {"base": "uo","diacritics": ["uō", "uó", "uǒ", "uò"]},
        "ie": {"base": "ie","diacritics": ["iē", "ié", "iě", "iè"]},
        "üe": {"base": "üe","diacritics": ["üē", "üé", "üě", "üè"]}
    },
    
    # 前长韵母 (8个) - 调号标在前面的a/o/e上
    "pre_long_finals": {
        "ai": {"base": "ai","diacritics": ["āi", "ái", "ǎi", "ài"]},
        "ei": {"base": "ei","diacritics": ["ēi", "éi", "ěi", "èi"]},
        "ao": {"base": "ao","diacritics": ["āo", "áo", "ǎo", "ào"]},
        "au": {"base": "au","diacritics": ["āu", "áu", "ǎu", "àu"]},        # ao 的基本形式
        "ou": {"base": "ou","diacritics": ["ōu", "óu", "ǒu", "òu"]},
        "an": {"base": "an","diacritics": ["ān", "án", "ǎn", "àn"]},
        "en": {"base": "en","diacritics": ["ēn", "én", "ěn", "èn"]},
        "ang": {"base": "ang","diacritics": ["āng", "áng", "ǎng", "àng"]},
        "eng": {"base": "eng","diacritics": ["ēng", "éng", "ěng", "èng"]}
    },
    
    # 三质韵母 (16个) - 按优先级标注
    "triple_quality_finals": {
        # a类标在a上
        "uai": {"base": "uai", "diacritics": ["uāi", "uái", "uǎi", "uài"]},
        "iao": {"base": "iao", "diacritics": ["iāo", "iáo", "iǎo", "iào"]},
        "iau": {"base": "iau", "diacritics": ["iāu", "iáu", "iǎu", "iàu"]},        # iao 的基本形式
        "ian": {"base": "ian", "diacritics": ["iān", "ián", "iǎn", "iàn"]},
        "uan": {"base": "uan", "diacritics": ["uān", "uán", "uǎn", "uàn"]},
        "üan": {"base": "üan", "diacritics": ["üān", "üán", "üǎn", "üàn"]},
        "iang": {"base": "iang", "diacritics": ["iāng", "iáng", "iǎng", "iàng"]},
        "uang": {"base": "uang", "diacritics": ["uāng", "uáng", "uǎng", "uàng"]},        

        # o类标在o上
        "iou": {"base": "iou", "diacritics": ["iōu", "ióu", "iǒu", "iòu"]},  # iu 的基本形式 
        "ong": {"base": "ong", "diacritics": ["ōng", "óng", "ǒng", "òng"]},  # ueng 的异体形式
        "iong": {"base": "iong", "diacritics": ["iōng", "ióng", "iǒng", "iòng"]},   # üeng 的异体形式

        # e类标在e上
        "uei": {"base": "uei", "diacritics": ["uēi", "uéi", "uěi", "uèi"]},          # ui 的基本形式
        "ien": {"base": "ien", "diacritics": ["iēn", "ién", "iěn", "ièn"]},          # in 的基本形式
        "uen": {"base": "uen", "diacritics": ["uēn", "uén", "uěn", "uèn"]},         # un 的基本形式
        "üen": {"base": "üen", "diacritics": ["üēn", "üén", "üěn", "üèn"]},        # ün 的基本形式
        "ieng": {"base": "ieng", "diacritics": ["iēng", "iéng", "iěng", "ièng"]},         # ing 的基本形式
        "ueng": {"base": "ueng", "diacritics": ["uēng", "uéng", "uěng", "uèng"]},        # ong 的基本形式
        "üeng": {"base": "üeng", "diacritics": ["üēng", "üéng", "üěng", "üèng"]},        # üeng 的基本形式

        # i类标在i上
        "ui": {"base": "ui", "diacritics": ["uī", "uí", "uǐ", "uì"]},  # uei 的简略形式，调号标在i上
        "in": {"base": "in", "diacritics": ["īn", "ín", "ǐn", "ìn"]},  # ien 的简略形式，调号标在i上
        "ing": {"base": "ing", "diacritics": ["īng", "íng", "ǐng", "ìng"]},  # ieng 的简略形式，调号标在i上
        
        # u类标在u上
        "un": {"base": "un","diacritics": ["ūn", "ún", "ǔn", "ùn"]},  # uen 的简略形式，调号标在u上
        "iu": {"base": "iu",  "diacritics": ["iū", "iú", "iǔ", "iù"]},  # iou 的简略形式，调号标在u上

        # ü类标在ü上
        "ün": {"base": "ün", "diacritics": ["ǖn", "ǘn", "ǚn", "ǜn"]}  # üen 的简略形式，调号标在ü上
    }
}

# 生成干音编码
def generate_ganyin_encoding(data):
    ganyin_encoding = {}
    
    for series_name, series_info in finals_tone_mapping.items():
        base = series_info["base"]
        series_data = {}
        
        # 第一声
        high_symbol = data["yinyuan_symbols"][f"high_tone_{base}"]
        series_data[series_info["diacritics"][0]] = high_symbol * 3
        
        # 第二声
        low_symbol = data["yinyuan_symbols"][f"low_tone_{base}"]
        mid_symbol = data["yinyuan_symbols"][f"mid_tone_{base}"]
        series_data[series_info["diacritics"][1]] = low_symbol + mid_symbol + high_symbol
        
        # 第三声
        series_data[series_info["diacritics"][2]] = low_symbol * 3
        
        # 第四声
        series_data[series_info["diacritics"][3]] = high_symbol + mid_symbol + low_symbol
        
        ganyin_encoding[f"{base}_series"] = series_data
    
    return ganyin_encoding

# 生成完整的JSON数据
data["ganyin_encoding"] = generate_ganyin_encoding(data)

# 保存到文件
with open("ganyin_encoding.json", "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print("干音编码已生成并保存到 ganyin_encoding.json")