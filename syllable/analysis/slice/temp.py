"""

"""
"""
在syllable\analysis\slice\ganyin.py中，对 split_syllable 这个方法：
类推 _generate_ganyin_data 的方法，把参数改为拼音数据字典 {数字标调拼音: 调号标调拼音}即pinyin_data.items的"值"（tone_pinyin），
同样分成首音，将生成的首音部分拼音数据，表示成{"首音": "首音"}键值对的形式：
即从数字标调拼音中切分出来的首音部分作键gyin_data的键，后者作的值，存入字典中。
"""
