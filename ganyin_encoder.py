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
  
  # 音元符号定义 - 确保所有字符都在Private Use Area-A (U+E000..U+F8FF)
  "yinyuan_symbols": {
    "high_tone_i": "󰌠",  # U+F0300
    "mid_tone_i": "󰌡",   # U+F0301
    "low_tone_i": "󰌤",   # U+F0304
    "high_tone_u": "󰌪",  # U+F032A
    "mid_tone_u": "󰌫",   # U+F032B
    "low_tone_u": "󰌮",   # U+F032E
    "high_tone_ü": "󰌴",  # U+F0334
    "mid_tone_ü": "󰌵",   # U+F0335
    "low_tone_ü": "󰌸",   # U+F0338
    "high_tone_a": "󰌾",  # U+F033E
    "mid_tone_a": "󰌿",   # U+F033F
    "low_tone_a": "󰍂",   # U+F0342
    "high_tone_o": "󰍒",  # U+F0352
    "mid_tone_o": "󰍓",   # U+F0353
    "low_tone_o": "󰍖",   # U+F0356
    "high_tone_e": "󰍡",  # U+F0361
    "mid_tone_e": "󰍢",   # U+F0362
    "low_tone_e": "󰍥",   # U+F0365
    "high_tone_-i": "󰍵", # U+F0375
    "mid_tone_-i": "󰍶",  # U+F0376
    "low_tone_-i": "󰍹",  # U+F0379
    "high_tone_er": "󰎄", # U+F0384
    "mid_tone_er": "󰎅",  # U+F0385
    "low_tone_er": "󰎈",  # U+F0388
    "high_tone_m": "󰎎",  # U+F038E
    "mid_tone_m": "󰎏",   # U+F038F
    "low_tone_m": "󰎒",   # U+F0392
    "high_tone_n": "󰎓",  # U+F0393
    "mid_tone_n": "󰎔",   # U+F0394
    "low_tone_n": "󰎗",   # U+F0397
    "high_tone_ng": "󰎘", # U+F0398
    "mid_tone_ng": "󰎙",  # U+F0399
    "low_tone_ng": "󰎜"   # U+F039C
  },

  "pattern_rules": {
    "first_tone": ["high", "high", "high"],
    "second_tone": ["low", "mid", "high"],
    "third_tone": ["low", "low", "low"],
    "fourth_tone": ["high", "mid", "low"]
  },
  "notes": "此编码系统暂不扩展到其他干音。其它干音的编码遵循不同模式规则。"
}

# 校验所有符号字符是否在key_symbol_mapping.json中定义
def validate_private_use_chars():
    """校验字符是否在key_symbol_mapping.json文件中定义"""
    # 加载key_symbol_mapping.json文件
    with open("internal_data/key_symbol_mapping.json", "r", encoding="utf-8") as f:
        symbol_mapping = json.load(f)
    
    # 获取所有允许的字符
    allowed_chars = set(symbol_mapping.values())
    
    invalid_chars = []
    for key, char in data["yinyuan_symbols"].items():
        if char not in allowed_chars:
            invalid_chars.append({
                'key': key,
                'char': char,
                'code': f"U+{ord(char):05X}",
                'status': 'Invalid (Not in key_symbol_mapping.json)'
            })
    
    if invalid_chars:
        print("发现不在key_symbol_mapping.json中的字符:")
        for item in invalid_chars:
            print(f"{item['key']}: {item['char']} ({item['code']})")
        return False
    return True

# 根据定义在internal_data/classified_finals.json中的韵母类型对干音编码
# 对三质干音

# 示例 finals_tone_mapping 定义（请根据实际 classified_finals.json 内容调整）
finals_tone_mapping = {
    "i": {
        "base": "i",
        "diacritics": ["ī", "í", "ǐ", "ì"]
    },
    "u": {
        "base": "u",
        "diacritics": ["ū", "ú", "ǔ", "ù"]
    },
    "ü": {
        "base": "ü",
        "diacritics": ["ǖ", "ǘ", "ǚ", "ǜ"]
    },
    "a": {
        "base": "a",
        "diacritics": ["ā", "á", "ǎ", "à"]
    },
    "o": {
        "base": "o",
        "diacritics": ["ō", "ó", "ǒ", "ò"]
    },
    "e": {
        "base": "e",
        "diacritics": ["ē", "é", "ě", "è"]
    }
    # 可根据需要添加更多韵母系列
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