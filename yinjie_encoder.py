"""项目根目录入口，复用包内的音节编码实现。"""

import sys
from pathlib import Path

from syllable.analysis.slice.yinjie_encoder import YinjieEncoder as SliceYinjieEncoder
from syllable.analysis.slice.yinjie_encoder import logger


class YinjieEncoder(SliceYinjieEncoder):
    """项目根目录版本，保持根目录输入输出路径。"""

    def __init__(self):
        super().__init__()
        self.base_dir = Path(__file__).parent

    def _get_input_path(self) -> Path:
        return self._validate_path(
            self.base_dir / "pinyin" / "hanzi_pinyin" / "pinyin_normalized.json"
        )

    def _get_output_path(self, subdir: str) -> Path:
        output_dir = self.base_dir / subdir
        output_dir.mkdir(parents=True, exist_ok=True)
        return output_dir / "yinjie_code.json"


def main():
    try:
        encoder = YinjieEncoder()
        output_path = encoder.encode_all_yinjie("")
        print(f"编码文件已生成: {output_path}")
    except Exception as error:
        logger.error(f"程序执行失败: {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()
