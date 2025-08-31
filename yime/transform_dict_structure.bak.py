import json
from pathlib import Path

def transform_dict(input_path, output_path):
    """
    将 code_pinyin.json 转换为目标字典结构，使用符号序列作为主键

    新结构示例：
    {
        "音元符号": {
            "􀀕􀀩􀀩􀀩": {  # 符号序列作为键
                "数字标调": "a1",
                "调号标调": "ā",
                "注音符号": "ㄚ",
                "反向映射": {
                    "a1": {"调号": "ā", "注音": "ㄚ"},
                    "ā": {"数字": "a1", "注音": "ㄚ"},
                    "ㄚ": {"数字": "a1", "调号": "ā"}
                }
            }
        }
    }
    """
    try:
        # 读取输入文件
        with open(input_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        result = {"音元符号": {}}

        for symbol, pinyin in data.items():
            # 创建条目
            entry = {
                "数字标调": pinyin,
                "调号标调": "",  # 需要外部数据补充
                "注音符号": "",   # 需要外部数据补充
                "反向映射": {
                    pinyin: {"调号": "", "注音": ""},  # 需要补充
                    "diaohao": {"数字": pinyin, "注音": ""},  # 调号位置
                    "shuma": {"数字": pinyin, "调号": ""}   # 注音位置
                }
            }

            result["音元符号"][symbol] = entry  # 使用符号序列作为键

        # 确保输出目录存在
        output_dir = Path(output_path).parent
        output_dir.mkdir(parents=True, exist_ok=True)

        # 写入输出文件
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

        return True

    except Exception as e:
        print(f"转换出错: {str(e)}")
        return False

if __name__ == "__main__":
    input_file = Path("code_pinyin.json")
    output_file = Path("yinjie_mapping.json")

    success = transform_dict(input_file, output_file)

    if success:
        print(f"转换成功！结果已保存到: {output_file}")
        print("注意：调号标调和注音符号字段需要后续补充")
    else:
        print("转换失败，请检查输入文件是否存在且格式正确")