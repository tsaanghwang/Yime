"""
测试键盘监听器
"""

import sys
import time
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).resolve().parent
sys.path.insert(0, str(project_root))

def test_keyboard_listener():
    """测试键盘监听器初始化"""
    print("="*60)
    print("测试键盘监听器")
    print("="*60)
    
    # 检查依赖
    print("\n检查依赖:")
    
    try:
        import win32api
        print("[OK] pywin32 已安装")
        has_win32 = True
    except ImportError:
        print("[MISSING] pywin32 未安装")
        has_win32 = False
    
    try:
        import pyHook
        print("[OK] pyHook 已安装")
        has_pyhook = True
    except ImportError:
        print("[MISSING] pyHook 未安装")
        has_pyhook = False
    
    try:
        from pynput import keyboard
        print("[OK] pynput 已安装")
        has_pynput = True
    except ImportError:
        print("[MISSING] pynput 未安装")
        has_pynput = False
    
    if not has_win32 and not has_pyhook and not has_pynput:
        print("\n[ERROR] 没有可用的键盘监听库")
        return False
    
    # 测试初始化
    print("\n测试键盘监听器初始化:")
    
    try:
        from yime.input_method.core.keyboard_listener import KeyboardListener
        
        # 创建回调
        key_presses = []
        
        def on_key_press(key_info):
            key_presses.append(key_info)
            print(f"  按键: {key_info.get('key')}")
            return True  # 继续传递
        
        # 创建监听器
        listener = KeyboardListener(on_key_press=on_key_press)
        print("[PASS] 键盘监听器初始化成功")
        
        # 启动监听
        listener.start()
        print("[PASS] 键盘监听器已启动")
        
        # 等待一下
        print("\n监听器正在运行，按任意键测试（5秒后自动停止）...")
        time.sleep(2)
        
        # 停止监听
        listener.stop()
        print("[PASS] 键盘监听器已停止")
        
        return True
        
    except Exception as e:
        print(f"[FAIL] 键盘监听器测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """运行测试"""
    success = test_keyboard_listener()
    
    print("\n" + "="*60)
    if success:
        print("测试通过！键盘监听器可以正常工作。")
    else:
        print("测试失败！请检查依赖安装。")
    print("="*60)
    
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
