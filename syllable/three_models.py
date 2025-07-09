# 1. 组合关系（Composition）:当部分对象不能独立存在时（如汽车与发动机）
class PartA:
    def __init__(self, a_property):
        self.a_property = a_property


class PartB:
    def __init__(self, b_property):
        self.b_property = b_property


class Whole:
    def __init__(self, a_property, b_property):
        self.part_a = PartA(a_property)  # 生命周期由Whole控制
        self.part_b = PartB(b_property)  # 强关联关系

# 2. 聚合关系（Aggregation）:当部分对象可以独立存在时（如学校与教师）
class PartA:
    def __init__(self, a_property):
        self.a_property = a_property


class PartB:
    def __init__(self, b_property):
        self.b_property = b_property


class Whole:
    def __init__(self, part_a, part_b):
        self.part_a = part_a  # 从外部传入，生命周期独立
        self.part_b = part_b  # 弱关联关系

# 3. 策略模式（Strategy Pattern）:当需要动态切换行为时
class BehaviorA:
    def execute(self):
        print("执行A部分行为")

class BehaviorB:
    def execute(self):
        print("执行B部分行为")

class Context:
    def __init__(self, behavior_a, behavior_b):
        self.behavior_a = behavior_a
        self.behavior_b = behavior_b
    
    def perform(self):
        self.behavior_a.execute()
        self.behavior_b.execute()