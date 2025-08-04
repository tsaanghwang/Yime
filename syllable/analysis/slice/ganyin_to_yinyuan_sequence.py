"""
干音的音元表示法
功能：生成干音的音元序列
流程：读取干音与片音序列的映射数据，并将其转换为干音与音元序列的映射数据。
"""
import json
from pathlib import Path
from yueyin_yinyuan import YueyinYinyuan
from ganyin_to_pianyin_sequence import enhance_i_variants


class GanyinToYinyuanSequence:
    """将干音转换为音元序列的处理器"""

    def __init__(self):
        self.yueyin_yinyuan = YueyinYinyuan(quality="", pitch="")

    def load_ganyin_data(self, input_path: str) -> dict:
        """加载干音数据"""
        with open(input_path, 'r', encoding='utf-8', errors='strict') as f:
            return json.load(f)

    def save_yinyuan_data(self, output_path: str, data: dict):
        """保存音元数据"""
        def ensure_unicode(obj):
            if isinstance(obj, str):
                return obj.encode('utf-8').decode('utf-8')
            elif isinstance(obj, dict):
                return {k: ensure_unicode(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [ensure_unicode(v) for v in obj]
            return obj

        with open(output_path, 'w', encoding='utf-8', errors='strict') as f:
            json.dump(ensure_unicode(data), f,
                      ensure_ascii=False,
                      indent=2,
                      separators=(',', ': '))

    def convert_pianyin_to_yinyuan(self, pianyin: str) -> str:
        """将片音转换为音元表示"""
        if not pianyin:
            return ""

        # 处理多值情况（用斜杠分隔）
        if "/" in pianyin:
            pianyin = pianyin.split("/")[0]

        quality = pianyin[:-1] if len(pianyin) > 1 else pianyin
        pitch = pianyin[-1] if len(pianyin) > 1 else ""

        processed = self.yueyin_yinyuan._process_dynamic_tonal_elements_model(
            {"temp": (quality, pitch)}
        )

        if processed:
            return next(iter(processed.keys()))
        return ""

    def process_ganyin(self, ganyin_data: dict) -> dict:
        """处理干音数据"""
        result = {}

        for ganyin_type, ganyin_list in ganyin_data.items():
            result[ganyin_type] = {}

            for ganyin_name, parts in ganyin_list.items():
                result[ganyin_type][ganyin_name] = {
                    "呼音": self.convert_pianyin_to_yinyuan(parts.get("呼音", "")),
                    "主音": self.convert_pianyin_to_yinyuan(parts.get("主音", "")),
                    "末音": self.convert_pianyin_to_yinyuan(parts.get("末音", ""))
                }

        return result

    def run(self, input_path: str, output_path: str):
        """执行转换流程"""
        ganyin_data = self.load_ganyin_data(input_path)
        yinyuan_data = self.process_ganyin(ganyin_data)

        # 只对 single quality ganyin 调用 enhance_i_variants
        if "single quality ganyin" in yinyuan_data:
            yinyuan_data["single quality ganyin"] = enhance_i_variants(
                yinyuan_data["single quality ganyin"]
            )

        self.save_yinyuan_data(output_path, yinyuan_data)

        # 可选：验证处理结果
        for category, items in yinyuan_data.items():
            for key, value in items.items():
                if key.startswith("_i"):
                    print(f"验证 {key}:")
                    print(json.dumps(value, ensure_ascii=False, indent=2))

        return yinyuan_data


if __name__ == "__main__":
    converter = GanyinToYinyuanSequence()
    input_file = Path(__file__).parent / "ganyin_to_pianyin_sequence.json"
    output_file = Path(__file__).parent / "ganyin_to_yinyuan_sequence.json"
    result = converter.run(str(input_file), str(output_file))
    print(f"转换完成，结果已保存到 {output_file}")
