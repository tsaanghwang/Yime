import json
import unittest
from pathlib import Path
from typing import cast

from syllable.analysis.yinyuan_categories import YinyuanCategory
from syllable.analysis.yueyin_mapper import YueyinMapper
from syllable.analysis.yueyin_yinyuan import YueyinYinyuan
from syllable.analysis.zaoyin_yinyuan import ClearZaoyin, VoicedZaoyin
from syllable.pianyin import (
    PitchedPianyin,
    UnpitchedPianyin,
    YueyinPianyin,
    ZaoyinPianyin,
)


SYLLABLE_DIR = Path(__file__).resolve().parents[2] / "syllable"
CONFIG_PATH = SYLLABLE_DIR / "yinyuan" / "variables_of_attributes.json"
ZAOYIN_REGISTRY_PATH = SYLLABLE_DIR / "yinyuan" / "zaoyin_yinyuan_enhanced.json"
YUEYIN_REGISTRY_PATH = SYLLABLE_DIR / "yinyuan" / "yueyin_yinyuan_enhanced.json"


class TestYinyuanRefactorFlow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mapper = YueyinMapper(CONFIG_PATH)

    def test_pianyin_and_yinyuan_share_category_axis(self):
        self.assertEqual(YueyinPianyin("a", "4").category, YinyuanCategory.YUEYIN)
        self.assertEqual(ZaoyinPianyin("p").category, YinyuanCategory.ZAOYIN)
        self.assertEqual(YueyinYinyuan("a", "4").category, YinyuanCategory.YUEYIN)
        self.assertEqual(ClearZaoyin("p").category, YinyuanCategory.ZAOYIN)
        self.assertEqual(VoicedZaoyin("m").category, YinyuanCategory.ZAOYIN)

    def test_legacy_names_are_only_compatibility_aliases(self):
        self.assertIs(PitchedPianyin, YueyinPianyin)
        self.assertIs(UnpitchedPianyin, ZaoyinPianyin)

    def test_registry_id_prefixes_match_category_axis(self):
        with ZAOYIN_REGISTRY_PATH.open(encoding="utf-8") as file:
            zaoyin_entries = json.load(file)["entries"].values()
        with YUEYIN_REGISTRY_PATH.open(encoding="utf-8") as file:
            yueyin_entries = json.load(file)["entries"].values()

        self.assertTrue(all(entry["yinyuan_id"].startswith("N") for entry in zaoyin_entries))
        self.assertTrue(all(entry["yinyuan_id"].startswith("M") for entry in yueyin_entries))

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
        yueyin = YueyinYinyuan.from_pianyin(YueyinPianyin("a", "4"))
        self.assertEqual(yueyin.quality, "a")
        self.assertEqual(yueyin.pitch, "4")

        with self.assertRaises(ValueError):
            YueyinYinyuan.from_pianyin(cast(YueyinPianyin, ZaoyinPianyin("p")))

        with self.assertRaises(ValueError):
            YueyinYinyuan.from_pianyin(
                cast(YueyinPianyin, ZaoyinPianyin("m", pitch="3"))
            )


if __name__ == "__main__":
    unittest.main()
