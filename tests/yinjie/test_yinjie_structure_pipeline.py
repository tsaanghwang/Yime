"""音段切分与编解码链结构化结果的一致性。"""

import unittest

from syllable.analysis.ganyin_encoder import GanyinEncoder
from syllable.analysis.segment_split import SegmentSplitResult, split_ganyin_segment_label
from syllable.analysis.syllable_encoding_pipeline import SyllableEncodingPipeline
from syllable.codec.yinjie import Yinjie
from syllable.codec.yinjie_encoder import YinjieEncoder


class TestSegmentSplitResult(unittest.TestCase):
    def test_zhong1_segments(self):
        segments = SyllableEncodingPipeline.analyze_syllable_segments("zhong1")
        self.assertEqual(segments.as_tuple(), ("zh", "ong1"))
        syllable = segments.to_syllable()
        self.assertEqual(syllable.initial, "zh")
        self.assertEqual(syllable.final, "ong")
        self.assertEqual(syllable.tone, "1")
        ganyin = segments.to_ganyin()
        self.assertEqual(ganyin.final, "ong")
        self.assertEqual(ganyin.gandiao, "1")

    def test_zero_initial_segment(self):
        segments = SyllableEncodingPipeline.analyze_syllable_segments("ai1")
        self.assertIsNone(segments.to_syllable().initial)

    def test_split_ganyin_label(self):
        self.assertEqual(split_ganyin_segment_label("ong1"), ("ong", "1"))


class TestGanyinEncoderSlots(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.encoder = GanyinEncoder()

    def test_slots_match_combined(self):
        for label in ("a1", "ong1", "iao1"):
            slots = self.encoder.encode_ganyin_slots(label)
            self.assertEqual(slots.combined, self.encoder.encode_ganyin(label))
            self.assertEqual(len(slots.combined), 3)


class TestEncodeYinjieStructured(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.encoder = YinjieEncoder()

    def test_structured_matches_legacy_string(self):
        for syllable in ("ma1", "zhong1", "shui3", "xue2"):
            legacy = self.encoder.encode_single_yinjie(syllable)
            structured = self.encoder.encode_yinjie_structured(syllable)
            self.assertEqual(structured.code, legacy)
            self.assertEqual(len(structured.code), 4)

    def test_yinjie_view_aligns_with_slots(self):
        result = self.encoder.encode_yinjie_structured("zhong1")
        yinjie = result.yinjie
        self.assertIsInstance(yinjie, Yinjie)
        self.assertEqual(yinjie.shouyin, result.shouyin_yinyuan)
        self.assertEqual(yinjie.huyin, result.ganyin_slots.huyin)
        self.assertEqual(yinjie.zhuyin, result.ganyin_slots.zhuyin)
        self.assertEqual(yinjie.moyin, result.ganyin_slots.moyin)


if __name__ == "__main__":
    unittest.main()
