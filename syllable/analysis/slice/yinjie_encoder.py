"""
音节编码模块重构版

功能：
1. 读取音节数据
2. 切分音节为首音和干音
3. 对首音和干音进行编码
4. 对音节编码并保存数据
"""
import sys
import json
import logging
from pathlib import Path
from typing import Dict, Any, Optional
from syllable_categorizer import SyllableCategorizer
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

    def _handle_special_ganyin(self, ganyin: str) -> Optional[str]:
        """
        处理特殊干音(hm/hn/hng)，使用固定编码映射

        Args:
            ganyin: 干音字符串(如"hm1", "hn2", "hng3"等)

        Returns:
            组合后的编码字符串，如果无法处理则返回None
        """
        if not ganyin.startswith(('hm', 'hn', 'hng')):
            return None

        # 提取声调和剩余部分
        tone = ganyin[-1]
        prefix = ganyin[:-1]

        # 获取h的编码
        shouyin_encoder = ShouyinEncoder()
        h_code = shouyin_encoder.encode_shouyin('h')
        if not h_code:
            logger.warning(f"无法获取'h'的编码")
            return None

        # 直接编码映射，避免依赖ganyin_encoder
        nasal_code_map = {
            # m音 + 不同声调
            "m1": "􀀸􀀸􀀸",
            "m2": "􀀺􀀹􀀸",
            "m3": "􀀺􀀺􀀺",
            "m4": "􀀸􀀹􀀺",
            "m5": "􀀹􀀹􀀹",

            # n音 + 不同声调
            "n1": "􀀻􀀻􀀻",
            "n2": "􀀽􀀼􀀻",
            "n3": "􀀽􀀽􀀽",
            "n4": "􀀻􀀼􀀽",
            "n5": "􀀼􀀼􀀼",

            # ng音 + 不同声调
            "ng1": "􀀾􀀾􀀾",
            "ng2": "􀁀􀀿􀀾",
            "ng3": "􀁀􀁀􀁀",
            "ng4": "􀀾􀀿􀁀",
            "ng5": "􀀿􀀿􀀿",
        }

        # 构建查找键，如 "m1", "ng3" 等
        lookup_key = f"{prefix[1:]}{tone}"

        if lookup_key in nasal_code_map:
            # 返回组合后的编码
            return h_code + nasal_code_map[lookup_key]
        else:
            logger.warning(f"特殊干音'{ganyin}'无法找到对应编码")
            return None

    def encode_single_yinjie(self, syllable: str) -> str:
        """
        编码单个音节

        Args:
            syllable: 要编码的音节字符串

        Returns:
            编码后的字符串

        Raises:
            ValueError: 如果输入无效或编码失败
        """
        # 验证音节格式
        if not syllable or not isinstance(syllable, str):
            raise ValueError("音节参数必须是非空字符串")

        # 切分音节并验证结果
        try:
            parts = SyllableCategorizer.analyze_syllable(syllable)
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

        # 处理特殊干音(hm/hn/hng)
        if not ganyin_code or len(ganyin_code) != 3:
            logger.warning(f"干音'{ganyin}'编码无效，尝试处理为特殊干音")
            special_code = self._handle_special_ganyin(ganyin)
            if special_code:
                logger.warning(f"使用组合编码处理特殊干音: {ganyin}")
                ganyin_code = special_code[3:]  # 只取干音部分(去掉h的编码)
            else:
                raise ValueError(f"干音编码无效: {ganyin_code}")

        # 修改验证和拼接逻辑
        if not shouyin_code:
            raise ValueError("首音编码为空")
        if not ganyin_code or len(ganyin_code) != 3:  # 检查是否是3个字符
            raise ValueError(f"干音编码无效: {ganyin_code}")

        return shouyin_code + ganyin_code

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
