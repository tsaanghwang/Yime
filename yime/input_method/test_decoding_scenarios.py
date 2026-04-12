"""
测试 yime.input_method 包的实际解码场景

测试真实的音元码输入和解码功能
"""

import sys
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(project_root))

from yime.input_method.core.decoders import CompositeCandidateDecoder


def test_real_decoding_scenarios():
    """测试实际解码场景"""
    print("="*60)
    print("测试实际解码场景")
    print("="*60)
    
    app_dir = Path(__file__).resolve().parent.parent
    decoder = CompositeCandidateDecoder(app_dir)
    
    # 测试用例：各种输入情况
    test_cases = [
        ("", "空输入"),
        ("a", "单字符"),
        ("ab", "双字符"),
        ("abc", "三字符"),
        ("abcd", "四字符"),
        ("abcde", "五字符（自动截取后4码）"),
        ("abcdefgh", "八字符（自动截取后4码）"),
        ("1234", "数字输入"),
        ("!@#$", "特殊字符"),
        ("测试", "中文字符"),
    ]
    
    print("\n解码测试结果:")
    print("-"*60)
    
    for test_input, description in test_cases:
        print(f"\n测试: {description}")
        print(f"输入: '{test_input}' (长度: {len(test_input)})")
        
        try:
            canonical, active_code, pinyin, candidates, status = decoder.decode_text(test_input)
            
            print(f"  规范编码: '{canonical}'")
            print(f"  当前4码: '{active_code}'")
            print(f"  拼音: '{pinyin}'")
            print(f"  候选词数量: {len(candidates)}")
            if candidates:
                print(f"  候选词: {candidates[:5]}")  # 只显示前5个
            print(f"  状态: {status}")
            
        except Exception as e:
            print(f"  错误: {e}")
    
    print("\n" + "="*60)


def test_input_flow():
    """测试输入流程"""
    print("\n" + "="*60)
    print("测试输入流程")
    print("="*60)
    
    from yime.input_method.core.input_manager import InputManager
    
    # 收集更新
    updates = []
    commits = []
    
    def on_update(candidates, pinyin, code, status):
        updates.append({
            'candidates': candidates,
            'pinyin': pinyin,
            'code': code,
            'status': status,
        })
    
    def on_commit(hanzi):
        commits.append(hanzi)
    
    # 创建管理器
    manager = InputManager(
        on_candidates_update=on_update,
        on_input_commit=on_commit,
    )
    
    # 设置解码器
    app_dir = Path(__file__).resolve().parent.parent
    decoder = CompositeCandidateDecoder(app_dir)
    manager.set_decoder(decoder)
    
    print("\n模拟输入流程:")
    print("-"*60)
    
    # 模拟输入 "abcd"
    test_input = "abcd"
    print(f"\n输入: {test_input}")
    for char in test_input:
        manager.process_key({'key': char, 'ascii': ord(char)})
    
    if updates:
        last_update = updates[-1]
        print(f"  当前缓冲区: '{manager.get_buffer()}'")
        print(f"  候选词数量: {len(last_update['candidates'])}")
        if last_update['candidates']:
            print(f"  候选词: {last_update['candidates'][:5]}")
        print(f"  拼音: {last_update['pinyin']}")
        print(f"  状态: {last_update['status']}")
    
    # 测试退格
    print("\n按退格键")
    manager.process_key({'key': 'Backspace', 'ascii': None})
    print(f"  当前缓冲区: '{manager.get_buffer()}'")
    
    # 测试ESC清空
    print("\n按ESC键")
    manager.process_key({'key': 'Escape', 'ascii': None})
    print(f"  当前缓冲区: '{manager.get_buffer()}'")
    
    print("\n" + "="*60)


def test_decoder_fallback():
    """测试解码器回退机制"""
    print("\n" + "="*60)
    print("测试解码器回退机制")
    print("="*60)
    
    app_dir = Path(__file__).resolve().parent.parent
    decoder = CompositeCandidateDecoder(app_dir)
    
    print(f"\n运行时解码器状态:")
    if decoder.runtime_decoder:
        print("  运行时解码器: 已加载")
    else:
        print("  运行时解码器: 未加载")
        if decoder.runtime_load_error:
            print(f"  错误: {decoder.runtime_load_error}")
    
    print(f"\n静态解码器: 已加载")
    
    # 测试一些编码，看是否能触发回退
    test_codes = ["abcd", "test", "code"]
    print("\n测试回退行为:")
    for code in test_codes:
        canonical, active, pinyin, candidates, status = decoder.decode_text(code)
        print(f"\n  输入: {code}")
        print(f"  候选词数量: {len(candidates)}")
        print(f"  状态: {status}")
    
    print("\n" + "="*60)


def main():
    """运行所有场景测试"""
    test_real_decoding_scenarios()
    test_input_flow()
    test_decoder_fallback()
    
    print("\n所有场景测试完成!")


if __name__ == "__main__":
    main()
