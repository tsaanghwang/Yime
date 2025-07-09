# pinyin/keys_to_yunmu.py
import json
from pathlib import Path
from typing import Dict, List
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def create_reverse_mapping(yunmu_to_keys: Dict[str, str]) -> Dict[str, List[str]]:
    """创建键位到韵母的反向映射

    Args:
        yunmu_to_keys: 韵母到键位的正向映射字典

    Returns:
        键位到韵母列表的字典（一个键位可能对应多个韵母）
    """
    keys_to_yunmu = {}
    for yunmu, key in yunmu_to_keys.items():
        if key not in keys_to_yunmu:
            keys_to_yunmu[key] = []
        keys_to_yunmu[key].append(yunmu)
    return keys_to_yunmu


def main():
    """主函数"""
    try:
        # 读取原始映射文件
        input_path = Path("yunmu_to_keys.json")
        with open(input_path, "r", encoding="utf-8") as f:
            yunmu_to_keys = json.load(f)

        # 创建反向映射
        keys_to_yunmu = create_reverse_mapping(yunmu_to_keys)

        # 确保输出目录存在
        output_path = Path(__file__).parent / "keys_to_yunmu.json"
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # 保存后立即检查文件是否存在
        if output_path.exists():
            print(f"文件已成功创建于: {output_path.absolute()}")
        else:
            print(f"文件创建失败，请检查目录权限: {output_path.parent}")
        # 保存结果
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(keys_to_yunmu, f, ensure_ascii=False, indent=2)

        logger.info(f"成功生成反向映射文件: {output_path}")
        print(f"反向映射已保存到 {output_path}")

    except FileNotFoundError as e:
        logger.error(f"文件未找到: {e}")
    except json.JSONDecodeError as e:
        logger.error(f"JSON解析错误: {e}")
    except Exception as e:
        logger.error(f"发生错误: {e}")


if __name__ == "__main__":
    main()
