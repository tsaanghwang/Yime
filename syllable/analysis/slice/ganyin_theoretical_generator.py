"""按预定义韵母集合生成理论干音。"""

from pathlib import Path
import json

try:
    from .final_categorizer import FinalCategorizer
except ImportError:
    from final_categorizer import FinalCategorizer


CATEGORY_TO_GROUP_NAME = {
    "单质韵母": "single quality ganyin",
    "前长韵母": "front long ganyin",
    "后长韵母": "back long ganyin",
    "三质韵母": "triple quality ganyin",
}

TONE_MARKS = {
    "a": {1: "ā", 2: "á", 3: "ǎ", 4: "à"},
    "e": {1: "ē", 2: "é", 3: "ě", 4: "è"},
    "i": {1: "ī", 2: "í", 3: "ǐ", 4: "ì"},
    "o": {1: "ō", 2: "ó", 3: "ǒ", 4: "ò"},
    "u": {1: "ū", 2: "ú", 3: "ǔ", 4: "ù"},
    "ü": {1: "ǖ", 2: "ǘ", 3: "ǚ", 4: "ǜ"},
}

SPECIAL_TONE_FORMS = {
    "ê": {1: "ê̄", 2: "ế", 3: "ê̌", 4: "ề", 5: "ê"},
    "m": {1: "m̄", 2: "ḿ", 3: "m̌", 4: "m̀", 5: "m"},
    "n": {1: "n̄", 2: "ń", 3: "ň", 4: "ǹ", 5: "n"},
    "ng": {1: "n̄g", 2: "ńg", 3: "ňg", 4: "ǹg", 5: "ng"},
}


def _display_final(final: str) -> str:
    """将内部韵母键转换为显示用干音基础形式。"""
    if final.startswith("_"):
        return "_" + _display_final(final[1:])
    return final.replace("v", "ü")


def _find_tone_position(display_final: str) -> int:
    if "a" in display_final:
        return display_final.index("a")
    if "o" in display_final:
        return display_final.index("o")
    if "e" in display_final:
        return display_final.index("e")

    for index in range(len(display_final) - 1, -1, -1):
        if display_final[index] in {"i", "u", "ü"}:
            return index

    raise ValueError(f"无法确定韵母 {display_final!r} 的标调位置")


def generate_theoretical_tone_form(final: str, tone: int) -> str:
    """为单个韵母生成指定声调的理论干音。"""
    if tone == 5:
        return _display_final(final)

    if final in SPECIAL_TONE_FORMS:
        return SPECIAL_TONE_FORMS[final][tone]

    prefix = ""
    core_final = final
    if final.startswith("_"):
        prefix = "_"
        core_final = final[1:]

    display_final = _display_final(core_final)
    tone_position = _find_tone_position(display_final)
    tone_char = display_final[tone_position]
    marked_char = TONE_MARKS[tone_char][tone]
    marked_final = display_final[:tone_position] + marked_char + display_final[tone_position + 1:]
    return prefix + marked_final


def generate_theoretical_grouped_ganyin() -> dict[str, dict[str, str]]:
    """生成按类别分组的理论干音 JSON 结构。"""
    grouped: dict[str, dict[str, str]] = {
        "single quality ganyin": {},
        "front long ganyin": {},
        "back long ganyin": {},
        "triple quality ganyin": {},
    }

    sorted_finals = FinalCategorizer.sort_finals_by_category(FinalCategorizer.get_all_finals())
    for category_name, finals in sorted_finals.items():
        group_name = CATEGORY_TO_GROUP_NAME[category_name]
        for final in finals:
            for tone in range(1, 6):
                grouped[group_name][f"{final}{tone}"] = generate_theoretical_tone_form(final, tone)

    return grouped


def generate_theoretical_flat_ganyin() -> dict[str, str]:
    """生成单层理论干音映射。"""
    grouped = generate_theoretical_grouped_ganyin()
    flat: dict[str, str] = {}
    for entries in grouped.values():
        flat.update(entries)
    return flat


def save_theoretical_ganyin_json(output_path: str | Path) -> Path:
    """将理论干音保存为 JSON 文件。"""
    target_path = Path(output_path)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    with open(target_path, "w", encoding="utf-8") as file:
        json.dump({"ganyin": generate_theoretical_grouped_ganyin()}, file, ensure_ascii=False, indent=2)
    return target_path


if __name__ == "__main__":
    default_output = Path(__file__).resolve().parent / "yinyuan" / "ganyin_theoretical.json"
    saved_path = save_theoretical_ganyin_json(default_output)
    print(f"理论干音已生成: {saved_path}")
