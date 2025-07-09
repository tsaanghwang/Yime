"""
Final Tone Marking System - Based on New Classification Framework
Features:
1. Load classified_finals.json data
2. Apply tone marking rules by final category
3. Display tone marking results
"""

import json
from typing import Dict, List

class FinalsToneMarker:
    def __init__(self):
        self.classified_finals = self.load_classified_finals()
        self.tone_markers = {
            1: "̄",  # 第一声
            2: "́",  # 第二声
            3: "̌",  # 第三声
            4: "̀"   # 第四声
        }

    def load_classified_finals(self) -> Dict[str, List[Dict[str, str]]]:
        """Load classified finals data (加载韵母分类数据)"""
        with open("internal_data/classified_finals.json", "r", encoding="utf-8") as f:
            return json.load(f)

    def mark_single_quality(self, pinyin: str, tone: int) -> str:
        """
        Single-quality final tone marking rules (单质韵母标调规则):
        1. For two-character single-quality finals "er" and "ng", mark tone on first character
        2. Other single-quality finals mark tone directly on the final symbol
        """
        if pinyin in ("er", "ng"):
            return pinyin[0] + self.tone_markers[tone] + pinyin[1:]
        return pinyin + self.tone_markers[tone]

    def mark_post_long(self, pinyin: str, tone: int) -> str:
        """
        Post-long final tone marking rules (后长韵母标调规则):
        Mark tone on the "a/o/e" that serves as the final nucleus (韵腹)
        """
        # 查找韵腹位置
        for vowel in ["a", "o", "e"]:
            pos = pinyin.rfind(vowel)  # 从后往前找最后一个韵腹
            if pos != -1:
                return pinyin[:pos] + pinyin[pos] + self.tone_markers[tone] + pinyin[pos+1:]
        return pinyin + self.tone_markers[tone]  # 默认加在末尾

    def mark_pre_long(self, pinyin: str, tone: int) -> str:
        """
        Pre-long final tone marking rules (前长韵母标调规则):
        Mark tone on the first character that serves as the final nucleus (韵腹)
        """
        # 查找韵腹起始位置
        vowels = "aeiouü"
        for i, c in enumerate(pinyin):
            if c in vowels:
                return pinyin[:i] + pinyin[i] + self.tone_markers[tone] + pinyin[i+1:]
        return pinyin + self.tone_markers[tone]  # 默认加在末尾

    def mark_triple_quality(self, pinyin: str, tone: int) -> str:
        """
        Triple-quality final tone marking rules (三质韵母标调规则):
        1. For finals with "a/o/e", mark tone on "a/o/e"
        2. For final "iu", mark tone on the following "u"
        3. For final "ui", mark tone on the following "i"
        4. For finals "in/ing/un/", mark tone on the preceding "i/u"
        
        Note: Add additional rules for any exceptions
        """
        # 规则1：对有"a/o/e"的韵母在"a/o/e"上标调
        for vowel in ["a", "o", "e"]:
            pos = pinyin.find(vowel)
            if pos != -1:
                return pinyin[:pos] + pinyin[pos] + self.tone_markers[tone] + pinyin[pos+1:]
        
        # 规则2：对韵母"iu"在后面的"u"上标调
        if pinyin == "iu":
            return "i" + "u" + self.tone_markers[tone]
        
        # 规则3：对韵母"ui"在后面的"i"上标调
        if pinyin == "ui":
            return "u" + "i" + self.tone_markers[tone]
        
        # 规则4：对韵母"in/ing/un/"在前面的"i/u"上标调
        if pinyin in ["in", "ing", "un"]:
            return pinyin[0] + self.tone_markers[tone] + pinyin[1:]
        
        # 默认情况：在中间位置加调号
        mid = len(pinyin) // 2
        return pinyin[:mid] + self.tone_markers[tone] + pinyin[mid:]

    def generate_all_tones(self):
        """Generate tone marked results for all finals (为所有韵母生成四声标调结果)"""
        results = {}
        
        # 处理单质韵母
        for final in self.classified_finals["单质韵母"]:
            pinyin = final["拼音"]
            results[pinyin] = {
                tone: self.mark_single_quality(pinyin, tone) 
                for tone in range(1, 5)
            }
        
        # 处理后长韵母
        for final in self.classified_finals["后长韵母"]:
            pinyin = final["拼音"]
            results[pinyin] = {
                tone: self.mark_post_long(pinyin, tone) 
                for tone in range(1, 5)
            }
        
        # 处理前长韵母
        for final in self.classified_finals["前长韵母"]:
            pinyin = final["拼音"]
            results[pinyin] = {
                tone: self.mark_pre_long(pinyin, tone) 
                for tone in range(1, 5)
            }
        
        # 处理三质韵母
        for final in self.classified_finals["三质韵母"]:
            pinyin = final["拼音"]
            results[pinyin] = {
                tone: self.mark_triple_quality(pinyin, tone) 
                for tone in range(1, 5)
            }
        
        return results

    def print_results(self, results: Dict[str, Dict[int, str]]):
        """Print tone marking results (打印标调结果)"""
        print("\n韵母标调结果:")
        print("=" * 60)
        for pinyin, tones in results.items():
            print(f"{pinyin}:")
            for tone, marked in tones.items():
                print(f"  第{tone}声: {marked}")
        print("=" * 60)

    def save_results(self, results: Dict[str, Dict[int, str]]):
        """Save tone marking results to JSON file (保存标调结果到JSON文件)"""
        import os
        os.makedirs("data_json_files", exist_ok=True)
        with open("internal_data/marked_finals.json", "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)

    def run(self):
        """Execute tone marking process (执行标调流程)"""
        results = self.generate_all_tones()
        self.print_results(results)
        self.save_results(results)
        return results

if __name__ == "__main__":
    marker = FinalsToneMarker()
    marker.run()