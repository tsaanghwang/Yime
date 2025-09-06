# syllable_mapping.py
import json
from pathlib import Path

class SyllableMapper:
    def __init__(self):
        self.syllable_map = {}  # 格式：{"zhao": [{"hanzi":"照","freq":100},...]}

    def load_mappings(self, map_file: Path):
        """加载预定义的音节-汉字映射表"""
        with open(map_file, 'r', encoding='utf-8') as f:
            self.syllable_map = json.load(f)

    def get_candidates(self, syllable: str) -> list:
        """获取音节对应的汉字候选列表"""
        return self.syllable_map.get(syllable, [])