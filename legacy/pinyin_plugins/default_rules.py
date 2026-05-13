from typing import List, Dict, Any
from ..rule_plugin import Rule, Plugin

class DefaultRule(Rule):
    def apply(self, yunmu: str, context: Dict[str, Any]) -> str:
        # 默认规则实现
        return yunmu.lower()

class DefaultRulesPlugin(Plugin):
    def load_rules(self):
        self.rules = [
            DefaultRule(rule_id="default_rule_1", priority=1),
            DefaultRule(rule_id="default_rule_2", priority=2)
        ]