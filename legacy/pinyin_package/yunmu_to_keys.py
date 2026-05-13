# pinyin/yunmu_to_keys.py
import json
from pathlib import Path
from typing import Dict, List, Tuple, Callable, Optional, Type, Any, Iterable, Set, NamedTuple
import logging
from collections import defaultdict
import re
from dataclasses import dataclass, field
from abc import ABC, abstractmethod
from functools import lru_cache
from .constants import YunmuConstants

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class ConversionRule:
    """韵母转换规则数据类"""
    condition: Callable[[str], bool]
    action: Callable[[str], str]
    description: str = ""
    priority: int = 0  # 优先级，数值越小优先级越高
    rule_id: str = field(default_factory=lambda: str(hash(str(id))))

    def __post_init__(self):
        if not self.description:
            self.description = f"规则{self.rule_id}"


class YunmuConverter:
    """优化后的韵母转换器"""

    def __init__(self):
        """初始化转换器"""
        self._constants = YunmuConstants()
        self.rule_counter: Dict[str, int] = defaultdict(int)
        self.total_conversions: int = 0
        self.successful_conversions: int = 0
        self.failed_conversions: int = 0
        self.rules = self._get_default_rules()
        self.replacement_table = self._constants.get_replacement_table()
        self._compile_regex_patterns()
        logger.info("韵母转换器初始化完成")

    def _get_default_rules(self) -> List[ConversionRule]:
        """获取默认转换规则"""
        return [
            ConversionRule(
                condition=lambda k: k == self._constants.I_APICAL,
                action=lambda v: self._constants.I_APICAL_REPLACEMENT,
                description="处理-i->ir转换",
                priority=1
            ),
            ConversionRule(
                condition=lambda k: k in [
                    self._constants.AO_FINAL, self._constants.IAO_FINAL],
                action=lambda v: v.replace(
                    self._constants.O_CODA, self._constants.U_CODA),
                description="处理ao->au, iao->iau转换",
                priority=2
            ),
            ConversionRule(
                condition=lambda k: k == self._constants.YNG_FINAL,
                action=lambda v: self._constants.FINAL_YONG,
                description="处理iong->vong转换",
                priority=3
            ),
            ConversionRule(
                condition=lambda k: k == self._constants.ING_FINAL,
                action=lambda v: self._constants.FINAL_IONG,
                description="处理ing->iong转换",
                priority=4
            ),
            ConversionRule(
                condition=lambda k: k == self._constants.O_UNROUNDED,
                action=lambda v: self._constants.O_ROUNDED,
                description="处理e->o转换",
                priority=5
            ),
            ConversionRule(
                condition=lambda k: k == self._constants.ENG_FINAL,
                action=lambda v: self._constants.FINAL_ONG,
                description="处理eng->ong转换",
                priority=6
            ),
            ConversionRule(
                condition=lambda k: k in (
                    self._constants.IN_FINAL, self._constants.YN_FINAL),
                action=lambda v: v.replace(
                    self._constants.Y_NEAR_ROUNDED, self._constants.Y_REPLACEMENT).replace("n", "en"),
                description="处理in->ien, ün->üen转换",
                priority=7
            ),
            ConversionRule(
                condition=lambda k: k in (
                    self._constants.UENG_FINAL, self._constants.YNG_FINAL),
                action=lambda v: self._constants.FINAL_UONG,
                description="处理ueng->uong, ong->uong转换",
                priority=8
            ),
            ConversionRule(
                condition=lambda k: True,
                action=lambda v: v.replace(
                    self._constants.Y_NEAR_ROUNDED, self._constants.Y_REPLACEMENT) if self._constants.Y_NEAR_ROUNDED in v else v,
                description="处理 ü->v 转换",
                priority=9
            )
        ]

    def _compile_regex_patterns(self) -> None:
        """预编译所有正则表达式"""
        self.patterns = {
            'yn': re.compile(rf"{self._constants.Y_NEAR_ROUNDED}n"),
            'vn': re.compile(r"vn"),
        }

    def validate_input(self, yunmu_dict: Dict[str, str]) -> None:
        """验证输入数据"""
        if not isinstance(yunmu_dict, dict):
            raise ValueError("输入必须是字典")
        if not all(isinstance(k, str) and isinstance(v, str) for k, v in yunmu_dict.items()):
            raise ValueError("字典键值都必须是字符串")
        required_finals = set(self._constants.REQUIRED_FINALS)
        if not required_finals.issubset(yunmu_dict.keys()):
            missing = required_finals - set(yunmu_dict.keys())
            raise ValueError(f"缺少必要的韵母: {missing}")

    def convert(self, yunmu_dict: Dict[str, str]) -> Dict[str, str]:
        """优化后的转换方法，带统计功能"""
        self.validate_input(yunmu_dict)
        converted = {}
        self.total_conversions = len(yunmu_dict)

        for key, value in yunmu_dict.items():
            try:
                converted_key = self._apply_rules(key)
                if key == self._constants.E_CIRCUMFLEX:
                    converted[self._constants.E_FRONT] = self._constants.E_FRONT
                elif key != self._constants.E_FRONT:
                    converted[key] = converted_key
                self.successful_conversions += 1
            except Exception as e:
                self.failed_conversions += 1
                logger.error("转换韵母 %s 失败: %s", key, str(e))
                raise

        logger.info("成功转换 %d/%d 个韵母 (成功率: %.2f%%)",
                    len(converted), len(yunmu_dict),
                    (self.successful_conversions / self.total_conversions * 100) if self.total_conversions else 0)
        return converted

    def _apply_rules(self, key: str) -> str:
        """应用规则进行转换并更新统计"""
        value = key
        for rule in self.rules:
            if rule.condition(key):
                try:
                    value = rule.action(value)
                    self.rule_counter[rule.rule_id] += 1
                    logger.debug("应用规则 %s: %s -> %s",
                                 rule.description, key, value)
                    break
                except Exception as e:
                    logger.error("规则 %s 应用失败: %s",
                                 rule.description, str(e))
                    raise
        return value

    def get_stats(self) -> Dict[str, Any]:
        """获取详细的转换统计信息"""
        stats = {
            'total_conversions': self.total_conversions,
            'successful_conversions': self.successful_conversions,
            'failed_conversions': self.failed_conversions,
            'success_rate': (self.successful_conversions / self.total_conversions * 100) if self.total_conversions else 0,
            'rule_stats': dict(self.rule_counter)
        }
        return stats


