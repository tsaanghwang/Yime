import json

# 定义音高和音色映射对象
PITCH_MAP = {
    "˥": ["˥"],
    "˦": ["˦"],
    "˩": ["˧", "˨", "˩"]
}

QUALITY_MAP = {
    "i": ["i", "ɪ"],
    "u": ["u", "ᴜ"],
    "ʏ": ["ʏ", "y"],
    "ᴀ": ["ᴀ", "a", "æ", "ɑ"],
    "o": ["o", "ɤ", "𐞑"],
    "ᴇ": ["ᴇ", "e", "ə", "ᵊ"],
    "ʅ": ["ʅ", "ɿ"],
    "ɚ": ["ɚ"],
    "m": ["m"],
    "n": ["n"],
    "ŋ": ["ŋ"]
}

def generate_combinations(pitch_map, quality_map):
    """生成所有可能的组合键（如 i˥, u˦ 等）"""
    combinations = []
    for quality_key in quality_map.keys():
        for pitch_key in pitch_map.keys():
            combinations.append(f"{quality_key}{pitch_key}")
    return combinations

def create_yinyuan_pianyin_mapping(pitch_map, quality_map, input_file, output_file):
    """创建音元-片音映射关系"""
    # 读取输入文件
    with open(input_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    # 提取片音计数数据
    pianyin_data = data["statistics"]["片音映射"]["data"]
    
    # 生成所有可能的组合键
    all_combinations = generate_combinations(pitch_map, quality_map)
    
    # 创建映射关系
    mapping = {}
    for combo in all_combinations:
        mapping[combo] = 0
    
    # 填充实际计数值
    for phoneme, tone_counts in pianyin_data.items():
        for pianyin, count in tone_counts.items():
            # 提取音元键
            yinyuan_key = f"{phoneme}{pianyin[-1]}"
            
            # 如果该组合存在，则累加计数
            if yinyuan_key in mapping:
                mapping[yinyuan_key] += count
    
    # 创建乐音列表
    yueyin_list = list(mapping.keys())
    
    # 构建最终输出结构
    output = {
        "pitch": pitch_map,
        "quality": quality_map,
        "yinyuan_pianyin_mapping": mapping,
        "yueyin": yueyin_list
    }
    
    # 写入输出文件
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    
    print(f"音元映射文件已成功生成：{output_file}")

def main():
    try:
        # 定义输入输出文件路径
        input_file = "internal_data/pianyin_counter.json"
        output_file = "internal_data/yinyuan_pianyin_mapping.json"
        
        # 创建音元-片音映射
        create_yinyuan_pianyin_mapping(PITCH_MAP, QUALITY_MAP, input_file, output_file)
        
    except FileNotFoundError:
        print("错误：找不到输入文件")
    except json.JSONDecodeError:
        print("错误：输入文件格式不正确")
    except KeyError as e:
        print(f"错误：输入文件缺少必要字段 - {e}")
    except Exception as e:
        print(f"发生未知错误：{str(e)}")

if __name__ == "__main__":
    main()