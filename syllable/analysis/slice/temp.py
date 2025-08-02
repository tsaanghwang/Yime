"""
请提供由syllable\analysis\slice\ganyin.json生成的syllable\analysis\slice\ganyin_enhanced.json文件的脚本。

输入文件的格式如下：
{
  "ganyin": {
    "single quality ganyin": {
      "_i1": "_ī",
      "_i2": "_í",
      "_i3": "_ǐ",
      "_i4": "_ì",
      "_i5": "_i",
      "a1": "ā",
      "a2": "á",
      "a3": "ǎ",
      ...
    },
    "front long ganyin": {
      ...
    },
    ...
  }
}
输出文件的格式如下：
{
  "ganyin": {
    "single quality ganyin": {
      "_i1": {
        "numeric_tone": "_i1",
        "tone_mark": "_ī",
        "ipa": "ʅ˥"
      },
      "_i2": {
        "numeric_tone": "_i2",
        "tone_mark": "_í",
        "ipa": "ʅ˧˥"
      },
      "_i3": {
        "numeric_tone": "_i3",
        "tone_mark": "_ǐ",
        "ipa": "ʅ˨˩˨"
      },
...

    },
... 其他分类同上
    "front long ganyin": {
      ...
    },
    ...
  }
}
"""

import json
from pathlib import Path

# 假设有一个简单的 tone_map，可以根据实际需要扩展
TONE_MARK_MAP = {
    "1": "̄",  # macron
    "2": "́",  # acute
    "3": "̌",  # caron
    "4": "̀",  # grave
    "5": "",   # no mark
}

# 假设有一个简单的 ipa_map，可以根据实际需要扩展
IPA_MAP = {
    "_i": "ʅ",
    "a": "a",
    # ... 其他音素映射 ...
}

def get_tone_mark(base: str, tone_num: str) -> str:
    # 处理下划线前缀
    if base.startswith("_"):
        base = base[1:]
    mark = TONE_MARK_MAP.get(tone_num, "")
    return base + mark

def get_ipa(base: str, tone_num: str) -> str:
    # 这里只是示例，实际应根据 base 和 tone_num 查表
    ipa_base = IPA_MAP.get(base.lstrip("_"), base.lstrip("_"))
    # 示例：不同声调可拼接不同音高符号
    tone_ipa = {
        "1": "˥",
        "2": "˧˥",
        "3": "˨˩˨",
        "4": "˩˧",
        "5": "",
    }
    return ipa_base + tone_ipa.get(tone_num, "")

def enhance_ganyin(input_path, output_path):
    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    enhanced = {"ganyin": {}}
    for category, items in data["ganyin"].items():
        enhanced[category] = {}
        for key, tone_mark in items.items():
            # key 例: "_i1"
            if key[-1].isdigit():
                base = key[:-1]
                tone_num = key[-1]
            else:
                base = key
                tone_num = "5"
            enhanced[category][key] = {
                "numeric_tone": key,
                "tone_mark": tone_mark,
                "ipa": get_ipa(base, tone_num)
            }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({"ganyin": enhanced}, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    base_dir = Path(__file__).parent
    input_path = base_dir / "ganyin.json"
    output_path = base_dir / "ganyin_enhanced.json"
    enhance_ganyin(input_path, output_path)
