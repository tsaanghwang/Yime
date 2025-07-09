"""
韵母音标components统计分析工具
统计所有韵母音标的基本构成components及其出现频率
"""

import json
import os
from typing import Dict, List, Tuple, Optional
from collections import defaultdict
from pathlib import Path

class FinalsComponentsAnalyzer:
    def __init__(self):
        self.input_file = "external_data/finals_IPA_mapping.json"
        self.output_file = "internal_data/final_components.json"
        self.custom_order_file = "internal_data/custom_component_order.json"
        self.preset_order_file = "config/sort_rules.json"
        self.preset_order_backup = "config/sort_rules.backup.json"
        self.components_stats = defaultdict(int)
        # 从配置文件加载预设排序顺序
        self.preset_order = self.load_preset_order()
        # 当前使用的排序顺序(默认为预设顺序)
        self.current_order = self.preset_order.copy()
        # 复用FinalsClassifier中的组合标记定义
        self.combining_marks = {
            '\u030D', '\u0329', '\u0308', '\u0302', '\u0300',
            '\u0301', '\u0304', '\u0306', '\u030C', '\u030B',
            '\u0303', '\u0325', '\u032F'
        }
    
    def load_data(self) -> Dict[str, str]:
        """加载音标-拼音映射数据"""
        with open(self.input_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def extract_components(self, ipa: str) -> List[str]:
        """
        提取音标中的基本components(考虑组合字符)
        返回: 包含所有基本components的列表
        """
        # 预处理：去除特定音标的成音节性符号
        normalized_ipa = ipa.replace("\u0329", "")
        
        components = []
        i = 0
        n = len(normalized_ipa)
        
        while i < n:
            # 处理组合标记
            if i > 0 and normalized_ipa[i] in self.combining_marks:
                # 将组合标记附加到前一个component
                if components:
                    components[-1] += normalized_ipa[i]
                i += 1
                continue
                
            # 添加新的component
            components.append(normalized_ipa[i])
            i += 1
            
        return components
    
    def analyze_components(self) -> None:
        """分析所有音标的components"""
        data = self.load_data()
        
        for ipa in data.keys():
            components = self.extract_components(ipa)
            for comp in components:
                self.components_stats[comp] += 1
    
    def get_sorted_results(self, sort_by: str = "frequency") -> List[Tuple[str, int]]:
        """
        获取排序后的统计结果
        sort_by: 
            "frequency" - 按频率降序
            "component" - 按component升序(Unicode顺序)
            "preset" - 按预设顺序排序
            "custom" - 按自定义顺序排序
        """
        if sort_by == "frequency":
            return sorted(self.components_stats.items(), 
                         key=lambda x: x[1], reverse=True)
        elif sort_by == "component":
            return sorted(self.components_stats.items(), 
                         key=lambda x: x[0])
        elif sort_by == "preset":
            # 按预设顺序排序，不在预设中的component放在最后
            return sorted(self.components_stats.items(),
                         key=lambda x: self.preset_order.index(x[0]) 
                         if x[0] in self.preset_order else len(self.preset_order))
        elif sort_by == "custom":
            # 按自定义顺序排序，不在自定义顺序中的component放在最后
            self.load_custom_order()
            return sorted(self.components_stats.items(),
                         key=lambda x: self.current_order.index(x[0]) 
                         if x[0] in self.current_order else len(self.current_order))
        else:
            raise ValueError("Invalid sort_by value. Use 'frequency', 'component', 'preset' or 'custom'")
    
    def save_results(self, sort_by: str = "frequency") -> None:
        """保存统计结果到JSON文件"""
        sorted_results = self.get_sorted_results(sort_by)
        
        result = {
            "components": [comp for comp, _ in sorted_results],
            "counts": [count for _, count in sorted_results],
            "total_unique": len(sorted_results),
            "total_occurrences": sum(count for _, count in sorted_results),
            "sort_method": sort_by,
            "order_used": self.current_order if sort_by in ["preset", "custom"] else None
        }
        
        # 确保输出目录存在
        os.makedirs(os.path.dirname(self.output_file), exist_ok=True)
        
        with open(self.output_file, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
    
    def validate_components(self) -> Tuple[List[str], List[str]]:
        """验证统计结果与预设音标数组的一致性
        返回: (missing_components, extra_components)
        """
        actual_components = list(self.components_stats.keys())
        
        # 找出缺失的预设音标
        missing = [c for c in self.preset_order if c not in actual_components]
        # 找出多余的音标
        extra = [c for c in actual_components if c not in self.preset_order]
        
        return missing, extra
    
    def print_summary(self) -> None:
        """打印统计摘要"""
        sorted_by_freq = self.get_sorted_results("frequency")
        
        print("\n韵母音标components统计报告:")
        print("=" * 50)
        print(f"共发现 {len(sorted_by_freq)} 种不同的音标components")
        print(f"总出现次数: {sum(count for _, count in sorted_by_freq)}")
        print("\n出现频率最高的10个components:")
        for comp, count in sorted_by_freq[:10]:
            print(f"  {comp}: {count}次")
        
        # 添加验证结果
        missing, extra = self.validate_components()
        if missing or extra:
            print("\n[警告] 音标验证不一致:")
            if missing:
                print(f"  缺失的预设音标: {', '.join(missing)}")
            if extra:
                print(f"  多余的音标: {', '.join(extra)}")
            print("  请检查数据源或更新预设音标数组")
        else:
            print("\n[验证通过] 所有音标与预设数组一致")
        
        print("=" * 50)
    
    def load_preset_order(self) -> List[str]:
        """从配置文件加载预设排序顺序"""
        try:
            # 先尝试读取主文件
            with open(self.preset_order_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
                return data["preset_order"]
        except (FileNotFoundError, json.JSONDecodeError):
            # 如果主文件有问题，尝试读取备份文件
            try:
                with open(self.preset_order_backup, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    return data["preset_order"]
            except (FileNotFoundError, json.JSONDecodeError):
                # 如果都没有，返回默认顺序
                return [
                    "i", "ɪ", "u", "ᴜ", "ʏ", "y", "ᴀ", "a", "æ", "ɑ", 
                    "o", "ɤ", "𐞑", "ᴇ", "e", "ə", "ᵊ", "ʅ", "ɿ", "ɚ",
                    "m", "n", "ŋ"
                ]

    def load_custom_order(self) -> Optional[List[str]]:
        """从文件加载自定义排序顺序"""
        if Path(self.custom_order_file).exists():
            with open(self.custom_order_file, 'r', encoding='utf-8') as f:
                self.current_order = json.load(f)
            return self.current_order
        return None
    
    def save_custom_order(self, custom_order: List[str]) -> None:
        """保存自定义排序顺序到文件"""
        # 先写入临时文件
        temp_file = self.custom_order_file + ".tmp"
        os.makedirs(os.path.dirname(temp_file), exist_ok=True)
        with open(temp_file, 'w', encoding='utf-8') as f:
            json.dump(custom_order, f, ensure_ascii=False, indent=2)
        
        # 创建备份
        if os.path.exists(self.custom_order_file):
            os.replace(self.custom_order_file, self.custom_order_file + ".bak")
        
        # 原子性替换
        os.replace(temp_file, self.custom_order_file)
        self.current_order = custom_order
        
        # 同时更新预设排序规则文件
        self._update_preset_order(custom_order)
    
    def _update_preset_order(self, new_order: List[str]) -> None:
        """更新预设排序规则文件"""
        # 先创建备份
        if os.path.exists(self.preset_order_file):
            os.replace(self.preset_order_file, self.preset_order_backup)
        
        # 写入临时文件
        temp_file = self.preset_order_file + ".tmp"
        with open(temp_file, 'w', encoding='utf-8') as f:
            json.dump({"preset_order": new_order}, f, ensure_ascii=False, indent=2)
        
        # 原子性替换
        os.replace(temp_file, self.preset_order_file)
    
    def run(self, sort_by: str = "frequency", custom_order: List[str] = None) -> None:
        """执行完整分析流程
        Args:
            sort_by: 排序方式 ("frequency", "component", "preset", "custom")
            custom_order: 可选的自定义排序顺序列表
        """
        self.analyze_components()
        
        if custom_order is not None:
            self.save_custom_order(custom_order)
        
        self.save_results(sort_by)
        self.print_summary()

if __name__ == "__main__":
    analyzer = FinalsComponentsAnalyzer()
    analyzer.run()