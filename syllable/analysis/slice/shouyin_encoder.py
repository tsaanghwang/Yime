import json
from typing import Dict, Any
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
from syllable.analysis.slice.zaoyin_yinyuan import NoiseYinyuan

class ShouyinEncoder:
    """首音编码处理器，整合音元映射和音元序列生成功能"""

    # 类常量
    SUBDIR = "yinyuan"
    ZAOYIN_SOURCE_FILENAME = "zaoyin_yinyuan_enhanced.json"
    ZAOYIN_COMPAT_FILENAME = "zaoyin_yinyuan.json"
    SHOUYIN_FILENAME = "shouyin_codepoint.json"
    YINYUAN_FILENAME = "yinyuan_codepoint.json"

    def __init__(self, data_path: Path | None = None):
        self.zaoyin_yinyuan = NoiseYinyuan(quality="")
        self.shouyin_data = None
        self.module_dir = Path(__file__).parent
        self.default_data_path = self.module_dir / self.SUBDIR / self.ZAOYIN_SOURCE_FILENAME
        if data_path:
            self.load_shouyin_data(data_path)

    def load_shouyin_data(self, input_path: Path) -> Dict[str, Any]:
        """加载首音数据

        Args:
            input_path: 输入文件路径

        Returns:
            返回加载的首音数据字典
        """
        with input_path.open('r', encoding='utf-8') as f:
            self.shouyin_data = json.load(f)
        return self.shouyin_data

    def _load_codepoint_mapping(self):
        """私有方法加载码位映射表"""
        map_path = self.module_dir / self.SUBDIR / self.SHOUYIN_FILENAME
        with open(map_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            self._codepoint_map = data["首音"]

    def map_shouyin_to_codepoint(self, shouyin: str) -> str:
        """将首音映射到码位"""
        if not hasattr(self, '_codepoint_map'):
            self._load_codepoint_mapping()
        return self._codepoint_map.get(shouyin, '')  # 现在直接访问映射字典

    def encode_shouyin(self, shouyin: str) -> str:
        """外部调用接口：将单个首音编码为码位字符

        Args:
            shouyin: 要编码的首音字符串

        Returns:
            返回对应的码位字符，如果找不到则返回空字符串
        """
        # 确保码位映射表已加载
        if not hasattr(self, '_codepoint_map'):
            self._load_codepoint_mapping()

        # 直接调用内部映射方法
        return self.map_shouyin_to_codepoint(shouyin)

    def save_yinyuan_data(self, output_path: Path, data: Dict[str, Any]) -> None:
        """保存音元数据"""
        with output_path.open('w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def process_shouyin(self, shouyin_data: Dict[str, Any]) -> Dict[str, Any]:
        """处理首音真源，提取运行时映射和兼容数据。"""
        entries = shouyin_data.get("entries", {})
        if not entries:
            return {}

        runtime_map = {}
        compat_map = {}
        semantic_codes = {}

        for shouyin, entry in entries.items():
            runtime_char = entry.get("runtime_char", "")
            if not runtime_char:
                raise ValueError(f"首音 `{shouyin}` 缺少 runtime_char")

            semantic_code = entry.get("semantic_code", "")
            if not semantic_code:
                raise ValueError(f"首音 `{shouyin}` 缺少 semantic_code")

            runtime_map[shouyin] = runtime_char
            compat_map[shouyin] = entry.get("ipa", [])
            semantic_codes[shouyin] = semantic_code

        return {
            "首音": list(entries.keys()),
            "首音映射": runtime_map,
            "zaoyin": runtime_map,
            "shouyin": compat_map,
            "语义码": semantic_codes,
        }

    def build_explicit_runtime_mapping(self, shouyin_data: Dict[str, Any]) -> Dict[str, str]:
        """从唯一真源中读取显式的首音到运行时字符映射。"""
        processed = self.process_shouyin(shouyin_data)
        return processed.get("首音映射", {})

    def generate_encoding_files(self):
        """生成所有编码相关文件"""
        zaoyin_yinyuan_path = self.module_dir / self.SUBDIR / self.ZAOYIN_SOURCE_FILENAME

        with open(zaoyin_yinyuan_path, "r", encoding="utf-8") as f:
            zaoyin_yinyuan_data = json.load(f)

        zaoyin = self.build_explicit_runtime_mapping(zaoyin_yinyuan_data)

        # 简化输出结构，只保留编码映射部分
        encoding_data = {
            "zaoyin": zaoyin
        }

        encoding_path = self.module_dir / self.SUBDIR / self.YINYUAN_FILENAME

        # 文件追加逻辑 - 处理空文件或不存在的情况
        existing_data: dict[str, Any] = {}
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

        # 2. 生成首音符号映射 - 音元分集文件
        output_file = self.module_dir / self.SUBDIR / self.SHOUYIN_FILENAME

        shouyin_data = self.load_shouyin_data(zaoyin_yinyuan_path)
        processed_data = self.process_shouyin(shouyin_data)

        # 保存结果
        result_data = {
            "首音": processed_data["首音映射"]
        }
        self.save_yinyuan_data(output_file, result_data)

        compat_output_path = self.module_dir / self.SUBDIR / self.ZAOYIN_COMPAT_FILENAME
        self.save_yinyuan_data(compat_output_path, {"shouyin": processed_data["shouyin"]})

        print(f"  首音编码字典:")
        print(f"- 噪音码元映射: {encoding_path}")
        print(f"- 首音码元映射: {output_file}")
        print(f"- 兼容首音清单: {compat_output_path}")

def main():
    encoder = ShouyinEncoder()
    encoder.generate_encoding_files()

if __name__ == "__main__":
    main()
