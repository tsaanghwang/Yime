import json
from collections import defaultdict


def generate_yinjie():
    # 1. 定义元数据
    metadata = {
        "version": "0.02",
        "description": "A syllable is composed of an initial and a final with a tone.",
        "created": "2025-06-08",
        "last_updated": "2025-06-09",
        "source": "dictionary",
        "license": "CC-BY-SA-4.0",
        "author": "Yinyuan System",
        "standards": "Standard Mandarin (Putonghua)"
    }

    # 2. 定义拼音规则
    conventions = {
        "pinyin_notation": "syllable = (initial + final) with a tone",
        "sorting_rule": "sorted by alphabetical sequence",
        "tone_marks": {
            "1": "̄ (high tone)",
            "2": "́ (rising tone)",
            "3": "̌ (low tone)",
            "4": "̀ (falling tone)",
            "5": " (neutral tone)"
        }
    }

    # 3. 定义基础音节数据（这里简化了，实际应从更基础的数据生成）
    # 实际项目中应该从声母、韵母和声调规则组合生成
    syllables = {
        "A": ["a", "ā", "á", "ǎ", "à"],
        "B": ["ba", "bā", "bá", "bǎ", "bà"],
        # ... 其他音节数据
    }

    # 4. 计算统计信息
    statistics = {
        "syllable_count_by_first_letter": {k: len(v)//5 for k, v in syllables.items()},
        "total_syllables": sum(len(v) for v in syllables.values()),
        "original_syllables": len(syllables),
        "tone_patterns": 5
    }

    # 5. 定义注意事项
    notes = [
        "在拼音系统中， ü 在 j 、 q 、 x 和 y 后简写为 u ，如 ju 、 qu 、 xu 和 yu 等。",
        "在输入拼音时，韵母 v 对应单独出现在 l 和 n 后的 ü ，亦即 lv 对应 lü 、 nv 对应 nü 。",
        "在输入拼音时，韵母 ve 或 ue 对应出现在 l 和 n 后的 üe ，例如 lue 或 lve 对应 lüe 。",
        "单质韵母 ê 、 m 、 n 和 ng 等未一并列入列表中。",
        "每个音节包含5个声调变体：1-4声和轻声",
        "特殊处理：'er'韵母只有4个声调变体（无轻声）"
    ]

    # 6. 组装最终数据结构
    yinjie_data = {
        "metadata": metadata,
        "conventions": conventions,
        "statistics": statistics,
        "notes": notes,
        "syllables_with_tone": syllables
    }

    # 7. 输出为JSON文件
    with open("pinyin/yinjie.json", "w", encoding="utf-8") as f:
        json.dump(yinjie_data, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    generate_yinjie()
