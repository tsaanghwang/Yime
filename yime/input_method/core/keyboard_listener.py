"""
键盘监听模块

提供全局键盘监听功能，支持pyHook和pynput两种方式
"""

import sys
import time
from typing import Callable, Optional, Dict, Any

# 尝试导入pyHook
try:
    import pyHook
    import pythoncom
    HAS_PYHOOK = True
except ImportError:
    HAS_PYHOOK = False

# 尝试导入pynput
try:
    from pynput import keyboard
    HAS_PYPUT = True
except ImportError:
    HAS_PYPUT = False


class KeyboardListener:
    """
    键盘监听器
    
    支持两种监听方式：
    1. pyHook - Windows全局钩子（推荐）
    2. pynput - 跨平台监听（备选）
    """
    
    def __init__(
        self,
        on_key_press: Callable[[Dict[str, Any]], bool],
        on_key_release: Optional[Callable[[Dict[str, Any]], bool]] = None,
    ) -> None:
        """
        初始化键盘监听器
        
        Args:
            on_key_press: 按键回调函数，返回True继续传递，False拦截
            on_key_release: 释放键回调函数（可选）
        """
        self.on_key_press = on_key_press
        self.on_key_release = on_key_release
        self.is_running = False
        self._listener = None
        
        # 检查可用的监听方式
        if not HAS_PYHOOK and not HAS_PYPUT:
            raise RuntimeError(
                "需要安装 pyHook 或 pynput。\n"
                "安装方法：\n"
                "  pip install pyHook-1.5.1-cp310-cp310-win_amd64.whl\n"
                "  或\n"
                "  pip install pynput"
            )
        
        # 选择监听方式
        if HAS_PYHOOK:
            print("使用 pyHook 进行键盘监听")
            self._init_pyhook()
        else:
            print("使用 pynput 进行键盘监听")
            self._init_pynput()
    
    def _init_pyhook(self) -> None:
        """使用pyHook初始化"""
        self._hook_manager = pyHook.HookManager()
        self._hook_manager.KeyDown = self._pyhook_key_down
        self._hook_manager.KeyUp = self._pyhook_key_up
    
    def _init_pynput(self) -> None:
        """使用pynput初始化"""
        self._listener = keyboard.Listener(
            on_press=self._pynput_key_press,
            on_release=self._pynput_key_release,
        )
    
    def _pyhook_key_down(self, event) -> bool:
        """
        pyHook按键事件处理
        
        Args:
            event: pyHook事件对象
        
        Returns:
            True继续传递按键，False拦截
        """
        try:
            # 转换为统一格式
            key_info = {
                'key': event.Key,
                'ascii': event.Ascii if event.Ascii > 0 else None,
                'scan_code': event.ScanCode,
                'is_extended': event.IsExtended,
                'is_injected': event.Injected,
                'time': time.time(),
                'window': event.Window,
                'window_name': event.WindowName,
            }
            
            # 调用回调
            if self.on_key_press:
                return self.on_key_press(key_info)
            return True
        except Exception as e:
            print(f"处理按键事件出错: {e}")
            return True  # 出错时继续传递
    
    def _pyhook_key_up(self, event) -> bool:
        """
        pyHook释放键事件处理
        
        Args:
            event: pyHook事件对象
        
        Returns:
            True继续传递按键，False拦截
        """
        try:
            if self.on_key_release:
                key_info = {
                    'key': event.Key,
                    'ascii': event.Ascii if event.Ascii > 0 else None,
                    'time': time.time(),
                }
                return self.on_key_release(key_info)
            return True
        except Exception as e:
            print(f"处理释放键事件出错: {e}")
            return True
    
    def _pynput_key_press(self, key) -> None:
        """
        pynput按键事件处理
        
        Args:
            key: pynput按键对象
        """
        try:
            # 转换为统一格式
            key_info = {
                'key': self._pynput_key_to_string(key),
                'ascii': getattr(key, 'char', None),
                'time': time.time(),
            }
            
            # 调用回调
            if self.on_key_press:
                # pynput不支持拦截，所以总是返回True
                self.on_key_press(key_info)
        except Exception as e:
            print(f"处理按键事件出错: {e}")
    
    def _pynput_key_release(self, key) -> None:
        """
        pynput释放键事件处理
        
        Args:
            key: pynput按键对象
        """
        try:
            if self.on_key_release:
                key_info = {
                    'key': self._pynput_key_to_string(key),
                    'time': time.time(),
                }
                self.on_key_release(key_info)
        except Exception as e:
            print(f"处理释放键事件出错: {e}")
    
    def _pynput_key_to_string(self, key) -> str:
        """
        将pynput按键对象转换为字符串
        
        Args:
            key: pynput按键对象
        
        Returns:
            按键字符串
        """
        try:
            if isinstance(key, keyboard.KeyCode):
                return key.char if key.char else str(key)
            elif isinstance(key, keyboard.Key):
                return key.name
            else:
                return str(key)
        except:
            return str(key)
    
    def start(self) -> None:
        """开始监听键盘"""
        if self.is_running:
            print("键盘监听已在运行")
            return
        
        self.is_running = True
        print("启动键盘监听...")
        
        if HAS_PYHOOK:
            # pyHook需要消息循环
            self._hook_manager.HookKeyboard()
            print("pyHook键盘钩子已安装")
            # 注意：pythoncom.PumpMessages()会阻塞
            # 在实际应用中，应该在单独的线程中运行
        else:
            # pynput在后台线程运行
            self._listener.start()
            print("pynput监听器已启动")
    
    def stop(self) -> None:
        """停止监听键盘"""
        if not self.is_running:
            return
        
        print("停止键盘监听...")
        self.is_running = False
        
        if HAS_PYHOOK:
            try:
                self._hook_manager.UnhookKeyboard()
                print("pyHook键盘钩子已卸载")
            except Exception as e:
                print(f"卸载pyHook钩子出错: {e}")
        else:
            try:
                if self._listener:
                    self._listener.stop()
                    print("pynput监听器已停止")
            except Exception as e:
                print(f"停止pynput监听器出错: {e}")
    
    def is_active(self) -> bool:
        """
        检查是否正在监听
        
        Returns:
            True如果正在监听，False否则
        """
        return self.is_running
    
    def pump_messages(self) -> None:
        """
        处理消息循环（仅pyHook需要）
        
        注意：这个方法会阻塞，应该在单独的线程中调用
        """
        if HAS_PYHOOK and self.is_running:
            print("开始处理消息循环...")
            pythoncom.PumpMessages()
