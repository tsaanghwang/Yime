#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from syllable.analysis.slice.syllable_categorizer import GanyinCategorizer


def test_categorization():
    print("=== 测试韵母分类功能 ===")

    # 测试示例
    samples = ["ī", "āi", "iā", "iāo"]

    for final in samples:
        normalized = GanyinCategorizer._remove_tone_from_ganyin(final)
        category = GanyinCategorizer.categorize(final)
        print(f"韵母 '{final}' -> 标准化: '{normalized}' -> 分类: {category}")

        # 调试信息
        if category == "未知类型":
            print(f"  调试: 标准化结果 '{normalized}' 在各个集合中的检查:")
            print(
                f"    SINGLE_QUALITY_FINALS: {normalized in GanyinCategorizer.SINGLE_QUALITY_FINALS}")
            print(
                f"    FRONT_LONG_FINALS: {normalized in GanyinCategorizer.FRONT_LONG_FINALS}")
            print(
                f"    BACK_LONG_FINALS: {normalized in GanyinCategorizer.BACK_LONG_FINALS}")
            print(
                f"    TRIPLE_QUALITY_FINALS: {normalized in GanyinCategorizer.TRIPLE_QUALITY_FINALS}")

    print("\n=== 四类韵母数据 ===")
    all_finals = GanyinCategorizer.get_all_finals()
    for category, finals in all_finals.items():
        print(f"{category}: {sorted(finals)}")

        def test_remove_tone_from_ganyin_removes_tone_segments():
            cases = [
                ("ā", "a"),
                ("á", "a"),
                ("ǎ", "a"),
                ("à", "a"),
                ("ē", "e"),
                ("é", "e"),
                ("ě", "e"),
                ("è", "e"),
                ("ī", "i"),
                ("í", "i"),
                ("ǐ", "i"),
                ("ì", "i"),
                ("ō", "o"),
                ("ó", "o"),
                ("ǒ", "o"),
                ("ò", "o"),
                ("ū", "u"),
                ("ú", "u"),
                ("ǔ", "u"),
                ("ù", "u"),
                ("ǖ", "ü"),
                ("ǘ", "ü"),
                ("ǚ", "ü"),
                ("ǜ", "ü"),
                ("ń", "n"),
                ("ň", "n"),
                ("ǹ", "n"),
                ("n̄", "n"),
                ("ḿ", "m"),
                ("m̌", "m"),
                ("m̀", "m"),
                ("m̄", "m"),
                ("ế", "ê"),
                ("ê̌", "ê"),
                ("ề", "ê"),
                ("ê̄", "ê"),
                ("āi", "ai"),
                ("iāo", "iao"),
                ("uāng", "uang"),
                ("_i", "_i"),
                ("er", "er"),
                ("ng", "ng"),
                ("a1", "a"),
                ("ēn", "en"),
                ("īn", "in"),
                ("ǖng", "üng"),
            ]
            for original, expected in cases:
                assert GanyinCategorizer._remove_tone_from_ganyin(
                    original) == expected

        def test_categorize_returns_correct_category():
            samples = [
                ("ī", "单质干音"),
                ("āi", "前长干音"),
                ("iā", "后长干音"),
                ("iāo", "三质干音"),
                ("er", "单质干音"),
                ("uang", "三质干音"),
                ("uen", "三质干音"),
                ("ua", "后长干音"),
                ("ai", "前长干音"),
                ("ü", "单质干音"),
                ("ng", "单质干音"),
                ("", "未知类型"),
                ("xyz", "未知类型"),
            ]
            for final, expected in samples:
                assert GanyinCategorizer.categorize(final) == expected

        def test_extract_final_returns_normalized_final():
            cases = [
                ("zhang1", "ang"),
                ("zhāng", "ang"),
                ("ai1", "ai"),
                ("āi", "ai"),
                ("iāo", "iao"),
                ("uāng", "uang"),
                ("er2", "er"),
                ("ng4", "ng"),
                ("", ""),
            ]
            for pinyin, expected in cases:
                assert GanyinCategorizer.extract_final(pinyin) == expected

        def test_add_final_to_category_adds_new_final():
            # Add a new, non-existing final
            new_final = "abc"
            assert GanyinCategorizer._add_final_to_category(new_final) is True
            # Should now be in SINGLE_QUALITY_FINALS by default
            assert new_final in GanyinCategorizer.SINGLE_QUALITY_FINALS

        def test_get_all_categories_and_get_finals_by_category():
            categories = GanyinCategorizer.get_all_categories()
            assert set(categories) == {"单质干音", "前长干音", "后长干音", "三质干音"}
            for cat in categories:
                finals = GanyinCategorizer.get_finals_by_category(cat)
                assert isinstance(finals, set)

        def test_split_syllable_special_and_regular():
            # Special syllables
            assert GanyinCategorizer.split_syllable("m1") == ("'", "m̄")
            assert GanyinCategorizer.split_syllable("n4") == ("'", "ǹ")
            # Regular syllables
            assert GanyinCategorizer.split_syllable("zhang1") == ("z", "hang1")
            assert GanyinCategorizer.split_syllable("shāng") == ("sh", "āng")
            assert GanyinCategorizer.split_syllable("ai1") == ("'", "ai1")
            assert GanyinCategorizer.split_syllable("") == ("", "")

        def test_generate_shouyin_data():
            pinyin_data = {
                "zhang1": "zhāng",
                "ai1": "āi",
                "m1": "m̄",
                "n4": "ǹ"
            }
            result = GanyinCategorizer.generate_shouyin_data(pinyin_data)
            # Should contain initials: z, ', m, n
            assert set(result.values()) >= {"z", "'", "m", "n"}


if __name__ == "__main__":
    test_categorization()
