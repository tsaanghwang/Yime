import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from yueyin_yinyuan import YueyinYinyuan

def load_and_validate_input(input_path: Path) -> dict:
    """加载并验证输入数据

    Args:
        input_path: 输入文件路径

    Returns:
        解析后的字典数据

    Raises:
        RuntimeError: 当数据加载失败时抛出
    """
    try:
        with open(input_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        raise RuntimeError(f"无法加载输入数据: {str(e)}")

def convert_pitch_style(input_data: dict, yueyin: YueyinYinyuan) -> dict:
    """转换音高样式

    Args:
        input_data: 输入数据字典
        yueyin: YueyinYinyuan实例

    Returns:
        转换后的数据字典
    """
    converted_data = {
        "ganyin_type": {
            key: {"呼音": key, "主音": key, "末音": key}
            for key in input_data.keys()
        }
    }

    symbol_data = yueyin._change_pitch_style(converted_data)

    result = {}
    for ganyin_type, ganyin_dict in symbol_data.items():
        for key, value in ganyin_dict.items():
            new_key = value["呼音"]
            if key in input_data:
                result[new_key] = input_data[key]
            else:
                print(f"警告：key '{key}' 不在输入数据中，已跳过。")
    return result

def main():
    # 获取当前脚本所在目录
    script_dir = Path(__file__).parent

    # 输入输出文件路径（使用绝对路径）
    input_path = script_dir / 'yinyuan' / 'pitched_yinyuan_of_mid_high_median_model.json'
    output_path = script_dir / 'yinyuan' / 'yueyin_yinyuan.json'

    # 确保输出目录存在
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # 创建 YueyinYinyuan 实例
    yueyin = YueyinYinyuan(
        quality='neutral',
        pitch='4',
        duration='neutral',
        loudness='neutral',
        pitch_style='number'
    )

    try:
        # 加载并验证输入数据
        input_data = load_and_validate_input(input_path)

        # 转换音高样式
        result = convert_pitch_style(input_data, yueyin)

        # 保存结果
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

        print(f"音高风格转换完成，结果已保存到: {output_path}")

    except Exception as e:
        print(f"错误: {str(e)}")
        exit(1)

if __name__ == '__main__':
    main()