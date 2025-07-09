"""
韵母分类方法
实现三步分类：
1. 全类韵母的单质/复合韵母分类
2. 复合韵母的二合/三合韵母分类
3. 二合韵母的前长/后长韵母分类
分类结果：韵母分成单质韵母、后长韵母、前长韵母和三质韵母四类。
"""

import json
from typing import Dict, List, Tuple, Union

class FinalsClassifier:
    def __init__(self, input_file: str, output_file: str):
        self.input_file = input_file
        self.output_file = output_file
        self.data: Dict[str, str] = {}
        self.classified: Dict[str, List[Dict[str, str]]] = {
            "单质韵母": [],
            "后长韵母": [],
            "前长韵母": [],
            "三质韵母": []
        }
        # 定义组合标记集合
        self.combining_marks = {
            '\u030D',  # ̎ COMBINING VERTICAL LINE ABOVE
            '\u0329',  # ̩ COMBINING VERTICAL LINE BELOW
            '\u0308',  # ̈ COMBINING DIAERESIS
            '\u0302',  # ̂ COMBINING CIRCUMFLEX ACCENT
            '\u0300',  # ̀ COMBINING GRAVE ACCENT
            '\u0301',  # ́ COMBINING ACUTE ACCENT
            '\u0304',  # ̄ COMBINING MACRON
            '\u0306',  # ̆ COMBINING BREVE
            '\u030C',  # ̌ COMBINING CARON
            '\u030B',  # ̋ COMBINING DOUBLE ACUTE ACCENT
            '\u0303',  # ̃ COMBINING TILDE
            '\u0325',  # ̥ COMBINING RING BELOW
            '\u032F',  # ̯ COMBINING INVERTED BREVE BELOW
        }
    
    def load_data(self) -> None:
        """加载音标-拼音映射数据"""
        with open(self.input_file, 'r', encoding='utf-8') as f:
            self.data = json.load(f)
    
    def count_symbols(self, ipa: str) -> int:
        """
        计算音标字符个数(考虑组合字符)
        例如: 
        - "n̍" (U+006E LATIN SMALL LETTER N + U+030D COMBINING VERTICAL LINE ABOVE) 算1个
        - "ŋ̩" (U+014B LATIN SMALL LETTER ENG + U+0329 COMBINING VERTICAL LINE BELOW) 算1个
        
        实现逻辑:
        1. 使用Unicode NFC规范化处理组合字符
        2. 识别常见的音标组合标记(如U+030D, U+0329等)
        3. 确保组合字符不被错误拆分为多个单位
        """
        if not ipa:
            return 0
            
        count = 0
        i = 0
        n = len(ipa)
        
        while i < n:
            # 跳过组合标记
            if i > 0 and ipa[i] in self.combining_marks:
                i += 1
                continue
                
            count += 1
            i += 1
            
        return count
    
    def is_back_long(self, ipa: str) -> bool:
        """
        判断是否为后长韵母
        规则: 
        1. 必须是二合音质韵母(已由调用方保证)
        2. 前一个音符是"i","u"或"ʏ"
        3. 后一音符是"ᴀ","o"或"ᴇ"
        """
        if len(ipa) < 2:
            return False
            
        # 扩展的前音符集合
        first_chars = {'i', 'u', 'ʏ', 'ɪ', 'ʊ'}  
        # 扩展的后音符集合
        second_chars = {'ᴀ', 'o', 'ᴇ', 'ɑ', 'ɔ', 'ɛ', 'œ'}
        
        # 获取第一个实际音标(处理组合字符)
        first_symbol = []
        i = 0
        while i < len(ipa):
            if ipa[i] in self.combining_marks:
                i += 1
                continue
            first_symbol.append(ipa[i])
            i += 1
            break
            
        if not first_symbol:
            return False
            
        # 获取第二个实际音标(跳过中间的组合标记)
        while i < len(ipa) and ipa[i] in self.combining_marks:
            i += 1
            
        if i >= len(ipa):
            return False
            
        second_symbol = ipa[i]
        
        return (''.join(first_symbol) in first_chars and 
                second_symbol in second_chars)
    
    def normalize_pinyin(self, pinyin: str) -> str:
        """规范化拼音表示：将ɑ(U+0251)改为a，ɡ(U+0261)改为g"""
        return pinyin.replace('ɑ', 'a').replace('ɡ', 'g')

    def classify(self) -> None:
        """执行三步分类流程"""
        for ipa, pinyin in self.data.items():
            # 规范化拼音表示
            normalized_pinyin = self.normalize_pinyin(pinyin)
            entry = {
                "音标": ipa,
                "拼音": normalized_pinyin
            }
            
            # 第一步: 单质/复合分类
            symbol_count = self.count_symbols(ipa)
            if symbol_count == 1:
                self.classified["单质韵母"].append(entry)
                continue
                
            # 第二步: 二合/三合分类
            if symbol_count == 2:
                # 第三步: 前长/后长分类
                if self.is_back_long(ipa):
                    self.classified["后长韵母"].append(entry)
                else:
                    self.classified["前长韵母"].append(entry)
            elif symbol_count == 3:
                self.classified["三质韵母"].append(entry)
    
    def save_results(self) -> None:
        """保存分类结果到JSON文件"""
        with open(self.output_file, 'w', encoding='utf-8') as f:
            json.dump(self.classified, f, ensure_ascii=False, indent=2)
    
    def generate_stats(self) -> Dict[str, Union[int, List[str]]]:
        """
        生成所有韵母的音标统计信息
        返回: {
            "total_count": N,  # 所有韵母总数
            "unique_phonetics": [音标1, 音标2, ...]  # 所有韵母中出现的不同音标
        }
        """
        # 收集所有韵母的音标
        all_phonetics = []
        for category_items in self.classified.values():
            for item in category_items:
                all_phonetics.append(item["音标"])
        
        # 获取唯一音标并排序
        unique_phonetics = sorted(list(set(all_phonetics)))
        
        return {
            "total_count": len(all_phonetics),
            "unique_phonetics": unique_phonetics
        }
    
    def print_stats(self) -> None:
        """打印韵母音标统计报告"""
        stats = self.generate_stats()
        print("\n韵母音标统计报告:")
        print("="*40)
        print(f"韵母总数: {stats['total_count']}个")
        print(f"不同音标: {len(stats['unique_phonetics'])}种")
        print("所有音标:")
        print(", ".join(stats['unique_phonetics']))
        print("="*40)
    
    def run(self) -> None:
        """执行完整分类流程"""
        self.load_data()
        self.classify()
        self.save_results()
        self.print_stats()

if __name__ == "__main__":
    # 确保输出目录存在
    import os
    os.makedirs("../internal_data", exist_ok=True)
    
    # 配置输入输出文件路径
    classifier = FinalsClassifier(
        input_file="external_data/finals_IPA_mapping.json",
        output_file="internal_data/classified_finals.json"
    )
    classifier.run()