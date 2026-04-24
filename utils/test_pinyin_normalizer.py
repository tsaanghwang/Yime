import unittest

from utils.pinyin_normalizer import (
    PinyinNormalizer,
    normalize_dict_existing_only,
    normalize_dict_with_supplements,
    normalize_existing_pinyin_dict,
    normalize_one,
    normalize_pinyin,
    process_pinyin_dict,
)


class TestPinyinNormalizerApi(unittest.TestCase):
    def test_normalize_one_handles_general_cases(self):
        cases = {
            "xue2": "xue\u0301",
            "lv3": "lü\u030c",
            "shui3": "shui\u030c",
            "": "",
            "ma": "ma",
        }

        for source, expected in cases.items():
            with self.subTest(source=source):
                self.assertEqual(normalize_one(source), expected)

    def test_normalize_one_handles_special_syllabic_qualities(self):
        cases = {
            "hm2": "hm\u0301",
            "ng4": "n\u0300g",
            "hng3": "hn\u030cg",
            "ê1": "ê\u0304",
        }

        for source, expected in cases.items():
            with self.subTest(source=source):
                self.assertEqual(normalize_one(source), expected)

    def test_normalize_dict_existing_only_does_not_add_missing_keys(self):
        normalized_dict, mismatch_count = normalize_dict_existing_only(
            {
                "hm2": "hm2",
                "lv3": "wrong",
            }
        )

        self.assertEqual(
            normalized_dict,
            {
                "hm2": "hm\u0301",
                "lv3": "lü\u030c",
            },
        )
        self.assertEqual(mismatch_count, 1)
        self.assertNotIn("hng5", normalized_dict)

    def test_normalize_dict_with_supplements_adds_special_keys(self):
        normalized_dict, mismatch_count = normalize_dict_with_supplements({})

        self.assertEqual(mismatch_count, 0)
        self.assertEqual(len(normalized_dict), len(PinyinNormalizer.SPECIAL_QUALITIES) * len(PinyinNormalizer.TONES))
        self.assertIn("hng5", normalized_dict)
        self.assertEqual(normalized_dict["hng5"], "hng")
        self.assertEqual(normalized_dict["ê2"], "ê\u0301")

    def test_compatibility_aliases_delegate_to_new_api(self):
        sample_dict = {"hm2": "hm2"}

        self.assertEqual(normalize_pinyin("hm2"), normalize_one("hm2"))
        self.assertEqual(
            normalize_existing_pinyin_dict(sample_dict),
            normalize_dict_existing_only(sample_dict),
        )
        self.assertEqual(
            process_pinyin_dict(sample_dict),
            normalize_dict_with_supplements(sample_dict),
        )


if __name__ == "__main__":
    unittest.main()
