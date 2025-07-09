import json
from collections import defaultdict

def analyze_pianyin_data():
    """分析片音数据，生成音标统计和片音映射"""
    # 读取pianyin_sequence_of_ganyin.json文件
    with open("internal_data/pianyin_sequence_of_ganyin.json", "r", encoding="utf-8") as f:
        data = json.load(f)
    
    # 初始化统计数据结构
    results = {
        "ipa_statistics": {
            "三质韵母": defaultdict(int),
            "前长韵母": defaultdict(int),
            "后长韵母": defaultdict(int),
            "单质韵母": defaultdict(int)
        },
        "pianyin_mapping": defaultdict(lambda: defaultdict(int)),
        "tone_symbols": ["˥", "˦", "˧", "˨", "˩"]  # 五个调号
    }
    
    # 遍历所有声调和韵母类型
    for tone_data in data["analysis_results"].values():
        for category in ["三质韵母", "前长韵母", "后长韵母", "单质韵母"]:
            for pianyin_list in tone_data[category]:
                for pianyin in pianyin_list:
                    # 分离音标和调号
                    ipa = pianyin[:-1]  # 去掉最后一个字符(调号)
                    tone = pianyin[-1]  # 调号
                    
                    # 统计音标出现次数
                    results["ipa_statistics"][category][ipa] += 1
                    
                    # 构建音标到片音的映射
                    results["pianyin_mapping"][ipa][pianyin] += 1
    
    # 转换defaultdict为普通dict以便JSON序列化
    results["ipa_statistics"] = {
        cat: dict(ipas) 
        for cat, ipas in results["ipa_statistics"].items()
    }
    
    # 对片音映射按调号顺序排序
    for ipa in results["pianyin_mapping"]:
        results["pianyin_mapping"][ipa] = dict(
            sorted(
                results["pianyin_mapping"][ipa].items(),
                key=lambda x: results["tone_symbols"].index(x[0][-1])
            )
        )

    return results

def derive_category_stats(ipa_statistics):
    """从音标统计数据派生分类统计"""
    category_stats = {}
    for category, ipa_counts in ipa_statistics.items():
        # 获取当前类别的所有音标
        phonetics = list(ipa_counts.keys())
        # 统计独特音标数量
        category_stats[category] = {
            "unique_phonetics": phonetics,
            "count": len(phonetics)
        }
    return category_stats

def main():
    # 执行分析
    analysis_results = analyze_pianyin_data()
    
    # 从音标统计数据派生分类统计
    category_stats = derive_category_stats(analysis_results["ipa_statistics"])
    
    # 添加描述信息
    output = {
        "description": "音标和片音统计结果",
        "statistics": {
            "音标统计": {
                "description": "分别出现在四类韵母不同的干音中的不同音标及其出现次数",
                "data": analysis_results["ipa_statistics"]
            },
            "片音映射": {
                "description": "在干音中实际存在的由每个音标与调号构成的片音及其频次",
                "data": analysis_results["pianyin_mapping"]
            },
            "分类音标统计": {
                "description": "分别出现在四类韵母中的各不相同的音标及其数量",
                "data": category_stats
            }
        }
    }
    
    # 写入结果文件
    with open("internal_data/pianyin_counter.json", "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    
    print("音标和片音统计完成，结果已保存到 internal_data/pianyin_counter.json")

if __name__ == "__main__":
    main()