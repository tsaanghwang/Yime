"""
音节编码模块重构版

功能：
1. 读取音节数据(pinyin/hanzi_pinyin/pinyin_normalized.json)
2. 调用run_analyzer.py将音节切分为首音和干音
3. 调用shouyin_encoder.py和ganyin_encoder.py进行编码
4. 将编码结果保存为JSON文件
"""
import json
import logging
from pathlib import Path
from typing import Dict, Any, Optional
import sys
from run_analyzer import analyze_syllable
from shouyin_encoder import ShouyinEncoder
from ganyin_encoder import GanyinEncoder

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class YinjieEncoder:
    """重构后的音节编码处理器"""

    def __init__(self):
        """初始化编码器并设置基础路径"""
        self.base_dir = Path(__file__).parent
        self._setup_paths()

    def _setup_paths(self):
        """设置项目路径和导入路径"""
        project_root = self.base_dir.parent.parent.parent
        sys.path.append(str(project_root))
        sys.path.append(str(self.base_dir))

    def _validate_path(self, path: Path) -> Path:
        """验证路径是否存在"""
        if not path.exists():
            raise FileNotFoundError(f"路径不存在: {path}")
        return path

    def encode_single_yinjie(self, syllable: str) -> str:
        # 验证音节格式
        if not syllable or not isinstance(syllable, str):
            raise ValueError("音节参数必须是非空字符串")

        # 切分音节并验证结果
        try:
            parts = analyze_syllable(syllable)
            if len(parts) != 2:
                raise ValueError("音节切分结果无效，应返回(首音,干音)元组")
            shouyin, ganyin = parts
        except Exception as e:
            raise ValueError(f"音节切分失败: {str(e)}") from e

        # 统一编码调用方式
        shouyin_encoder = ShouyinEncoder()
        shouyin_code = shouyin_encoder.encode_shouyin(shouyin)
        ganyin_encoder = GanyinEncoder()
        ganyin_code = ganyin_encoder.encode_ganyin(ganyin)

        # 安全拼接编码
        required_keys = {"首音", "呼音", "主音", "末音"}
        if not all(k in shouyin_code for k in {"首音"}):
            raise ValueError("首音编码缺少必要字段")
        if not all(k in ganyin_code for k in {"呼音", "主音", "末音"}):
            raise ValueError("干音编码缺少必要字段")

        return (
            shouyin_code["首音"]
            + ganyin_code["呼音"]
            + ganyin_code["主音"]
            + ganyin_code["末音"]
        )

    def encode_all_yinjie(self, output_subdir: str = "yinyuan") -> Path:
        """
        编码所有音节并保存结果

        Args:
            output_subdir: 输出子目录名

        Returns:
            生成的输出文件路径
        """
        input_path = self._get_input_path()
        output_path = self._get_output_path(output_subdir)

        pinyin_data = self._load_json(input_path)
        yinjie_list = list(pinyin_data.keys())

        yinjie_code_dict = {}
        for yinjie in yinjie_list:
            try:
                code = self.encode_single_yinjie(yinjie)
                yinjie_code_dict[yinjie] = code
            except Exception as e:
                logger.warning(f"跳过音节 '{yinjie}': {str(e)}")
                continue

        self._save_json(output_path, yinjie_code_dict)
        logger.info(f"成功生成编码文件: {output_path}")
        return output_path

    def _get_input_path(self) -> Path:
        """获取输入文件路径"""
        # 从当前文件向上查找项目根目录(包含pinyin目录的层级)
        current = Path(__file__).parent
        while not (current / "pinyin").exists() and current.parent != current:
            current = current.parent

        if not (current / "pinyin").exists():
            raise FileNotFoundError("无法找到项目根目录(包含pinyin目录)")

        return self._validate_path(
            current / "pinyin" / "hanzi_pinyin" / "pinyin_normalized.json"
        )

    def _get_output_path(self, subdir: str) -> Path:
        """获取输出文件路径并确保目录存在"""
        # 保持原样，使用相对路径
        output_dir = self.base_dir / subdir
        output_dir.mkdir(parents=True, exist_ok=True)
        return output_dir / "yinjie_code.json"

    def _load_json(self, path: Path) -> Dict[str, Any]:
        """加载JSON文件"""
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    def _save_json(self, path: Path, data: Dict[str, Any]) -> None:
        """保存数据到JSON文件"""
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def generate_encoding_files(self) -> Path:
        """
        生成编码文件(兼容旧接口)

        Returns:
            生成的输出文件路径
        """
        return self.encode_all_yinjie()

def main():
    """主入口函数"""
    try:
        encoder = YinjieEncoder()
        output_path = encoder.encode_all_yinjie()
        print(f"编码文件已生成: {output_path}")
    except Exception as e:
        logger.error(f"程序执行失败: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()