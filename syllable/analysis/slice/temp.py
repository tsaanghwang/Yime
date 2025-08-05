"""
在syllable\analysis\slice\ganyin_to_yinyuan_sequence.py中：
1. 保留现有功能不变
2. 对经过当前模块处理还未写入文件的中间数据，调用syllable\analysis\slice\yueyin_yinyuan.py中定义的_change_pitch_style方法
改变音元的音调标记方式, 把结果写入ganyin_to_yinyuan_seq_marks.json文件中
3. 同时检查syllable\analysis\slice\yueyin_yinyuan.py中是处理音调标记的逻辑是否完整和正确
"""
