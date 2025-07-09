"""测试音元(Yinyuan)类的基本功能"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # 添加项目根目录到Python路径

from yinyuan.yinyuan import Yinyuan

# 测试直接创建音元
def test_yinyuan_creation():
    y = Yinyuan(code=23, notation="i˥")
    assert y.code == 23
    assert y.notation == "i˥"
    print(f"测试通过 - 直接创建的Yinyuan对象: {y}")

if __name__ == "__main__":
    test_yinyuan_creation()