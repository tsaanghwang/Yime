"""
在模块pinyin\hanzi_pinyin\pinyin_normalizer.py中，在适当位置添加代码：
1.在61-62"    
if not pinyin_with_tone or not pinyin_with_tone[-1].isdigit():
        return pinyin_with_tone  # 没有调号，直接返回
"后, 不是“没有调号直接返回不带调号的拼音”，而是在终端输出信息：
"音节{占位符}没有调号，需要改成有调号的拼音再作处理"。

2. 检查因没有找到可标调的元音而返回的不带调号的拼音是否：
在["m", "n", "ng", "hm", "r"]。

"""
