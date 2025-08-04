"""
目前验证结果如下：
验证 _i1:
{
  "呼音": "ʅ˥",
  "主音": "ʅ˥",
  "末音": "ʅ˥"
}
验证 _i2:
{
  "呼音": "ʅ˩",
  "主音": "ʅ˦",
  "末音": "ʅ˥"
}
验证 _i3:
{
  "呼音": "ʅ˩",
  "主音": "ʅ˩",
  "末音": "ʅ˩"
}
验证 _i4:
{
  "呼音": "ʅ˥",
  "主音": "ʅ˦",
  "末音": "ʅ˩"
}
验证 _i5:
{
  "呼音": "ʅ˦",
  "主音": "ʅ˦",
  "末音": "ʅ˦"
}
要求验证结果：
验证 _i1:
{
  "呼音": "ɿ˥/ʅ˥",
  "主音": "ɿ˥/ʅ˥",
  "末音": "ɿ˥/ʅ˥"
}
验证 _i2:
{
  "呼音": "ɿ˩/ʅ˩",
  "主音": "ɿ˦/ʅ˦",
  "末音": "ɿ˥/ʅ˥"
}
验证 _i3:
{
  "呼音": "ɿ˩/ʅ˩",
  "主音": "ɿ˩/ʅ˩",
  "末音": "ɿ˩/ʅ˩"
}
验证 _i4:
{
  "呼音": "ɿ˥/ʅ˥",
  "主音": "ɿ˦/ʅ˦",
  "末音": "ɿ˩/ʅ˩"
}
验证 _i5:
{
  "呼音": "ɿ˦/ʅ˦",
  "主音": "ɿ˦/ʅ˦",
  "末音": "ɿ˦/ʅ˦"
}

在syllable\analysis\slice\ganyin_slicer.py中处理
这组输入数据：
    "_i1": {
      "呼音": "ɿ˥/ʅ˥",
      "主音": "ɿ˥/ʅ˥",
      "末音": "ɿ˥/ʅ˥"
    },
    },
    "_i5": {
      "ime": "_i5",
      "pinyin": "_i",
      "ipa": "ɿ˦˦/ʅ˦˦"
    },
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
