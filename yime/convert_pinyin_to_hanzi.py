# convert_pinyin_to_hanzi.py
import json
from pathlib import Path

class YinYuanInputConverter:
    def __init__(self,
                yinyuan_map_path=None,
                pinyin_hanzi_path=None,
                universal_map_path=None):
        """初始化转换器，自动创建或加载通用映射表"""
        # 设置默认路径(使用Path对象)
        base_dir = Path(__file__).parent
        self.yinyuan_map_path = Path(yinyuan_map_path) if yinyuan_map_path else base_dir / "enhanced_yinjie_mapping.json"
        self.pinyin_hanzi_path = Path(pinyin_hanzi_path) if pinyin_hanzi_path else base_dir / "pinyin_hanzi.json"
        self.universal_map_path = Path(universal_map_path) if universal_map_path else base_dir / "universal_mapping.json"

        # 检查文件是否存在
        if not self.yinyuan_map_path.exists():
            raise FileNotFoundError(f"音元映射文件不存在: {self.yinyuan_map_path}")
        if not self.pinyin_hanzi_path.exists():
            raise FileNotFoundError(f"拼音汉字映射文件不存在: {self.pinyin_hanzi_path}")

        self.yinyuan_map = self._load_json(self.yinyuan_map_path)['音元符号']
        self.pinyin_hanzi_map = self._load_json(self.pinyin_hanzi_path)

        # 检查并创建通用映射表
        if not self.universal_map_path.exists():
            self._create_universal_map(self.yinyuan_map_path, self.pinyin_hanzi_path, self.universal_map_path)
        self.universal_map = self._load_json(self.universal_map_path)

    def _load_json(self, path):
        """加载JSON文件"""
        try:
            with open(path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"JSON文件解析错误: {path} - {str(e)}")
        except Exception as e:
            raise IOError(f"无法读取文件: {path} - {str(e)}")

    def _create_universal_map(self, mapping_file, pinyin_hanzi_file, output_file):
        """整合自create_universal_mapping.py的功能"""
        universal_map = {}
        for yinjie, mappings in self.yinyuan_map.items():
            pinyin_variants = [
                mappings['数字标调'],
                mappings['调号标调'],
                mappings['注音符号']
            ]
            for pinyin in pinyin_variants:
                if pinyin in self.pinyin_hanzi_map:
                    universal_map[pinyin] = {
                        '汉字': self.pinyin_hanzi_map[pinyin],
                        '音元符号': yinjie,
                        '其他形式': [v for v in pinyin_variants if v != pinyin]
                    }
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(universal_map, f, ensure_ascii=False, indent=2)
        except Exception as e:
            raise IOError(f"无法写入通用映射文件: {output_file} - {str(e)}")

    def convert(self, input_text):
        """核心转换方法，处理音元输入"""
        # 这里实现您的转换逻辑
        pass