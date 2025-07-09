from typing import List
from pinyin.yunmu_to_keys import RulePlugin, ConversionRule
from pinyin.constants import YunmuConstants

class ExamplePlugin(RulePlugin):
    """示例插件，演示如何创建自定义规则"""
    
    @classmethod
    def get_rules(cls) -> List[ConversionRule]:
        """获取示例规则"""
        constants = YunmuConstants()
        return [
            ConversionRule(
                condition=lambda k: k == constants.FINAL_ING,
                action=lambda v: "ying",
                description="示例规则：ing->ying",
                priority=10,
                rule_id="example_ing_to_ying"
            ),
            ConversionRule(
                condition=lambda k: k == constants.FINAL_ANG,
                action=lambda v: "ang",
                description="示例规则：ang保持不变",
                priority=20,
                rule_id="example_ang_no_change"
            )
        ]