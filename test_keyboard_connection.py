#!/usr/bin/env python3
"""
键盘连接测试脚本

测试键盘监听和输入管理功能
"""

import sys
from pathlib import Path

# 添加项目路径
sys.path.insert(0, str(Path(__file__).parent))

from yime.input_method import InputMethodApp


def test_keyboard_connection():
    """测试键盘连接"""
    print("=" * 60)
    print("  音元输入法键盘连接测试")
    print("=" * 60)
    print()
    print("使用说明：")
    print("1. 启动后，敲击键盘会触发输入")
    print("2. 输入音元码元后，会显示候选词")
    print("3. 按数字键选择候选词")
    print("4. 按ESC清空输入")
    print("5. 按Enter提交首选候选词")
    print()
    print("注意：")
    print("- 如果没有安装pyHook或pynput，将使用手动输入模式")
    print("- 遇到问题可以运行 dev_unlock.cmd 解锁")
    print()
    print("=" * 60)
    print()
    
    try:
        # 创建应用
        app = InputMethodApp(auto_paste=True)
        
        # 运行应用
        app.run()
        
    except KeyboardInterrupt:
        print("\n用户中断")
    except Exception as e:
        print(f"\n错误: {e}")
        import traceback
        traceback.print_exc()
    finally:
        print("\n测试结束")


if __name__ == "__main__":
    test_keyboard_connection()
