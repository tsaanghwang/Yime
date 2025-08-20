import json
from collections import defaultdict

def classify_tone(tone_symbol):
    """将调号分类为高调、中调或低调"""
    if tone_symbol == "˥":
        return "high"
    elif tone_symbol == "˦":
        return "mid"
    else:  # ˧, ˨, ˩
        return "low"

def map_yinyuan_to_codepoint(pianyin_data):
    """创建音元到片音的映射关系"""
    yinyuan_mapping = defaultdict(lambda: defaultdict(int))

    for phoneme, tone_counts in pianyin_data.items():
        for pianyin, count in tone_counts.items():
            tone_symbol = pianyin[-1]  # 获取调号
            tone_category = classify_tone(tone_symbol)

            # 构建音元名称 (音标 + 分类调号)
            yinyuan = f"{phoneme}{'˥' if tone_category == 'high' else '˦' if tone_category == 'mid' else '˩'}"

            # 累加相同音元的片音计数
            yinyuan_mapping[yinyuan][pianyin] += count

    return dict(yinyuan_mapping)

def main():
    try:
        # 读取pianyin_counter.json文件
        with open("internal_data/pianyin_counter.json", "r", encoding="utf-8") as f:
            data = json.load(f)

        # 获取片音映射数据
        pianyin_data = data["statistics"]["片音映射"]["data"]

        # 创建音元映射
        yinyuan_mapping = map_yinyuan_to_codepoint(pianyin_data)

        # 构建输出数据结构
        output = {
            "description": "音元与片音映射关系",
            "tone_classification": {
                "high": "高调音元(˥)",
                "mid": "中调音元(˦)",
                "low": "低调音元(˩)"
            },
            "yinyuan_mapping": yinyuan_mapping
        }

        # 写入结果文件
        with open("internal_data/ganyin_to_yinyuan.json", "w", encoding="utf-8") as f:
            json.dump(output, f, ensure_ascii=False, indent=2)

        print("音元映射文件已成功生成：internal_data/ganyin_to_yinyuan.json")

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