def main():
    """主函数"""
    # 创建 YunmuConstants 实例
    constants = YunmuConstants()

    # 创建韵母字典
    yunmu = {k: "" for k in constants.REQUIRED_FINALS}
    # 创建转换器实例
    converter = YunmuConverter()

    # 确保输出目录存在
    output_dir = Path(__file__).parent
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        # 执行转换
        yunmu_to_keys = converter.convert(yunmu)
        logger.info(
            f"成功转换 {converter.successful_conversions}/{converter.total_conversions} 个韵母")

        # 生成统计报告
        stats = converter.get_stats()

        # 打印统计摘要
        print("\n=== 转换统计 ===")
        print(f"总尝试转换: {stats['total_conversions']}")
        print(f"成功转换: {stats['successful_conversions']}")
        print(f"失败转换: {stats['failed_conversions']}")
        print(f"成功率: {stats['success_rate']:.2f}%")

        print("\n=== 详细规则应用统计 ===")
        # 按应用次数降序排列
        sorted_rules = sorted(
            stats['rule_stats'].items(),
            key=lambda x: x[1],
            reverse=True
        )

        for rule_id, count in sorted_rules:
            # 查找规则描述
            rule_desc = ""
            for rule in converter.rules:
                if rule.rule_id == rule_id:
                    rule_desc = rule.description
                    break

            print(f"{rule_id} ({rule_desc}): {count}次应用")

        # 定义结果文件路径
        result_path = output_dir / "yunmu_to_keys.json"

        # 保存转换结果到JSON文件
        with open(result_path, 'w', encoding='utf-8') as f:
            json.dump(yunmu_to_keys, f, ensure_ascii=False, indent=2)

        print(f"\n转换结果已保存到: {result_path}")

        # 保存统计信息到JSON文件
        stats_path = Path(__file__).parent / "conversion_stats.json"
        with open(stats_path, 'w', encoding='utf-8') as f:
            json.dump(stats, f, ensure_ascii=False, indent=2)
        print(f"\n统计信息已保存到 {stats_path}")

    except Exception as e:
        logger.error(f"转换过程中发生错误: {e}")
        raise


if __name__ == "__main__":
    main()
