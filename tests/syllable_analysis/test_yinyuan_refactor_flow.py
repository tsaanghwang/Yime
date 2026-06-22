import unittest
from pathlib import Path

from syllable.analysis.yinyuan_categories import YinyuanCategory
from syllable.analysis.yueyin_mapper import YueyinMapper
from syllable.analysis.yueyin_yinyuan import YueyinYinyuan
from syllable.analysis.zaoyin_yinyuan import ClearNoise
from syllable.pianyin import PitchedPianyin, UnpitchedPianyin


SYLLABLE_DIR = Path(__file__).resolve().parents[2] / "syllable"
CONFIG_PATH = SYLLABLE_DIR / "yinyuan" / "variables_of_attributes.json"


class TestYinyuanRefactorFlow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mapper = YueyinMapper(CONFIG_PATH)

    def test_pianyin_and_yinyuan_share_category_axis(self):
        self.assertEqual(PitchedPianyin("a", "4").category, YinyuanCategory.YUEYIN)
        self.assertEqual(UnpitchedPianyin("p").category, YinyuanCategory.ZAOYIN)
        self.assertEqual(YueyinYinyuan("a", "4").category, YinyuanCategory.YUEYIN)
        self.assertEqual(ClearNoise("p").category, YinyuanCategory.ZAOYIN)

    def test_mapper_normalizes_pianyin_text(self):
        self.assertEqual(self.mapper.normalize_pianyin_text("a˦"), "ᴀ˦")
        self.assertEqual(self.mapper.normalize_pianyin_text("a˨/a˦"), "ᴀ˩")
        self.assertEqual(self.mapper.normalize_pianyin_text(""), "")

    def test_mapper_supports_both_pitch_models(self):
        self.assertEqual(
            self.mapper.normalize_symbol("a", "˥", model="mid_high_median_model"),
            "ᴀ˥",
        )
        self.assertEqual(
            self.mapper.normalize_symbol("a", "˥", model="mid_level_median_model"),
            "ᴀ˥",
        )
        self.assertEqual(
            self.mapper.normalize_symbol("a", "˨", model="mid_high_median_model"),
            "ᴀ˩",
        )
        self.assertEqual(
            self.mapper.normalize_symbol("a", "˦", model="mid_level_median_model"),
            "ᴀ˥",
        )

    def test_yueyin_from_pianyin_rejects_noise(self):
        yueyin = YueyinYinyuan.from_pianyin(PitchedPianyin("a", "4"))
        self.assertEqual(yueyin.quality, "a")
        self.assertEqual(yueyin.pitch, "4")

        with self.assertRaises(ValueError):
            YueyinYinyuan.from_pianyin(UnpitchedPianyin("p"))


if __name__ == "__main__":
    unittest.main()
