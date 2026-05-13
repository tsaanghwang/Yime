from typing import List, Dict, Any, Optional
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)

@dataclass
class Rule:
    """韵母转换规则基类"""
    rule_id: str
    priority: int = 0
    
    def apply(self, yunmu: str, context: Dict[str, Any]) -> Optional[str]:
        """应用转换规则"""
        raise NotImplementedError("子类必须实现apply方法")

class Plugin:
    """插件基类"""
    def __init__(self):
        self.rules: List[Rule] = []
        
    def load_rules(self) -> None:
        """加载规则"""
        raise NotImplementedError("子类必须实现load_rules方法")