#!/usr/bin/env python3
"""
干音分析器运行脚本
执行干音分析并打印结果摘要
"""

from tools.ganyin_analyzer import GanyinAnalyzer
import json

def print_analysis_summary(results: dict):
    """打印分析结果摘要"""
    print("\n干音分析结果摘要:")
    print("=" * 50)
    
    for tone, tone_data in results["analysis_results"].items():
        print(f"\n{tone.replace('_', ' ').title()} 分析结果:")
        print("-" * 40)
        
        for final_type, finals in tone_data.items():
            print(f"\n{final_type} 类韵母:")
            for i, final in enumerate(finals[:3]):  # 只显示前3个示例
                print(f"  {i+1}. {'-'.join(final)}")
            if len(finals) > 3:
                print(f"  ...(共 {len(finals)} 个)")

if __name__ == "__main__":
    print("开始干音分析...")
    analyzer = GanyinAnalyzer()
    
    try:
        with open("internal_data/classified_finals.json", "r", encoding="utf-8") as f:
            finals_data = json.load(f)
        
        # 只分析三质韵母
        if "三质韵母" not in finals_data:
            raise ValueError("classified_finals.json 中缺少三质韵母数据")
            
        results = analyzer.analyze_all_finals({
            "三质韵母": finals_data["三质韵母"]
        })
        
        with open("internal_data/ganyin_analyzer.json", "w", encoding="utf-8") as f:
            json.dump({
                "description": "干音分析结果",
                "encoding_rules": analyzer.tone_patterns,
                "analysis_results": results
            }, f, ensure_ascii=False, indent=2)
        
        print_analysis_summary({
            "analysis_results": results,
            "encoding_rules": analyzer.tone_patterns
        })
        print("\n分析完成! 完整结果已保存到 internal_data/ganyin_analyzer.json")
    
    except FileNotFoundError as e:
        print(f"错误: 缺少必要数据文件 - {e}")
    except Exception as e:
        print(f"分析过程中发生错误: {e}")