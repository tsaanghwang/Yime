import json
from pathlib import Path
from typing import Dict, Any
from zaoyin_yinyuan import NoiseYinyuan

def map_shouyin_to_codepoint(shouyin_list):
    """从音元符号列表创建音元到编码点的映射

    Args:
        shouyin_list: 音元符号列表(如从zaoyin_yinyuan.json的keys获取)

    Returns:
        返回一个字典，key是音元符号(如"ɪ́")，value是对应的编码点字符
    """
    start_codepoint = 0x100000  # 从补充私用区开始
    return {yinyuan: chr(start_codepoint + i)
           for i, yinyuan in enumerate(shouyin_list)}

class ShouyinEncoder:
    """首音编码处理器，整合音元映射和音元序列生成功能"""

    def __init__(self):
        self.zaoyin_yinyuan = NoiseYinyuan(quality="")

    def load_shouyin_data(self, input_path: Path) -> Dict[str, Any]:
        """加载首音数据"""
        with input_path.open('r', encoding='utf-8') as f:
            return json.load(f)

    def save_yinyuan_data(self, output_path: Path, data: Dict[str, Any]) -> None:
        """保存音元数据"""
        with output_path.open('w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def process_shouyin(self, shouyin_data: Dict[str, Any]) -> Dict[str, Any]:
        """处理首音数据生成音元序列"""
        # 情况1：处理带有codes字段的结构
        if "codes" in shouyin_data:
            codes = shouyin_data.get("codes", {})
            return {"首音": list(codes.keys())}

        # 情况2：处理带有shouyin字段的结构
        elif "shouyin" in shouyin_data:
            shouyin = shouyin_data.get("shouyin", {})
            return {"首音": list(shouyin.keys())}

        # 其他情况返回空字典
        return {}

    def generate_encoding_files(self):
            """生成所有编码相关文件"""
            base_dir = Path(__file__).parent

            # 1. 生成音元编码映射 - 修改为使用简化版文件
            zaoyin_yinyuan_path = base_dir / "yinyuan" / "zaoyin_yinyuan.json"
            with open(zaoyin_yinyuan_path, "r", encoding="utf-8") as f:
                zaoyin_yinyuan_data = json.load(f)

            zaoyin = list(zaoyin_yinyuan_data.get("shouyin", {}).keys())
            zaoyin = map_shouyin_to_codepoint(zaoyin)

            # 简化输出结构，只保留编码映射部分
            encoding_data = {
                "zaoyin": zaoyin
            }

            encoding_path = base_dir / "yinyuan" / "yinyuan.json"

            # 恢复文件追加逻辑 - 处理空文件或不存在的情况
            existing_data = {}
            if encoding_path.exists():
                try:
                    with open(encoding_path, "r", encoding="utf-8") as f:
                        content = f.read()
                        if content.strip():  # 检查文件是否非空
                            existing_data = json.loads(content)
                except json.JSONDecodeError:
                    # 如果文件内容不是有效的JSON，创建新文件
                    existing_data = {}

            # 更新数据
            existing_data.update(encoding_data)
            encoding_data = existing_data

            self.save_yinyuan_data(encoding_path, encoding_data)

            # 2. 生成首音符号映射
            input_file = base_dir / 'yinyuan' / 'zaoyin_yinyuan.json'
            output_file = base_dir / 'yinyuan' / 'shouyin_yinyuan.json'

            shouyin_data = self.load_shouyin_data(input_file)
            yinyuan_data = self.process_shouyin(shouyin_data)

            # 获取首音列表并映射为编码点
            shouyin_list = yinyuan_data.get("首音", [])
            codepoint_mapping = map_shouyin_to_codepoint(shouyin_list)

            # 保存结果
            result_data = {
                "首音": {shouyin: codepoint for shouyin, codepoint in codepoint_mapping.items()}
            }
            self.save_yinyuan_data(output_file, result_data)

            print(f"  首音编码字典:")
            print(f"- 噪音码元映射: {encoding_path}")
            print(f"- 首音码元映射: {output_file}")

def main():
    encoder = ShouyinEncoder()
    encoder.generate_encoding_files()

if __name__ == "__main__":
    main()