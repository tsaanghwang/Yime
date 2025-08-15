import json
from pathlib import Path

"""将数字标调的干音数据转换为带声调标记和IPA的格式"""

# 韵母与国际音标（IPA）的映射


def load_final_styles():
    """加载韵母与IPA的映射关系"""
    final_styles_path = Path(__file__).parent / "final_styles.json"
    with open(final_styles_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 构建韵母到IPA的映射字典
    ipa_map = {}
    for category in data["finals"].values():
        for final, info in category.items():
            # 处理特殊韵母"_i"的IPA值（ɿ/ʅ）
            if final == "_i":
                ipa_map[final] = info["ipa"].split("/")[0]  # 默认使用第一个变体
                ipa_map["i"] = info["ipa"].split("/")[1]    # 添加i的映射
            else:
                ipa_map[final] = info["ipa"]
    return ipa_map


# 全局韵母-IPA映射表
IPA_MAP = load_final_styles()

# 数字调号到声调标记的映射
TONE_MARK_MAP = {
    "1": "̄",  # macron
    "2": "́",  # acute
    "3": "̌",  # caron
    "4": "̀",  # grave
    "5": "",   # no mark
}


def get_pinyin(base: str, tone_num: str) -> str:
    # 处理下划线前缀
    if base.startswith("_"):
        base = base[1:]
    mark = TONE_MARK_MAP.get(tone_num, "")
    return base + mark


def get_ipa(base: str, tone_num: str) -> str:
    """获取韵母的IPA表示（含声调）"""
    # 特殊处理带下划线的韵母（如"_i"）
    base_key = base if base.startswith("_") else base.lstrip("_")
    ipa_base = IPA_MAP.get(base_key, base_key)
    tone_ipa = {
        "1": "˥˥˥",    # 高平调
        "2": "˧˦˥",   # 中升调
        "3": "˨˩˨",  # 低平调
        "4": "˥˦˩",   # 高降调
        "5": "˦˦˦",     # 轻声调
    }
    """
    # 字体引用逻辑
    def get_ipa(base: str, tone_num: str) -> str:
        tone_ipa = {
            "1": "<span class='tone'>\uE001</span>",  # 使用PUA字符
            "3": "<span class='tone'>\uE002</span>",
            # ...其他调值
        }
    """
    """
    # 修改tone_ipa字典，添加长调专用符号
    tone_ipa = {
        "1": "\uE001",  # 自定义长高平调PUA字符
        "2": "˧˦˥",    # 中升调保持不变
        "3": "\uE002",  # 自定义长低平调PUA字符
        "4": "˥˦˩",    # 高降调保持不变
        "5": "\uE003",  # 自定义长轻声调
    }
    """

    # 特殊处理 "_i" 韵母，返回两种变体
    if base_key == "_i":
        return f"ɿ{tone_ipa.get(tone_num, '')}/ʅ{tone_ipa.get(tone_num, '')}"

    return ipa_base + tone_ipa.get(tone_num, "")


def enhance_ganyin(input_path, output_path):
    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    enhanced = {}
    for category, items in data["ganyin"].items():
        enhanced[category] = {}
        for key, pinyin in items.items():
            # key 例: "_i1"
            if key[-1].isdigit():
                base = key[:-1]
                tone_num = key[-1]
            else:
                base = key
                tone_num = "5"
            enhanced[category][key] = {
                "ime": key,
                "pinyin": pinyin,
                "ipa": get_ipa(base, tone_num)
            }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(enhanced, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    base_dir = Path(__file__).parent
    input_path = base_dir / "ganyin.json"
    output_path = base_dir / 'yinyuan' / 'ganyin_enhanced.json'
    enhance_ganyin(input_path, output_path)

    print(f"转换完成，结果已保存到 {output_path}")

